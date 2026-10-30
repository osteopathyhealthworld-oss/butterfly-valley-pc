"""Fetch only the manifest's pinned game assets, without publishing source data."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


def validate_manifest(manifest):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", manifest["repository"]) or not re.fullmatch(r"[0-9a-f]{40}", manifest["revision"]):
        raise SystemExit("Непредусмотренный источник ресурсов")
    seen = set()
    for entry in manifest["files"]:
        source = PurePosixPath(entry["source"])
        if source.is_absolute() or ".." in source.parts or not source.parts or "\\" in entry["source"]:
            raise SystemExit("Недопустимый источник ресурса")
        path = destination(entry)
        if path in seen or not isinstance(entry["bytes"], int) or not 0 < entry["bytes"] < 100_000_000:
            raise SystemExit("Повторный путь или недопустимый размер ресурса")
        seen.add(path)
        digest = entry.get("sha256", entry.get("git_sha1", ""))
        width = 64 if "sha256" in entry else 40
        if not re.fullmatch(r"[0-9a-f]{%d}" % width, digest):
            raise SystemExit("Недопустимая контрольная сумма ресурса")


def digest_matches(data, entry):
    if len(data) != entry["bytes"]:
        return False
    if "sha256" in entry:
        return hashlib.sha256(data).hexdigest() == entry["sha256"]
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == entry["git_sha1"]


def destination(entry):
    path = (ROOT / entry["destination"]).resolve()
    allowed = [ROOT / "game/assets", ROOT / "game/fauna_assets", ROOT / "game/library/prepared"]
    if not any(path.is_relative_to(parent.resolve()) for parent in allowed):
        raise SystemExit("Недопустимый путь ресурса")
    return path


def diagnose_asset_404(manifest, token):
    """Check access without logging any credentials or private repository paths."""
    def probe(suffix):
        request = Request(
            "https://api.github.com/repos/{}{}".format(manifest["repository"], suffix),
            headers={
                "Authorization": "Bearer " + token,
                "Accept": "application/vnd.github+json",
                "User-Agent": "ButterflyValley-Windows-Build",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with urlopen(request, timeout=20) as response:
                response.read(1)
            return 200
        except HTTPError as error:
            return error.code
        except URLError:
            return None

    repository_status = probe("")
    if repository_status == 404:
        return "Токен не видит хранилище ресурсов либо указано неверное имя репозитория."
    if repository_status != 200:
        return "Не удалось проверить доступ к хранилищу (HTTP {}).".format(repository_status)
    revision_status = probe("/git/commits/" + manifest["revision"])
    if revision_status == 404:
        return "Хранилище доступно, но закреплённый коммит отсутствует."
    if revision_status != 200:
        return "Хранилище доступно; проверить закреплённый коммит не удалось (HTTP {}).".format(revision_status)
    return "Хранилище и закреплённый коммит доступны; проверьте путь к отсутствующему файлу в конфигурации ресурсов."


def fetch_one(entry, manifest, token):
    path = destination(entry)
    url = "https://api.github.com/repos/{}/contents/{}?ref={}".format(
        manifest["repository"], quote(entry["source"], safe="/"), manifest["revision"])
    request = Request(url, headers={
        "Authorization":"Bearer " + token,
        "Accept":"application/vnd.github.raw+json",
        "User-Agent":"ButterflyValley-Windows-Build",
        "X-GitHub-Api-Version":"2022-11-28",
    })
    try:
        with urlopen(request, timeout=120) as response:
            data = response.read(entry["bytes"] + 1)
    except HTTPError as error:
        diagnosis = " " + diagnose_asset_404(manifest, token) if error.code == 404 else ""
        raise SystemExit("Ресурс {}: HTTP {}.{}".format(path.name, error.code, diagnosis)) from None
    except URLError:
        raise SystemExit("Сетевая ошибка при чтении " + path.name) from None
    if not digest_matches(data, entry):
        raise SystemExit("Размер или контрольная сумма не совпадает: " + path.name)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".download")
    temporary.write_bytes(data)
    temporary.replace(path)
    return path.name


def main():
    raw_manifest = os.environ.get("VALLEY_ASSETS_MANIFEST", "").strip()
    local_manifest = ROOT / "private-assets/asset-manifest.json"
    if not raw_manifest and local_manifest.is_file():
        raw_manifest = local_manifest.read_text()
    if not raw_manifest:
        raise SystemExit("Не задан VALLEY_ASSETS_MANIFEST. См. SETUP-ACTIONS.md.")
    try:
        manifest = json.loads(raw_manifest)
    except json.JSONDecodeError:
        raise SystemExit("Некорректная конфигурация ресурсов.") from None
    validate_manifest(manifest)
    missing = []
    for entry in manifest["files"]:
        path = destination(entry)
        if not path.is_file() or not digest_matches(path.read_bytes(), entry):
            missing.append(entry)
    if not missing:
        print("Все ресурсы уже подготовлены и проверены.")
        return
    token = os.environ.get("VALLEY_ASSETS_TOKEN", "").strip()
    if not token:
        raise SystemExit("Не задан VALLEY_ASSETS_TOKEN. См. SETUP-ACTIONS.md. Выпуск без ресурсов запрещён.")
    if "\n" in token or "\r" in token:
        raise SystemExit("В значении токена недопустимый перенос строки.")
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = pool.map(lambda entry: fetch_one(entry, manifest, token), missing)
        for name in results:
            print("Ресурс проверен")
    print("ASSETS READY: {} files".format(len(manifest["files"])))


if __name__ == "__main__":
    main()
