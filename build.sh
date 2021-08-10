#!/bin/bash
#
# This is free software, license use GPLv3.
#
# Copyright (c) 2021, Chuck <fanck0605@qq.com>
#

set -eu

maintain=false

while getopts 'm' opt; do
	case $opt in
	m)
		maintain=true
		;;
	*)
		echo "usage: $0 [-m]"
		exit 1
		;;
	esac
done

apply_patches() {
	ln -sf "$1" patches
	find patches/ -maxdepth 1 -name '*.patch' -printf '%f\n' | sort >patches/series
	quilt push -a
	$maintain &&
		while IFS= read -r patch; do
			quilt refresh -p ab --no-timestamps --no-index -f "$patch"
		done <patches/series
	return 0
}

download_clash_core() { (
	cd "$1"
	mkdir -p etc/openclash/core
	cd etc/openclash/core
	premium_version=$(curl -sL https://github.com/vernesong/OpenClash/raw/master/core_version | sed -n 2p)
	curl -sL https://github.com/vernesong/OpenClash/releases/download/Clash/clash-linux-"$2".tar.gz | tar -xOz >clash
	curl -sL https://github.com/vernesong/OpenClash/releases/download/TUN-Premium/clash-linux-"$2"-"$premium_version".gz | zcat >clash_tun
	curl -sL https://github.com/vernesong/OpenClash/releases/download/TUN/clash-linux-"$2".tar.gz | tar -xOz >clash_game
	chmod +x clash
	chmod +x clash_tun
	chmod +x clash_game
); }

proj_dir=$(pwd)

# clone openwrt
cd "$proj_dir"
rm -rf openwrt
git clone -b v21.02.0-rc4 https://github.com/openwrt/openwrt.git openwrt

# patch openwrt
cd "$proj_dir/openwrt"
apply_patches ../patches

# clone feeds
cd "$proj_dir/openwrt"
./scripts/feeds update -a

# patch feeds
cd "$proj_dir/openwrt"
awk '/^src-git/ { print $2 }' feeds.conf.default | while IFS= read -r feed; do
	if [ -d "$proj_dir/patches/$feed" ]; then
		cd "$proj_dir/openwrt/feeds/$feed"
		apply_patches ../../../patches/"$feed"
	fi
done

# addition packages
cd "$proj_dir/openwrt/package"
# luci-app-openclash
svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash custom/luci-app-openclash
download_clash_core custom/luci-app-openclash/root armv8
# luci-app-arpbind
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-arpbind custom/luci-app-arpbind
# luci-app-xlnetacc
svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-xlnetacc custom/luci-app-xlnetacc
sed -i 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g' custom/luci-app-xlnetacc/Makefile
# luci-app-oled
git clone --depth 1 https://github.com/NateLol/luci-app-oled.git custom/luci-app-oled
# luci-app-unblockmusic
svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/luci-app-unblockneteasemusic custom/luci-app-unblockneteasemusic
svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/UnblockNeteaseMusic custom/UnblockNeteaseMusic
# luci-app-autoreboot
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-autoreboot custom/luci-app-autoreboot
# luci-app-vsftpd
svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-vsftpd custom/luci-app-vsftpd
sed -i 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g' custom/luci-app-vsftpd/Makefile
svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/vsftpd-alt custom/vsftpd-alt
# luci-app-netdata
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-netdata custom/luci-app-netdata
# ddns-scripts
svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/ddns-scripts_aliyun custom/ddns-scripts_aliyun
svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/ddns-scripts_dnspod custom/ddns-scripts_dnspod
# luci-theme-argon
git clone -b master --depth 1 https://github.com/jerrykuku/luci-theme-argon.git custom/luci-theme-argon
# luci-app-uugamebooster
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/luci-app-uugamebooster custom/luci-app-uugamebooster
svn co https://github.com/coolsnowwolf/lede/trunk/package/lean/uugamebooster custom/uugamebooster

# clean up packages
cd "$proj_dir/openwrt/package"
find . -name .svn -exec rm -rf {} +
find . -name .git -exec rm -rf {} +

# zh_cn to zh_Hans
cd "$proj_dir/openwrt/package"
"$proj_dir/scripts/convert_translation.sh"

# create acl files
cd "$proj_dir/openwrt"
"$proj_dir/scripts/create_acl_for_luci.sh" -a

$maintain && exit 0

# install packages
cd "$proj_dir/openwrt"
./scripts/feeds install -a

# customize configs
cd "$proj_dir/openwrt"
cat "$proj_dir/config.seed" >.config
make defconfig

# build openwrt
cd "$proj_dir/openwrt"
make download -j8
make -j$(($(nproc) + 1)) || make -j1 V=s

# copy output files
cd "$proj_dir"
cp -rf openwrt/bin/targets/*/* artifact
