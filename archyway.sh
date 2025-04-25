#!/bin/bash

set -e

clear
cat << "EOF"

/ ___|  ___ _ __(_)_ __ | |_ 
\___ \ / __| '__| | '_ \| __|
 ___) | (__| |  | | |_) | |_ 
|____/ \___|_|  |_| .__/ \__|
                  |_|        
| __ ) _   _ 
|  _ \| | | |
| |_) | |_| |
|____/ \__, |
       |___/ 
| ____|_ __ / _| __ _ _ __   |  \/  | ___  _   _ ___  __ ___   _(_)
|  _| | '__| |_ / _` | '_ \  | |\/| |/ _ \| | | / __|/ _` \ \ / / |
| |___| |  |  _| (_| | | | | | |  | | (_) | |_| \__ \ (_| |\ V /| |
|_____|_|  |_|  \__,_|_| |_| |_|  |_|\___/ \__,_|___/\__,_| \_/ |_|


EOF
sleep 2
clear
echo "Welcome to your custom Arch Linux installer!"

# Step: Check internet and time
timedatectl
ping -c 1 archlinux.org || { echo "Internet not available!"; exit 1; }

# Ask for disk only if not already partitioned
if ! ls /dev/mapper/cryptroot >/dev/null 2>&1; then
    lsblk
    read -rp "Enter install disk (e.g., /dev/sda or /dev/nvme0n1): " DISK

    echo "This will erase everything on $DISK. Are you sure? (yes/no): "
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted"
        exit 1
    fi

    wipefs -a "$DISK"
    parted -s "$DISK" mklabel gpt

    parted -s "$DISK" mkpart primary fat32 1MiB 1025MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary ext4 1025MiB 100%

    if [[ "$DISK" == *"nvme"* ]]; then
        BOOT_PART="${DISK}p1"
        CRYPT_PART="${DISK}p2"
    else
        BOOT_PART="${DISK}1"
        CRYPT_PART="${DISK}2"
    fi

    mkfs.fat -F32 "$BOOT_PART"

    echo "Encrypting root partition..."
    cryptsetup luksFormat "$CRYPT_PART"
    cryptsetup open "$CRYPT_PART" cryptroot

    pvcreate /dev/mapper/cryptroot
    vgcreate vg0 /dev/mapper/cryptroot

    read -rp "Enter swap size in GB (e.g., 2): " SWAP_SIZE
    read -rp "Enter root size in GB (e.g., 20): " ROOT_SIZE

    lvcreate -L "${SWAP_SIZE}G" vg0 -n swap
    lvcreate -L "${ROOT_SIZE}G" vg0 -n root
    lvcreate -l 100%FREE vg0 -n home

    mkfs.ext4 /dev/vg0/root
    mkfs.ext4 /dev/vg0/home
    mkswap /dev/vg0/swap
    swapon /dev/vg0/swap

    mount /dev/vg0/root /mnt
    mkdir -p /mnt/{boot,home}
    mount "$BOOT_PART" /mnt/boot
    mount /dev/vg0/home /mnt/home
else
    echo "Encrypted volume already opened. Mounting..."
    mount /dev/vg0/root /mnt || true
    mount /dev/vg0/home /mnt/home || true
    mount "$BOOT_PART" /mnt/boot || true
    swapon /dev/vg0/swap || true
fi

# Step: Base install (skip if already exists)
if [ ! -f /mnt/etc/fstab ]; then
    echo "Installing base system..."
    pacstrap /mnt base linux linux-firmware vim sudo lvm2 grub efibootmgr networkmanager dhclient bash-completion man-db man-pages git reflector
    genfstab -U /mnt >> /mnt/etc/fstab
fi

# Step: chroot configuration
arch-chroot /mnt /bin/bash <<'EOF'
set -e

# Locale and time
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
hwclock --systohc
sed -i '/en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "archlinux" > /etc/hostname
cat << HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
HOSTS

# Initramfs
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Root password setup
while true; do
    echo "Set root password:"
    if passwd; then
        break
    else
        echo "Password setting failed, try again..."
    fi
done

# GRUB setup
UUID=$(blkid -s UUID -o value "$(blkid | grep cryptroot | cut -d: -f1)")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:cryptroot root=/dev/vg0/root\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager
EOF

echo "Installation finished successfully! You can now reboot."