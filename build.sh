#!/bin/bash

set -eu

rm -rf openwrt
git clone https://github.com/coolsnowwolf/lede.git openwrt

# customize patches
pushd openwrt
git am -3 ../patches/*.patch
popd

# addition packages
pushd openwrt/package
# luci-theme-argon
rm -rf lean/luci-theme-argon
git clone --depth 1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon.git lean/luci-theme-argon
# luci-app-filebrowser
svn co https://github.com/project-openwrt/openwrt/trunk/package/ctcgfw/luci-app-filebrowser lean/luci-app-filebrowser
svn co https://github.com/project-openwrt/openwrt/trunk/package/ctcgfw/filebrowser lean/filebrowser
# luci-app-oled
git clone --depth 1 https://github.com/NateLol/luci-app-oled.git lean/luci-app-oled
popd

# initialize feeds
p_list=$(ls -l patches | grep ^d | awk '{print $NF}')
pushd openwrt
# clone feeds
./scripts/feeds update -a
# patching
pushd feeds
for p in $p_list ; do
  [ -d $p ] && {
    pushd $p
    git am -3 ../../../patches/$p/*.patch
    popd
  }
done
popd
popd

#install packages
pushd openwrt
./scripts/feeds install -a
popd

# customize configs
pushd openwrt
cat ../config.seed > .config
make defconfig
popd

# build openwrt
pushd openwrt
make download -j8
make -j$(($(nproc) + 1)) || make -j1 V=s
popd

# package output files
archive_tag=OpenWrt_$(date +%Y%m%d)_NanoPi-R2S
pushd openwrt/bin/targets/*/*
# repack openwrt*.img.gz
set +e
gunzip openwrt*.img.gz
set -e
gzip openwrt*.img
sha256sum -b $(ls -l | grep ^- | awk '{print $NF}' | grep -v sha256sums) >sha256sums
tar zcf $archive_tag.tar.gz $(ls -l | grep ^- | awk '{print $NF}')
popd
mv openwrt/bin/targets/*/*/$archive_tag.tar.gz .
