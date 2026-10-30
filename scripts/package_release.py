"""Package only the exported game; never include source credentials or raw models."""
import hashlib
import os
from pathlib import Path
import shutil
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    folder = ROOT / "build/windows"
    exe, pck = folder / "ButterflyValley.exe", folder / "ButterflyValley.pck"
    executable = exe.read_bytes()
    if len(executable) < 1024*1024 or executable[:2] != b"MZ":
        raise SystemExit("Missing or invalid Windows executable")
    offset = struct.unpack_from("<I", executable, 0x3C)[0]
    if executable[offset:offset+4] != b"PE\0\0" or struct.unpack_from("<H", executable, offset+4)[0] != 0x8664:
        raise SystemExit("Expected a Windows x64 PE executable")
    if pck.stat().st_size < 1024*1024:
        raise SystemExit("Game PCK is unexpectedly small")
    with pck.open("rb") as stream:
        if stream.read(4) != b"GDPC":
            raise SystemExit("Invalid Godot resource pack")
    for source, target in [("game/PLAY-WINDOWS.md","READ-ME.md"),
                           ("game/LIVING-VALLEY-DESIGN.md","DESIGN.md"),
                           ("CREDITS.md","CREDITS.md"),
                           ("LICENSE.md","LICENSE.md"),
                           ("game/fauna_assets/SOURCES.md","ANIMAL-CREDITS.md"),
                           ("game/assets/audio/AUDIO-LICENSES.md","AUDIO-CREDITS.md")]:
        shutil.copy2(ROOT / source, folder / target)
    (folder / "Start-Compatible.bat").write_bytes(
        b'@echo off\r\ncd /d "%~dp0"\r\nstart "" ButterflyValley.exe --rendering-method gl_compatibility -- --safe-graphics\r\n')
    (folder / "SOURCE-COMMIT.txt").write_text(os.environ.get("GITHUB_SHA","local-build") + "\n")
    hashes = []
    allowed = {"ButterflyValley.exe","ButterflyValley.pck","ButterflyValley.console.exe",
               "READ-ME.md","DESIGN.md","CREDITS.md","LICENSE.md","ANIMAL-CREDITS.md",
               "AUDIO-CREDITS.md","Start-Compatible.bat","SOURCE-COMMIT.txt","SHA256SUMS.txt"}
    for path in sorted(folder.iterdir()):
        if path.is_symlink() or path.name not in allowed or not path.is_file():
            raise SystemExit("Unexpected file in release directory: " + path.name)
        if path.is_file():
            if path.name == "SHA256SUMS.txt":
                continue
            hashes.append(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name)
    (folder / "SHA256SUMS.txt").write_text("\n".join(hashes) + "\n")
    archive = ROOT / "build/ButterflyValley-Windows.zip"
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as output:
        for path in sorted(folder.iterdir()):
            if path.is_file():
                if path.suffix.lower() in {".glb",".fbx",".key"}:
                    raise SystemExit("Raw model or credential must not enter the release")
                output.write(path, "ButterflyValley-Windows/" + path.name)
    print("Windows archive ready: {} bytes".format(archive.stat().st_size))


if __name__ == "__main__":
    main()
