## Netfilter and iptables extension for [FULLCONENAT](https://github.com/Chion82/netfilter-full-cone-nat) target ported to OpenWrt.

Compile
---
```
# cd to OpenWrt source path
# Clone this repo
git clone -b master --single-branch https://github.com/LGA1150/openwrt-fullconenat package/fullconenat
# Select Network -> Firewall -> iptables-mod-fullconenat
make menuconfig
# Compile
make V=s
```

Usage
---
You can apply [this patch](https://github.com/LGA1150/fullconenat-fw3-patch) to OpenWrt's Firewall3 (Recommended).

Or manually add the following rules to `/etc/firewall.user`
```
iptables -t nat -A zone_wan_prerouting -j FULLCONENAT
iptables -t nat -A zone_wan_postrouting -j FULLCONENAT
```

Workaround for conflicting with module `nf_conntrack_netlink`
---
This module uses conntrack events to register a callback function. In the same netns, only one callback method can be registered, that causes conflicts with `nf_conntrack_netlink`, which also uses conntrack events. Qualcomm Shortcut FE has introduced a patch to allow multiple callbacks to be registered. To apply, put [this patch](https://github.com/coolsnowwolf/lede/blob/master/target/linux/generic/hack-4.14/952-net-conntrack-events-support-multiple-registrant.patch) into `target/linux/generic/hack-4.14`.
