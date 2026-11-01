#!/usr/bin/env python3
"""Register Swift source files in ARIA.xcodeproj/project.pbxproj.

The pbxproj is hand-maintained (never run xcodegen). For each repo-relative path this adds:
  1. a PBXBuildFile            "<build_id> /* Name.swift in Sources */"
  2. a PBXFileReference        "<ref_id> /* Name.swift */"
  3. a child of the PBXGroup whose `path = <parent dir>;` matches (must be unique)
  4. an entry in the ARIA target's Sources phase (55CA12502415B19B5140E021)
IDs are deterministic (md5 of the path), so re-running is a no-op.

Usage:
  python3 scripts/pbxproj-add-swift.py ARIA/Services/DeviceEventQueue.swift [...]
  python3 scripts/pbxproj-add-swift.py --self-test
"""
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBX = ROOT / "ARIA.xcodeproj" / "project.pbxproj"
ARIA_SOURCES_PHASE = "55CA12502415B19B5140E021"

GROUP_RE = re.compile(
    r"(\t\t[0-9A-F]{24} /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)(.*?)(\t\t\t\);\n)(.*?\n\t\t\};)",
    re.S,
)


def ids_for(rel: str) -> tuple[str, str]:
    ref = hashlib.md5(rel.encode()).hexdigest().upper()[:24]
    build = hashlib.md5((rel + "#build").encode()).hexdigest().upper()[:24]
    return ref, build


def add(text: str, rel: str) -> str:
    path = pathlib.PurePosixPath(rel)
    name, parent = path.name, path.parent.name
    ref_id, build_id = ids_for(rel)
    if ref_id in text:
        return text

    groups = [m for m in GROUP_RE.finditer(text) if f"\t\t\tpath = {parent};\n" in m.group(4)]
    if len(groups) != 1:
        raise SystemExit(f"{rel}: expected exactly one PBXGroup with path = {parent}; found {len(groups)}")
    g = groups[0]
    text = text[: g.start(3)] + f"\t\t\t\t{ref_id} /* {name} */,\n" + text[g.start(3):]

    phase_hdr = (f"\t\t{ARIA_SOURCES_PHASE} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n"
                 f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n")
    if phase_hdr not in text:
        raise SystemExit("ARIA Sources phase header not found")
    text = text.replace(phase_hdr, phase_hdr + f"\t\t\t\t{build_id} /* {name} in Sources */,\n", 1)

    build_line = f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n"
    ref_line = (f"\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
                f'path = {name}; sourceTree = "<group>"; }};\n')
    for marker, line in (("/* Begin PBXBuildFile section */\n", build_line),
                         ("/* Begin PBXFileReference section */\n", ref_line)):
        if marker not in text:
            raise SystemExit(f"missing section marker {marker.strip()}")
        text = text.replace(marker, marker + line, 1)
    return text


def self_test() -> None:
    text = PBX.read_text()
    probes = ["ARIA/Services/ZZProbe.swift", "ARIA/Models/ZZProbe2.swift", "ARIA/Intents/ZZProbe3.swift"]
    for rel in probes:
        text = add(text, rel)
    assert add(text, probes[0]) == text, "re-adding must be a no-op"
    for rel in probes:
        ref_id, build_id = ids_for(rel)
        assert text.count(ref_id) == 3, f"{rel}: fileRef should appear 3x (ref, buildfile, group)"
        assert text.count(build_id) == 2, f"{rel}: build id should appear 2x (buildfile, phase)"
    print("self-test OK; real project untouched")


def main(argv: list[str]) -> None:
    if argv == ["--self-test"]:
        self_test()
        return
    if not argv:
        raise SystemExit(__doc__)
    text = PBX.read_text()
    for rel in argv:
        if not (ROOT / rel).exists():
            raise SystemExit(f"{rel}: file does not exist (create it first)")
        text = add(text, rel)
        print(f"registered {rel}")
    PBX.write_text(text)


if __name__ == "__main__":
    main(sys.argv[1:])
