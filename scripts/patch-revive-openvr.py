#!/usr/bin/env python3
"""Patch Revive 3.2.0's Vulkan extension probes under Proton.

Revive's ovr_GetInstanceExtensionsVk and ovr_GetDeviceExtensionsVk always call
strncpy, including Vulkan's normal size-only query where extensionNames is
NULL. Microsoft's CRT turns that into FAST_FAIL_INVALID_ARG under Proton. Both
call sites are redirected through a tiny NULL-safe thunk in existing alignment
padding; non-NULL calls still execute Revive's original copy routine.

Revive also asks OpenVR for device extensions before ovr_GetSessionPhysicalDeviceVk
has populated its global VkPhysicalDevice. SteamVR accepts that null handle,
whereas Proton's OpenVR bridge rejects it. A second thunk skips only that early
host query; queries made after a real physical device is selected are unchanged.
"""

from hashlib import sha256
from pathlib import Path
import sys


PRISTINE_SHA256 = "ef9ffd5342bb4afad9b1c0f4fee1ca3bf32f9d3159d49dd841cc9e22f02663e4"
PREVIOUS_PATCHED_SHA256 = "54d9ec3d3cfcf43b969ca7cc5632bfb7641c7b37d4856556459dcc47020acce2"
DEVICE_QUERY_PATCHED_SHA256 = "286afb1f4b9e14f29b4d454bbd880f15b736adb1a5ff70caf3fb72083ed126fc"

# PE image base is 0x180000000. The .text section maps file offset 0x400 to
# RVA 0x1000 in the official Revive 3.2.0 LibRevive64.dll.
THUNK_OFFSET = 0x6F30
ERROR_THUNK_OFFSET = 0x83E0
INSTANCE_COPY_CALL_OFFSET = 0x9100
DEVICE_COPY_CALL_OFFSET = 0x955F
ERROR_COPY_CALL_OFFSET = 0xFBA5
DEVICE_QUERY_THUNK_OFFSET = 0x15080
DEVICE_HOST_QUERY_CALL_OFFSET = 0x9349
WAIT_GET_POSES_CALL_OFFSET = 0x4EB1

EMPTY_CAVE = bytes.fromhex("cc " * 16)
NULL_SAFE_STRNCPY_THUNK = bytes.fromhex(
    # test rcx, rcx; jz null; jmp 0x18002ef80; null: mov rax, rcx; ret
    "48 85 c9 74 05 e9 46 74 02 00 48 8b c1 c3 cc cc"
)
INSTANCE_ORIGINAL_CALL = bytes.fromhex("e8 7b 52 02 00")
INSTANCE_PATCHED_CALL = bytes.fromhex("e8 2b de ff ff")
DEVICE_ORIGINAL_CALL = bytes.fromhex("e8 1c 4e 02 00")
DEVICE_PATCHED_CALL = bytes.fromhex("e8 cc d9 ff ff")
NULL_SAFE_STRCPY_S_THUNK = bytes.fromhex(
    # test r8, r8; jz null; jmp 0x18002f448; null: *rcx=0; return 0
    "4d 85 c0 74 05 e9 5e 64 02 00 c6 01 00 31 c0 c3"
)
ERROR_ORIGINAL_CALL = bytes.fromhex("e8 9e ec 01 00")
ERROR_PATCHED_CALL = bytes.fromhex("e8 36 88 ff ff")
NULL_SAFE_DEVICE_QUERY_THUNK = bytes.fromhex(
    # test rdx,rdx; jz null; call [r10+0x140]; ret; null: xor eax,eax; ret
    "48 85 d2 74 08 41 ff 92 40 01 00 00 c3 31 c0 c3"
)
DEVICE_HOST_QUERY_ORIGINAL_CALL = bytes.fromhex("41 ff 92 40 01 00 00")
DEVICE_HOST_QUERY_PATCHED_CALL = bytes.fromhex("e8 32 bd 00 00 90 90")
WAIT_GET_POSES_ORIGINAL_CALL = bytes.fromhex("41 ff 52 10")
WAIT_GET_POSES_PATCHED_CALL = bytes.fromhex("31 c0 90 90")


def patch_at(data: bytearray, offset: int, original: bytes, patched: bytes, label: str) -> None:
    current = bytes(data[offset : offset + len(original)])
    if current == patched:
        return
    if current != original:
        raise SystemExit(
            f"unexpected bytes for {label} at file offset {offset:#x}: {current.hex(' ')}"
        )
    data[offset : offset + len(original)] = patched


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} LIBREVIVE64.DLL", file=sys.stderr)
        return 2

    dll = Path(sys.argv[1])
    original = dll.read_bytes()
    data = bytearray(original)

    already_patched = (
        bytes(data[THUNK_OFFSET : THUNK_OFFSET + 16]) == NULL_SAFE_STRNCPY_THUNK
        and bytes(data[INSTANCE_COPY_CALL_OFFSET : INSTANCE_COPY_CALL_OFFSET + 5])
        == INSTANCE_PATCHED_CALL
        and bytes(data[DEVICE_COPY_CALL_OFFSET : DEVICE_COPY_CALL_OFFSET + 5])
        == DEVICE_PATCHED_CALL
        and bytes(data[ERROR_THUNK_OFFSET : ERROR_THUNK_OFFSET + 16])
        == NULL_SAFE_STRCPY_S_THUNK
        and bytes(data[ERROR_COPY_CALL_OFFSET : ERROR_COPY_CALL_OFFSET + 5])
        == ERROR_PATCHED_CALL
        and bytes(data[DEVICE_QUERY_THUNK_OFFSET : DEVICE_QUERY_THUNK_OFFSET + 16])
        == NULL_SAFE_DEVICE_QUERY_THUNK
        and bytes(data[DEVICE_HOST_QUERY_CALL_OFFSET : DEVICE_HOST_QUERY_CALL_OFFSET + 7])
        == DEVICE_HOST_QUERY_PATCHED_CALL
        and bytes(data[WAIT_GET_POSES_CALL_OFFSET : WAIT_GET_POSES_CALL_OFFSET + 4])
        == WAIT_GET_POSES_PATCHED_CALL
    )
    if already_patched:
        print(f"already patched: {dll}")
        return 0

    actual_sha256 = sha256(original).hexdigest()
    if actual_sha256 not in {
        PRISTINE_SHA256,
        PREVIOUS_PATCHED_SHA256,
        DEVICE_QUERY_PATCHED_SHA256,
    }:
        raise SystemExit(
            "refusing to patch an unknown LibRevive64.dll: "
            f"expected pristine or previous patch, got {actual_sha256}"
        )

    patch_at(data, THUNK_OFFSET, EMPTY_CAVE, NULL_SAFE_STRNCPY_THUNK, "NULL-safe thunk")
    patch_at(
        data,
        ERROR_THUNK_OFFSET,
        EMPTY_CAVE,
        NULL_SAFE_STRCPY_S_THUNK,
        "NULL-safe error-description thunk",
    )
    patch_at(
        data,
        INSTANCE_COPY_CALL_OFFSET,
        INSTANCE_ORIGINAL_CALL,
        INSTANCE_PATCHED_CALL,
        "ovr_GetInstanceExtensionsVk",
    )
    patch_at(
        data,
        DEVICE_COPY_CALL_OFFSET,
        DEVICE_ORIGINAL_CALL,
        DEVICE_PATCHED_CALL,
        "ovr_GetDeviceExtensionsVk",
    )
    patch_at(
        data,
        ERROR_COPY_CALL_OFFSET,
        ERROR_ORIGINAL_CALL,
        ERROR_PATCHED_CALL,
        "ovr_GetLastErrorInfo",
    )
    patch_at(
        data,
        DEVICE_QUERY_THUNK_OFFSET,
        EMPTY_CAVE,
        NULL_SAFE_DEVICE_QUERY_THUNK,
        "NULL-safe VkPhysicalDevice query thunk",
    )
    patch_at(
        data,
        DEVICE_HOST_QUERY_CALL_OFFSET,
        DEVICE_HOST_QUERY_ORIGINAL_CALL,
        DEVICE_HOST_QUERY_PATCHED_CALL,
        "GetVulkanDeviceExtensionsRequired",
    )
    patch_at(
        data,
        WAIT_GET_POSES_CALL_OFFSET,
        WAIT_GET_POSES_ORIGINAL_CALL,
        WAIT_GET_POSES_PATCHED_CALL,
        "Revive WaitToBeginFrame timing",
    )

    dll.write_bytes(data)
    print(f"patched Revive 3.2.0 Vulkan size queries: {dll}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
