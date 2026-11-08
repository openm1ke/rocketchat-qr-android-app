#!/usr/bin/env python3
"""Download the pinned Gradle ZIP with retries before invoking the wrapper."""

import argparse
import hashlib
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit


def prepare(properties: Path, download_dir: Path) -> None:
    content = properties.read_text(encoding="utf-8")
    values = dict(
        line.split("=", 1)
        for line in content.splitlines()
        if line and not line.startswith("#") and "=" in line
    )
    url = values["distributionUrl"].replace(r"\:", ":")
    checksum = values["distributionSha256Sum"].strip().lower()
    if not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise ValueError("A pinned Gradle SHA-256 checksum is required")

    download_dir.mkdir(parents=True, exist_ok=True)
    filename = Path(urlsplit(url).path).name
    if not filename.endswith(".zip"):
        raise ValueError("The pinned Gradle distribution must be a ZIP archive")
    # Flutter detects the Gradle version from this filename.
    archive = download_dir.resolve() / filename
    subprocess.run(
        [
            "curl", "--silent", "--show-error", "--fail", "--location", "--retry", "5",
            "--retry-all-errors", "--retry-delay", "5",
            "--connect-timeout", "20", "--max-time", "120",
            "--output", str(archive), url,
        ],
        check=True,
    )
    digest = hashlib.sha256()
    with archive.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != checksum:
        archive.unlink()
        raise ValueError("Downloaded Gradle ZIP does not match the pinned checksum")

    # Only the CI checkout changes: the wrapper reads the verified local ZIP
    # instead of repeating the fragile network download inside Java.
    updated = re.sub(
        r"^distributionUrl=.*$",
        f"distributionUrl={archive.as_uri()}",
        content,
        flags=re.MULTILINE,
    )
    properties.write_text(updated, encoding="utf-8")
    print("Prepared pinned Gradle distribution; SHA-256 verified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--properties", type=Path, required=True)
    parser.add_argument("--download-dir", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.properties, args.download_dir)
