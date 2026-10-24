"""Embedded in the .desktop Exec key; opens its own embedded installer."""
import base64
import configparser
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit


MESSAGES = {
    "de": ("Linux Handheld Starter Kit wird gestartet …", "Start fehlgeschlagen:", "Zum Schließen Enter drücken …"),
    "en": ("Starting Linux Handheld Starter Kit…", "Startup failed:", "Press Enter to close…"),
    "es": ("Iniciando Linux Handheld Starter Kit…", "Error al iniciar:", "Pulsa Intro para cerrar…"),
    "fr": ("Démarrage de Linux Handheld Starter Kit…", "Échec du démarrage :", "Appuyez sur Entrée pour fermer…"),
    "ru": ("Запуск Linux Handheld Starter Kit…", "Ошибка запуска:", "Нажмите Enter, чтобы закрыть…"),
    "zh": ("正在启动 Linux Handheld Starter Kit……", "启动失败：", "按 Enter 关闭……"),
    "ja": ("Linux Handheld Starter Kit を起動しています…", "起動に失敗しました：", "Enter キーで閉じます…"),
}


def main():
    language = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG", "en")
    messages = MESSAGES.get(language.split("_")[0].split(".")[0], MESSAGES["en"])
    status = 1
    try:
        if sys.version_info < (3, 9):
            raise RuntimeError("Python 3.9+ is required.")
        if len(sys.argv) != 2 or not sys.argv[1]:
            raise RuntimeError("Open the downloaded .desktop file from your file manager.")
        reference = sys.argv[1]
        location = urlsplit(reference)
        if location.scheme:
            if location.scheme != "file" or location.netloc not in ("", "localhost"):
                raise ValueError("The launcher must be a local file.")
            reference = unquote(location.path)
        launcher = Path(reference).resolve(strict=True)
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        config.read_string(launcher.read_text(encoding="utf-8"))
        entry = config["Desktop Entry"]
        installer = base64.b64decode(entry["X-Starter-Kit-Installer-Base64"], validate=True)
        expected = entry["X-Starter-Kit-Installer-SHA256"]
        if hashlib.sha256(installer).hexdigest() != expected:
            raise ValueError("Installer checksum mismatch. Download the .desktop file again.")
        print(messages[0], flush=True)
        with tempfile.TemporaryDirectory(prefix="handheld-starter-kit-desktop-") as directory:
            script = Path(directory) / "install.sh"
            script.write_bytes(installer)
            script.chmod(0o700)
            # Terminal=true already supplies a terminal. Do not open another one.
            environment = {**os.environ, "STARTER_KIT_TERMINAL": "1"}
            status = subprocess.run(["bash", str(script)], env=environment).returncode
        if status:
            print(messages[1], "exit", status, file=sys.stderr, flush=True)
    except KeyboardInterrupt:
        status = 130
    except Exception as error:
        print(messages[1], str(error), file=sys.stderr, flush=True)
    if status and sys.stdin.isatty():
        try:
            input(messages[2])
        except (EOFError, KeyboardInterrupt):
            pass
    return status


if __name__ == "__main__":
    raise SystemExit(main())
