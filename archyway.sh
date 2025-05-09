#!/bin/bash

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

base_install() {
    timedatectl set-ntp true

    lsblk
    read -rp "Enter target disk (e.g., /dev/sda, /dev/nvme0n1): " DISK

    wipefs -a "$DISK"
    sgdisk -Z "$DISK"
    sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
    sgdisk -n 2:0:0 -t 2:8300 "$DISK"

    if [[ "$DISK" == *"nvme"* ]]; then
        BOOT="${DISK}p1"
        CRYPTPART="${DISK}p2"
    else
        BOOT="${DISK}1"
        CRYPTPART="${DISK}2"
    fi

    mkfs.fat -F32 "$BOOT"
    cryptsetup luksFormat "$CRYPTPART"
    cryptsetup open "$CRYPTPART" cryptroot
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

    mount /dev/vg0/root /mnt
    mkdir -p /mnt/{boot,home}
    mount "$BOOT" /mnt/boot
    mount /dev/vg0/home /mnt/home
    swapon /dev/vg0/swap

    until pacstrap /mnt base linux linux-firmware vim lvm2 grub efibootmgr dhclient sudo git; do
        echo "Pacstrap failed retrying in 3 sec..."
        sleep 3
    done

    genfstab -U /mnt >> /mnt/etc/fstab
    arch-chroot /mnt passwd

    read -rp "Enter system hostname: " HOST_NAME
    read -rp "Enter username to create: " USER_NAME
    read -rp "Enter password for $USER_NAME: " USER_PASS

    arch-chroot /mnt /bin/bash << EOF
set -e
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOST_NAME" > /etc/hostname
cat << EOH > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOST_NAME.localdomain $HOST_NAME
EOH

useradd -m -G wheel -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASS" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P

CRYPTUUID=\$(blkid -s UUID -o value "$CRYPTPART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$CRYPTUUID:cryptroot root=/dev/vg0/root\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

post_install() {
    while true; do
        clear
        echo "======================="
        echo "       Post Install       "
        echo "======================="
        echo "1. Post install in arch installation iso "
        echo "2. Post install in installed arch system "
        echo "3. Back"
        echo
        read -p "Choose an option [1-3]: " choice

        case $choice in
            1)
                arch-chroot /mnt /bin/bash << EOF
git clone https://github.com/erfanmousavi-dev/Arch-Hyprland
cd Arch-Hyprland
./install.sh
EOF
                ;;
            2)
                git clone https://github.com/erfanmousavi-dev/Arch-Hyprland.git
                cd Arch-Hyprland
                ./install.sh
                ;;
            3)
                echo "Exiting post install menu..."
                break
                ;;
            *)
                echo "Invalid option!"
                ;;
        esac
        read -p "Press Enter to continue..." dummy
    done
}

while true; do
    clear
    echo "======================="
    echo "       Main Menu       "
    echo "======================="
    echo "1. Install Base System"
    echo "2. Install Desktop Environment"
    echo "3. Exit"
    echo
    read -p "Choose an option [1-3]: " choice

    case $choice in
        1)
            base_install
            ;;
        2)
            post_install
            ;;
        3)
            echo "Exiting..."
            break
            ;;
        *)
            echo "Invalid option!"
            ;;
    esac

    echo
    read -p "Press Enter to continue..." dummy
done