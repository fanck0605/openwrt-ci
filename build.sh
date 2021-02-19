#!/bin/bash
#
# This is free software, license use GPLv3.
#
# Copyright (c) 2020, Chuck <fanck0605@qq.com>
#

set -eu

rm -rf openwrt
git clone -b openwrt-21.02 https://github.com/openwrt/openwrt.git openwrt

# customize patches
pushd openwrt
git am -3 ../patches/*.patch
popd

# initialize feeds
feed_list=$(cd patches && find * -type d)
pushd openwrt
# clone feeds
./scripts/feeds update -a
# patching
pushd feeds
for feed in $feed_list ; do
  [ -d $feed ] && {
    pushd $feed
    git am -3 ../../../patches/$feed/*.patch
    popd
  }
done
popd
popd

# addition packages
pushd openwrt/package
# luci-app-helloworld
svn co https://github.com/fw876/helloworld/trunk/luci-app-ssr-plus lean/luci-app-ssr-plus
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/shadowsocksr-libev lean/shadowsocksr-libev
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/pdnsd-alt lean/pdnsd-alt
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/microsocks lean/microsocks
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/dns2socks lean/dns2socks
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/simple-obfs lean/simple-obfs
svn co https://github.com/fw876/helloworld/trunk/tcping lean/tcping
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/v2ray-plugin lean/v2ray-plugin
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/trojan lean/trojan
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/ipt2socks lean/ipt2socks
svn co https://github.com/fw876/helloworld/trunk/naiveproxy lean/naiveproxy
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/redsocks2 lean/redsocks2
# luci-app-openclash
svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash lean/luci-app-openclash
# luci-app-filebrowser
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/ctcgfw/luci-app-filebrowser lean/luci-app-filebrowser
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/ctcgfw/filebrowser lean/filebrowser
# luci-app-arpbind
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-arpbind lean/luci-app-arpbind
# coremark
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/coremark lean/coremark
# luci-app-xlnetacc
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/lean/luci-app-xlnetacc lean/luci-app-xlnetacc
# luci-app-oled
git clone --depth 1 https://github.com/NateLol/luci-app-oled.git lean/luci-app-oled
# luci-app-unblockmusic
svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/luci-app-unblockneteasemusic lean/luci-app-unblockneteasemusic
svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/UnblockNeteaseMusic lean/UnblockNeteaseMusic
# luci-app-autoreboot
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-autoreboot lean/luci-app-autoreboot
# luci-app-vsftpd
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/lean/luci-app-vsftpd lean/luci-app-vsftpd
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/lean/vsftpd-alt lean/vsftpd-alt
# luci-app-netdata
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-netdata lean/luci-app-netdata
# ddns-scripts
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/lean/ddns-scripts_aliyun lean/ddns-scripts_aliyun
svn co https://github.com/immortalwrt/immortalwrt/branches/master/package/lean/ddns-scripts_dnspod lean/ddns-scripts_dnspod
popd

# zh_cn to zh_Hans
pushd openwrt/package
../../scripts/convert_translation.sh
popd

# create acl files
pushd openwrt
../scripts/create_acl_for_luci.sh -a
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
tar -zcf $archive_tag.tar.gz *
popd
mv openwrt/bin/targets/*/*/$archive_tag.tar.gz .
