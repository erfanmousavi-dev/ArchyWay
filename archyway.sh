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
sleep 3
clear 
echo "Hi there !"

#Setting time
timedatectl

#Making Partitions 
clear
lsblk
read -rp "Enter install disk (e.g., /dev/sda or /dev/nvme0n1): " DISK
echo "This will remove everything on $DISK. Are you sure (yes/no)? "
read -r confirm
if [[ $confirm != "yes" ]]; then
	echo "Aborted"
	exit 1
fi

echo "Creating partitions on $DISK ..."
parted -s "$DISK" mklabel gpt
fdisk "$DISK" <<EOF
g
n
1

+1G
t
1
n
2


w
EOF

BOOT_PART="${DISK}1"
CRYPT_PART="${DISK}2"

mkfs.fat -F32 "$BOOT_PART"

echo "Encrypting root partition..."
cryptsetup luksFormat "$CRYPT_PART"
cryptsetup open "$CRYPT_PART" cryptroot

pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
read -rp "Enter swap size (e.g., 2): " SWAP_SIZE
read -rp "Enter root size (e.g., 20): " ROOT_SIZE
lvcreate -L "${SWAP_SIZE}G" vg0 -n swap
lvcreate -L "${ROOT_SIZE}G" vg0 -n root
lvcreate -l 100%FREE vg0 -n home

mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/home
mkswap /dev/vg0/swap
swapon /dev/vg0/swap

mount /dev/vg0/root /mnt
mkdir /mnt/boot
mount "$BOOT_PART" /mnt/boot
mkdir /mnt/home
mount /dev/vg0/home /mnt

# Installing base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware vim sudo lvm2 grub efibootmgr networkmanager dhclient

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# chroot into system
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "archlinux" > /etc/hostname
cat << EOH > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
EOH

# Initramfs with encrypt and lvm2
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "Set root password"
passwd

# Install GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

UUID=$(blkid -s UUID -o value "$CRYPT_PART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:cryptroot root=/dev/vg0/root\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
EOF

echo "Installation complete! You can reboot now."