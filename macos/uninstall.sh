#!/bin/bash
#
# Remove the macOS installation of rastertokpsl-re.
# If Kyocera's original PPD is still present, queues are switched back
# to it -- note that the original filter is Intel-only and needs Rosetta 2.
#
set -euo pipefail

FILTER_DIR="/Library/Printers/Kyocera-RE"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"

say(){  printf '\033[1m==>\033[0m %s\n' "$1"; }
ok(){   printf '    \033[32m%s\033[0m %s\n' "OK" "$1"; }
warn(){ printf '    \033[33m%s\033[0m %s\n' "!!" "$1"; }
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }

say "Checking print queues"
FOUND=0
while read -r q; do
  [[ -z "$q" ]] && continue
  grep -q "rastertokpsl-re" "/etc/cups/ppd/$q.ppd" 2>/dev/null || continue
  FOUND=1
  ORIG=$(ls "$PPD_DIR"/Kyocera*GDI.ppd 2>/dev/null | grep -v -- "-RE.ppd" | head -1 || true)
  if [[ -n "$ORIG" ]]; then
    lpadmin -p "$q" -P "$ORIG" 2>&1 | grep -viE "deprecat|verworfen" || true
    ok "'$q' reverted to $(basename "$ORIG")"
    warn "That filter is Intel-only and requires Rosetta 2."
  else
    warn "'$q' uses rastertokpsl-re but no original PPD is available."
    warn "Leaving it untouched -- removing it would break printing entirely."
    warn "To delete the queue:  sudo lpadmin -x $q"
  fi
done < <(lpstat -v 2>/dev/null | cut -d: -f1 | awk '{print $NF}')
[[ $FOUND -eq 1 ]] || ok "no queue was using rastertokpsl-re"

say "Removing files"
rm -f "$PPD_DIR"/Kyocera_*GDI-RE.ppd && ok "PPD(s) removed" || true
rm -rf "$FILTER_DIR" && ok "filter removed" || true
say "Done."
