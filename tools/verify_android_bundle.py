"""Inspect a release AAB's 64-bit ELF and APK-packaging page alignment.

Uses only Python's standard library. This checks the artifact, not runtime
behavior on a 16 KB Android device or Google Play policy acceptance.
BundleConfig fields: google/bundletool/src/main/proto/config.proto.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
from zipfile import ZipFile


def protobuf_fields(data):
    offset = 0

    def varint():
        nonlocal offset
        value = 0
        for shift in range(0, 70, 7):
            byte = data[offset]
            offset += 1
            value |= (byte & 0x7F) << shift
            if byte < 128:
                return value
        raise ValueError("Invalid protobuf varint")

    fields = {}
    while offset < len(data):
        tag = varint()
        wire = tag & 7
        if wire == 0:
            value = varint()
        elif wire in (1, 2, 5):
            size = varint() if wire == 2 else (8 if wire == 1 else 4)
            value = data[offset:offset + size]
            offset += size
            if len(value) != size:
                raise ValueError("Truncated protobuf field")
        else:
            raise ValueError(f"Unsupported protobuf wire type {wire}")
        fields[tag >> 3] = value
    return fields


def inspect_bundle(path):
    libraries = []
    with ZipFile(path) as bundle:
        config = protobuf_fields(bundle.read("BundleConfig.pb"))
        optimizations = protobuf_fields(config[2])
        native = protobuf_fields(optimizations[2])
        alignment = native.get(2, 0)
        if native.get(1) != 1 or alignment not in (2, 3):
            raise ValueError("Bundle does not request 16 KB or greater native ZIP alignment")
        for name in sorted(bundle.namelist()):
            if not name.endswith(".so") or not any(
                f"/lib/{abi}/" in name for abi in ("arm64-v8a", "x86_64")
            ):
                continue
            elf = bundle.read(name)
            if elf[:6] != b"\x7fELF\x02\x01":
                raise ValueError(f"Expected little-endian ELF64: {name}")
            phoff = struct.unpack_from("<Q", elf, 32)[0]
            entry_size, count = struct.unpack_from("<HH", elf, 54)
            loads = []
            headers = [
                struct.unpack_from("<IIQQQQQQ", elf, phoff + index * entry_size)
                for index in range(count)
            ]
            for kind, _, offset, address, _, _, memory_size, page in headers:
                if kind == 1:  # PT_LOAD
                    if page < 16384 or offset % page != address % page:
                        raise ValueError(f"Unaligned load segment: {name}")
                    loads.append(page)
                elif kind == 0x6474E552:
                    end = address + memory_size
                    protected_end = (end + 16383) // 16384 * 16384
                    # An isolated RELRO LOAD can end within a page, provided
                    # rounding protection up cannot cover subsequent writable data.
                    if any(
                        h[0] == 1 and h[1] & 2
                        and max(end, h[3]) < min(protected_end, h[3] + h[6])
                        for h in headers
                    ):
                        raise ValueError(f"RELRO protection overlaps writable data: {name}")
            if not loads:
                raise ValueError(f"No load segments found: {name}")
            libraries.append({"path": name, "minimum_load_alignment": min(loads)})
    if not libraries:
        raise ValueError("No 64-bit native libraries found")
    return {
        "bundle": str(path),
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "native_zip_alignment": "PAGE_ALIGNMENT_16K" if alignment == 2 else "PAGE_ALIGNMENT_64K",
        "libraries": libraries,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect_bundle(args.bundle), indent=2))
