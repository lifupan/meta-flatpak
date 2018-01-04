REFKIT_DEFAULT_DISTRO_FEATURES += " \
    usrmerge \
    systemd \
    pam \
    flatpak \
"

# Enable D-Bus session bus support, needed by flatpak.
PACKAGECONFIG_append_pn-dbus_df-refkit-config = " user-session"

OSTREE_INITRAMFS_IMAGE ?= "initramfs-ostree-image"
OSTREE_REPO ?= "${DEPLOY_DIR_IMAGE}/ostree_repo"

OSTREE_BRANCHNAME ?= "${MACHINE}-ota"
OSTREE_OSNAME ?= "pulsar-gw"
OSTREE_BOOTLOADER ??= 'grub'
OSTREE_INITRAMFS_IMAGE ?= "initramfs-ostree-image"
OSTREE_KERNEL_ARGS ?= "ramdisk_size=16384 rw rootfstype=ext4 rootwait rootdelay=2 ostree_root=/dev/sda2"

INITRAMFS_FSTYPES = "${@oe.utils.ifelse(d.getVar('OSTREE_BOOTLOADER', True) == 'u-boot', 'ext4.gz.u-boot', 'ext4.gz')}"

IMAGE_BOOT_FILES ?= "grub-efi-bootx64.efi grub.cfg bzImage"
