#!/usr/bin/env python3
"""Validates the unsigned archive that the hosted iOS signing job receives from the build job
(Issue #71, docs/IOS_HOSTED_SIGNING.md section 2.3).

The archive was produced by a job that ran third-party code (Flutter, CocoaPods, Xcode build
scripts). The signing job holds the Apple API key, so it must never extract such an archive
unchecked. Two commands, both READ-ONLY and credential-free:

    python3 -I tool/validate_handover_archive.py list TAR [--top Runner.xcarchive]
        BEFORE extraction. Reads the member list of an uncompressed tar and refuses:
        an absolute or `..` member name, a name outside the one top-level directory, control
        characters or backslashes in a name, a duplicate name, a member that is not a regular file,
        a directory, a symbolic link or a hard link, a set-id or sticky bit, a symbolic link whose
        target is absolute or leaves the top-level directory, a hard link to anything but an earlier
        regular file inside it, a member whose path runs THROUGH an earlier symbolic link, and an
        archive beyond the member and size limits.

    python3 -I tool/validate_handover_archive.py tree DIR
        AFTER extraction. Walks the extracted tree without following links and refuses: a special
        file (device, FIFO, socket), a set-id or sticky bit, and any symbolic link whose fully
        resolved target is not inside DIR (an absolute target, a `..` escape, a loop or a chain).

Exit 0: nothing was refused. Exit 1: at least one refusal (each is printed). Exit 2: wrong use.
It extracts nothing, writes nothing and runs no other program.
"""
import argparse
import os
import posixpath
import stat
import sys
import tarfile

sys.dont_write_bytecode = True

MAX_MEMBERS = 200000
MAX_BYTES = 6 * 1024 ** 3
SETID_MASK = 0o7000  # setuid, setgid, sticky


def refusals_for_list(path, top, max_members=MAX_MEMBERS, max_bytes=MAX_BYTES):
    bad = []
    seen = {}
    symlinks = set()
    total = 0
    count = 0
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
                if not name or "\x00" in name or any(ord(c) < 0x20 or ord(c) == 0x7F for c in name) or "\\" in name:
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
                norm = "/".join(parts)
                if norm in seen:
                    bad.append("%s: duplicate member name" % where)
                    continue
                # a path that runs THROUGH an earlier symbolic link would be written through it
                for i in range(1, len(parts)):
                    if "/".join(parts[:i]) in symlinks:
                        bad.append("%s: the path runs through the symbolic link %s" % (where, "/".join(parts[:i])))
                        break
                if m.mode & SETID_MASK:
                    bad.append("%s: set-id or sticky bit (mode %o)" % (where, m.mode))
                if m.isreg():
                    seen[norm] = "file"
                    total += m.size
                    if total > max_bytes:
                        bad.append("regular files add up to more than %d bytes" % max_bytes)
                        break
                elif m.isdir():
                    seen[norm] = "dir"
                elif m.issym():
                    seen[norm] = "symlink"
                    symlinks.add(norm)
                    target = m.linkname
                    if not target or "\x00" in target or "\\" in target or any(ord(c) < 0x20 for c in target):
                        bad.append("%s: symbolic link with an empty or unsafe target" % where)
                    elif target.startswith("/"):
                        bad.append("%s: symbolic link to the absolute path %r" % (where, target))
                    else:
                        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(norm), target))
                        if not (resolved == top or resolved.startswith(top + "/")):
                            bad.append("%s: symbolic link to %r, which leaves '%s'" % (where, target, top))
                elif m.islnk():
                    seen[norm] = "hardlink"
                    target = m.linkname
                    tparts = target.split("/") if target else []
                    if (not target or target.startswith("/") or any(p in ("", ".", "..") for p in tparts)
                            or tparts[0] != top or "/".join(tparts) not in seen
                            or seen["/".join(tparts)] != "file"):
                        bad.append("%s: hard link to %r, which is not an earlier regular file inside '%s'" % (where, target, top))
                else:
                    bad.append("%s: not a regular file, directory or link (type %r)" % (where, m.type))
        except (tarfile.TarError, OSError, EOFError) as e:
            bad.append("the tar is damaged or unreadable: %s" % e)
    if count == 0:
        bad.append("the tar is empty")
    if top not in {n.split("/")[0] for n in seen} and count:
        bad.append("the top-level directory '%s' is missing" % top)
    if not bad:
        print("validate_handover_archive list: OK (%d members, %d bytes of files, %d symbolic links)" % (count, total, len(symlinks)))
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
