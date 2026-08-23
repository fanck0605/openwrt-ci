#!/bin/bash
#
# This is free software, license use GPLv3.
#
# Copyright (c) 2021, Chuck <fanck0605@qq.com>
#

set -euo pipefail

PROJ_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly PROJ_DIR

VERSION=v25.12.5
OPENWRT_REPO=https://github.com/openwrt/openwrt.git
readonly OPENWRT_REPO
MANUAL=false
ORIGIN=origin
readonly ORIGIN
BUILD=false
AUTO_BUILD=true
target=x86-64

sync_git_repository() {
	local -r destination=$1
	local -r repository=$2
	local -r ref=$3
	shift 3
	local -a clean_args=(-dfx)
	local exclude
	for exclude in "$@"; do
		clean_args+=(-e "$exclude")
	done

	if [ ! -e "$destination" ]; then
		echo "开始克隆 $repository: $ref"
		git clone --depth 1 --origin "$ORIGIN" --branch "$ref" \
			"$repository" "$destination" || return
		return
	fi

	if ! git -C "$destination" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo >&2 "错误: $destination 已存在，但不是 Git 工作树"
		return 1
	fi

	echo "开始更新 $repository: $ref"
	if git -C "$destination" remote get-url "$ORIGIN" >/dev/null 2>&1; then
		git -C "$destination" remote set-url "$ORIGIN" "$repository" || return
	else
		git -C "$destination" remote add "$ORIGIN" "$repository" || return
	fi

	git -C "$destination" fetch --depth 1 "$ORIGIN" "$ref" || return
	git -C "$destination" reset --hard HEAD || return
	git -C "$destination" clean "${clean_args[@]}" || return
	git -C "$destination" checkout --detach --force FETCH_HEAD || return
}

# 初始化 OpenWrt 源码及官方 feeds。此操作会清除 openwrt/ 中的本地改动。
init_trunk() {
	echo "开始初始化 OpenWrt 源码"
	sync_git_repository "$PROJ_DIR/openwrt" "$OPENWRT_REPO" "$VERSION" /dl /feeds
	echo "OpenWrt 源码初始化完毕"

	cd "$PROJ_DIR/openwrt"
	echo "开始初始化 OpenWrt feeds"

	sed -i 's|https://git.openwrt.org/feed/|https://github.com/openwrt/|g' ./feeds.conf.default
	sed -i 's|https://git.openwrt.org/project/|https://github.com/openwrt/|g' ./feeds.conf.default
	if ! grep -q '^src-git nikki ' ./feeds.conf.default; then
		printf '%s\n' 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;v1.26.1' >>./feeds.conf.default
	fi

	local feed
	while IFS= read -r feed; do
		if git -C "./feeds/$feed" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			git -C "./feeds/$feed" reset --hard HEAD
			git -C "./feeds/$feed" clean -dfx
		fi
	done <<<"$(awk '/^src-git/ { print $2 }' ./feeds.conf.default)"

	./scripts/feeds update -a
	echo "OpenWrt feeds 初始化完毕"
}

# 初始化第三方软件包，可以在同步后添加自定义处理。
init_packages() {
	sync_git_repository "$PROJ_DIR/immortalwrt-luci" \
		https://github.com/immortalwrt/luci.git openwrt-25.12
	sync_git_repository "$PROJ_DIR/immortalwrt-packages" \
		https://github.com/immortalwrt/packages.git openwrt-25.12

	# addition packages
	cd "$PROJ_DIR/openwrt"

	# luci-app-autoreboot
	mkdir -p feeds/luci/applications/luci-app-autoreboot
	rsync -a --delete "$PROJ_DIR/immortalwrt-luci/applications/luci-app-autoreboot/" feeds/luci/applications/luci-app-autoreboot/
	# ddns-scripts
	# TODO 恢复 aliyun ddns
	# cp -rf "$PROJ_DIR/immortalwrt-packages/net/ddns-scripts_aliyun" feeds/packages/net/ddns-scripts_aliyun
	mkdir -p feeds/packages/net/ddns-scripts_dnspod
	rsync -a --delete "$PROJ_DIR/immortalwrt-packages/net/ddns-scripts_dnspod/" feeds/packages/net/ddns-scripts_dnspod/
}

# 这里将安装 feeds 中所有的软件包, 并读取 config.seed 来生成默认配置文件
prepare_build() {
	# install packages
	cd "$PROJ_DIR/openwrt"
	# 在添加自定义软件包后必须再次 update
	./scripts/feeds update -i
	./scripts/feeds install -a

	# install root filesystem overlay
	mkdir -p "$PROJ_DIR/openwrt/files"
	rsync -a --delete "$PROJ_DIR/files/" "$PROJ_DIR/openwrt/files/"

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

main() {
	while getopts 'mbv:t:' opt; do
		case $opt in
		t)
			target=$OPTARG
			;;
		m)
			MANUAL=true
			AUTO_BUILD=false
			;;
		v)
			VERSION=$OPTARG
			;;
		b)
			BUILD=true
			AUTO_BUILD=false
			;;
		*)
			echo "usage: $0 [-mb] [-v version] [-t target]"
			return 1
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
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	main "$@"
fi
