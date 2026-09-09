from __future__ import annotations

import base64
import hashlib
import json
import zipfile
from pathlib import Path

NAME = "tracehook_demo"
DIST = "tracehook_demo-1.0.0.dist-info"
VERSION = "1.0.0"


def _metadata():
    return (
        "Metadata-Version: 2.1\n"
        "Name: tracehook-demo\n"
        f"Version: {VERSION}\n"
        "Summary: Benign PEP 517 build-hook trace package\n"
        "Requires-Python: >=3.11\n"
        "\n"
    )


def _wheel_metadata():
    return (
        "Wheel-Version: 1.0\n"
        "Generator: tracehook-demo custom PEP 517 backend\n"
        "Root-Is-Purelib: true\n"
        "Tag: py3-none-any\n"
        "\n"
    )


def get_requires_for_build_wheel(config_settings=None):
    return []


def prepare_metadata_for_build_wheel(metadata_directory, config_settings=None):
    dist = Path(metadata_directory) / DIST
    dist.mkdir(parents=True, exist_ok=True)
    (dist / "METADATA").write_text(_metadata(), encoding="utf-8")
    (dist / "WHEEL").write_text(_wheel_metadata(), encoding="utf-8")
    return DIST


def _record_row(path: str, data: bytes):
    digest = base64.urlsafe_b64encode(
        hashlib.sha256(data).digest()
    ).rstrip(b"=").decode("ascii")
    return f"{path},sha256={digest},{len(data)}"


def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    marker = {
        "event": "pep517-build-backend-executed",
        "package": "tracehook-demo",
        "version": VERSION,
        "generatedBy": "tracehook_backend.build_wheel",
        "message": (
            "This content did not exist in the source distribution. "
            "The PEP 517 backend generated it while building the wheel."
        ),
    }

    marker_json = json.dumps(marker, indent=2, sort_keys=True) + "\n"

    module = (
        "TRACE_DATA = " + repr(marker) + "\n\n"
        "def trace_data():\n"
        "    return dict(TRACE_DATA)\n"
    )

    files = {
        f"{NAME}/__init__.py": module.encode("utf-8"),
        f"{NAME}/build-hook.json": marker_json.encode("utf-8"),
        f"{DIST}/METADATA": _metadata().encode("utf-8"),
        f"{DIST}/WHEEL": _wheel_metadata().encode("utf-8"),
    }

    record_path = f"{DIST}/RECORD"
    record = "\n".join(
        [_record_row(path, data) for path, data in files.items()]
        + [f"{record_path},,"]
    ) + "\n"
    files[record_path] = record.encode("utf-8")

    wheel_name = "tracehook_demo-1.0.0-py3-none-any.whl"
    wheel_path = Path(wheel_directory) / wheel_name

    with zipfile.ZipFile(wheel_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path, data in files.items():
            zf.writestr(path, data)

    return wheel_name
