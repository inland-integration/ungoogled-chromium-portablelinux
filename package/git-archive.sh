#!/bin/bash

set -e
set -C

function cleanup() {
    rm -f $TMPFILE
    rm -f $TMPLIST
    rm -f $TOARCHIVE
}

PROGRAM="git-archive"
FORMAT="tar"
EXTENSION="zst"
COMPRESSOR="zstd"
ARCHIVE_OPTS=""
COMP_OPTS="-T0"
TREEISH="HEAD"
OLD_PWD="$(realpath $(pwd))"
TMPDIR="${TMPDIR:-/tmp}"
TMPFILE=`mktemp "$TMPDIR/$PROGRAM.XXXXXX"` # Create a place to store our work's progress
TMPLIST=`mktemp "$TMPDIR/$PROGRAM.submodules.XXXXXX"`
TOARCHIVE=`mktemp "$TMPDIR/$PROGRAM.toarchive.XXXXXX"`
OUT_FILE="$(realpath $OLD_PWD/..)"

trap 'cleanup' QUIT EXIT

if [ ! -d ".git" ]; then
    echo "cannot find .git directory" >&2
    exit 1
fi
BASENAME="${BASENAME:-$(basename $(pwd))}"
TAG=$(git tag --points-at HEAD | head -n 1)
HASH=$(git rev-parse HEAD)
if [ -z "$TAG" -a -z "$HASH" ]; then
    echo "cannot find tag or hash" >&2
    exit 1
fi

if [ "$1" = "hash" ]; then
    TAG=
fi

if [ -z "$PREFIX" ]; then
    if [ -n "$TAG" ]; then
        TAG=$(echo $TAG | sed -e "s/^v//")
        PREFIX=$(echo $BASENAME-$TAG | sed -e "s/$BASENAME-$BASENAME-/$BASENAME-/" -e "s/-release\$//")
    else
        PREFIX="$BASENAME-$HASH"
    fi
fi
OUT_FILE="$OUT_FILE/$PREFIX.tar.$EXTENSION"

# Create the superproject's git-archive
TMPNAME="$TMPDIR/$BASENAME.$FORMAT"
echo "creating superproject archive"
rm -f $TMPNAME
git archive --format=$FORMAT --prefix="$PREFIX/" $ARCHIVE_OPTS $TREEISH > $TMPNAME

echo $TMPNAME >| $TMPFILE # clobber on purpose
superfile=`head -n 1 $TMPFILE`

echo "looking for subprojects"
# find all '.git' dirs, these show us the remaining to-be-archived dirs
# we only want directories that are below the current directory
find . -mindepth 2 -name '.git' -type d -print | sed -e 's/^\.\///' -e 's/\.git$//' >> $TOARCHIVE
# as of version 1.7.8, git places the submodule .git directories under the superprojects .git dir
# the submodules get a .git file that points to their .git dir. we need to find all of these too
find . -mindepth 2 -name '.git' -type f -print | xargs grep -l "gitdir" | sed -e 's/^\.\///' -e 's/\.git$//' >> $TOARCHIVE

cat $TOARCHIVE | while read archive; do
    echo "found: $archive"
done

echo "archiving submodules"
git submodule >>"$TMPLIST"
while read path; do
    echo " $path"
    # git submodule does not list trailing slashes in $path
    TREEISH=$(grep "^ .*${path%/} " "$TMPLIST" | cut -d ' ' -f 2)
    TMPNAME="$TMPDIR"/"$(echo "$path" | sed -e 's/\//./g')"$FORMAT
    cd "$path"
    rm -f $TMPNAME
    git archive --format=$FORMAT --prefix="${PREFIX}/$path" $ARCHIVE_OPTS ${TREEISH:-HEAD} > $TMPNAME
    echo "$TMPDIR"/"$(echo "$path" | sed -e 's/\//./g')"$FORMAT >> $TMPFILE
    cd "$OLD_PWD"
done < $TOARCHIVE

echo "concatenating archives"
# concatenate archives into a super-archive.
sed -e '1d' $TMPFILE | while read file; do
    tar --concatenate -f "$superfile" "$file" && rm -f "$file"
done
echo "$superfile" >| $TMPFILE  # clobber on purpose

echo "compressing archive"
while read file; do
    cat "$file" | $COMPRESSOR $COMP_OPTS - >| "$OUT_FILE"
    rm -f "$file"
done < $TMPFILE

echo "$HASH"
echo "$(basename $OUT_FILE)"
