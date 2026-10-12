#!/usr/bin/env python3
"""
ci/compare_binaries.py — DiskDude original vs rebuilt comparison suite.

Runs on GitHub Actions macOS runners (python3, no third-party deps).
Compares:
  1. Bundle structure + resource hashes (Info.plist, PkgInfo, AppIcon.icns)
  2. Mach-O fat layout (slices, load commands, segments, sections)
  3. Swift reflection metadata sizes (__swift5_* sections)
  4. String inventory (coverage both ways)
Outputs a JSON report + GitHub step summary. Exit 0 unless --strict.
"""
import hashlib
import json
import os
import struct
import subprocess
import sys

ORIG_APP = sys.argv[1] if len(sys.argv) > 1 else "original/DiskDude.app"
BUILT_APP = sys.argv[2] if len(sys.argv) > 2 else "build/DiskDude.app"
OUT = sys.argv[3] if len(sys.argv) > 3 else "comparison-report.json"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def bundle_files(app):
    out = {}
    for root, _, names in os.walk(app):
        for n in names:
            p = os.path.join(root, n)
            rel = os.path.relpath(p, app)
            if rel.startswith("Contents/_CodeSignature"):
                continue  # codesign artifacts differ by design
            out[rel] = {"sha256": sha256(p), "bytes": os.path.getsize(p)}
    return out


def parse_fat(data):
    magic = struct.unpack(">I", data[:4])[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        nfat = struct.unpack(">I", data[4:8])[0]
        slices = []
        off = 8
        for _ in range(nfat):
            cpu, sub, fo, sz, al = struct.unpack(">IIIII", data[off:off + 20])
            slices.append({"cputype": cpu, "offset": fo, "size": sz})
            off += 20
        return slices
    return [{"cputype": "single", "offset": 0, "size": len(data)}]


def parse_macho(data, base=0):
    magic = struct.unpack("<I", data[base:base + 4])[0]
    if magic != 0xFEEDFACF:
        return None
    _magic, cputype, _cpusub, _ftype, ncmds, _szcmds, flags, _res = struct.unpack(
        "<IiiIIIII", data[base:base + 32])
    info = {"cputype": cputype, "ncmds": ncmds, "flags": hex(flags),
            "segments": [], "sections": [], "lcs": {}}
    p = base + 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", data[p:p + 8])
        info["lcs"][hex(cmd)] = info["lcs"].get(hex(cmd), 0) + 1
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = data[p + 8:p + 24].rstrip(b"\0").decode(errors="replace")
            vmaddr, vmsize, fileoff, filesize = struct.unpack("<QQQQ", data[p + 24:p + 56])
            nsects, _flags2 = struct.unpack("<II", data[p + 56:p + 64])
            info["segments"].append({"name": segname, "vmsize": vmsize, "filesize": filesize})
            q = p + 72
            for _ in range(nsects):
                sn = data[q:q + 16].rstrip(b"\0").decode(errors="replace")
                sg = data[q + 16:q + 32].rstrip(b"\0").decode(errors="replace")
                size = struct.unpack("<Q", data[q + 64:q + 72])[0]
                info["sections"].append(f"{sg},{sn}:{size}")
                q += 80
        p += cmdsize
    return info


def swift5_sizes(info):
    out = {}
    for sec in info["sections"]:
        name, size = sec.rsplit(":", 1)
        if "__swift5" in name:
            out[name] = int(size)
    return out


def cstrings_via_tool(path):
    try:
        r = subprocess.run(["strings", "-a", path], capture_output=True, text=True, timeout=120)
        return [s for s in r.stdout.split("\n") if s.strip()]
    except Exception:
        return []


def app_owned(s):
    """UI-grade string: readable English-ish text, not mangled/symbol noise."""
    if len(s) < 5 or len(s) > 120:
        return False
    if s.startswith(("_", "$s", "@", "GCC", "rust", "Xcode", "libswift", "swift_",
                     "NSObject", "OS_", "NSString", "/Library", "/usr", ".")):
        return False
    # require mostly-printable word characters with spaces/punctuation
    alpha = sum(c.isalpha() for c in s)
    if alpha < max(3, len(s) // 3):
        return False
    if not all(c.isalnum() or c in " .,!?'\"…()/-&%:;_+~@#*$" for c in s):
        return False
    # reject strings that look like hex/base64 garbage
    words = s.split()
    if words and all(w.isupper() or (len(w) in (2, 4) and all(c in "0123456789abcdefABCDEF" for c in w)) for w in words):
        return False
    return True


def main():
    report = {"original": ORIG_APP, "rebuilt": BUILT_APP, "checks": {}}

    orig_bin = os.path.join(ORIG_APP, "Contents/MacOS/DiskDude")
    built_bin = os.path.join(BUILT_APP, "Contents/MacOS/DiskDude")

    ob, bb = bundle_files(ORIG_APP), bundle_files(BUILT_APP)
    report["checks"]["bundle"] = {
        "identical": sorted(k for k in ob.keys() & bb.keys() if ob[k]["sha256"] == bb[k]["sha256"]),
        "differing": sorted(k for k in ob.keys() & bb.keys() if ob[k]["sha256"] != bb[k]["sha256"]),
        "missing_in_rebuilt": sorted(ob.keys() - bb.keys()),
        "extra_in_rebuilt": sorted(bb.keys() - ob.keys()),
    }

    if not os.path.exists(built_bin):
        report["checks"]["macho"] = {"error": "rebuilt binary missing"}
        json.dump(report, open(OUT, "w"), indent=2)
        print("rebuilt binary missing — report written")
        sys.exit(0)

    od, bd = open(orig_bin, "rb").read(), open(built_bin, "rb").read()
    report["checks"]["macho"] = {
        "original_bytes": len(od), "rebuilt_bytes": len(bd),
        "byte_identical": od == bd,
        "sha256_original": hashlib.sha256(od).hexdigest(),
        "sha256_rebuilt": hashlib.sha256(bd).hexdigest(),
    }

    oslices, bslices = parse_fat(od), parse_fat(bd)
    per_slice = []
    for osl, bsl in zip(oslices, bslices):
        oi = parse_macho(od, osl["offset"])
        bi = parse_macho(bd, bsl["offset"])
        if oi is None or bi is None:
            continue
        per_slice.append({
            "cputype": osl.get("cputype"),
            "sections_match": oi["sections"] == bi["sections"],
            "n_sections_orig": len(oi["sections"]),
            "n_sections_rebuilt": len(bi["sections"]),
            "segments_orig": [s["name"] for s in oi["segments"]],
            "segments_rebuilt": [s["name"] for s in bi["segments"]],
            "lcs_orig": oi["lcs"], "lcs_rebuilt": bi["lcs"],
            "swift5_orig": swift5_sizes(oi), "swift5_rebuilt": swift5_sizes(bi),
        })
    report["checks"]["slices"] = per_slice

    ostr = set(cstrings_via_tool(orig_bin))
    bstr = set(cstrings_via_tool(built_bin))
    oa = {s for s in ostr if app_owned(s)}
    ba = {s for s in bstr if app_owned(s)}
    report["checks"]["strings"] = {
        "original_total": len(ostr), "rebuilt_total": len(bstr),
        "original_app_owned_count": len(oa), "rebuilt_app_owned_count": len(ba),
        "missing_in_rebuilt": sorted(oa - ba),
        "extra_in_rebuilt": sorted(ba - oa),
        "coverage_pct": round(100 * len(oa & ba) / max(1, len(oa)), 1),
    }

    json.dump(report, open(OUT, "w"), indent=2)

    b = report["checks"]["bundle"]
    s = report["checks"]["strings"]
    m = report["checks"]["macho"]
    lines = [
        "## DiskDude — Original vs Rebuilt Comparison", "",
        f"- Mach-O: original {m['original_bytes']:,} B vs rebuilt {m['rebuilt_bytes']:,} B — "
        f"{'**BYTE-IDENTICAL** ✅' if m['byte_identical'] else 'differs ⚠️'}",
        f"- Bundle: {len(b['identical'])} identical / {len(b['differing'])} differing / "
        f"{len(b['missing_in_rebuilt'])} missing / {len(b['extra_in_rebuilt'])} extra files",
        f"- Strings: **{s['coverage_pct']}%** of original app-owned strings present "
        f"({len(oa & ba)}/{len(oa)})",
        f"- Missing strings ({len(s['missing_in_rebuilt'])}):",
    ] + [f"  - {x!r}" for x in s["missing_in_rebuilt"][:40]]
    summary = "\n".join(lines)
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(summary + "\n")

    if "--strict" in sys.argv and not m["byte_identical"]:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
