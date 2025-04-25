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
sleep 3
clear 
echo "This Script will install Arch linux with encryption and nix package manager and hyprland for WM"

clear
lsblk
echo ""
read -p  "Please select a disk for arch linux installation(/dev/sdX) : " DISK

fdisk $DISK <<EOF
g
w
EOF

fdisk $DISK <<EOF
n

+1G
n


+1G
n



t
1
44
w
EOF