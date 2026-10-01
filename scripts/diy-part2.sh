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
DAED_PKGS="dae daed luci-app-daed luci-app-daede vmlinux-btf"
# 4. iStore 应用商店（store feed = https://github.com/linkease/istore，由 diy-part1.sh 追加）
STORE_PKGS="luci-app-store luci-lib-taskd luci-lib-xterm taskd"
# 5. iStoreOS 外观：Argon 主题（来自 immortalwrt/luci）
THEME_PKGS="luci-theme-argon luci-app-argon-config"

for p in $DAED_PKGS $STORE_PKGS $THEME_PKGS; do
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

# 6. iStore 的依赖链里有两个容易「不存在」的名字，单独点名确认它们真的在树里：
#      script-utils    -> package/utils/util-linux 的子包
#      coreutils-stty  -> 由 utils/coreutils 的 COREUTILS_APPLETS 循环生成
#    这两个符号一旦不存在，taskd 会被 defconfig 静默丢弃，整个应用商店消失。
grep -q 'BuildPackage,script-utils' package/utils/util-linux/Makefile \
	|| fail "util-linux 未提供 script-utils 子包（taskd 依赖，缺则 iStore 整条链被丢弃）"
[ -d package/feeds/packages/coreutils ] \
	|| fail "找不到 coreutils 包目录（taskd 依赖 coreutils-stty）"
grep -q 'stty' package/feeds/packages/coreutils/Makefile \
	|| fail "coreutils 未包含 stty applet（taskd 依赖 coreutils-stty）"
[ -e package/system/uci/Makefile ] || fail "找不到 uci 包目录"
grep -q 'BuildPackage,libuci-lua' package/system/uci/Makefile \
	|| fail "uci 未提供 libuci-lua 子包（luci-app-store 直接依赖）"

# 7. 首次启动固化设置：中文 + Argon 默认主题 + 关键服务自启
#    uci-defaults 由 base-files 的 /etc/init.d/boot(S10boot) 逐个 `.` 源入执行，
#    所以 ① 不需要执行位；② 必须自己 start（S10boot 跑的时候 S9x 的 rc.d 已经错过）。
#    写进 package/base-files/files/ 会随 base-files 包一起落到根文件系统。
UCI_DEFAULTS_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS_DIR"
cat > "$UCI_DEFAULTS_DIR/99-natserver" <<'EOF'
#!/bin/sh
# NatserverWrt · CMCC RAX3000M (eMMC) 首次启动固化设置

# 1) 默认语言固定为简体中文（只在空/auto 时改，用户自己改过就尊重用户）
cur="$(uci -q get luci.main.lang 2>/dev/null)"
case "$cur" in
	""|auto) uci -q set luci.main.lang=zh-cn ;;
esac
uci -q set luci.languages.zh_cn='简体中文 (Simplified Chinese)'
uci -q commit luci

# 2) 默认主题 Argon（iStoreOS 同款外观）
#    luci-theme-argon 自带的 30_luci-theme-argon 已做同样的事，这里做幂等兜底，
#    避免包顺序变化时退回 bootstrap 主题。
if [ -d /www/luci-static/argon ]; then
	uci -q get luci.themes.Argon >/dev/null 2>&1 || \
		uci -q set luci.themes.Argon=/luci-static/argon
	case "$(uci -q get luci.main.mediaurlbase)" in
		""|/luci-static/bootstrap)
			uci -q set luci.main.mediaurlbase=/luci-static/argon ;;
	esac
	uci -q commit luci
fi

# 3) 服务开机自启
#    taskd 的包只装 /etc/init.d/tasks，不建 /etc/rc.d/S??tasks 软链；
#    从源码全新构建（而非官方预编译镜像）时首次启动就是停的，
#    表现就是「iStore 应用商店打不开」。逐个探测，缺包时跳过。
enable_if_present() {
	for s in "$@"; do
		[ -x "/etc/init.d/$s" ] || continue
		/etc/init.d/"$s" enable >/dev/null 2>&1
		/etc/init.d/"$s" start  >/dev/null 2>&1
	done
}
enable_if_present tasks ttyd

rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
exit 0
EOF
chmod 644 "$UCI_DEFAULTS_DIR/99-natserver"
[ -s "$UCI_DEFAULTS_DIR/99-natserver" ] || fail "uci-defaults 脚本写入失败"
sh -n "$UCI_DEFAULTS_DIR/99-natserver" || fail "uci-defaults 脚本语法错误"

echo "diy-part2 OK"
