#!/bin/bash

BUILD_START=$(date)
echo "==============================================================="
echo "  Build package start at ${BUILD_START}"
echo "==============================================================="

clone=false
while getopts "c" opt; do
    case "${opt}" in
        c) clone=true
        ;;
    esac
done

# directories
# ==================================================
root_dir="$(dirname $(readlink -f $0))"
main_repo="${root_dir}/ungoogled-chromium"

build_dir="${root_dir}/build"
download_cache="${build_dir}/download_cache"
src_dir="${build_dir}/src"

# clean
# ==================================================
echo "cleaning up directories"
rm -rf "${src_dir}" "${build_dir}/domsubcache.tar.gz"
mkdir -p "${src_dir}" "${download_cache}"

## fetch sources
# ==================================================
if $clone;  then
    "${main_repo}/utils/clone.py" --sysroot amd64 -o "${src_dir}"
else
    "${main_repo}/utils/downloads.py" retrieve -i "${main_repo}/downloads.ini" -c "${download_cache}"
    "${main_repo}/utils/downloads.py" unpack -i "${main_repo}/downloads.ini" -c "${download_cache}" "${src_dir}"
fi
mkdir -p "${src_dir}/out/Default"

# prepare sources
# ==================================================
## apply ungoogled-chromium patches
"${main_repo}/utils/prune_binaries.py" "${src_dir}" "${main_repo}/pruning.list"
"${main_repo}/utils/patches.py" apply "${src_dir}" "${main_repo}/patches"
"${main_repo}/utils/domain_substitution.py" apply -r "${main_repo}/domain_regex.list" -f "${main_repo}/domain_substitution.list" -c "${build_dir}/domsubcache.tar.gz" "${src_dir}"

cd "${main_repo}"

patch --no-backup-if-mismatch -Np1 -i ${root_dir}/update-version-string.patch

cd "${src_dir}"

for f in ${root_dir}/patches/*; do
   patch --no-backup-if-mismatch -Np1 -i ${f}
done

# combine local and ungoogled-chromium gn flags
cat "${main_repo}/flags.gn" "${root_dir}/flags.gn" >"${src_dir}/out/Default/args.gn"

# adjust host name to download prebuilt tools below and sysroot files from
# (see e.g. https://github.com/ungoogled-software/ungoogled-chromium/issues/1846)
sed -e 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' \
    -i ./build/linux/sysroot_scripts/sysroots.json
sed -e 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' \
    -i ./tools/clang/scripts/update.py

## use prebuilt tools for rust and clang insetad of system libs
# use prebuilt rust
./tools/rust/update_rust.py
# to link to rust libraries we need to compile with prebuilt clang
./tools/clang/scripts/update.py
# install sysroot if according gn flag is set to true
if grep -q -F "use_sysroot=true" "${src_dir}/out/Default/args.gn"; then
    ./build/linux/sysroot_scripts/install-sysroot.py --arch=amd64
fi

## Link to system tools required by the build
mkdir -pv third_party/node/linux/node-linux-x64/bin && \
    ln -sv /usr/bin/node third_party/node/linux/node-linux-x64/bin
mkdir -pv third_party/gperf/cipd/bin && \
    ln -svf /usr/bin/gperf third_party/gperf/cipd/bin/gperf
mkdir -pv third_party/dawn/tools/golang/linux-amd64/bin && \
    ln -svf /usr/bin/go third_party/dawn/tools/golang/linux-amd64/bin/go

### build
# ==================================================
_clang_path="${src_dir}/third_party/llvm-build/Release+Asserts/bin"
## env vars
export CC=${_clang_path}/clang
export CXX=${_clang_path}/clang++
export AR=${_clang_path}/llvm-ar
export NM=${_clang_path}/llvm-nm
export LLVM_BIN=${_clang_path}
## flags
llvm_resource_dir=$("$CC" --print-resource-dir)
export CXXFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
export CPPFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
export CFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
## build vars
export BUILD_CC=$CC
export BUILD_CXX=$CXX
export BUILD_AR=$AR
export BUILD_NM=$NM
export BUILD_LLVM_BIN=$LLVM_BIN
export BUILD_CXXFLAGS=$CXXFLAGS
export BUILD_CPPFLAGS=$CPPFLAGS
export BUILD_CFLAGS=$CLFAGS
## go vars
export GOMODCACHE=${src_dir}/.go/mod
export GOCACHE=${src_dir}/.go/build
export GOPATH=${src_dir}/.go/go

# execute build
mkdir -pv ${GOMODCACHE} ${GOCACHE} ${GOPATH}
./tools/gn/bootstrap/bootstrap.py -o out/Default/gn --skip-generate-buildfiles
./out/Default/gn gen out/Default --fail-on-unused-args

ninja -C out/Default chrome chrome_sandbox chromedriver
RETVAL=$?

BUILD_END=$(date)
echo "==============================================================="
echo "  Build package start at ${BUILD_START}"
echo "  Build package end   at ${BUILD_END}"
echo "==============================================================="

exit $RETVAL
