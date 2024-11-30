#!/bin/bash

set -e

echo "Arch Linux Extended Installer"

# Confirm drive selection
lsblk
read -p "Enter the drive to install Arch Linux (e.g., sda): " DRIVE
DRIVE="/dev/$DRIVE"

# Confirm erasure
echo "WARNING: This will erase all data on $DRIVE!"
read -p "Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Installation canceled."
    exit 1
fi

# Set hostname
read -p "Enter a hostname for your system: " HOSTNAME

# Partition the drive
echo "Partitioning $DRIVE..."
parted -s "$DRIVE" mklabel gpt
parted -s "$DRIVE" mkpart primary fat32 1MiB 512MiB
parted -s "$DRIVE" set 1 esp on
parted -s "$DRIVE" mkpart primary ext4 512MiB 100%

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F32 "${DRIVE}1"
mkfs.ext4 "${DRIVE}2"

# Mount the partitions
echo "Mounting partitions..."
mount "${DRIVE}2" /mnt
mkdir -p /mnt/boot
mount "${DRIVE}1" /mnt/boot

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware vim base-devel git

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configure system
echo "Configuring system..."
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone) /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t$HOSTNAME.localdomain\t$HOSTNAME" >> /etc/hosts
mkinitcpio -P
passwd
EOF

# Install bootloader
echo "Installing GRUB bootloader..."
arch-chroot /mnt /bin/bash <<EOF
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=$HOSTNAME
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Create a user
read -p "Enter username for the new user: " USERNAME
arch-chroot /mnt /bin/bash <<EOF
useradd -m -G wheel -s /bin/bash "$USERNAME"
passwd "$USERNAME"
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
EOF

# Install additional packages and configurations
arch-chroot /mnt /bin/bash <<EOF
yay -Syu --noconfirm xorg-server xorg-xinit openbox xfce4-panel feh xfce4-whiskermenu-plugin sublime-text-4 gedit 
cp /bin/pacman /bin/pac
cp /bin/clear /bin/cls
complete -cf sudo
echo "KEYMAP=uk" > /etc/vconsole.conf

# Prompt for laptop-specific setup
read -p "Is this a laptop? (y/n): " laptop
if [ "\$laptop" = "y" ]; then
  pacman -S acpi --noconfirm
  echo "export PS1='[\$(acpi -b | grep -P -o \"[0-9]+(?=%)\")%]\u@\h: \w\$'" >> "/home/$USERNAME/.bashrc"
else
  echo "export PS1='\u@\h: \w\$'" >> "/home/$USERNAME/.bashrc"
fi

# Enable bash completion
printf '\nif [ -f /usr/share/bash-completion/bash_completion ]; then\n    . /usr/share/bash-completion/bash_completion\nfi\n' >> "/home/$USERNAME/.bashrc"
EOF

# Prompt for additional packages
echo "You can now add any additional packages to be installed."
read -p "Enter any extra packages you want to install (space-separated): " EXTRA_PACKAGES
arch-chroot /mnt /bin/bash <<EOF
pacman -S --noconfirm $EXTRA_PACKAGES
EOF

# Finish up
umount -R /mnt
echo "Installation complete! You can now reboot into your new system."