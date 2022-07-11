#!/bin/sh

DNSMASQ_CHINA_LIST=https://github.com/felixonmars/dnsmasq-china-list/raw/master

curl -sL "$DNSMASQ_CHINA_LIST/accelerated-domains.china.conf" | sed -n 's|^server=/\(.*\?\)/.*$|nameserver /\1/china|p' >/etc/smartdns/base.china.conf
curl -sL "$DNSMASQ_CHINA_LIST/google.china.conf" | sed -n 's|^server=/\(.*\?\)/.*$|nameserver /\1/china|p' >/etc/smartdns/google.china.conf
curl -sL "$DNSMASQ_CHINA_LIST/apple.china.conf" | sed -n 's|^server=/\(.*\?\)/.*$|nameserver /\1/china|p' >/etc/smartdns/apple.china.conf

/etc/init.d/smartdns reload
