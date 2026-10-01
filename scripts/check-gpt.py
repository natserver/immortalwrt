#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解析 OpenWrt 生成的 GPT 镜像（emmc-gpt.bin），打印分区表并断言关键分区大小。

用法:
    check-gpt.py <gpt.bin> [--expect NAME=SIZE_MIB ...]

为什么需要它：CONFIG_TARGET_ROOTFS_PARTSIZE 是通过
target/linux/mediatek/image/filogic.mk 的 Build/mt798x-gpt -> ptgen 生成分区表的。
kconfig 里写对了不等于分区表里生效（符号被 defconfig 丢弃 / 变量没传到 ptgen 都会静默出错），
所以这里直接解析产物，把「系统分区到底是多大」变成构建期的硬断言。
"""
import struct
import sys


def read_gpt(path):
    with open(path, 'rb') as fh:
        data = fh.read()

    if data[512:520] != b'EFI PART':
        raise SystemExit('::error::%s 不是合法的 GPT（LBA1 没有 EFI PART 签名）' % path)

    hdr = data[512:512 + 92]
    entry_lba = struct.unpack_from('<Q', hdr, 72)[0]
    num_entries = struct.unpack_from('<I', hdr, 80)[0]
    entry_size = struct.unpack_from('<I', hdr, 84)[0]
    base = entry_lba * 512

    parts = []
    for i in range(num_entries):
        ent = data[base + i * entry_size:base + (i + 1) * entry_size]
        if len(ent) < 128 or ent[:16] == b'\x00' * 16:
            continue
        first = struct.unpack_from('<Q', ent, 32)[0]
        last = struct.unpack_from('<Q', ent, 40)[0]
        name = ent[56:128].decode('utf-16-le').rstrip('\x00')
        parts.append({
            'name': name,
            # 分区表按 512B 扇区计数
            'start_mib': first * 512 / 1048576.0,
            'size_mib': (last - first + 1) * 512 / 1048576.0,
        })
    return parts


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)

    path = argv[1]
    expects = {}
    it = iter(argv[2:])
    for arg in it:
        if arg == '--expect':
            spec = next(it, None)
            if not spec or '=' not in spec:
                raise SystemExit('--expect 需要 NAME=SIZE_MIB 形式')
            name, size = spec.split('=', 1)
            expects[name.strip()] = float(size.strip())
        else:
            raise SystemExit('无法识别的参数: %s' % arg)

    parts = read_gpt(path)
    print('分区表 (%s):' % path)
    for p in parts:
        print('  %-12s %10.1f MiB  @ %8.1f MiB' % (p['name'], p['size_mib'], p['start_mib']))

    by_name = {p['name']: p for p in parts}
    failed = False
    for name, want in expects.items():
        got = by_name.get(name)
        if got is None:
            print('::error::GPT 里没有 %s 分区' % name)
            failed = True
            continue
        if abs(got['size_mib'] - want) > 0.5:
            print('::error::%s 分区 = %.1f MiB，期望 %.1f MiB'
                  % (name, got['size_mib'], want))
            failed = True
        else:
            print('  ok      %s = %.0f MiB' % (name, got['size_mib']))

    if failed:
        return 1
    print('分区校验通过')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
