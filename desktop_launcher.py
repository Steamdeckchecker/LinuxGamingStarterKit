"""Build a standard, single-file desktop entry with its installer embedded."""
import base64
import hashlib
from pathlib import Path

FILENAME = "Linux-Handheld-Starter-Kit.desktop"
COMMENTS = {
    "": "Set up your Linux handheld with Steam Deck Checker",
    "de": "Deinen Linux-Handheld mit Steam Deck Checker einrichten",
    "es": "Configura tu consola Linux con Steam Deck Checker",
    "fr": "Configurez votre console Linux avec Steam Deck Checker",
    "ru": "Настройка Linux-консоли со Steam Deck Checker",
    "zh": "通过 Steam Deck Checker 设置 Linux 掌机",
    "ja": "Steam Deck Checker で Linux ハンドヘルドをセットアップ",
}


def build_desktop(installer):
    bootstrap = Path(__file__).with_name("desktop_bootstrap.py").read_bytes()
    compile(bootstrap, "desktop_bootstrap.py", "exec")
    code = base64.b64encode(bootstrap).decode("ascii")
    payload = base64.b64encode(installer).decode("ascii")
    digest = hashlib.sha256(installer).hexdigest()
    # No shell expansion is involved. %k is a separate, single argument and may
    # be either a local filename or a file: URI, including paths with spaces.
    lines = [
        "#!/usr/bin/env xdg-open", "[Desktop Entry]", "Version=1.0", "Type=Application",
        "Name=Linux Handheld Starter Kit", "Icon=applications-games",
        "Terminal=true", "StartupNotify=false", "TryExec=python3", "Categories=Game;Utility;",
        f'Exec=python3 -c "import base64; exec(base64.b64decode(\'{code}\'))" %k',
    ]
    for language, comment in COMMENTS.items():
        suffix = f"[{language}]" if language else ""
        lines.append(f"Comment{suffix}={comment}")
    lines += [f"X-Starter-Kit-Installer-SHA256={digest}", f"X-Starter-Kit-Installer-Base64={payload}"]
    return "\n".join(lines) + "\n"
