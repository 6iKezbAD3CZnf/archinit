# Inspired by https://github.com/altercation/archinit.git

typeset -A BOOT CONFIG DEVICE
typeset -a SERVICES PACKAGES

# Configuration

ISVM=true

CONFIG=(
    username    tatsu
    shell       zsh
    timezone    Asia/Tokyo
    locale      "en_US.UTF-8 UTF-8"
    lang        "en_US.UTF-8"
)
if $ISVM; then
    CONFIG+=(hostname ArchVM)
else
    CONFIG+=(hostname Arch)
fi

PACKAGES=(
    base
    linux
    linux-firmware
    git
    sudo
    neovim
    zsh
    grub
    efibootmgr
    xorg-server
    xorg-xinit
    networkmanager
    reflector
)

SERVICES=(
    NetworkManager
    reflector.timer
)

# System Values

SWAPSIZE=512M
DRIVE=/dev/sda
MOUNT=/mnt

# Boot Setting

BOOT=(
    name    EFI
    dir     /boot
    type    ef00
)

# Functions

chrooted () { arch-chroot $MOUNT zsh -c "$*"; }

# Make Partitions

# boot partition
sgdisk --new=1:0:+512M --change-name=1:$BOOT[name] -t 1:$BOOT[type] $DRIVE

DEVICE[boot]=${DRIVE}1

# Make swap partition
# 8200 == 0657FD6D-A4AB-43C4-84E5-0933C84B4F4F == Linux swap
sgdisk --new=2:0:+$SWAPSIZE -c 2:"swap" -t 2:8200 $DRIVE

# Make system partition
# 8304 == 4f68bce3-e8cd-4db1-96e7-fbcaf984b709 == Linux x86-64 root
sgdisk --new=3:0:0 -c 3:"root" -t 3:8304 $DRIVE

DEVICE[swap]=${DRIVE}2
DEVICE[system]=${DRIVE}3

# Make Swap & Filesystems

# swap
mkswap -L swap $DEVICE[swap] # make swap device
swapon -d -L swap # activate swap device

# root filesystem
mkfs.ext4 $DEVICE[system]
mount -v $DEVICE[system] $MOUNT

# boot filesystem
mkfs.fat -F32 $DEVICE[boot]
mkdir -v $MOUNT$BOOT[dir]
mount -v $DEVICE[boot] $MOUNT$BOOT[dir]

# Install Packages

if [ -f ./pacman.conf ]; then
    cp ./pacman.conf /etc/pacman.conf
fi
reflector --verbose --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
pacstrap $MOUNT $PACKAGES

# Fstab

genfstab -U $MOUNT >> $MOUNT/etc/fstab

# System Config

chrooted ln -sf /usr/share/$CONFIG[timezone] /etc/localtime

chrooted hwclock --systohc --utc

print $CONFIG[locale] >> $MOUNT/etc/locale.gen
chrooted locale-gen

print "LANG=$CONFIG[lang]" >> $MOUNT/etc/locale.conf

print $CONFIG[hostname] >> $MOUNT/etc/hostname

cat $MOUNT/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $CONFIG[hostname].localdomain   $CONFIG[hostname]
EOF

# Enable Services

for servicename in $SERVICES; do
    chrooted systemctl enable $servicename
done

# Users / Passwords

chrooted "useradd -m -G wheel \
    -s /usr/bin/$CONFIG[shell] \
    $CONFIG[username]"

for user in root $CONFIG[username]; do
    chrooted "print -r $user:$user | chpasswd"
done

tmpfile=$(mktemp)
echo "%wheel ALL=(ALL) ALL" > $tmpfile
visudo -cf $tmpfile \
    && { mv $tmpfile $MOUNT/etc/sudoers.d/wheel } \
    || { print "ERROR updating sudoers; no change made" }

# Boot Loader

chrooted "grub-install --target=x86_64-efi --efi-directory=$BOOT[dir] --bootloader-id=GRUB"
chrooted "grub-mkconfig -o /boot/grub/grub.cfg"

# Pacman

if [ -f ./pacman.conf ]; then
    cp ./pacman.conf $MOUNT/etc/pacman.conf
fi
cp /etc/pacman.d/mirrorlist $MOUNT/etc/pacman.d/mirrorlist

# Dotfiles
HOME=/home/$CONFIG[username]
URL="https://github.com/6iKezbAD3CZnf/dotfiles.git"
COMMAND="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"
chrooted "echo '.dotfiles' >> .gitignore"
chrooted "git clone --bare $URL $HOME/.dotfiles"
chrooted "$COMMAND config --local status.showUntrackedFiles no"
chrooted "$COMMAND checkout -f"
chrooted "$COMMAND submodule update --init --recursive"

# End

umount -R $MOUNT
