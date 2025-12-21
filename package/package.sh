#!/bin/bash

CURRENT_DIR=$(dirname $(readlink -f $0))

ROOT_DIR=$(cd ${CURRENT_DIR}/.. && pwd)
BUILD_DIR="${ROOT_DIR}/build"

chromium_version=$(cat ${ROOT_DIR}/ungoogled-chromium/chromium_version.txt)
ungoogled_revision=$(cat ${ROOT_DIR}/ungoogled-chromium/revision.txt)

FILE_PREFIX="ungoogled-chromium-${chromium_version}.${ungoogled_revision}"
ARCHIVE_OUTPUT="${CURRENT_DIR}/${FILE_PREFIX}.tar.xz"

set -e

FILES="chrome
chrome_100_percent.pak
chrome_200_percent.pak
chrome_crashpad_handler
chromedriver
chrome-wrapper
icudtl.dat
libEGL.so
libGLESv2.so
libqt5_shim.so
libqt6_shim.so
libvk_swiftshader.so
libvulkan.so.1
locales/
product_logo_48.png
resources.pak
v8_context_snapshot.bin
vk_swiftshader_icd.json
xdg-mime
xdg-settings"

mkdir -p ${CURRENT_DIR}/${FILE_PREFIX}
cp ${BUILD_DIR}/src/LICENSE ${CURRENT_DIR}/${FILE_PREFIX}/LICENSE.chromium
cp ${ROOT_DIR}/LICENSE ${CURRENT_DIR}/${FILE_PREFIX}/LICENSE.ungoogled
for i in $FILES ; do
    cp -r ${BUILD_DIR}/src/out/Default/$i ${CURRENT_DIR}/${FILE_PREFIX}
done

(cd ${CURRENT_DIR} && tar cvf ${FILE_PREFIX}.tar ${FILE_PREFIX})

rm -rf ${CURRENT_DIR}/${FILE_PREFIX} && xz -T 0 "${CURRENT_DIR}/${FILE_PREFIX}.tar"

set +e

mv "${CURRENT_DIR}/${FILE_PREFIX}.tar.xz" ${ROOT_DIR}
