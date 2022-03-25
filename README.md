# NanoPi R2s 的 OpenWrt 固件

## 注意事项

- WAN 和 LAN 默认是**互换**的，请注意网线接法。

- 刷机最好**不要**保留配置，以免产生未知的问题！

## 说明

使用本项目编译脚本初始化的源码，或者通过 CI 编译的固件，默认配置如下：

- ipv4: 192.168.33.1
- username: root
- password: fa

## 自行编译

### 1.  安装依赖

**注意：**相比 OpenWrt 的官方版本多了 `quilt` 这个软件包

```
sudo apt update
sudo apt install build-essential ccache ecj fastjar file g++ gawk gettext git java-propose-classpath libelf-dev libncurses5-dev libncursesw5-dev libssl-dev python python2.7-dev python3 unzip wget python3-distutils python3-setuptools python3-dev quilt rsync subversion swig time xsltproc zlib1g-dev
```

### 2. 固件编译

#### 2.1 一键编译

全自动编译, 编译完后固件将会在 `./artifact` 文件夹下

```
./build.sh
```

#### 2.2 手动编译

通过 `./build.sh -m` 可以初始化 OpenWrt 源码，这将自动下载一些常用第三方软件包, 并且~~负~~优化部分 OpenWrt 的配置。

初始化完毕后后，你可以手动选择需要的软件包进行编译。

```
./build.sh -m
cd ./openwrt
make menuconfig
make -j$(($(nproc) + 1))
```

**注意：**多次使用 `build.sh` 将会**清除**您对 openwrt 源码的改动
