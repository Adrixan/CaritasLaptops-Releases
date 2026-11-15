#!/usr/bin/env bash
# Leak guard for the public release target (decision D47 B, 2026-11-15).
# Fails (exit 1) when a scanned file or ZIP contains a known secret or a credential pattern.
#
# Usage: release/leak-guard.sh [--patterns-only] <dir|file|zip>...
#   Known secrets come from an untracked denylist, one literal per line ('#' starts a comment):
#   $CARITAS_LEAK_DENYLIST, default <repo>/.leak-denylist (listed in .gitignore, never committed).
#   Without --patterns-only a missing or empty denylist is an error (fail closed).
#   --patterns-only is for the public repository's CI, which has no denylist.
# Output names file, line and rule only; matched values are never printed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
patterns_only=0
if [[ "${1:-}" == "--patterns-only" ]]; then patterns_only=1; shift; fi
if [[ $# -eq 0 ]]; then
  echo "usage: $0 [--patterns-only] <dir|file|zip>..." >&2
  exit 2
fi

denylist="${CARITAS_LEAK_DENYLIST:-$here/../.leak-denylist}"
declare -a secrets=()
if [[ $patterns_only -eq 0 ]]; then
  if [[ ! -r "$denylist" ]]; then
    echo "leak-guard: denylist '$denylist' missing (fail closed). Create it from the private repo, one secret per line." >&2
    exit 2
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    secrets+=("$line")
  done < "$denylist"
  if [[ ${#secrets[@]} -eq 0 ]]; then
    echo "leak-guard: denylist '$denylist' is empty (fail closed)." >&2
    exit 2
  fi
fi

# Generic credential patterns (ERE). Name|pattern. Literal passwords are flagged; variables ($x) are not.
rules=(
  'plaintext-securestring|ConvertTo-SecureString[[:space:]]+["'"'"'][^"'"'"'$]'
  'password-literal-assignment|\$[A-Za-z_]*([Pp]ass|PASS|[Kk]ennwort|[Pp]asswort)[A-Za-z_]*[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"'$]'
  'winlogon-defaultpassword-literal|DefaultPassword"?[[:space:]]+-Value[[:space:]]+["'"'"']'
  'net-user-literal-password|net(\.exe)?["'"'"']?[[:space:]]+user[[:space:]]+[^[:space:]/]+[[:space:]]+["'"'"']?[^"'"'"'$[:space:]/]+["'"'"']?[[:space:]]+/'
  'unattend-value|<Value>[^<$]+</Value>'
  'private-key|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'github-token|(gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,})'
  'aws-key|AKIA[0-9A-Z]{16}'
  'product-key|[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}'
  'consumer-mail-login|[A-Za-z0-9._%+-]+@(outlook|hotmail|live|gmail|gmx|icloud)\.[a-z]{2,}'
)

# Only plain text may ship, so every byte is greppable.
allowed_ext_re='\.(ps1|cmd|json|md|txt|yml|yaml|sh)$'
forbidden_name_re='(^|/)(autounattend[^/]*|\.leak-denylist|credentials\.json|Zugangsdaten[^/]*|HANDBUCH[^/]*|software-inventory[^/]*)$'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
report() { echo "LEAK  $1  ($2)"; fail=1; }

scan_tree() {
  local root="$1" label="$2"
  local f rel n i
  while IFS= read -r -d '' f; do
    rel="${f#"$root"/}"
    [[ "$rel" == "$f" ]] && rel="$(basename "$f")"
    if [[ "$rel" =~ $forbidden_name_re ]]; then report "$label:$rel" "forbidden file"; continue; fi
    if [[ ! "$rel" =~ $allowed_ext_re && "$(basename "$rel")" != "LICENSE" ]]; then
      report "$label:$rel" "file type not allowed in public build"; continue
    fi
    i=0
    for s in "${secrets[@]+"${secrets[@]}"}"; do
      i=$((i + 1))
      while IFS= read -r n; do report "$label:$rel:$n" "denylist entry #$i"; done \
        < <(grep -a -n -i -F -e "$s" -- "$f" 2>/dev/null | cut -d: -f1 || true)
      # UTF-16LE files (PowerShell 5.1 Out-File default) would hide literals from a byte grep.
      if [[ "$(head -c 2 -- "$f" | od -An -tx1 | tr -d ' \n')" == "fffe" ]] \
        && iconv -f UTF-16LE -t UTF-8 -- "$f" 2>/dev/null | grep -a -q -i -F -e "$s"; then
        report "$label:$rel" "denylist entry #$i (UTF-16)"
      fi
    done
    for r in "${rules[@]}"; do
      local name="${r%%|*}" pat="${r#*|}"
      while IFS= read -r n; do report "$label:$rel:$n" "pattern $name"; done \
        < <(grep -a -n -E -e "$pat" -- "$f" 2>/dev/null | cut -d: -f1 || true)
    done
  done < <(find "$root" \( -name .git -prune \) -o -type f -print0)
}

for target in "$@"; do
  if [[ -d "$target" ]]; then
    scan_tree "$(cd "$target" && pwd)" "$target"
  elif [[ -f "$target" && "$target" == *.zip ]]; then
    dest="$work/$(basename "$target").d"
    mkdir -p "$dest"
    if ! unzip -q -o "$target" -d "$dest"; then report "$target" "unreadable zip"; continue; fi
    scan_tree "$dest" "$target"
  elif [[ -f "$target" ]]; then
    dest="$work/single.$RANDOM"
    mkdir -p "$dest"
    cp -- "$target" "$dest/"
    scan_tree "$dest" "$(dirname "$target")"
  else
    echo "leak-guard: '$target' not found" >&2
    exit 2
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "leak-guard: FAILED. Nothing may be published." >&2
  exit 1
fi
mode=$([[ $patterns_only -eq 1 ]] && echo "patterns only" || echo "${#secrets[@]} denylist entries + patterns")
echo "leak-guard: clean ($mode)."
