#!/usr/bin/env python3

from pathlib import Path
import base64
import hashlib
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / "python-repo"
SOURCES = ROOT / "python-sources"

REPO.mkdir(parents=True, exist_ok=True)

for old in REPO.iterdir():
    if old.is_file():
        old.unlink()


def record_row(path: str, data: bytes) -> str:
    digest = base64.urlsafe_b64encode(
        hashlib.sha256(data).digest()
    ).rstrip(b"=").decode("ascii")
    return f"{path},sha256={digest},{len(data)}"


def build_reportkit_wheel():
    metadata = (SOURCES / "reportkit" / "METADATA.template").read_text("utf-8")
    metadata = metadata.rstrip() + "\n\n"

    wheel_meta = (
        "Wheel-Version: 1.0\n"
        "Generator: kcdc-trace-lab\n"
        "Root-Is-Purelib: true\n"
        "Tag: py3-none-any\n"
        "\n"
    )

    files = {
        "reportkit/__init__.py": (
            SOURCES / "reportkit" / "reportkit" / "__init__.py"
        ).read_bytes(),
        "reportkit-1.0.0.dist-info/METADATA": metadata.encode("utf-8"),
        "reportkit-1.0.0.dist-info/WHEEL": wheel_meta.encode("utf-8"),
    }

    record_path = "reportkit-1.0.0.dist-info/RECORD"
    record = "\n".join(
        [record_row(path, data) for path, data in files.items()]
        + [f"{record_path},,"]
    ) + "\n"
    files[record_path] = record.encode("utf-8")

    out = REPO / "reportkit-1.0.0-py3-none-any.whl"
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path, data in files.items():
            zf.writestr(path, data)

    print(out.relative_to(ROOT))


def build_tracehook_sdist():
    src = SOURCES / "tracehook-demo"
    out = REPO / "tracehook_demo-1.0.0.tar.gz"

    with tarfile.open(out, "w:gz") as tf:
        for path in sorted(src.rglob("*")):
            if path.is_file():
                arcname = Path("tracehook_demo-1.0.0") / path.relative_to(src)
                tf.add(path, arcname=str(arcname))

    print(out.relative_to(ROOT))


build_reportkit_wheel()
build_tracehook_sdist()
