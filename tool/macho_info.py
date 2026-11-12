#!/usr/bin/env python3
"""Reads the platform, minimum OS and SDK that a Mach-O binary (or a static library) records.

    python3 -I tool/macho_info.py FILE

FILE may be a thin Mach-O, a fat (universal) Mach-O, or a static library (an `ar` archive of
Mach-O objects, thin or inside a fat file). One line per distinct combination is printed:

    arch=arm64 platform=ios minos=14.0 sdk=26.2 count=1

`count` is the number of Mach-O objects with that combination (always 1 for a binary, the
object count for a static library). `sdk=n/a` means the load command does not record one (the
old LC_VERSION_MIN_* form can). Exit status: 0 = at least one Mach-O object read, 1 = FILE is
not a Mach-O/fat/ar file or has no readable load commands (the reason goes to stderr).

Read-only, standard library only, no Xcode tools: it runs on the macOS runner and on Linux, so
the same code is tested here and used by tool/verify_artifact.sh. It is evidence of what the
binary SAYS (a compiled artifact's own metadata), not an authenticated statement.
"""
import struct
import sys

FAT_MAGIC, FAT_MAGIC_64 = 0xCAFEBABE, 0xCAFEBABF
MH_MAGIC, MH_MAGIC_64 = 0xFEEDFACE, 0xFEEDFACF
LC_VERSION_MIN_MACOSX, LC_VERSION_MIN_IPHONEOS = 0x24, 0x25
LC_VERSION_MIN_TVOS, LC_VERSION_MIN_WATCHOS, LC_BUILD_VERSION = 0x2F, 0x30, 0x32

PLATFORMS = {1: "macos", 2: "ios", 3: "tvos", 4: "watchos", 5: "bridgeos", 6: "maccatalyst",
             7: "ios-simulator", 8: "tvos-simulator", 9: "watchos-simulator", 10: "driverkit",
             11: "visionos", 12: "visionos-simulator"}
MIN_COMMANDS = {LC_VERSION_MIN_MACOSX: "macos", LC_VERSION_MIN_IPHONEOS: "ios",
                LC_VERSION_MIN_TVOS: "tvos", LC_VERSION_MIN_WATCHOS: "watchos"}
CPUS = {0x0100000C: "arm64", 0x01000007: "x86_64", 0x0200000C: "arm64_32", 0x0C: "armv7",
        0x07: "i386"}
AR_MAGIC = b"!<arch>\n"


class NotMachO(Exception):
    pass


def version(v):
    """X.Y.Z nibbles of a Mach-O packed version; the patch part is shown only when not zero."""
    major, minor, patch = v >> 16, (v >> 8) & 0xFF, v & 0xFF
    return "%d.%d.%d" % (major, minor, patch) if patch else "%d.%d" % (major, minor)


def thin(data, offset=0):
    """(arch, platform, minos, sdk) of the Mach-O at data[offset:]."""
    magic = struct.unpack_from("<I", data, offset)[0]
    if magic == MH_MAGIC_64:
        header = 32
    elif magic == MH_MAGIC:
        header = 28
    else:
        raise NotMachO("not a little-endian Mach-O (magic %08x)" % magic)
    cputype, _sub, _ft, ncmds, sizeofcmds = struct.unpack_from("<iiIII", data, offset + 4)
    arch = CPUS.get(cputype & 0xFFFFFFFF, "cpu-%x" % (cputype & 0xFFFFFFFF))
    pos, end = offset + header, offset + header + sizeofcmds
    if end > len(data):
        raise NotMachO("load commands run past the end of the file")
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, pos)
        if size < 8:
            raise NotMachO("malformed load command")
        if cmd == LC_BUILD_VERSION:
            platform, minos, sdk = struct.unpack_from("<III", data, pos + 8)
            return arch, PLATFORMS.get(platform, "platform-%d" % platform), version(minos), \
                version(sdk) if sdk else "n/a"
        if cmd in MIN_COMMANDS:
            minos, sdk = struct.unpack_from("<II", data, pos + 8)
            return arch, MIN_COMMANDS[cmd], version(minos), version(sdk) if sdk else "n/a"
        pos += size
    raise NotMachO("no LC_BUILD_VERSION / LC_VERSION_MIN_* load command")


def archive_members(data, start, end):
    """Yield (offset) of every Mach-O object inside the `ar` archive data[start:end]."""
    pos = start + len(AR_MAGIC)
    while pos + 60 <= end:
        name = data[pos:pos + 16].decode("ascii", "replace").strip()
        try:
            size = int(data[pos + 48:pos + 58].decode("ascii").strip())
        except ValueError:
            raise NotMachO("malformed archive member header")
        body = pos + 60
        if name.startswith("#1/"):          # BSD long name: the name precedes the data
            body += int(name[3:])
        if body + 4 <= end and struct.unpack_from("<I", data, body)[0] in (MH_MAGIC, MH_MAGIC_64):
            yield body
        pos += 60 + size
        pos += pos & 1                      # members are 2-byte aligned


def slices(data):
    """Yield (arch_hint, offset, end) for every thin object or archive in the file."""
    if len(data) < 8:
        raise NotMachO("file too short")
    be = struct.unpack_from(">I", data, 0)[0]
    if be in (FAT_MAGIC, FAT_MAGIC_64):
        count = struct.unpack_from(">I", data, 4)[0]
        step = 20 if be == FAT_MAGIC else 32
        for i in range(count):
            base = 8 + i * step
            if be == FAT_MAGIC:
                off, size = struct.unpack_from(">II", data, base + 8)
            else:
                off, size = struct.unpack_from(">QQ", data, base + 8)
            yield off, off + size
    else:
        yield 0, len(data)


def summarize(data):
    counts = {}
    for off, end in slices(data):
        if data[off:off + len(AR_MAGIC)] == AR_MAGIC:
            offsets = list(archive_members(data, off, end))
            if not offsets:
                raise NotMachO("archive without Mach-O objects")
        else:
            offsets = [off]
        for o in offsets:
            key = thin(data, o)
            counts[key] = counts.get(key, 0) + 1
    if not counts:
        raise NotMachO("no Mach-O object found")
    return counts


def main(argv):
    if len(argv) != 2:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    try:
        with open(argv[1], "rb") as f:
            data = f.read()
        counts = summarize(data)
    except (OSError, NotMachO, struct.error) as e:
        print("macho_info: %s: %s" % (argv[1], e), file=sys.stderr)
        return 1
    for (arch, platform, minos, sdk), n in sorted(counts.items()):
        print("arch=%s platform=%s minos=%s sdk=%s count=%d" % (arch, platform, minos, sdk, n))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
