#!/bin/bash
# 在 ./scripts/feeds install -a 之后、cp .config && make defconfig 之前执行
# 工作目录: openwrt/
set -euo pipefail

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

# 1. 默认 LAN IP -> 192.168.100.1
sed -i 's/192\.168\.1\.1/192.168.100.1/g' package/base-files/files/bin/config_generate
grep -q '192\.168\.100\.1' package/base-files/files/bin/config_generate \
	|| fail "LAN IP 192.168.100.1 未写入 config_generate"

# 2. 默认主机名 -> NatserverWrt
sed -i "s/hostname='ImmortalWrt'/hostname='NatserverWrt'/g" package/base-files/files/bin/config_generate
grep -q "hostname='NatserverWrt'" package/base-files/files/bin/config_generate \
	|| fail "hostname NatserverWrt 未写入 config_generate"

# 3. 确认 daed 相关的包都已被 feeds install 装入
#    dae / daed / luci-app-daed 可能来自官方 packages、luci 源，也可能来自 daede 源，
#    所以在 package/feeds/*/ 下面找，而不是只看某一个源。
for p in dae daed luci-app-daed luci-app-daede vmlinux-btf; do
	found=""
	for d in package/feeds/*/"$p"; do
		if [ -e "$d" ]; then
			found="$d"
			break
		fi
	done
	if [ -z "$found" ]; then
		ls -l package/feeds/* 2>/dev/null || true
		fail "feeds 中找不到包 $p (diy-part1 是否执行? feeds install 是否成功?)"
	fi
	echo "  feeds 包 $p -> $found"
done

echo "diy-part2 OK"
