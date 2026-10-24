#!/usr/bin/env python3
"""Build the standalone shell installer and desktop launcher."""
from pathlib import Path
import hashlib
import re
import subprocess
from desktop_launcher import build_desktop, FILENAME

BASE = Path(__file__).resolve().parent
source = (BASE / "starterkit.py").read_text(encoding="utf-8")
recommend = (BASE / "recommend.txt").read_text(encoding="utf-8-sig")
source = re.sub(r"# BEGIN EMBEDDED RECOMMENDATIONS\n.*?\n# END EMBEDDED RECOMMENDATIONS", lambda match: "# BEGIN EMBEDDED RECOMMENDATIONS\nEMBEDDED_RECOMMENDATIONS = " + repr(recommend) + "\n# END EMBEDDED RECOMMENDATIONS", source, flags=re.S)
compile(source, "starterkit.py", "exec")
header = r'''#!/usr/bin/env bash
# Linux Handheld Starter Kit — Steam Deck Checker — 0.1.0
# Run as your normal desktop user: bash install.sh
# The embedded Python code uses only the standard library.
set -euo pipefail
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Python 3.9+ is required. Bitte Python 3.9+ installieren.' >&2
    exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))'; then
    printf '%s\n' 'Python 3.9+ is required.' >&2
    exit 1
fi
STARTER_KIT_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export STARTER_KIT_BASE
# GUI launches from a file manager get a terminal for live progress as well.
starter_kit_diagnostics=0
for starter_kit_arg in "$@"; do
    case "$starter_kit_arg" in --check|--help|-h) starter_kit_diagnostics=1 ;; esac
done
if [[ ! -t 1 && "$starter_kit_diagnostics" == 0 && "${STARTER_KIT_TERMINAL:-0}" != 1 ]] && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    export STARTER_KIT_TERMINAL=1
    starter_kit_script="$STARTER_KIT_BASE/$(basename -- "${BASH_SOURCE[0]}")"
    if command -v konsole >/dev/null 2>&1; then
        exec konsole --separate --nofork -e bash "$starter_kit_script" "$@"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec gnome-terminal --wait -- bash "$starter_kit_script" "$@"
    elif command -v xterm >/dev/null 2>&1; then
        exec xterm -e bash "$starter_kit_script" "$@"
    fi
fi
starter_kit_work="$(mktemp -d -t handheld-starter-kit-launcher.XXXXXXXX)"
chmod 700 "$starter_kit_work"
starter_kit_child=''
starter_kit_cleanup() {
    rm -rf -- "$starter_kit_work"
}
starter_kit_stop() {
    if [[ -n "$starter_kit_child" ]]; then
        kill -TERM "$starter_kit_child" 2>/dev/null || true
        wait "$starter_kit_child" 2>/dev/null || true
    fi
    exit 130
}
trap starter_kit_cleanup EXIT
trap starter_kit_stop INT TERM
cat > "$starter_kit_work/starterkit.py" <<'HANDHELD_STARTER_KIT_PYTHON'
'''
footer = r'''HANDHELD_STARTER_KIT_PYTHON
python3 "$starter_kit_work/starterkit.py" "$@" &
starter_kit_child=$!
set +e
wait "$starter_kit_child"
starter_kit_status=$?
set -e
exit "$starter_kit_status"
'''
target = BASE / "install.sh"
target.write_text(header + source + "\n" + footer, encoding="utf-8", newline="\n")
target.chmod(0o755)
subprocess.run(["bash", "-n", str(target)], check=True)
digest = hashlib.sha256(target.read_bytes()).hexdigest()
desktop = BASE / FILENAME
desktop.write_text(build_desktop(target.read_bytes()), encoding="utf-8", newline="\n")
desktop.chmod(0o755)
desktop_digest = hashlib.sha256(desktop.read_bytes()).hexdigest()
(BASE / "SHA256SUMS").write_text(f"{digest}  install.sh\n{desktop_digest}  {FILENAME}\n", encoding="ascii")
print(f"Built {target.name} ({target.stat().st_size} bytes)")
print(f"Built {desktop.name} ({desktop.stat().st_size} bytes)")
