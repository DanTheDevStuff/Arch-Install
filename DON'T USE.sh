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
echo "root:root" | chpasswd
EOF

# Install bootloader
echo "Installing GRUB bootloader..."
arch-chroot /mnt /bin/bash <<EOF
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Create a user
read -p "Enter username for the new user: " USERNAME
arch-chroot /mnt /bin/bash <<EOF
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERNAME" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
EOF

# Install yay (AUR helper)
echo "Installing yay (AUR helper)..."
arch-chroot /mnt /bin/bash <<EOF
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
EOF

# Package search function
search_packages() {
    echo "Search for a package in the official Arch repositories and AUR:"
    read -p "Enter package name or keyword to search: " PACKAGE_SEARCH_TERM

    echo "Searching in official repositories..."
    pacman -Ss "$PACKAGE_SEARCH_TERM"

    echo "Searching in AUR..."
    yay -Ss "$PACKAGE_SEARCH_TERM"
}

# Call the search function
search_packages

# Package selection
echo "Please select the packages you want to install by number (separate choices with spaces):"
echo "1) feh - Lightweight image viewer"
echo "2) openbox - Lightweight window manager"
echo "3) xfce4-panel - XFCE panel"
echo "4) xorg-server - Xorg server"
echo "5) xorg-xinit - X init system"
echo "6) vlc - Media player"
echo "7) pulseaudio - Sound system"
echo "8) yay - AUR helper"
echo "9) mono - Mono runtime"
echo "10) neofetch - System information tool"
echo "11) htop - Interactive process viewer"
echo "12) git - Version control system"
echo "13) vim - Text editor"
echo "14) acpi - Battery and power management"
read -p "Enter the numbers of the packages you want to install (e.g., 1 2 3): " PACKAGE_NUMBERS

# Define package list based on selection
PACKAGE_LIST=""
for number in $PACKAGE_NUMBERS; do
    case $number in
        1) PACKAGE_LIST+=" feh" ;;
        2) PACKAGE_LIST+=" openbox" ;;
        3) PACKAGE_LIST+=" xfce4-panel" ;;
        4) PACKAGE_LIST+=" xorg-server" ;;
        5) PACKAGE_LIST+=" xorg-xinit" ;;
        6) PACKAGE_LIST+=" vlc" ;;
        7) PACKAGE_LIST+=" pulseaudio" ;;
        8) PACKAGE_LIST+=" yay" ;;
        9) PACKAGE_LIST+=" mono" ;;
        10) PACKAGE_LIST+=" neofetch" ;;
        11) PACKAGE_LIST+=" htop" ;;
        12) PACKAGE_LIST+=" git" ;;
        13) PACKAGE_LIST+=" vim" ;;
        14) PACKAGE_LIST+=" acpi" ;;
        *) echo "Invalid selection: $number" ;;
    esac
done

# Install selected packages
if [[ -n "$PACKAGE_LIST" ]]; then
    echo "Installing selected packages: $PACKAGE_LIST"
    arch-chroot /mnt /bin/bash <<EOF
pacman -S --noconfirm $PACKAGE_LIST
EOF
else
    echo "No packages selected."
fi

# Ask for additional packages
read -p "Do you want to install additional packages? (yes/no): " ADDITIONAL
if [ "$ADDITIONAL" = "yes" ]; then
    read -p "Enter additional packages (space-separated): " EXTRA_PACKAGES
    echo "Installing additional packages: $EXTRA_PACKAGES"
    arch-chroot /mnt /bin/bash <<EOF
pacman -S --noconfirm $EXTRA_PACKAGES
EOF
else
    echo "Skipping additional packages installation."
fi

# Configure additional settings
arch-chroot /mnt /bin/bash <<EOF
cp /bin/pacman /bin/pac
cp /bin/clear /bin/cls
complete -cf sudo
echo "KEYMAP=uk" > /etc/vconsole.conf

# Laptop-specific setup
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

# Finish up
umount -R /mnt
echo "Installation complete! You can now reboot into your new system."