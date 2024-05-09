#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Set up keyboard layout
loadkeys la-latin1

# Set the system clock
timedatectl set-ntp true
timedatectl status

# Partition the disk (assuming /dev/sda)
parted /dev/sda --script mklabel gpt
parted /dev/sda --script mkpart ESP fat32 1MiB 1025MiB
parted /dev/sda --script set 1 esp on
parted /dev/sda --script mkpart primary ext4 1025MiB 100%

# Format the partitions
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

# Mount the file systems
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

# Install base system
pacstrap /mnt base base-devel gnome gnome-tweaks grub linux linux-firmware nano networkmanager sudo vi

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into new system and configure further
arch-chroot /mnt /bin/bash <<EOF

# Generate swap file
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Set time zone
ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime
hwclock --systohc

# Localization
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Set the console keyboard layout
echo "KEYMAP=la-latin1" > /etc/vconsole.conf

# Network configuration
# Manual entry for hostname and user setup
echo "Enter a hostname for your system:"
read hostname
echo "\$hostname" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 \$hostname.localdomain \$hostname" >> /etc/hosts

# Root password
echo "Enter password for root user:"
passwd root

# Add another user with sudo privileges
echo "Enter a username for the primary user:"
read username
useradd -m -G wheel -s /bin/bash \$username
echo "Enter password for user \$username:"
passwd \$username
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Install and configure bootloader
pacman -S grub --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable necessary services
systemctl enable gdm
systemctl enable NetworkManager

# Set regional formats
localectl set-locale LC_NUMERIC=es_CL.UTF-8 LC_TIME=es_CL.UTF-8 LC_MONETARY=es_CL.UTF-8 LC_PAPER=es_CL.UTF-8 LC_NAME=es_CL.UTF-8 LC_ADDRESS=es_CL.UTF-8 LC_TELEPHONE=es_CL.UTF-8 LC_MEASUREMENT=es_CL.UTF-8 LC_IDENTIFICATION=es_CL.UTF-8

EOF

# Exit chroot is now redundant because the EOF marks the end of the chroot commands

# Unmount all partitions
umount -R /mnt
swapoff -a

# Reboot
reboot