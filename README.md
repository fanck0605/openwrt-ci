# OpenWrt 固件编译 CI

## 注意事项

- 刷机最好**不要**保留配置，以免产生未知的问题！

- 后台 IP: 10.33.0.1

## 自行编译

### 1.  安装依赖

```
sudo apt update
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libelf-dev libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget
```

### 2. 固件编译

#### 2.1 一键编译

全自动编译, 编译完后固件将会在 `./artifact` 文件夹下

源码直接使用官方 OpenWrt `v25.12.5` tag。固件选项维护在 `config/`，首次启动配置维护在 `files/`。

```
./build.sh -t nanopi-r2s
```

#### 2.2 手动编译

通过 `./build.sh -m` 可以初始化 OpenWrt 源码，这将自动下载一些常用第三方软件包, 并且~~负~~优化部分 OpenWrt 的配置。

```
./build.sh -m
```

初始化完毕后后，你可以手动选择需要的软件包进行编译。

```
cd ./openwrt
make menuconfig
make -j$(($(nproc) + 1))
```

也可以使用 `./build.sh -b` 来替代 `make -j`，这将会先执行 make download 再进行编译，再网络环境较差的地方可以提高编译成功率。

```
cd ../
./build.sh -b
```

**注意:** 多次使用 `build.sh` 将会**清除**您对 openwrt 源码的改动

## 常用命令

### 指定版本号

不同版本补丁不一定兼容，可能初始化失败

```
./build.sh -v v25.12.5
```
