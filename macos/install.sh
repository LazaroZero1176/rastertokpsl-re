#!/bin/bash
#
# Install rastertokpsl-re as a CUPS filter on macOS and point a print
# queue at it. Replaces Kyocera's Intel-only filter, so printing keeps
# working without Rosetta 2.
#
# Usage:  sudo ./macos/install.sh [--model FS-1040] [--queue NAME]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER_DIR="/Library/Printers/Kyocera-RE"
FILTER="$FILTER_DIR/rastertokpsl-re"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
MODEL="FS-1040"
QUEUE=""

say(){  printf '\033[1m==>\033[0m %s\n' "$1"; }
ok(){   printf '    \033[32m%s\033[0m %s\n' "OK" "$1"; }
warn(){ printf '    \033[33m%s\033[0m %s\n' "!!" "$1"; }
die(){  printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    --queue) QUEUE="${2:?--queue needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "Run with sudo:  sudo $0"
[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."

SRC_PPD="$ROOT/Kyocera_${MODEL}GDI.ppd"
[[ -f "$SRC_PPD" ]] || die "No PPD for model '$MODEL'. Available: $(ls "$ROOT"/Kyocera_*.ppd 2>/dev/null | xargs -n1 basename | sed 's/^Kyocera_//;s/GDI\.ppd$//' | tr '\n' ' ')"

say "System"
ok "macOS $(sw_vers -productVersion), $(uname -m)"

# --- binary ---------------------------------------------------------
if [[ ! -x "$ROOT/bin/rastertokpsl-re" ]]; then
  warn "Binary not built yet -- building now."
  sudo -u "${SUDO_USER:-$USER}" "$ROOT/macos/build.sh" || die "Build failed."
fi

ARCHS=$(lipo -archs "$ROOT/bin/rastertokpsl-re")
case "$(uname -m)" in
  arm64)  [[ "$ARCHS" == *arm64*  ]] || die "Binary lacks arm64 (has: $ARCHS). Re-run macos/build.sh." ;;
  x86_64) [[ "$ARCHS" == *x86_64* ]] || die "Binary lacks x86_64 (has: $ARCHS). Re-run macos/build.sh." ;;
esac
ok "binary architectures: $ARCHS"

say "Installing filter"
mkdir -p "$FILTER_DIR"
install -m 755 -o root -g wheel "$ROOT/bin/rastertokpsl-re" "$FILTER"
xattr -d com.apple.quarantine "$FILTER" 2>/dev/null || true
ok "$FILTER"

# --- PPD ------------------------------------------------------------
say "Installing PPD for $MODEL"
DEST_PPD="$PPD_DIR/Kyocera_${MODEL}GDI-RE.ppd"
mkdir -p "$PPD_DIR"
sed -e "s|^\*cupsFilter:.*|*cupsFilter: \"application/vnd.cups-raster 0 $FILTER\"|" \
    -e "s|^\*NickName:.*|*NickName: \"Kyocera $MODEL (KPSL-RE)\"|" \
    -e "s|^\*ShortNickName:.*|*ShortNickName: \"Kyocera $MODEL (KPSL-RE)\"|" \
    "$SRC_PPD" > "$DEST_PPD"
chown root:wheel "$DEST_PPD"; chmod 644 "$DEST_PPD"
grep -q "$FILTER" "$DEST_PPD" || die "PPD patch failed."
ok "$DEST_PPD"

# --- queue ----------------------------------------------------------
say "Print queue"
if [[ -z "$QUEUE" ]]; then
  while read -r q; do
    [[ -z "$q" ]] && continue
    if grep -qi "rastertokpsl" "/etc/cups/ppd/$q.ppd" 2>/dev/null; then QUEUE="$q"; break; fi
  done < <(lpstat -v 2>/dev/null | cut -d: -f1 | awk '{print $NF}')
fi

if [[ -n "$QUEUE" ]] && lpstat -p "$QUEUE" >/dev/null 2>&1; then
  lpadmin -p "$QUEUE" -P "$DEST_PPD" 2>&1 | grep -viE "deprecat|verworfen" || true
  cupsenable "$QUEUE" 2>/dev/null || true
  ok "queue '$QUEUE' now uses rastertokpsl-re"
else
  warn "No existing Kyocera queue found -- searching for the printer."
  URI=$(lpinfo -v 2>/dev/null | awk '/usb:|riousbprint|dnssd:/ {print $2}' | head -1)
  if [[ -z "$URI" ]]; then
    warn "Printer not found. Filter and PPD are installed; add the queue manually:"
    warn "  sudo lpadmin -p Kyocera -v <device-uri> -P \"$DEST_PPD\" -E"
    exit 0
  fi
  QUEUE="Kyocera_${MODEL//-/_}"
  lpadmin -p "$QUEUE" -v "$URI" -P "$DEST_PPD" -E 2>&1 | grep -viE "deprecat|verworfen" || true
  ok "created queue '$QUEUE' -> $URI"
fi

say "Verifying"
grep -q "rastertokpsl-re" "/etc/cups/ppd/$QUEUE.ppd" || die "Queue does not use the new filter."
ok "PPD points at rastertokpsl-re"
lpstat -p "$QUEUE" 2>&1 | sed 's/^/    /'

echo
say "Done."
echo "    Test print:  lp -d $QUEUE /etc/hosts"
echo "    Revert:      sudo ./macos/uninstall.sh"
