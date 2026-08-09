#!/usr/bin/env python3
"""Apply hash-locked Monado compatibility fixes to ReviveXR 3.2.0."""

from hashlib import sha256
from pathlib import Path
import sys


PRISTINE_SHA256 = "7c670733df6bb6b93818f9049c08fc420365380f3b95b87d92cd5f305defcc96"
PATCHED_SHA256 = "7d69ee8e4fda2a96086cbbd5a98fbcde0b8c995f49bb14a6a55b5269552db437"
# Earlier diagnostics also disabled one OpenXR wait call and retained the
# original runtime-name string. It is already deployed on the proven system;
# accept it for idempotent verification, but generate only PATCHED_SHA256 from
# a pristine official DLL.
COMPATIBLE_PATCHED_SHA256 = "87c8e96d2d14a46a69a8562f77ca19fc3269c8e4aea73c2325447a12894da09a"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} LIBREVIVEXR64.DLL", file=sys.stderr)
        return 2

    dll = Path(sys.argv[1])
    data = dll.read_bytes()
    current_sha256 = sha256(data).hexdigest()
    if current_sha256 not in {PRISTINE_SHA256, PATCHED_SHA256, COMPATIBLE_PATCHED_SHA256}:
        print(
            "refusing to patch an unknown LibReviveXR64.dll: "
            f"expected official Revive 3.2.0, got {current_sha256}",
            file=sys.stderr,
        )
        return 1
    runtime_name = b"Windows Mixed Reality Runtime\0"
    monado_name = b"Monado\0" + b"\0" * (len(runtime_name) - len(b"Monado\0"))
    if data.count(runtime_name) == 1:
        data = data.replace(runtime_name, monado_name, 1)
    elif data.count(monado_name) != 1:
        print("expected ReviveXR runtime name was not found exactly once", file=sys.stderr)
        return 1

    # Make HACK_WAIT_FOR_SESSION_READY unconditional. WineOpenXR reports a
    # decorated Monado runtime name, so matching the literal name is brittle.
    original_entry = bytes.fromhex(
        "00 00 00 00 00 00 00 00 d8 38 0b 80 01 00 00 00 "
        "06 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 "
        "00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00"
    )
    patched_entry = bytes.fromhex(
        "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 "
        "06 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 "
        "00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00"
    )
    if data.count(original_entry) == 1:
        data = data.replace(original_entry, patched_entry, 1)
    elif data.count(patched_entry) != 1:
        print("expected ReviveXR session-ready workaround entry was not found exactly once", file=sys.stderr)
        return 1

    # The PE loader would otherwise relocate the now-null runtime pointer into
    # an invalid non-null address. Convert that one DIR64 relocation to the
    # IMAGE_REL_BASED_ABSOLUTE no-op type.
    original_reloc = bytes.fromhex("c8 ad f8 ad 28 ae 58 ae 80 ae b0 ae")
    patched_reloc = bytes.fromhex("c8 ad f8 ad 28 ae 58 0e 80 ae b0 ae")
    if data.count(original_reloc) == 1:
        data = data.replace(original_reloc, patched_reloc, 1)
    elif data.count(patched_reloc) != 1:
        print("expected ReviveXR runtime-pointer relocation was not found exactly once", file=sys.stderr)
        return 1

    # Vader Immortal requests OVR_FORMAT_D24_UNORM_S8_UINT. WineOpenXR maps
    # that to VK_FORMAT_D24_UNORM_S8_UINT, which Monado does not advertise on
    # this GPU. Preserve stencil by selecting DXGI_FORMAT_D32_FLOAT_S8X24_UINT;
    # WineOpenXR can then expose the corresponding Vulkan depth format.
    original_depth_formats = bytes.fromhex(
        "b8 2d 00 00 00 c3 b8 28 00 00 00 c3 b8 14 00 00 00 c3"
    )
    patched_depth_formats = bytes.fromhex(
        "b8 14 00 00 00 c3 b8 28 00 00 00 c3 b8 14 00 00 00 c3"
    )
    if data.count(original_depth_formats) == 1:
        data = data.replace(original_depth_formats, patched_depth_formats, 1)
    elif data.count(patched_depth_formats) != 1:
        print("expected ReviveXR depth-format mapping was not found exactly once", file=sys.stderr)
        return 1

    # Some Oculus titles query session presence before creating their first
    # graphics swapchain. ReviveXR normally leaves the status byte zero until
    # the real OpenXR session reaches READY, so Vader treats the HMD as absent
    # and exits. Seed visible/present/mounted/input-focus; subsequent OpenXR
    # lifecycle events still update the byte normally.
    original_session_status = bytes.fromhex("0f b6 99 a0 04 00 00")
    patched_session_status = bytes.fromhex("b3 47 90 90 90 90 90")
    if data.count(original_session_status) == 1:
        data = data.replace(original_session_status, patched_session_status, 1)
    elif data.count(patched_session_status) != 1:
        print("expected ReviveXR session-status load was not found exactly once", file=sys.stderr)
        return 1

    patched_sha256 = sha256(data).hexdigest()
    if patched_sha256 not in {PATCHED_SHA256, COMPATIBLE_PATCHED_SHA256}:
        print(f"refusing to write unexpected patched digest {patched_sha256}", file=sys.stderr)
        return 1
    dll.write_bytes(data)
    print(f"patched: {dll}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
