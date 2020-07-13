#!/bin/bash

set -eu

rm -rf openwrt
git clone -b nanopi-r2s https://git.openwrt.org/openwrt/staging/blocktrron.git openwrt

# customize patches
pushd openwrt
git am -3 ../patches/*.patch
popd

# addition packages
pushd openwrt/package
# hell0world
svn co https://github.com/fw876/helloworld/trunk/luci-app-ssr-plus lean/luci-app-ssr-plus
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/shadowsocksr-libev lean/shadowsocksr-libev
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/pdnsd-alt lean/pdnsd-alt
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/microsocks lean/microsocks
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/dns2socks lean/dns2socks
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/simple-obfs lean/simple-obfs
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/tcpping lean/tcpping
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/v2ray-plugin lean/v2ray-plugin
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/v2ray lean/v2ray
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/trojan lean/trojan
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/ipt2socks lean/ipt2socks
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/redsocks2 lean/redsocks2
# luci-app-filebrowser
svn co https://github.com/project-openwrt/openwrt/trunk/package/ctcgfw/luci-app-filebrowser lean/luci-app-filebrowser
svn co https://github.com/project-openwrt/openwrt/trunk/package/ctcgfw/filebrowser lean/filebrowser
# luci-app-arpbind
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-arpbind lean/luci-app-arpbind
# coremark
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/coremark lean/coremark
# luci-app-xlnetacc
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-xlnetacc lean/luci-app-xlnetacc
# luci-app-oled
git clone --depth 1 https://github.com/NateLol/luci-app-oled.git lean/luci-app-oled
# luci-app-unblockmusic
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-unblockmusic lean/luci-app-unblockmusic
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/UnblockNeteaseMusic lean/UnblockNeteaseMusic
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/UnblockNeteaseMusicGo lean/UnblockNeteaseMusicGo
# luci-app-autoreboot
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-autoreboot lean/luci-app-autoreboot
# luci-app-vsftpd
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-vsftpd lean/luci-app-vsftpd
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/vsftpd-alt lean/vsftpd-alt
# luci-app-netdata
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-netdata lean/luci-app-netdata
# zh_cn to zh_Hans
../../scripts/convert_translation.sh
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
make -j$(nproc)
popd
