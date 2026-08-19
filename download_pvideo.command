#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Downloading pvideo manifest and binaries..."
python3 - "$SCRIPT_DIR" <<'PY'
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


DEFAULT_MANIFEST = "https://pizazz.s3.bitiful.net/pvideo.json"
USER_AGENT = "okhttp/4.12.0"
PVIDEO_PREFIX = "pvideo-"
ABIS = {"arm64-v8a", "armeabi-v7a", "x86", "x86_64"}


def output_root(script_dir):
    configured = os.environ.get("PVIDEO_OUTPUT_ROOT")
    if configured:
        return Path(configured)
    android_root = script_dir / "app" / "src" / "main"
    return android_root if android_root.exists() else script_dir


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request) as response:
        return response.read()


def write_file(path, data, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False, dir=path.parent) as temp:
        temp.write(data)
        temp_path = Path(temp.name)
    if executable:
        temp_path.chmod(0o755)
    shutil.move(str(temp_path), path)
    if executable:
        path.chmod(0o755)


def abi_for(name):
    abi = name.removeprefix(PVIDEO_PREFIX)
    if abi not in ABIS:
        raise ValueError(f"unsupported pvideo ABI entry: {name}")
    return abi


def archive_name(name, url):
    suffix = Path(urllib.parse.urlparse(url).path).suffix
    return f"{name}{suffix if suffix else '.zip'}"


def extract_binary(archive_path, expected_name):
    if not zipfile.is_zipfile(archive_path):
        return archive_path.read_bytes()
    with zipfile.ZipFile(archive_path) as zip_file:
        names = [info.filename for info in zip_file.infolist() if not info.is_dir()]
        if not names:
            raise ValueError(f"{archive_path.name} contains no files")
        selected = expected_name if expected_name in names else names[0]
        return zip_file.read(selected)


def main():
    script_dir = Path(sys.argv[1])
    root = output_root(script_dir)
    assets_dir = root / "assets" / "pvideo"
    jni_dir = root / "jniLibs"
    manifest_url = os.environ.get("PVIDEO_MANIFEST", DEFAULT_MANIFEST)

    manifest_data = fetch(manifest_url)
    manifest = json.loads(manifest_data.decode("utf-8"))
    write_file(assets_dir / "pvideo.json", json.dumps(manifest, ensure_ascii=False, indent=4).encode("utf-8"))

    installed = 0
    for name, url in manifest.items():
        if name.endswith(".md5") or not name.startswith(PVIDEO_PREFIX) or not url:
            continue
        abi = abi_for(name)
        archive_data = fetch(url)
        archive_path = assets_dir / archive_name(name, url)
        write_file(archive_path, archive_data)

        binary_data = extract_binary(archive_path, name)
        actual_md5 = hashlib.md5(binary_data).hexdigest()
        expected_md5 = manifest.get(f"{name}.md5")
        if expected_md5 and actual_md5.lower() != str(expected_md5).lower():
            raise ValueError(f"{name} md5 mismatch: {actual_md5} != {expected_md5}")

        so_path = jni_dir / abi / "libpvideo.so"
        write_file(so_path, binary_data, executable=True)
        print(f"{name}: {archive_path} -> {so_path} md5={actual_md5}")
        installed += 1

    print(f"manifest: {assets_dir / 'pvideo.json'}")
    if installed == 0:
        raise ValueError("manifest contained no pvideo-* entries")


if __name__ == "__main__":
    main()
PY
STATUS=$?

echo
if [ "$STATUS" -eq 0 ]; then
    echo "Done."
else
    echo "Download failed."
fi
echo "Press Enter to close this window."
read -r
exit "$STATUS"
