#!/bin/bash
# 在 ./scripts/feeds update -a 之前执行，工作目录: openwrt/
set -euo pipefail

# dae / daed / luci-app-daede / vmlinux-btf
if ! grep -q "openwrt-daede" feeds.conf.default; then
	echo 'src-git daede https://github.com/kenzok8/openwrt-daede.git' >> feeds.conf.default
fi

echo "===== feeds.conf.default ====="
cat feeds.conf.default
