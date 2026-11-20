#!/usr/bin/env python3
"""Validates the unsigned archive that the hosted iOS signing job receives from the build job
(Issue #71, docs/IOS_HOSTED_SIGNING.md section 2.1).

The archive was produced by a job that ran third-party code (Flutter, CocoaPods, Xcode build
scripts). The signing job holds the Apple API key, so it must never extract such an archive
unchecked. Two commands, both READ-ONLY and credential-free:

    python3 -I tool/validate_handover_archive.py list TAR [--top Runner.xcarchive]
        BEFORE extraction. Reads the member list of an uncompressed tar and SIMULATES the tree that
        extraction would create, the way macOS creates it: names are compared case-insensitively and
        after Unicode normalization (APFS), because `a` and `A`, or `e` with a combining accent and the
        precomposed letter, are ONE file there. It refuses:
          - an absolute or `..` name, a name outside the one top-level directory, control characters,
            NUL or backslashes in a name;
          - a name that is the same as an earlier one once case and normalization are ignored;
          - a member whose path runs THROUGH a symbolic link (so extraction never writes through one);
          - a symbolic link whose target is absolute, or which, resolved PHYSICALLY in the simulated tree
            (following every other link, in the final state, `..` included), leaves the top-level directory
            or loops. (A lexical check is not enough: `d -> .` and `E -> d/..` each look contained, yet `E`
            is the parent of the archive.)
          - a hard link to anything but an earlier regular file inside the archive;
          - every member type except regular file, directory, symbolic link and hard link (so no device,
            FIFO, sparse or contiguous member), a set-id or sticky bit, and archives beyond the member and
            size limits.
        Symbolic links that stay inside the archive are accepted: nothing shows that a genuine iOS archive
        has none (the diagnostics did not record links), and rejecting them would risk stopping a genuine run.

    python3 -I tool/validate_handover_archive.py tree DIR
        AFTER extraction. Walks the extracted tree without following links and refuses: a special
        file (device, FIFO, socket), a set-id or sticky bit, and any symbolic link whose fully
        resolved target (by the real filesystem) is not inside DIR. This is the backstop for whatever the
        simulation could not foresee (a difference between how Python's tarfile and the system tar read a
        crafted archive, a filesystem rule not modelled).

Exit 0: nothing was refused. Exit 1: at least one refusal (each is printed). Exit 2: wrong use.
It extracts nothing, writes nothing and runs no other program.
"""
import argparse
import os
import stat
import sys
import tarfile
import unicodedata
from collections import deque

sys.dont_write_bytecode = True

MAX_MEMBERS = 200000
MAX_BYTES = 6 * 1024 ** 3
SETID_MASK = 0o7000  # setuid, setgid, sticky
MAX_LINK_HOPS = 40
MAX_STEPS = 4000


def fold(s):
    """The name as an APFS (case-insensitive, normalization-insensitive) volume compares it. Deliberately a little
    stricter than APFS (full case folding): over-matching only refuses more."""
    n = unicodedata.normalize("NFD", s)
    return unicodedata.normalize("NFD", n.casefold())


def bad_text(s):
    return (not s) or "\x00" in s or "\\" in s or any(ord(c) < 0x20 or ord(c) == 0x7F for c in s)


def resolve_link(nodes, base, target):
    """Resolves `target` PHYSICALLY from the directory `base` (a tuple of folded components, the first being the
    top-level directory) in the simulated tree, following every symbolic link. None when it stays inside; otherwise
    the reason."""
    stack = list(base)
    work = deque(target.split("/"))
    steps = hops = 0
    while work:
        c = work.popleft()
        if c in ("", "."):
            continue
        steps += 1
        if steps > MAX_STEPS:
            return "is too deep or loops"
        if c == "..":
            if len(stack) <= 1:
                return "leaves the top-level directory"
            stack.pop()
            continue
        stack.append(fold(c))
        node = nodes.get(tuple(stack))
        if node is not None and node["kind"] == "symlink":
            stack.pop()
            hops += 1
            if hops > MAX_LINK_HOPS:
                return "is a chain or loop of symbolic links"
            work.extendleft(reversed(node["target"].split("/")))
    return None


def refusals_for_list(path, top, max_members=MAX_MEMBERS, max_bytes=MAX_BYTES):
    bad = []
    nodes = {}
    ftop = fold(top)
    total = 0
    count = 0
    nlinks = 0
    try:
        tf = tarfile.open(path, "r:")  # uncompressed only: no decompression bomb, no format guessing
    except (tarfile.TarError, OSError) as e:
        return ["cannot read %s as an uncompressed tar: %s" % (path, e)]
    with tf:
        try:
            for m in tf:
                count += 1
                if count > max_members:
                    bad.append("more than %d members" % max_members)
                    break
                name = m.name
                where = repr(name)
                if bad_text(name):
                    bad.append("%s: empty name, control character, NUL or backslash in the name" % where)
                    continue
                if name.startswith("/"):
                    bad.append("%s: absolute member name" % where)
                    continue
                parts = name.rstrip("/").split("/")
                if any(p in ("", ".", "..") for p in parts):
                    bad.append("%s: empty, '.' or '..' component in the name" % where)
                    continue
                if parts[0] != top:
                    bad.append("%s: not inside the single top-level directory '%s'" % (where, top))
                    continue
                key = tuple(fold(p) for p in parts)
                # a path that runs THROUGH a symbolic link would be written through it
                through = next(("/".join(parts[:i]) for i in range(1, len(key)) if nodes.get(key[:i], {}).get("kind") == "symlink"), None)
                if through:
                    bad.append("%s: the path runs through the symbolic link %s (names compared ignoring case and normalization)" % (where, through))
                    continue
                notdir = next(("/".join(parts[:i]) for i in range(1, len(key)) if nodes.get(key[:i], {}).get("kind") in ("file", "hardlink")), None)
                if notdir:
                    bad.append("%s: its parent %s is not a directory" % (where, notdir))
                    continue
                old = nodes.get(key)
                if old is not None and not (m.isdir() and old["kind"] == "dir"):
                    bad.append("%s: the same name as %s once case and Unicode normalization are ignored (one file on macOS)" % (where, repr(old["name"])))
                    continue
                if m.mode & SETID_MASK:
                    bad.append("%s: set-id or sticky bit (mode %o)" % (where, m.mode))
                for i in range(1, len(key)):  # parents that the archive does not list are created implicitly
                    nodes.setdefault(key[:i], {"kind": "dir", "name": "/".join(parts[:i])})
                if m.type in (tarfile.REGTYPE, tarfile.AREGTYPE):
                    nodes[key] = {"kind": "file", "name": name}
                    total += m.size
                    if total > max_bytes:
                        bad.append("regular files add up to more than %d bytes" % max_bytes)
                        break
                elif m.isdir():
                    nodes[key] = {"kind": "dir", "name": name}
                elif m.issym():
                    target = m.linkname
                    if bad_text(target):
                        bad.append("%s: symbolic link with an empty or unsafe target" % where)
                    elif target.startswith("/"):
                        bad.append("%s: symbolic link to the absolute path %r" % (where, target))
                    else:
                        nodes[key] = {"kind": "symlink", "name": name, "target": target}
                        nlinks += 1
                elif m.islnk():
                    target = m.linkname
                    tparts = target.split("/") if target else []
                    tkey = tuple(fold(p) for p in tparts)
                    if (bad_text(target) or target.startswith("/") or any(p in ("", ".", "..") for p in tparts)
                            or tparts[0] != top or nodes.get(tkey, {}).get("kind") != "file"
                            or any(nodes.get(tkey[:i], {}).get("kind") == "symlink" for i in range(1, len(tkey)))):
                        bad.append("%s: hard link to %r, which is not an earlier regular file inside '%s'" % (where, target, top))
                    else:
                        nodes[key] = {"kind": "hardlink", "name": name}
                else:
                    bad.append("%s: not a regular file, directory or link (type %r)" % (where, m.type))
        except (tarfile.TarError, OSError, EOFError) as e:
            bad.append("the tar is damaged or unreadable: %s" % e)
    if count == 0:
        bad.append("the tar is empty")
    elif (ftop,) not in nodes:
        bad.append("the top-level directory '%s' is missing" % top)
    # the FINAL state: every link resolved physically in the whole simulated tree (a link may point at a link that is
    # created later, and a later member can change where an earlier link leads)
    for key, node in nodes.items():
        if node["kind"] == "symlink":
            why = resolve_link(nodes, key[:-1], node["target"])
            if why:
                bad.append("%s: symbolic link to %r %s" % (repr(node["name"]), node["target"], why))
    if not bad:
        print("validate_handover_archive list: OK (%d members, %d bytes of files, %d symbolic links, all contained)" % (count, total, nlinks))
    return bad


def refusals_for_tree(root):
    bad = []
    root_real = os.path.realpath(root)
    if not os.path.isdir(root):
        return ["%s is not a directory" % root]
    n = 0
    links = 0
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in dirnames + filenames:
            full = os.path.join(dirpath, name)
            n += 1
            try:
                st = os.lstat(full)
            except OSError as e:
                bad.append("%s: cannot be read (%s)" % (full, e))
                continue
            rel = os.path.relpath(full, root)
            if stat.S_ISLNK(st.st_mode):
                links += 1
                target = os.readlink(full)
                if os.path.isabs(target):
                    bad.append("%s: symbolic link to the absolute path %r" % (rel, target))
                    continue
                real = os.path.realpath(full)
                if not (real == root_real or real.startswith(root_real + os.sep)):
                    bad.append("%s: symbolic link to %r resolves outside the archive (%s)" % (rel, target, real))
            elif stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode):
                if st.st_mode & SETID_MASK:
                    bad.append("%s: set-id or sticky bit (mode %o)" % (rel, st.st_mode & 0o7777))
            else:
                bad.append("%s: special file (not a regular file, directory or link)" % rel)
    if not bad:
        print("validate_handover_archive tree: OK (%d entries, %d symbolic links, all inside the archive)" % (n, links))
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    pl = sub.add_parser("list", help="check the member list of the tar BEFORE extraction")
    pl.add_argument("tar")
    pl.add_argument("--top", default="Runner.xcarchive")
    pl.add_argument("--max-members", type=int, default=MAX_MEMBERS)
    pl.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    pt = sub.add_parser("tree", help="check the extracted tree AFTER extraction")
    pt.add_argument("dir")
    args = ap.parse_args(argv)
    if args.cmd == "list":
        bad = refusals_for_list(args.tar, args.top, args.max_members, args.max_bytes)
    else:
        bad = refusals_for_tree(args.dir)
    for b in bad[:30]:
        print("REFUSED: %s" % b)
    if len(bad) > 30:
        print("REFUSED: ... and %d more" % (len(bad) - 30))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
