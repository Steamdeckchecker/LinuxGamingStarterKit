#!/usr/bin/env python3
"""Build deterministic release files without including local/deployment data."""
from pathlib import Path
import hashlib
import re
import shutil
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
version = (ROOT / "VERSION").read_text(encoding="ascii").strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("VERSION must contain a numeric major.minor.patch version")
source_version = re.search(r'^VERSION = "([^"]+)"', (ROOT / "starterkit.py").read_text(encoding="utf-8"), re.M)
if source_version is None or source_version[1] != version:
    raise SystemExit("VERSION and starterkit.py disagree")
subprocess.run([sys.executable, str(ROOT / "build.py")], check=True)

out = ROOT / "release"
out.mkdir(exist_ok=True)
launchers = ["install.sh", "Linux-Handheld-Starter-Kit.desktop"]
for name in launchers:
    shutil.copy2(ROOT / name, out / name)

root_files = ["VERSION", ".gitignore", ".gitattributes", "LICENSE", "README.md", "README.en.md", "CHANGELOG.md", "CONTRIBUTING.md", "SHA256SUMS", "build.py", "desktop_bootstrap.py", "desktop_launcher.py", "starterkit.py", "recommend.txt", *launchers]
files = [ROOT / name for name in root_files]
for folder in ["assets", "tests", "scripts", "docs", ".github", "website"]:
    for path in (ROOT / folder).rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if "__pycache__" in relative.parts or path.suffix == ".pyc":
            continue
        if relative.parts[0] == "website":
            if relative.parts[1] == "dist" or relative.as_posix() == "website/worker/index.js":
                continue
            if relative.parts[1] == "public" and relative.parts[2] != "assets":
                continue
        files.append(path)

archive = out / f"Linux-Handheld-Starter-Kit-v{version}.zip"
prefix = f"Linux-Handheld-Starter-Kit-v{version}/"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
    for path in sorted(set(files)):
        relative = path.relative_to(ROOT).as_posix()
        info = zipfile.ZipInfo(prefix + relative, date_time=(2026, 1, 1, 0, 0, 0))
        info.create_system = 3
        mode = 0o755 if path.suffix in {".sh", ".desktop"} else 0o644
        info.external_attr = (stat.S_IFREG | mode) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        target.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)

assets = [out / name for name in launchers] + [archive]
(out / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in assets), encoding="ascii")
downloads = ROOT / "website/public/downloads"
downloads.mkdir(parents=True, exist_ok=True)
for path in assets + [out / "SHA256SUMS", ROOT / "recommend.txt"]:
    shutil.copy2(path, downloads / path.name)
for path in assets + [out / "SHA256SUMS"]:
    print(f"{path.name}: {path.stat().st_size} bytes")
