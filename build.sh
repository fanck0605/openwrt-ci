#!/bin/bash
#
# This is free software, license use GPLv3.
#
# Copyright (c) 2021, Chuck <fanck0605@qq.com>
#

set -eu
shopt -s extglob

PROJ_DIR=$(pwd)
readonly PROJ_DIR

VERSION=v21.02.2
MANUAL=false

refresh_patches() {
	local patch
	while IFS= read -r patch; do
		quilt refresh -p ab --no-timestamps --no-index -f "$patch"
	done <patches/series

	return 0
}

refresh() {
	cd "$PROJ_DIR/files/openwrt"
	find -- * -type f -exec cp "$PROJ_DIR"/openwrt/{} ./{} \;
	cd "$PROJ_DIR/openwrt"
	refresh_patches

	cd "$PROJ_DIR/openwrt"
	awk '/^src-git/ { print $2 }' ./feeds.conf.default | while IFS= read -r feed; do
		if [ -d "$PROJ_DIR/files/$feed" ]; then
			cd "$PROJ_DIR/files/$feed"
			find -- * -type f -exec cp "$PROJ_DIR"/openwrt/feeds/"$feed"/{} ./{} \;
		fi
		if [ -d "$PROJ_DIR/patches/$feed" ]; then
			cd "$PROJ_DIR/openwrt/feeds/$feed"
			refresh_patches
		fi
	done
}

apply_patches() {
	ln -sf "$1" patches
	find patches/ -maxdepth 1 -name '*.patch' -printf '%f\n' | sort >patches/series
	quilt push -a

	return 0
}

fetch_clash_download_urls() {
	local -r CPU_ARCH=$1

	echo >&2 "Fetching Clash download urls..."
	local LATEST_VERSIONS
	readarray -t LATEST_VERSIONS < <(curl -sL https://github.com/vernesong/OpenClash/raw/master/core_version)
	readonly LATEST_VERSIONS

	echo https://github.com/vernesong/OpenClash/releases/download/Clash/clash-linux-"$CPU_ARCH".tar.gz
	echo https://github.com/vernesong/OpenClash/releases/download/TUN-Premium/clash-linux-"$CPU_ARCH"-"${LATEST_VERSIONS[1]}".gz
	echo https://github.com/vernesong/OpenClash/releases/download/TUN/clash-linux-"$CPU_ARCH".tar.gz

	return 0
}

download_clash_files() {
	local -r WORKING_DIR=$(pwd)/${1%/}
	local -r CLASH_HOME=$WORKING_DIR/etc/openclash
	local -r CPU_ARCH=$2

	local -r GEOIP_DOWNLOAD_URL=https://github.com/clashdev/geolite.clash.dev/raw/gh-pages/Country.mmdb

	local CLASH_DOWNLOAD_URLS
	readarray -t CLASH_DOWNLOAD_URLS < <(fetch_clash_download_urls "$CPU_ARCH")
	readonly CLASH_DOWNLOAD_URLS

	mkdir -p "$CLASH_HOME"
	echo "Downloading GeoIP database..."
	curl -sL "$GEOIP_DOWNLOAD_URL" >"$CLASH_HOME"/Country.mmdb

	mkdir -p "$CLASH_HOME"/core
	echo "Downloading Clash core..."
	curl -sL "${CLASH_DOWNLOAD_URLS[0]}" | tar -xOz >"$CLASH_HOME"/core/clash
	curl -sL "${CLASH_DOWNLOAD_URLS[1]}" | zcat >"$CLASH_HOME"/core/clash_tun
	curl -sL "${CLASH_DOWNLOAD_URLS[2]}" | tar -xOz >"$CLASH_HOME"/core/clash_game
	chmod +x "$CLASH_HOME"/core/clash{,_tun,_game}

	return 0
}

prepare() {
	# clone openwrt
	cd "$PROJ_DIR"
	echo "开始初始化 OpenWrt 源码"
	echo "当前目录: ""$(pwd)"
	if [ -d "./openwrt" ] && [ -d "./openwrt/.git" ]; then
		echo "OpenWrt 源码已存在"
		pushd ./openwrt
		echo "开始清理 OpenWrt 源码"
		find ./!(.git|feeds) -name .git -exec rm -rf {} +
		git clean -dfx
		# 防止暂存区文件影响 checkout
		git reset --hard HEAD
		echo "开始更新 OpenWrt 源码"
		# FIXME: 这个实现太丑陋了, 快来修复一下
		if [[ "$VERSION" =~ ^v[0-9.rc-]+$ ]]; then
			git fetch origin "tags/$VERSION:tags/$VERSION"
			git checkout "tags/$VERSION"
		else
			git fetch origin "heads/$VERSION:remotes/origin/$VERSION"
			git checkout -B "$VERSION" "remotes/origin/$VERSION"
		fi
		popd
	else
		echo "OpenWrt 源码不存在"
		echo "开始克隆 OpenWrt 源码"
		git clone -b "$VERSION" https://github.com/openwrt/openwrt.git openwrt
	fi
	echo "OpenWrt 源码初始化完毕"

	# patch openwrt
	cd "$PROJ_DIR/openwrt"
	echo "开始修补 OpenWrt 源码"
	echo "当前目录: ""$(pwd)"
	cp -lr "$PROJ_DIR/files/openwrt"/* ./
	# 因为使用了软链接, 尽量使用相对目录
	apply_patches ../patches/openwrt
	echo "OpenWrt 源码修补完毕"

	# clone feeds
	cd "$PROJ_DIR/openwrt"
	echo "Initializing OpenWrt feeds..."
	echo "Current directory: ""$(pwd)"
	awk '/^src-git/ { print $2 }' feeds.conf.default | while IFS= read -r feed; do
		if [ -d "./feeds/$feed" ]; then
			pushd "./feeds/$feed"
			find ./!(.git) -name .git -exec rm -rf {} +
			git reset --hard
			git clean -dfx
			popd
		fi
	done
	./scripts/feeds update -a

	# patch feeds
	echo "Patching OpenWrt feeds..."
	echo "Current directory: ""$(pwd)"
	cd "$PROJ_DIR/openwrt"
	awk '/^src-git/ { print $2 }' feeds.conf.default | while IFS= read -r feed; do
		if [ -d "$PROJ_DIR/files/$feed" ]; then
			cd "$PROJ_DIR/openwrt/feeds/$feed"
			cp -lr "$PROJ_DIR/files/$feed"/* ./
		fi
		if [ -d "$PROJ_DIR/patches/$feed" ]; then
			cd "$PROJ_DIR/openwrt/feeds/$feed"
			# 因为使用了软链接, 尽量使用相对目录
			apply_patches ../../../patches/"$feed"
		fi
	done

	# addition packages
	cd "$PROJ_DIR/openwrt"
	# luci-app-openclash
	svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash package/custom/luci-app-openclash
	download_clash_files package/custom/luci-app-openclash/root armv8
	# luci-app-arpbind
	svn co https://github.com/coolsnowwolf/luci/trunk/applications/luci-app-arpbind feeds/luci/applications/luci-app-arpbind
	# luci-app-xlnetacc
	svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-xlnetacc feeds/luci/applications/luci-app-xlnetacc
	# luci-app-oled
	git clone --depth 1 https://github.com/NateLol/luci-app-oled.git package/custom/luci-app-oled
	# luci-app-unblockmusic
	svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/luci-app-unblockneteasemusic package/custom/luci-app-unblockneteasemusic
	svn co https://github.com/cnsilvan/luci-app-unblockneteasemusic/trunk/UnblockNeteaseMusic package/custom/UnblockNeteaseMusic
	# luci-app-autoreboot
	svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-autoreboot feeds/luci/applications/luci-app-autoreboot
	# luci-app-vsftpd
	svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-vsftpd feeds/luci/applications/luci-app-vsftpd
	rm -rf ./feeds/packages/net/vsftpd
	svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/vsftpd feeds/packages/net/vsftpd
	# luci-app-netdata
	svn co https://github.com/coolsnowwolf/luci/trunk/applications/luci-app-netdata feeds/luci/applications/luci-app-netdata
	# ddns-scripts
	svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/ddns-scripts_aliyun feeds/packages/net/ddns-scripts_aliyun
	svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/ddns-scripts_dnspod feeds/packages/net/ddns-scripts_dnspod
	# luci-theme-argon
	git clone -b master --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/custom/luci-theme-argon
	# luci-app-uugamebooster
	svn co https://github.com/immortalwrt/luci/branches/openwrt-21.02/applications/luci-app-uugamebooster feeds/luci/applications/luci-app-uugamebooster
	svn co https://github.com/immortalwrt/packages/branches/openwrt-21.02/net/uugamebooster feeds/packages/net/uugamebooster

	# install packages
	cd "$PROJ_DIR/openwrt"
	# 在添加自定义软件包后必须再次 update
	./scripts/feeds update -a
	./scripts/feeds install -a

	# zh_cn to zh_Hans
	cd "$PROJ_DIR/openwrt/package"
	"$PROJ_DIR/scripts/convert_translation.sh"

	# create acl files
	cd "$PROJ_DIR/openwrt"
	"$PROJ_DIR/scripts/create_acl_for_luci.sh" -a
	"$PROJ_DIR/scripts/create_acl_for_luci.sh" -c

	# customize configs
	cd "$PROJ_DIR/openwrt"
	cat "$PROJ_DIR/config.seed" >.config
	make defconfig

	return 0
}

# build openwrt
build() {
	cd "$PROJ_DIR/openwrt"

	make download -j16
	make -j$(($(nproc) + 1)) || make -j1 V=s

	mkdir -p "$PROJ_DIR"/artifact
	cp -r ./bin/targets/*/*/* "$PROJ_DIR"/artifact/

	return 0
}

while getopts 'mrv:' opt; do
	case $opt in
	m)
		MANUAL=true
		;;
	v)
		VERSION="$OPTARG"
		;;
	r)
		refresh
		exit 0
		;;
	*)
		echo "usage: $0 [-mv]"
		exit 1
		;;
	esac
done

prepare

$MANUAL || build
