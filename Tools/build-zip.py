"""Builds the CurseForge zip by hand, the same as the release workflow's packager.

For when GitHub can't run the "Package and release" workflow (the account is
down): tag the release locally, then

    python -I Tools/build-zip.py v2.0.44

and upload Release/Cinematic-v2.0.44.zip on CurseForge (Files > Add File).

It packs the files committed at that tag (never the working tree, so
uncommitted work stays out), leaves out what .pkgmeta's ignore: lists and the
dot files, writes the tag into the .toc's @project-version@, and fills in
ChangelogCommits.lua the way Tools/commits.sh does in the workflow.
"""
import io
import os
import subprocess
import sys
import tarfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(*args, binary=False):
    out = subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True).stdout
    return out if binary else out.decode("utf-8")


def pkgmeta():
    """package-as name and the ignore: list, from the committed .pkgmeta."""
    name, ignore, in_ignore = "Cinematic", [], False
    for line in open(os.path.join(ROOT, ".pkgmeta"), encoding="utf-8"):
        line = line.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        if line.startswith("package-as:"):
            name = line.split(":", 1)[1].strip()
        in_ignore = line.startswith("ignore:") or (in_ignore and line.startswith(" "))
        if in_ignore and line.strip().startswith("- "):
            ignore.append(line.strip()[2:].strip().rstrip("/"))
    return name, ignore


def ignored(path, ignore):
    # Dot files and folders (.github, .claude, .pkgmeta...) never ship.
    if any(part.startswith(".") for part in path.split("/")):
        return True
    return any(path == p or path.startswith(p + "/") for p in ignore)


def changelog_commits(tag):
    """Tools/commits.sh's output, for the commits up to this tag."""
    tags = git("tag", "--list", "v*", "--merged", tag, "--sort=v:refname").split()
    ranges, prev = [], ""
    for t in tags:
        ranges.append((f"{prev}..{t}" if prev else t, t[1:]))
        prev = t
    ranges.append((f"{prev}..{tag}", "next"))  # empty when tag is the newest
    lines = [
        "-- Made by Tools/commits.sh: every commit, newest first. Don't edit by hand.",
        "local _, ns = ...",
        "ns.CHANGELOG_COMMITS = {",
    ]
    for rng, version in reversed(ranges):
        for row in git("log", "--no-merges", "--format=%as%x09%s", rng).splitlines():
            date, subject = row.split("\t", 1)
            subject = subject.replace("]==]", "] ==]")
            lines.append(f'\t{{ "{version}", "{date}", [==[{subject}]==] }},')
    lines.append("}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def main():
    if len(sys.argv) != 2 or not sys.argv[1].startswith("v"):
        sys.exit("usage: python -I Tools/build-zip.py vX.Y.Z  (a tag that exists)")
    tag = sys.argv[1]
    if tag not in git("tag", "--list", tag).split():
        sys.exit(f"no tag {tag}: tag the release first (git tag -a {tag} -m \"{tag}\")")

    name, ignore = pkgmeta()
    tar = tarfile.open(fileobj=io.BytesIO(git("archive", "--format=tar", tag, binary=True)))
    os.makedirs(os.path.join(ROOT, "Release"), exist_ok=True)
    out = os.path.join(ROOT, "Release", f"{name}-{tag}.zip")

    count, tocs = 0, []
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for m in tar.getmembers():
            if not m.isfile() or ignored(m.name, ignore):
                continue
            data = tar.extractfile(m).read()
            if m.name == "ChangelogCommits.lua":
                data = changelog_commits(tag)
            elif m.name.endswith((".toc", ".lua", ".xml")) and b"@project-version@" in data:
                data = data.replace(b"@project-version@", tag.encode())
                tocs.append(m.name)
            z.writestr(f"{name}/{m.name}", data)
            count += 1

    if f"{name}.toc" not in tocs:
        sys.exit(f"{name}.toc had no @project-version@ to fill in: check the zip")
    print(f"wrote {os.path.relpath(out, ROOT)}: {count} files, version {tag}")


if __name__ == "__main__":
    main()
