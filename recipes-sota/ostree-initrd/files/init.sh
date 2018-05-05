#!/bin/sh

#/*
#*init.sh , a script to init the ostree system in initramfs
#* 
#* Copyright (c) 2018 Wind River Systems, Inc.
#* 
#* This program is free software; you can redistribute it and/or modify
#* it under the terms of the GNU General Public License version 2 as
#* published by the Free Software Foundation.
#* 
#* This program is distributed in the hope that it will be useful,
#* but WITHOUT ANY WARRANTY; without even the implied warranty of
#* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#* See the GNU General Public License for more details.
#* 
#* You should have received a copy of the GNU General Public License
#* along with this program; if not, write to the Free Software
#* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#* 
#*/ 

set -eu
# -------------------------------------------

log_info() { echo "$0[$$]: $*" >&2; }
log_error() { echo "$0[$$]: ERROR $*" >&2; }

do_mount_fs() {
	log_info "mounting FS: $*"
	[[ -e /proc/filesystems ]] && { grep -q "$1" /proc/filesystems || { log_error "Unknown filesystem"; return 1; } }
	[[ -d "$2" ]] || mkdir -p "$2"
	[[ -e /proc/mounts ]] && { grep -q -e "^$1 $2 $1" /proc/mounts && { log_info "$2 ($1) already mounted"; return 0; } }
	mount -t "$1" "$1" "$2"
}

bail_out() {
	log_error "$@"
	log_info "Rebooting..."
	#exec reboot -f
	exec sh
}

get_ostree_sysroot() {
	for opt in $(cat /proc/cmdline); do
		arg=$(echo "$opt" | cut -d'=' -f1)
		if [ "$arg" == "ostree_root" ]; then
			echo "$opt" | cut -d'=' -f2-
			return
		fi
	done
	echo "LABEL=otaroot"
}

export PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/lib/ostree:/usr/lib64/ostree

log_info "Starting OSTree initrd script"

do_mount_fs proc /proc
do_mount_fs sysfs /sys
do_mount_fs devtmpfs /dev
do_mount_fs devpts /dev/pts
do_mount_fs tmpfs /dev/shm
do_mount_fs tmpfs /tmp
do_mount_fs tmpfs /run

udevd --daemon 
udevadm trigger --action=add

# check if smack is active (and if so, mount smackfs)
grep -q smackfs /proc/filesystems && {
	do_mount_fs smackfs /sys/fs/smackfs

	# adjust current label and network label
	echo System >/proc/self/attr/current
	echo System >/sys/fs/smackfs/ambient
}

mkdir -p /sysroot
ostree_sysroot=$(get_ostree_sysroot)

while [ 1 ] ; do
    mount "$ostree_sysroot" /sysroot || {
        log_info "Mounting $ostree_sysroot failed, waiting 0.1s for the device to be available..."
        sleep 0.1
        continue
    }
    break
done

while [ 1 ] ; do
    mount "LABEL=otaboot" /sysroot/boot || {
        log_info "Mounting boot partition failed, waiting 0.1s for the device to be available..."
        sleep 0.1
        continue
    }
    break
done

killall -q udevd || true

ostree-prepare-root /sysroot

# move mounted devices to new root
cd /sysroot
for x in dev proc sys; do
	log_info "Moving /$x to new rootfs"
	mount --move "/$x" "$x"
done

# switch to new rootfs
log_info "Switching to new rootfs"
mkdir -p run/initramfs

# !!! The Big Fat Warnings !!!
#
# The IMA policy may enforce appraising the executable and verifying the
# signature stored in xattr. However, ramfs doesn't support xattr, and all
# other initializations must *NOT* be placed after IMA initialization!
ROOT_MOUNT="/sysroot"
[ -x /init.ima ] && /init.ima $ROOT_MOUNT && {
    # switch_root is an exception. We call it in the real rootfs and it
    # should be already signed properly.
    pivot_root="usr/sbin/pivot_root.static"
} || {
    pivot_root="pivot_root"
}

${pivot_root} . run/initramfs || bail_out "pivot_root failed."

log_info "Launching target init"

exec chroot . sh -c 'umount /run/initramfs; exec /sbin/init' \
	  <dev/console >dev/console 2>&1

