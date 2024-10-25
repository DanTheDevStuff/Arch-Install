#!/bin/bash

# Arch Linux Installation Script
# DanTheDevStuff’s Original Arch Installation Script with Modifications

# Update the system clock
timedatectl set-ntp true

# Prompt for disk selection
echo "Select the disk to install Arch Linux (e.g., /dev/sda):"
read DISK

DISK = /dev/DISK

# Prompt for hostname setup
echo "Enter the desired hostname:"
read HOSTNAME

# Prompt for timezone selection
echo "Select your timezone (e.g., Europe/London):"
read TIMEZONE

# Partitioning (modify as needed for your system)
(
echo o       # Create a new empty DOS partition table
echo n       # Add a new partition
echo p       # Primary partition
echo 1       # Partition number
echo         # First sector (accept default)
echo +20G    # Last sector (20 GB partition for root)
echo n       # Add another partition
echo p       # Primary partition
echo 2       # Partition number
echo         # First sector (accept default)
echo         # Last sector (rest of the disk for home)
echo w       # Write changes
) | fdisk "$DISK"

# Format the partitions
mkfs.ext4 "${DISK}1"
mkfs.ext4 "${DISK}2"

# Mount the partitions
mount "${DISK}1" /mnt
mkdir /mnt/home
mount "${DISK}2" /mnt/home

# Install essential packages
pacstrap /mnt base linux linux-firmware

# Generate an fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
cat <<NETEOF >> /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
NETEOF

# Set root password
echo "Set the root password:"
passwd

# Prompt for username and password
echo "Enter username:"
read USERNAME
echo "Set password for $USERNAME:"
useradd -m -G wheel "$USERNAME"
passwd "$USERNAME"

# Install necessary packages
pacman -S --noconfirm grub efibootmgr networkmanager

# Static IP Configuration
cat <<STATICIP >> /etc/systemd/network/20-wired.network
[Match]
Name=en*

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=1.1.1.1
STATICIP

# Enable systemd-networkd
systemctl enable systemd-networkd.service
systemctl start systemd-networkd.service

# Firewall Configuration
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # Allow SSH access
iptables -A INPUT -i lo -j ACCEPT              # Allow loopback access

# Save the firewall rules
iptables-save > /etc/iptables/iptables.rules
systemctl enable iptables
systemctl start iptables

# Install and configure bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install Yay and Git
pacman -S --noconfirm git
cd /opt
git clone https://aur.archlinux.org/yay.git
chown -R $USER:$USER yay
cd yay
sudo -u $USER makepkg -si --noconfirm
cd ..

# Enable NetworkManager
systemctl enable NetworkManager

# Exit chroot
exit
EOF

# Unmount partitions
umount -R /mnt

# Prompt for reboot
echo "Installation complete! Would you like to reboot now? (y/n):"
read REBOOT_OPTION

if [[ "$REBOOT_OPTION" == "y" || "$REBOOT_OPTION" == "Y" ]]; then
    reboot
else
    echo "You can reboot later by running 'reboot' command."
fi