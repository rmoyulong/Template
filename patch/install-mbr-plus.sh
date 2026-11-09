#!/bin/bash
# install-mbr-plus.sh —— 把 /root/rootfs.tar.gz 安装到目标内部硬盘（MBR 分区表）
# 分区对齐 build-img-mbr.yml：msdos 分区表，p1 FAT32 200MiB(boot on)，p2 EXT4 剩余
# rootfs 来源：/root/rootfs.tar.gz（可用第 1 个参数或环境变量 ROOTFS_TARBALL 指定）
# 内核与 modules 来源：当前运行的 U 盘系统（/boot、/lib/modules），不使用 tar 内的
# 三路 GRUB：BIOS(i386-pc) + 64 位 UEFI + 32 位 UEFI（兼容 J1800 这类 32 位 UEFI 老机器）
set -euo pipefail

# ---------- 0. 前置检查 ----------
if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo $0" >&2
  echo "Please run with root privileges: sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# rootfs 压缩包：命令行参数 > 环境变量 > 常见位置自动查找
ROOTFS_TARBALL="${1:-${ROOTFS_TARBALL:-}}"
if [ -z "$ROOTFS_TARBALL" ]; then
  for c in /root/rootfs.tar.gz /rootfs.tar.gz /rootfs/rootfs.tar.gz ./rootfs.tar.gz; do
    if [ -f "$c" ]; then
      ROOTFS_TARBALL="$c"
      break
    fi
  done
fi

if [ -z "$ROOTFS_TARBALL" ] || [ ! -f "$ROOTFS_TARBALL" ]; then
  echo "找不到 rootfs 压缩包。Could not find the rootfs archive." >&2
  echo "请把它放到 /root/rootfs.tar.gz，或显式指定路径：" >&2
  echo "Please place it at /root/rootfs.tar.gz, or explicitly specify the path:" >&2
  echo "  $0 /path/to/rootfs.tar.gz" >&2
  exit 1
fi

# 校验确实是可读的 gzip tar，避免解压到一半才发现文件坏了（大包会需要几十秒）
echo "正在校验 rootfs 压缩包完整性...Verifying the integrity of the rootfs archive..."
if ! tar -tzf "$ROOTFS_TARBALL" >/dev/null 2>&1; then
  echo "rootfs 压缩包无法读取（不是有效的 tar.gz？）：$ROOTFS_TARBALL" >&2
  echo "rootfs The archive cannot be read (is it not a valid tar.gz file?)：$ROOTFS_TARBALL" >&2
  exit 1
fi

echo "rootfs 压缩包（Compressed archive）：$ROOTFS_TARBALL ($(du -h "$ROOTFS_TARBALL" | cut -f1))"

# 依赖自检（缺则自动安装）
MISSING=()
for cmd in parted partprobe mkfs.ext4 mkfs.vfat blkid tar grub-install; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "缺少命令: ${MISSING[*]}，尝试自动安装..."
  echo "Missing commands: ${MISSING[*]}; attempting automatic installation..."
  apt-get update
  apt-get install -y --no-install-recommends \
    parted dosfstools e2fsprogs tar \
    grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin grub-common
  for cmd in "${MISSING[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "仍然缺少: $cmd，请检查网络/软件源" >&2
	  echo "Still missing: $cmd; please check your network or software sources." >&2
      exit 1
    }
  done
fi

# 校验源系统内核存在（rootfs 不含内核，必须从当前系统补入）
if ! ls /boot/vmlinuz-* >/dev/null 2>&1 && [ ! -f /boot/bzImage ]; then
  echo "当前系统 /boot 下既没有 vmlinuz-* 也没有 bzImage，无法补入内核" >&2
  echo "There are neither vmlinuz-* nor bzImage files under /boot in the current system, making it impossible to add a kernel." >&2
  exit 1
fi

# ---------- 1. 识别当前系统所在盘（将被排除，避免误格 U 盘） ----------
ROOT_SRC=$(findmnt -n -o SOURCE /)
if [[ "$ROOT_SRC" =~ ^/dev/ ]]; then
  ROOT_DISK_NAME=$(lsblk -no PKNAME "$ROOT_SRC")
else
  ROOT_DISK_NAME=$(lsblk -no PKNAME "/dev/${ROOT_SRC##*/}")
fi
ROOT_DISK="/dev/$ROOT_DISK_NAME"
echo "当前系统所在盘（将被排除）：$ROOT_DISK"
echo "The drive containing the current system (will be excluded)：$ROOT_DISK"

# ---------- 2. 列出其他候选硬盘 ----------
mapfile -t CANDIDATES < <(lsblk -dno NAME,TYPE | awk '$2=="disk" {print $1}')
TARGETS=()
for d in "${CANDIDATES[@]}"; do
  dev="/dev/$d"
  [ "$dev" = "$ROOT_DISK" ] && continue
  TARGETS+=("$dev")
done
if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "没有找到可安装的目标硬盘（已排除当前盘 $ROOT_DISK）" >&2
  echo "No target hard drive available for installation (current drive excluded $ROOT_DISK）" >&2
  exit 1
fi

echo
echo "可安装的目标硬盘："
echo "Target hard drive available for installation："
for i in "${!TARGETS[@]}"; do
  dev="${TARGETS[$i]}"
  info=$(lsblk -dno SIZE,MODEL "$dev" 2>/dev/null || echo "")
  echo " [$i] $dev $info"
done
echo "Please select the target hard drive number (enter q to exit):"
read -rp "请选择目标硬盘编号（输入 q 退出）: " choice
[ "$choice" = "q" ] && exit 0
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge ${#TARGETS[@]} ]; then
  echo "无效选择" >&2
  echo "Invalid Choice" >&2; exit 1
fi
TARGET="${TARGETS[$choice]}"
echo "目标盘：$TARGET"
echo "Target Disk：$TARGET"

echo "Warning: All data on $TARGET will be erased. Confirm to continue? (yes/no):"
read -rp "警告：$TARGET 上的所有数据将被清空，确认继续？(yes/no): " confirm
[ "$confirm" = "yes" ] || { echo "已取消（Cancelled）"; exit 0; }

# ---------- 3. 卸载目标盘上已挂载的分区 ----------
for p in $(lsblk -lno NAME "$TARGET" 2>/dev/null | tail -n +2); do
  umount "/dev/$p" 2>/dev/null || true
done

# ---------- 4. 分区：msdos + p1 FAT32 200MiB(boot on) + p2 EXT4 剩余 ----------
echo "正在分区：$TARGET"
parted -s "$TARGET" mklabel msdos
parted -s "$TARGET" mkpart primary fat32 1MiB 201MiB
parted -s "$TARGET" set 1 boot on
parted -s "$TARGET" mkpart primary ext4 201MiB 100%
partprobe "$TARGET"

# 等待分区节点出现（兼容 NVMe: nvme0n1p1 和 sdX: sda1 两种命名）
if [[ "$TARGET" =~ nvme ]]; then
  P1="${TARGET}p1"
  P2="${TARGET}p2"
else
  P1="${TARGET}1"
  P2="${TARGET}2"
fi
for i in 1 2 3 4 5; do
  sleep 1
  [ -b "$P1" ] && [ -b "$P2" ] && break
done
[ -b "$P1" ] && [ -b "$P2" ] || {
  echo "分区设备节点未出现，请检查磁盘" >&2; exit 1
}

mkfs.vfat -F32 "$P1"
mkfs.ext4 -F -L rootfs "$P2"

ROOT_UUID=$(blkid -s UUID -o value "$P2")
echo "根分区 UUID: $ROOT_UUID"

# ---------- 5. 先挂根分区并解压 rootfs；EFI 分区必须在解压之后才挂 ----------
mkdir -p /mnt/target
mount "$P2" /mnt/target

#/mnt子目录
sudo mkdir -p /mnt/target/mnt/aliyundrive /mnt/target/mnt/boot /mnt/target/mnt/rootfs /mnt/target/mnt/music
sudo mkdir -p /mnt/target/mnt/sd /mnt/target/mnt/usb /mnt/target/mnt/NAS 


echo "解压 rootfs 到目标盘（文件较大，请耐心等待）..."
# --xattrs --acls 必须与打包端（build-rootfs.yml: tar --acls --xattrs）对应；
# 少了它们，文件 capability（如 ping 的 cap_net_raw）与 POSIX ACL 会在解压时静默丢失。
if ! tar -xzf "$ROOTFS_TARBALL" -C /mnt/target --numeric-owner --xattrs --acls; then
  echo "解压失败：请检查目标盘剩余空间与压缩包完整性" >&2
  exit 1
fi

echo "补入当前系统的内核与模块（覆盖 tar 内的同名内容）..."
# 模块：先清掉 tar 里带来的，避免多版本混杂
rm -rf /mnt/target/lib/modules
mkdir -p /mnt/target/lib/modules
cp -a /lib/modules/. /mnt/target/lib/modules/

# 内核 / initrd / config：同样先清掉 tar 里带来的
mkdir -p /mnt/target/boot
rm -f /mnt/target/boot/vmlinuz-* /mnt/target/boot/initrd.img-* /mnt/target/boot/config-* 2>/dev/null || true
if ls /boot/vmlinuz-* >/dev/null 2>&1; then
  cp -a /boot/vmlinuz-* /mnt/target/boot/
  cp -a /boot/initrd.img-* /mnt/target/boot/ 2>/dev/null || true
  cp -a /boot/config-* /mnt/target/boot/ 2>/dev/null || true
else
  # 仅有 bzImage 时按当前内核版本命名
  cp -a /boot/bzImage "/mnt/target/boot/vmlinuz-$(uname -r)"
  cp -a /boot/config-* /mnt/target/boot/ 2>/dev/null || true
fi

# 基础目录（/boot/efi 必须等 rootfs 解压出来后再建、再挂）
mkdir -p /mnt/target/{proc,sys,dev,run,tmp,mnt,media,boot/efi}
chmod 1777 /mnt/target/tmp

# EFI 分区挂载必须晚于 rootfs 解压：挂载点 /boot/efi 是由 rootfs 解压产生的
mount "$P1" /mnt/target/boot/efi
mountpoint -q /mnt/target/boot/efi || {
  echo "EFI 分区挂载失败：$P1 -> /mnt/target/boot/efi" >&2; exit 1
}

# fstab：根用 UUID（唯一稳定），EFI 分区按 UUID 挂载
EFI_UUID=$(blkid -s UUID -o value "$P1")
cat > /mnt/target/etc/fstab <<EOF
UUID=${ROOT_UUID} / ext4 errors=remount-ro 0 1
UUID=${EFI_UUID} /boot/efi vfat umask=0077 0 1
EOF

# ---------- 6. chroot 安装 GRUB（BIOS + 64EFI + 32EFI） ----------
mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys

# 把当前系统的 GRUB 平台模块复制进目标，保证离线时 32 位/64 位 UEFI 也能安装
# （目标 rootfs 由 debootstrap 生成，通常不含 grub-efi-ia32-bin）
mkdir -p /mnt/target/usr/lib/grub
for t in i386-pc x86_64-efi i386-efi; do
  if [ -d "/usr/lib/grub/$t" ]; then
    rm -rf "/mnt/target/usr/lib/grub/$t"
    cp -a "/usr/lib/grub/$t" /mnt/target/usr/lib/grub/
  else
    echo "[warn] 当前系统缺少 /usr/lib/grub/$t（该引导目标可能安装失败）"
  fi
done

echo "chroot 内安装 GRUB..."
chroot /mnt/target /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
# 目标 rootfs 若仍缺 32 位 EFI 模块，尝试联网补齐（离线时忽略即可，上面已从源系统复制）
[ -d /usr/lib/grub/i386-efi ] || (apt-get update && apt-get install -y --no-install-recommends grub-efi-ia32-bin) || true
grub-install --target=i386-pc --recheck --force '$TARGET' || echo '[warn] i386-pc 安装失败'
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck || echo '[warn] x86_64-efi 安装失败'
grub-install --target=i386-efi  --efi-directory=/boot/efi --bootloader-id=debian --recheck || echo '[warn] i386-efi 安装失败'
"

# chroot 失败则宿主机回退（BIOS 部分）
if [ ! -f /mnt/target/boot/grub/i386-pc/normal.mod ]; then
  echo "[warn] chroot BIOS 安装失败，使用宿主机 grub 回退"
  grub-install --target=i386-pc --boot-directory=/mnt/target/boot --force "$TARGET" || true
fi

# --- 固化 initramfs 配置：与 CI 构建镜像保持一致 ---
# MODULES=dep：只放入挂载根设备真正需要的模块，initramfs 最小化、开机最快。
#   本机内核已把 SATA/USB 控制器、USB 存储、键鼠 HID、VT 控制台、ext4 全部
#   内建，所以这里几乎不需要放任何 .ko。前提是 /boot/config-$(uname -r) 存在
#   （本脚本已随内核一起把它拷到目标盘）；若被删掉，dep 会判断不准。
# COMPRESS=zstd：initramfs 自身用 zstd 压缩，解压比 gzip 快 2~3 倍。
# FRAMEBUFFER=y：initramfs 阶段启用帧缓冲，GRUB 的 splash 才有开机画面。
# 已存在则改、不存在则追加，不动其它自定义项。
echo "固化 initramfs 配置（MODULES=dep, COMPRESS=zstd, FRAMEBUFFER=y）..."
chroot /mnt/target /bin/bash -c '
set -e
CONF=/etc/initramfs-tools/initramfs.conf
mkdir -p /etc/initramfs-tools
[ -f "$CONF" ] || : > "$CONF"
set_kv() {
  key="$1"; val="$2"
  if grep -qE "^[[:space:]]*${key}=" "$CONF"; then
    sed -i -E "s|^[[:space:]]*${key}=.*|${key}=${val}|" "$CONF"
  else
    printf "%s=%s\n" "$key" "$val" >> "$CONF"
  fi
}
set_kv MODULES dep
set_kv COMPRESS zstd
set_kv FRAMEBUFFER y
grep -E "^(MODULES|COMPRESS|FRAMEBUFFER)=" "$CONF" || true
'

# 重建 initramfs（避免源盘 UUID/resume 残留在 initrd 里）
echo "重建 initramfs..."
chroot /mnt/target /bin/bash -c "update-initramfs -u -k all 2>/dev/null || true"

# ---------- 7. 写 grub.cfg（LABEL + UUID 双根参数，与 CI 对齐） ----------
KVER=$(ls /mnt/target/boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|.*/vmlinuz-||')
if [ -z "$KVER" ]; then
  echo "未找到内核镜像" >&2; exit 1
fi
mkdir -p /mnt/target/boot/grub
cat > /mnt/target/boot/grub/grub.cfg <<EOF
set default=0
# 开机菜单停留 5 秒（与 rootfs 的 GRUB_TIMEOUT=5 保持一致）
set timeout=5
insmod all_video
set gfxmode=auto
set gfxpayload=keep

menuentry "Debian ${KVER}" {
    linux /boot/vmlinuz-${KVER} root=LABEL=rootfs root=UUID=${ROOT_UUID} rw quiet splash loglevel=3 console=tty1 vt.global_cursor_default=0 pcie_aspm=off usbcore.autosuspend=-1
    initrd /boot/initrd.img-${KVER}
}

menuentry "Debian ${KVER} (recovery)" {
    linux /boot/vmlinuz-${KVER} root=LABEL=rootfs root=UUID=${ROOT_UUID} rw single console=tty1
    initrd /boot/initrd.img-${KVER}
}
EOF

# Plymouth 生效性检查：initramfs 内必须含 plymouth，splash 才会出现开机画面
if chroot /mnt/target /bin/bash -c "lsinitramfs /boot/initrd.img-${KVER} 2>/dev/null | grep -q plymouth" 2>/dev/null; then
  echo "Plymouth 已打入 initramfs ✅"
else
  echo "WARN: initramfs 内未发现 plymouth，开机画面会退回纯文字"
fi

# 同步到 EFI 分区各引导目录，并放好 fallback 引导文件
mkdir -p /mnt/target/boot/efi/EFI/debian /mnt/target/boot/efi/EFI/BOOT
cp /mnt/target/boot/grub/grub.cfg /mnt/target/boot/efi/EFI/debian/grub.cfg 2>/dev/null || true
cp /mnt/target/boot/grub/grub.cfg /mnt/target/boot/efi/EFI/BOOT/grub.cfg 2>/dev/null || true
if [ -f /mnt/target/boot/efi/EFI/debian/grubx64.efi ]; then
  cp /mnt/target/boot/efi/EFI/debian/grubx64.efi /mnt/target/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true
fi
if [ -f /mnt/target/boot/efi/EFI/debian/grubia32.efi ]; then
  cp /mnt/target/boot/efi/EFI/debian/grubia32.efi /mnt/target/boot/efi/EFI/BOOT/BOOTIA32.EFI 2>/dev/null || true
fi

# ---------- 8. 卸载 ----------
sync
umount /mnt/target/dev /mnt/target/proc /mnt/target/sys 2>/dev/null || true
umount /mnt/target/boot/efi 2>/dev/null || true
umount /mnt/target 2>/dev/null || true

echo
echo "安装完成（MBR/msdos 分区表）。"
echo "  rootfs 来源: $ROOTFS_TARBALL"
echo "  目标盘    : $TARGET"
echo "  p1        : FAT32 200MiB (boot) → 用于 EFI 引导文件"
echo "  p2        : EXT4 rootfs → LABEL=rootfs UUID=$ROOT_UUID"
echo "  内核/模块 : 来自当前启动系统（$KVER）"
echo
echo "请拔掉当前启动介质，从 $TARGET 启动。"
echo "（老机器请在 BIOS 中设置 XHCI Hand-off=Disabled、EHCI Hand-off=Enabled）"
