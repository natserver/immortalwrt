#!/bin/bash
# 在 ./scripts/feeds update -a 之前执行，工作目录: openwrt/
set -euo pipefail

# dae / daed / luci-app-daede / vmlinux-btf
if ! grep -q "openwrt-daede" feeds.conf.default; then
	echo 'src-git daede https://github.com/kenzok8/openwrt-daede.git' >> feeds.conf.default
fi

# iStore 应用商店（iStoreOS 同款）：luci-app-store / taskd / luci-lib-taskd / luci-lib-xterm
# 对应参考脚本 imm.sh 里 do_istore() 干的事——只是我们走源码编译，而不是刷机后再联网装 ipk。
if ! grep -q "linkease/istore" feeds.conf.default; then
	echo 'src-git store https://github.com/linkease/istore.git;main' >> feeds.conf.default
fi

echo "===== feeds.conf.default ====="
cat feeds.conf.default
