#!/bin/bash
# ---- 依赖自检 ----
MISSING=()
for cmd in parted mkfs.ext4 mkfs.vfat rsync blkid grub-install; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "缺少命令: ${MISSING[*]}，尝试自动安装..."
  apt-get update && apt-get install -y \
    parted dosfstools e2fsprogs rsync grub-pc-bin grub-efi-amd64-bin grub-common
  # 安装后复检
  for cmd in "${MISSING[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "仍然缺少: $cmd，请检查网络/软件源"; exit 1; }
  done
fi
# ---- 以下是原有逻辑 ----
set -euo pipefail

# 必须以 root 运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo $0"
  exit 1
fi

# ---------- 1. 识别当前系统所在的盘（U 盘） ----------
ROOT_SRC=$(findmnt -n -o SOURCE /)
ROOT_DISK_NAME=$(lsblk -no PKNAME "$ROOT_SRC")
ROOT_DISK="/dev/$ROOT_DISK_NAME"
echo "当前系统所在盘（将被排除）：$ROOT_DISK"

# ---------- 2. 列出其他候选硬盘 ----------
mapfile -t CANDIDATES < <(
  lsblk -dno NAME,SIZE,MODEL,TYPE |
  awk '$4=="disk" {print $1}'
)

TARGETS=()
for d in "${CANDIDATES[@]}"; do
  dev="/dev/$d"
  [ "$dev" = "$ROOT_DISK" ] && continue
  TARGETS+=("$dev")
done

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "没有找到可安装的目标硬盘（已排除 U 盘 $ROOT_DISK）"
  exit 1
fi

echo
echo "可安装的目标硬盘："
for i in "${!TARGETS[@]}"; do
  dev="${TARGETS[$i]}"
  info=$(lsblk -dno SIZE,MODEL "$dev")
  echo "  [$i] $dev  $info"
done

read -rp "请选择目标硬盘编号（输入后回车，输入 q 退出）: " choice
[ "$choice" = "q" ] && exit 0
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge ${#TARGETS[@]} ]; then
  echo "无效选择"
  exit 1
fi

TARGET="${TARGETS[$choice]}"
echo "目标盘：$TARGET"

read -rp "警告：$TARGET 上的所有数据将被清空，确认继续？(yes/no): " confirm
[ "$confirm" = "yes" ] || { echo "已取消"; exit 0; }

# ---------- 3. 卸载目标盘上已挂载的分区 ----------
for p in $(lsblk -lno NAME "$TARGET" | tail -n +2); do
  umount "/dev/$p" 2>/dev/null || true
done

# ---------- 4. 分区 ----------
# GPT：p1 BIOS boot 2M，p2 EFI 100M，p3 root 剩余
parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart biosboot 1MiB 3MiB
parted -s "$TARGET" set 1 bios_grub on
parted -s "$TARGET" mkpart efi fat32 3MiB 103MiB
parted -s "$TARGET" set 2 esp on
parted -s "$TARGET" mkpart root ext4 103MiB 100%
partprobe "$TARGET"
sleep 2

# 设备名后缀：/dev/sda -> sda1；/dev/nvme0n1 -> nvme0n1p1
if [[ "$TARGET" =~ nvme ]]; then
  P1="${TARGET}p1"; P2="${TARGET}p2"; P3="${TARGET}p3"
else
  P1="${TARGET}1"; P2="${TARGET}2"; P3="${TARGET}3"
fi

mkfs.fat -F32 "$P2"
mkfs.ext4 -F -L rootfs "$P3"

# ---------- 5. 复制 rootfs / 内核 / 模块 ----------
mkdir -p /mnt/target /mnt/target-efi
mount "$P3" /mnt/target
mount "$P2" /mnt/target-efi

echo "复制根文件系统..."
rsync -aAXHSx --numeric-ids --exclude=/proc --exclude=/sys --exclude=/dev \
      --exclude=/mnt --exclude=/media --exclude=/run --exclude=/tmp \
      --exclude=/boot --exclude=/lib/modules \
      / /mnt/target/

# 内核
mkdir -p /mnt/target/boot
cp /boot/vmlinuz-* /mnt/target/boot/
cp /boot/initrd.img-* /mnt/target/boot/ 2>/dev/null || true
cp /boot/config-* /mnt/target/boot/ 2>/dev/null || true

# 模块
mkdir -p /mnt/target/lib/modules
cp -a /lib/modules/* /mnt/target/lib/modules/

# 基础目录
mkdir -p /mnt/target/{proc,sys,dev,run,tmp,mnt,media}
chmod 1777 /mnt/target/tmp

# fstab
cat > /mnt/target/etc/fstab <<EOF
LABEL=rootfs  /          ext4  errors=remount-ro  0  1
UUID=$(blkid -s UUID -o value "$P2")  /boot/efi  vfat  umask=0077  0  1
EOF

# ---------- 6. chroot 装 GRUB ----------
mount --bind /dev  /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys  /mnt/target/sys

chroot /mnt/target /bin/bash -c "
  export DEBIAN_FRONTEND=noninteractive
  grub-install --target=i386-pc --recheck '$TARGET' || true
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck || true
"

# 如果 chroot 失败，用当前系统的 grub 回退
if [ ! -f /mnt/target/boot/grub/i386-pc/normal.mod ]; then
  grub-install --target=i386-pc --boot-directory=/mnt/target/boot "$TARGET" || true
fi

# 写 grub.cfg
KVER=$(ls /mnt/target/boot/vmlinuz-* | head -1 | sed 's|.*/vmlinuz-||')
cat > /mnt/target/boot/grub/grub.cfg <<EOF
set default=0
set timeout=5

menuentry "Debian ${KVER}" {
    linux /boot/vmlinuz-${KVER} root=LABEL=rootfs rw quiet
    initrd /boot/initrd.img-${KVER}
}

menuentry "Debian ${KVER} (recovery)" {
    linux /boot/vmlinuz-${KVER} root=LABEL=rootfs rw single
    initrd /boot/initrd.img-${KVER}
}
EOF

umount /mnt/target/dev /mnt/target/proc /mnt/target/sys 2>/dev/null || true
umount /mnt/target-efi
umount /mnt/target

echo "安装完成。拔出 U 盘，从 $TARGET 启动。"