# NanoPi R2s 的 OpenWrt 固件

## 注意事项

- WAN 和 LAN 默认是**互换**的，请注意网线接法。

- 刷机最好**不要**保留配置，以免产生未知的问题！

- 后台 IP: 192.168.33.1

## 自行编译

### 1.  安装依赖

**注意:** 相比 OpenWrt 的官方版本多了 `quilt` 这个软件包

```
sudo apt update
sudo apt install build-essential ccache ecj fastjar file g++ gawk gettext git java-propose-classpath libelf-dev libncurses5-dev libncursesw5-dev libssl-dev python python2.7-dev python3 unzip wget python-distutils-extra python3-setuptools python3-dev quilt rsync subversion swig time xsltproc zlib1g-dev 
```

### 2. 固件编译

#### 2.1 一键编译

全自动编译, 编译完后固件将会在 `./artifact` 文件夹下

```
./build.sh
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
./build.sh -v openwrt-22.03
```

### 刷新补丁

因为使用 `./script/feeds update -i` 可能会把 quilt 储存在 .pc 文件夹下的临时文件识别成软件包，因此在使用 `./build.sh` 初始化源码后会把 quilt 产生的临时文件夹移除，需要使用 `-s` 参数重新装载，如果已经使用过一次 `-s` 参数则无需再次添加

```
./build.sh -r [-s]
```

通过配合 `-m` 参数可以直接克隆源码并刷新补丁

```
./build.sh -msr
```
