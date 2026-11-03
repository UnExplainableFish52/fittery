"""Read device-targeting metadata directly from a built AAB, without dependencies.

The compiled manifest uses aapt.pb.XmlNode/XmlElement/XmlAttribute from:
https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/tools/aapt2/Resources.proto
This reports package constraints, not the private Google Play device catalog.
"""

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile


def fields(data):
    offset = 0

    def varint():
        nonlocal offset
        value = 0
        for shift in range(0, 70, 7):
            byte = data[offset]
            offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value
        raise ValueError("Invalid protobuf varint")

    result = {}
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
            raise ValueError(f"Unsupported protobuf wire type: {wire}")
        result.setdefault(tag >> 3, []).append(value)
    return result


def element(node):
    values = fields(node)
    if 1 not in values:  # Text node.
        return None
    values = fields(values[1][0])
    attributes = {}
    for encoded in values.get(4, []):
        attribute = fields(encoded)
        attributes[attribute[2][0].decode()] = attribute.get(3, [b""])[0].decode()
    return {
        "tag": values[3][0].decode(),
        "attributes": attributes,
        "children": [child for encoded in values.get(5, []) if (child := element(encoded)) is not None],
    }


def inspect_bundle(path):
    with ZipFile(path) as bundle:
        root = element(bundle.read("base/manifest/AndroidManifest.xml"))
        if root["tag"] != "manifest":
            raise ValueError("Expected a manifest root")
        children = root["children"]
        features = [node["attributes"] for node in children if node["tag"] == "uses-feature"]
        permissions = sorted(node["attributes"]["name"] for node in children if node["tag"] == "uses-permission")
        wifi = next((feature for feature in features if feature.get("name") == "android.hardware.wifi"), None)
        application = next(node for node in children if node["tag"] == "application")
        native = {}
        for name in sorted(bundle.namelist()):
            parts = name.split("/")
            if len(parts) == 4 and parts[0:2] == ["base", "lib"] and name.endswith(".so"):
                native.setdefault(parts[2], []).append(parts[3])
        return {
            "bundle": str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "manifest": root["attributes"],
            "sdk": next(node["attributes"] for node in children if node["tag"] == "uses-sdk"),
            "permissions": permissions,
            "declared_features": features,
            "wifi_hardware_required": (wifi.get("required", "true") != "false" if wifi is not None
                                       else "android.permission.ACCESS_WIFI_STATE" in permissions),
            "screen_and_configuration_constraints": [node for node in children if node["tag"] in (
                "supports-screens", "compatible-screens", "uses-configuration", "supports-gl-texture")],
            "libraries": [node["attributes"] for node in application["children"] if node["tag"] in (
                "uses-library", "uses-native-library")],
            "native_libraries": native,
            "native_targeting_sha256": hashlib.sha256(bundle.read("base/native.pb")).hexdigest(),
            "bundle_config_sha256": hashlib.sha256(bundle.read("BundleConfig.pb")).hexdigest(),
        }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundles", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([inspect_bundle(path) for path in args.bundles], indent=2))
