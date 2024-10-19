#!/bin/bash

#Get info from user for install
echo What disk do you want to install Arch to?
read selDisk

echo Create a hostname:
read HOSTNAME

echo Create a user:
read USERNAME

echo Add a password:
read PASSWORD


# Variables - adjust as needed
DISK="/dev/$selDisk"

# Update system clock
timedatectl set-ntp true

# Partition the disk (modify as needed)
echo "Partitioning the disk..."
(
  echo o      # Create a new empty DOS partition table
  echo n      # Add a new partition (primary)
  echo p
  echo 1      # Partition number
  echo        # Default - start at beginning of disk
  echo +512M  # Size for boot partition
  echo n      # Add another partition (root)
  echo p
  echo 2
  echo        # Default - start immediately after preceding partition
  echo        # Default - extend to end of disk
  echo a      # Make partition 1 bootable
  echo 1
  echo w      # Write changes
) | fdisk $DISK

# Format partitions
echo "Formatting partitions..."
mkfs.ext4 "${DISK}2"
mkfs.fat -F32 "${DISK}1"

# Mount the file systems
echo "Mounting partitions..."
mount "${DISK}2" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base packages
echo "Installing base packages..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the system
echo "Entering chroot environment..."
arch-chroot /mnt /bin/bash <<EOF

# Set time zone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

# Localization
echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Set root password
echo root:root | chpasswd

# Install essential packages
pacman -S grub efibootmgr networkmanager nano dotnet-sdk iwd --noconfirm

# Install GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable iwd

# Create a new user
useradd -m -G wheel $USERNAME
echo $USERNAME:$PASSWORD | chpasswd

# Allow wheel group to use sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

EOF

# Unmount and reboot
echo "Unmounting and rebooting..."
umount -R /mnt
reboot