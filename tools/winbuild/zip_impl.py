"""Enough of Info-ZIP's `zip` for scripts/build_android.sh, on Windows.

Git for Windows ships unzip but not zip, which is the one tool standing between
a Windows checkout and a local Android build.  Rather than fetching a binary
from somewhere unaudited, this covers exactly the two forms the build script
uses and refuses anything it does not understand, so a future flag fails loudly
instead of silently producing a wrong archive:

    zip -q -9 -r out.love main.lua src data -x '*.DS_Store' -x 'data/generated/*'
    zip -q out.love src/core/Version.lua        # add or replace one entry

Paths are stored relative to the working directory with forward slashes, and
directories are walked in sorted order so the archive is reproducible.
"""
import fnmatch
import os
import sys
import zipfile


def excluded(name, patterns):
    # zip's wildcards cross directory separators, which is also what fnmatch
    # does, so the build script's '*/.git/*' behaves the same either way.
    return any(fnmatch.fnmatch(name, pattern) for pattern in patterns)


def collect(paths, patterns):
    """-> archive-relative names, in a stable order."""
    names = []
    for path in paths:
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs.sort()
                for f in sorted(files):
                    full = os.path.join(root, f)
                    name = os.path.relpath(full, ".").replace(os.sep, "/")
                    if not excluded(name, patterns):
                        names.append(name)
        elif os.path.isfile(path):
            name = os.path.relpath(path, ".").replace(os.sep, "/")
            if not excluded(name, patterns):
                names.append(name)
        else:
            sys.stderr.write("zip: %s not found\n" % path)
            return None
    return names


def main(argv):
    patterns, paths, archive = [], [], None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "-x":
            # Info-ZIP accepts one -x followed by several patterns, which is how
            # pack_love.sh and build.sh write their excludes.  Consume every
            # following non-flag argument as a pattern; paths always come before
            # -x in those scripts, so this does not steal archive members.
            i += 1
            if i >= len(argv) or argv[i].startswith("-"):
                sys.stderr.write("zip: -x needs a pattern\n")
                return 2
            while i < len(argv) and not argv[i].startswith("-"):
                patterns.append(argv[i])
                i += 1
            continue
        elif arg in ("-q", "-9", "-r", "-X", "-o"):
            pass  # quiet, compression level, recurse, no-extra, ordering
        elif arg.startswith("-"):
            sys.stderr.write("zip shim: unsupported flag %s\n" % arg)
            return 2
        elif archive is None:
            archive = arg
        else:
            paths.append(arg)
        i += 1

    if archive is None or not paths:
        sys.stderr.write("usage: zip [-q9r] [-x pat] archive path...\n")
        return 2

    names = collect(paths, patterns)
    if names is None:
        return 1

    # Adding to an existing archive means rewriting it: zipfile can append, but
    # appending a name that is already in there leaves both copies and readers
    # disagree about which one wins.  The version stamp does exactly that.
    keep = []
    if os.path.exists(archive):
        replacing = set(names)
        with zipfile.ZipFile(archive, "r") as old:
            for info in old.infolist():
                if info.filename not in replacing:
                    keep.append((info, old.read(info.filename)))

    tmp = archive + ".shimtmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for info, data in keep:
            out.writestr(info, data)
        for name in names:
            out.write(name, name)

    if os.path.exists(archive):
        os.remove(archive)
    os.rename(tmp, archive)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
