# Image to use with u-boot as BIOS and OSTree deployment system

#inherit image_types

# Boot filesystem size in MiB
# OSTree updates may require some space on boot file system for
# boot scripts, kernel and initramfs images
#

do_image_otaimg[depends] += "e2fsprogs-native:do_populate_sysroot \
                             ${@'grub:do_populate_sysroot' if d.getVar('OSTREE_BOOTLOADER', True) == 'grub' else ''} \
                             ${@'virtual/bootloader:do_deploy' if d.getVar('OSTREE_BOOTLOADER', True) == 'u-boot' else ''}"

calculate_size () {
	BASE=$1
	SCALE=$2
	MIN=$3
	MAX=$4
	EXTRA=$5
	ALIGN=$6

	SIZE=`echo "$BASE * $SCALE" | bc -l`
	REM=`echo $SIZE | cut -d "." -f 2`
	SIZE=`echo $SIZE | cut -d "." -f 1`

	if [ -n "$REM" -o ! "$REM" -eq 0 ]; then
		SIZE=`expr $SIZE \+ 1`
	fi

	if [ "$SIZE" -lt "$MIN" ]; then
		$SIZE=$MIN
	fi

	SIZE=`expr $SIZE \+ $EXTRA`
	SIZE=`expr $SIZE \+ $ALIGN \- 1`
	SIZE=`expr $SIZE \- $SIZE \% $ALIGN`

	if [ -n "$MAX" ]; then
		if [ "$SIZE" -gt "$MAX" ]; then
			return -1
		fi
	fi
	
	echo "${SIZE}"
}

export OSTREE_OSNAME
export OSTREE_BRANCHNAME
export OSTREE_REPO
export OSTREE_BOOTLOADER

IMAGE_CMD_otaimg () {
	if ${@bb.utils.contains('IMAGE_FSTYPES', 'otaimg', 'true', 'false', d)}; then
		if [ -z "$OSTREE_REPO" ]; then
			bbfatal "OSTREE_REPO should be set in your local.conf"
		fi

		if [ -z "$OSTREE_OSNAME" ]; then
			bbfatal "OSTREE_OSNAME should be set in your local.conf"
		fi

		if [ -z "$OSTREE_BRANCHNAME" ]; then
			bbfatal "OSTREE_BRANCHNAME should be set in your local.conf"
		fi


		PHYS_SYSROOT=`mktemp -d ${WORKDIR}/ota-sysroot-XXXXX`

		ostree admin --sysroot=${PHYS_SYSROOT} init-fs ${PHYS_SYSROOT}
		ostree admin --sysroot=${PHYS_SYSROOT} os-init ${OSTREE_OSNAME}

		mkdir -p ${PHYS_SYSROOT}/boot/loader.0
		ln -s loader.0 ${PHYS_SYSROOT}/boot/loader

		if [ "${OSTREE_BOOTLOADER}" = "grub" ]; then
			mkdir -p ${PHYS_SYSROOT}/boot/efi/EFI/BOOT
			if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'Y', '', d)}" ]; then
				cp ${DEPLOY_DIR_IMAGE}/grubx64.efi ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/bootx64.efi
				cp ${DEPLOY_DIR_IMAGE}/grub.cfg.p7b ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/
			else
				cp ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/bootx64.efi
			fi
			cp ${DEPLOY_DIR_IMAGE}/grub.cfg ${PHYS_SYSROOT}/boot/efi/EFI/BOOT/
			#create the OS vendor fallback boot dir
			mkdir ${PHYS_SYSROOT}/boot/efi/EFI/"${@(d.getVar('DISTRO', False) or 'pulsar')}"
			cp ${DEPLOY_DIR_IMAGE}/grub.cfg ${PHYS_SYSROOT}/boot/efi/EFI/"${@(d.getVar('DISTRO', False) or 'pulsar')}"

		elif [ "${OSTREE_BOOTLOADER}" = "u-boot" ]; then
			touch ${PHYS_SYSROOT}/boot/loader/uEnv.txt
		else
			bberror "Invalid bootloader: ${OSTREE_BOOTLOADER}"
		fi;

		ostree --repo=${PHYS_SYSROOT}/ostree/repo pull-local --remote=${OSTREE_OSNAME} ${OSTREE_REPO} ${OSTREE_BRANCHNAME}
		export OSTREE_BOOT_PARTITION="/boot"
		kargs_list=""
		for arg in ${OSTREE_KERNEL_ARGS}; do
			kargs_list="${kargs_list} --karg-append=$arg"
		done

		ostree admin --sysroot=${PHYS_SYSROOT} deploy ${kargs_list} --os=${OSTREE_OSNAME} ${OSTREE_BRANCHNAME}

		# Copy deployment /home and /var/sota to sysroot
		HOME_TMP=`mktemp -d ${WORKDIR}/home-tmp-XXXXX`
		tar --xattrs --xattrs-include='*' -C ${HOME_TMP} -xf ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.rootfs.ostree.tar.bz2 ./boot/efi || true
		cp -a ${HOME_TMP}/boot/efi ${PHYS_SYSROOT}/boot
#		tar --xattrs --xattrs-include='*' -C ${HOME_TMP} -xf ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.rootfs.ostree.tar.bz2 ./usr/homedirs  ./var/local || true
#		mv ${HOME_TMP}/var/sota ${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/ || true
#		mv ${HOME_TMP}/var/local ${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/ || true
		# Create /var/sota if it doesn't exist yet
#		mkdir -p ${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/sota || true
#		mv ${HOME_TMP}/usr/homedirs/home ${PHYS_SYSROOT}/ || true
#		install -d ${PHYS_SYSROOT}/usr/homedirs/home
		# Ensure that /var/local exists (AGL symlinks /usr/local to /var/local)
#		install -d ${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/local

		# Calculate image type
		OTA_ROOTFS_SIZE=$(calculate_size `du -ks $PHYS_SYSROOT | cut -f 1`  "${IMAGE_OVERHEAD_FACTOR}" "${IMAGE_ROOTFS_SIZE}" "${IMAGE_ROOTFS_MAXSIZE}" `expr ${IMAGE_ROOTFS_EXTRA_SPACE}` "${IMAGE_ROOTFS_ALIGNMENT}")

		if [ $OTA_ROOTFS_SIZE -lt 0 ]; then
			exit -1
		fi

		# create image
		rm -rf ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.otaimg
		rm -rf ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_efi.otaimg
		rm -rf ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_var.otaimg
		sync
                #create an image with the free space equal the rootfs size
		dd if=/dev/zero of=${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.otaimg seek=$OTA_ROOTFS_SIZE count=$OTA_ROOTFS_SIZE bs=1024
		mkfs.ext4 -O ^64bit ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.otaimg -L otaroot -d ${PHYS_SYSROOT}
		#create an efi boot partition with 20M
		dd if=/dev/zero of=${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_efi.otaimg count=20000 bs=1024
		mkfs.vfat ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_efi.otaimg -n otaefi 
		mcopy -i ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_efi.otaimg  -s ${PHYS_SYSROOT}/boot/efi/* ::/
		#create an var data partiton
		dd if=/dev/zero of=${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_var.otaimg count=20000 bs=1024

		cat<<EOF>>${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/wic.wks.sample
part /boot/efi --source  rootfs --rootfs-dir=/boot/efi  --ondisk sda --fstype=vfat --label otaefi --active --align 4
part / --source rootfs --rootfs-dir=/sysroot --ondisk sda --fstype=ext4 --label otaroot --align 4
part /var --source rootfs --rootfs-dir=/ostree/deploy/pulsar-linux/var  --ondisk sda --fstype=ext4 --label fluxdata --active --align 4
EOF
                
		mkfs.ext4 -O ^64bit ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}_var.otaimg -L fluxdata -d ${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/
		rm ${PHYS_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/wic.wks.sample
		
#		rm -rf ${HOME_TMP}
		rm -rf ${PHYS_SYSROOT}

		rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.otaimg
		rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}_efi.otaimg
		rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}_var.otaimg
		ln -s ${IMAGE_NAME}_efi.otaimg ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}_efi.otaimg
		ln -s ${IMAGE_NAME}.otaimg ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.otaimg
		ln -s ${IMAGE_NAME}_var.otaimg ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}_var.otaimg
	fi
}

IMAGE_TYPEDEP_otaimg = "ostree"
