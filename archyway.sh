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

while true; do
    echo "Main Menu"
    echo "1)Make Partitions"
    echo "2)Install Base System"
    echo "3)Exit"
    read -p "Please Enter an option : " choice

    case $choice in
        1)
            # Sync clock
timedatectl set-ntp true

# Select disk
lsblk
read -rp "Enter target disk (e.g., /dev/sda, /dev/nvme0n1): " DISK

# Wipe and partition
wipefs -a "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 -t 2:8300 "$DISK"

# Assign partitions
if [[ "$DISK" == *"nvme"* ]]; then
    BOOT="${DISK}p1"
    CRYPTPART="${DISK}p2"
else
    BOOT="${DISK}1"
    CRYPTPART="${DISK}2"
fi

# Make filesystem
mkfs.fat -F32 "$BOOT"

# Setup LUKS
cryptsetup luksFormat "$CRYPTPART"
cryptsetup open "$CRYPTPART" cryptroot

# Setup LVM
pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot

read -rp "Enter swap size in GB (e.g., 2): " SWAP_SIZE
read -rp "Enter root size in GB (e.g., 20): " ROOT_SIZE

lvcreate -L "${SWAP_SIZE}G" vg0 -n swap
lvcreate -L "${ROOT_SIZE}G" vg0 -n root
lvcreate -l 100%FREE vg0 -n home

# Filesystem setup
mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/home
mkswap /dev/vg0/swap

# Mounting
mount /dev/vg0/root /mnt
mkdir -p /mnt/{boot,home}
mount "$BOOT" /mnt/boot
mount /dev/vg0/home /mnt/home
swapon /dev/vg0/swap

            ;;
        2)
            # Install base system
until pacstrap /mnt base linux linux-firmware vim sudo lvm2 networkmanager grub efibootmgr; do
    echo "pacstrap failed retrying in 3 sec..."
    sleep 3
    done

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Passwd
arch-chroot /mnt passwd
# Chroot
arch-chroot /mnt /bin/bash << EOF
set -e

# Time, Locale
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "archlinux" > /etc/hostname
cat << HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
HOSTS

# Initramfs for encryption and lvm
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Configure GRUB
CRYPTUUID=\$(blkid -s UUID -o value "$CRYPTPART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$CRYPTUUID:cryptroot root=/dev/vg0/root\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
EOF

echo -e "Installation completed successfully! You can now reboot."
            ;;
        3)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
    echo
done