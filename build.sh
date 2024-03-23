#!/bin/bash
#
# This is free software, license use GPLv3.
#
# Copyright (c) 2021, Chuck <fanck0605@qq.com>
#

set -euo pipefail

PROJ_DIR=$(pwd)
readonly PROJ_DIR

VERSION=openwrt-22.03
MANUAL=false
ORIGIN=origin
BUILD=false
AUTO_BUILD=true
target=x86-64

fetch_clash_download_urls() {
	local -r CPU_ARCH=$1

	echo >&2 "Fetching Clash download urls..."
	local LATEST_VERSIONS
	readarray -t LATEST_VERSIONS <<<"$(curl -sLf https://github.com/vernesong/OpenClash/raw/core/master/core_version)"
	readonly LATEST_VERSIONS

	echo https://github.com/vernesong/OpenClash/raw/core/master/dev/clash-linux-"$CPU_ARCH".tar.gz
	echo https://github.com/vernesong/OpenClash/raw/core/master/premium/clash-linux-"$CPU_ARCH"-"${LATEST_VERSIONS[1]}".gz
	echo https://github.com/vernesong/OpenClash/raw/core/master/meta/clash-linux-"$CPU_ARCH".tar.gz

	return 0
}

download_clash_files() {
	local -r WORKING_DIR=$(pwd)/${1%/}
	local -r CLASH_HOME=$WORKING_DIR/etc/openclash
	local -r CPU_ARCH=$2

	local -r GEOIP_DOWNLOAD_URL=https://github.com/alecthw/mmdb_china_ip_list/raw/release/lite/Country.mmdb

	local CLASH_DOWNLOAD_URLS
	readarray -t CLASH_DOWNLOAD_URLS <<<"$(fetch_clash_download_urls "$CPU_ARCH")"
	readonly CLASH_DOWNLOAD_URLS

	mkdir -p "$CLASH_HOME"
	echo "Downloading GeoIP database..."
	curl -Lf "$GEOIP_DOWNLOAD_URL" -o "$CLASH_HOME"/Country.mmdb

	local -r download_dir=$(mktemp -d)
	echo "Download ${CLASH_DOWNLOAD_URLS[0]}"
	mkdir "$download_dir"/clash_dev
	curl -Lf "${CLASH_DOWNLOAD_URLS[0]}" -o "$download_dir"/clash_dev/clash.tar.gz
	tar -zxf "$download_dir"/clash_dev/clash.tar.gz -C "$download_dir"/clash_dev

	echo "Download ${CLASH_DOWNLOAD_URLS[1]}"
	mkdir "$download_dir"/clash_tun
	curl -Lf "${CLASH_DOWNLOAD_URLS[1]}" -o "$download_dir"/clash_tun/clash.gz
	gzip -dk "$download_dir"/clash_tun/clash.gz

	echo "Download ${CLASH_DOWNLOAD_URLS[2]}"
	mkdir "$download_dir"/clash_meta
	curl -Lf "${CLASH_DOWNLOAD_URLS[2]}" -o "$download_dir"/clash_meta/clash.tar.gz
	tar -zxf "$download_dir"/clash_meta/clash.tar.gz -C "$download_dir"/clash_meta

	mkdir -p "$CLASH_HOME"/core
	install -m 755 "$download_dir"/clash_dev/clash "$CLASH_HOME"/core/clash
	install -m 755 "$download_dir"/clash_tun/clash "$CLASH_HOME"/core/clash_tun
	install -m 755 "$download_dir"/clash_meta/clash "$CLASH_HOME"/core/clash_meta

	return 0
}

# 初始化 OpenWrt 主干代码, 包括 OpenWrt 本身以及官方 feeds
# 注意: feeds 仅克隆了源码, 需要使用 ./script/feeds update -i 来生成索引才能使用
init_trunk() {
	# clone openwrt
	cd "$PROJ_DIR"
	echo "开始初始化 OpenWrt 源码"
	echo "当前目录: ""$(pwd)"
	if [ -d "./openwrt" ] && [ -d "./openwrt/.git" ]; then
		echo "OpenWrt 源码已存在"
		pushd ./openwrt
		echo "开始清理 OpenWrt 源码"
		git clean -dfx
		# 防止暂存区文件影响 checkout
		git reset --hard HEAD
		echo "开始更新 OpenWrt 源码"
		# FIXME: 这个实现太丑陋了, 快来修复一下
		if [[ "$VERSION" =~ ^v[0-9.rc-]+$ ]]; then
			git fetch "$ORIGIN" "refs/tags/$VERSION:refs/tags/$VERSION"
			git checkout "refs/tags/$VERSION"
		else
			git fetch "$ORIGIN" "refs/heads/$VERSION:refs/remotes/$ORIGIN/$VERSION"
			git checkout -B "$VERSION" "refs/remotes/$ORIGIN/$VERSION"
		fi
		popd
	else
		echo "OpenWrt 源码不存在"
		echo "开始克隆 OpenWrt 源码"
		git clone -b "$VERSION" https://github.com/fanck0605/openwrt.git openwrt
	fi
	echo "OpenWrt 源码初始化完毕"

	# clone feeds
	cd "$PROJ_DIR/openwrt"
	echo "Initializing OpenWrt feeds..."
	echo "Current directory: ""$(pwd)"

	sed -i 's|https://git.openwrt.org/feed|https://github.com/openwrt|g' ./feeds.conf.default
	sed -i 's|https://git.openwrt.org/project|https://github.com/openwrt|g' ./feeds.conf.default

	local feed
	while IFS= read -r feed; do
		if [ -d "./feeds/$feed" ]; then
			pushd "./feeds/$feed"
			git reset --hard
			git clean -dfx
			popd
		fi
	done <<<"$(awk '/^src-git/ { print $2 }' ./feeds.conf.default)"

	./scripts/feeds update -a
	# 再次清除缓存, 防止后面 update -i 出错
	git clean -dfx
}

get_cpu_arch() {
	case $target in
	x86-64)
		echo amd64
		;;
	nanopi-r2s)
		echo arm64
		;;
	esac
}

# 初始化第三方软件包, 可以在这里自行添加需要的软件包
# 如需继续修改第三方软件包, 可以在下面的阶段进行 patch
init_packages() {
	cd "$PROJ_DIR"
	rm -rf OpenClash
	git clone --depth 1 -b master https://github.com/vernesong/OpenClash.git
	rm -rf immortalwrt-luci
	git clone --depth 1 -b openwrt-21.02 https://github.com/immortalwrt/luci.git immortalwrt-luci
	rm -rf immortalwrt-packages
	git clone --depth 1 -b openwrt-21.02 https://github.com/immortalwrt/packages.git immortalwrt-packages

	# addition packages
	cd "$PROJ_DIR/openwrt"
	mkdir -p package/custom
	mkdir -p feeds/luci/applications
	mkdir -p feeds/packages/net

	# luci-app-openclash
	cp -rf "$PROJ_DIR/OpenClash/luci-app-openclash" package/custom
	download_clash_files package/custom/luci-app-openclash/root "$(get_cpu_arch)"
	# luci-app-autoreboot
	cp -rf  "$PROJ_DIR/immortalwrt-luci/applications/luci-app-autoreboot" feeds/luci/applications/luci-app-autoreboot
	# ddns-scripts
	cp -rf  "$PROJ_DIR/immortalwrt-packages/net/ddns-scripts_aliyun" feeds/packages/net/ddns-scripts_aliyun
	cp -rf  "$PROJ_DIR/immortalwrt-packages/net/ddns-scripts_dnspod" feeds/packages/net/ddns-scripts_dnspod

	# 注意下面的脚本不会影响克隆到 feeds 的源码
	# zh_cn to zh_Hans
	cd "$PROJ_DIR/openwrt/package"
	"$PROJ_DIR/scripts/convert_translation.sh"

	# create acl files
	cd "$PROJ_DIR/openwrt"
	"$PROJ_DIR/scripts/create_acl_for_luci.sh" -a
	"$PROJ_DIR/scripts/create_acl_for_luci.sh" -c
}

# 这里将会读取项目根目录下的额外文件和补丁文件, 并将修改合并到源码上
patch_source() {
	# patch openwrt
	cd "$PROJ_DIR/openwrt"
	echo "开始修补 OpenWrt 源码"
	echo "当前目录: ""$(pwd)"
	if [ -d "$PROJ_DIR/trunk/files" ]; then
		cp -lfr "$PROJ_DIR/trunk/files"/* ./
	fi
	# 因为使用了软链接, 尽量使用相对目录
	apply_patches ../trunk
	echo "OpenWrt 源码修补完毕"

	# patch feeds
	echo "Patching OpenWrt feeds..."
	echo "Current directory: ""$(pwd)"
	cd "$PROJ_DIR/openwrt"
	local feed
	while IFS= read -r feed; do
		if [ -d "$PROJ_DIR/$feed/files" ]; then
			cd "$PROJ_DIR/openwrt/feeds/$feed"
			cp -lfr "$PROJ_DIR/$feed/files"/* ./
		fi
		if [ -d "$PROJ_DIR/$feed/patches" ]; then
			cd "$PROJ_DIR/openwrt/feeds/$feed"
			# 因为使用了软链接, 尽量使用相对目录
			apply_patches ../../../"$feed"
		fi
	done <<<"$(awk '/^src-git/ { print $2 }' ./feeds.conf.default)"
}

# 这里将安装 feeds 中所有的软件包, 并读取 config.seed 来生成默认配置文件
prepare_build() {
	# install packages
	cd "$PROJ_DIR/openwrt"
	# 在添加自定义软件包后必须再次 update
	./scripts/feeds update -i
	./scripts/feeds install -a

	# customize configs
	cd "$PROJ_DIR/openwrt"
	cat "$PROJ_DIR/config/config_$target" >.config
	cat "$PROJ_DIR/config/config_common" >>.config
	make defconfig

	return 0
}

# 编译完成后将会把编译结果复制到项目根目录的 artifact 文件夹中
build() {
	cd "$PROJ_DIR/openwrt"

	make download -j16
	make -j$(($(nproc) + 1)) || make -j1 V=s

	mkdir -p "$PROJ_DIR"/artifact
	cp -r ./bin/targets/*/*/* "$PROJ_DIR"/artifact/

	return 0
}

while getopts 'msrbv:o:t:' opt; do
	case $opt in
	m)
		MANUAL=true
		AUTO_BUILD=false
		;;
	v)
		VERSION=$OPTARG
		AUTO_BUILD=false
		;;
	o)
		ORIGIN=$OPTARG
		AUTO_BUILD=false
		;;
	b)
		BUILD=true
		AUTO_BUILD=false
		;;
	t)
		target=$OPTARG
		;;
	*)
		echo "usage: $0 [-msrb] [-v version] [-o origin] [-t target]"
		exit 1
		;;
	esac
done

if $MANUAL; then
	init_trunk

	init_packages

	prepare_build
fi

if $BUILD; then
	build
fi

if $AUTO_BUILD; then
	init_trunk

	init_packages

	prepare_build

	build
fi
