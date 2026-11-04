apt update
apt install -y cloud-guest-utils
ROOT_PART=$(findmnt -n -o SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_PART")
PART_NUM=$(cat /sys/class/block/$(basename "$ROOT_PART")/partition)
growpart "/dev/$ROOT_DISK" "$PART_NUM"
resize2fs "$ROOT_PART"