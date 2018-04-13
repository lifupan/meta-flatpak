# OSTree deployment

do_image_ostree[depends] = "ostree-native:do_populate_sysroot \
                        openssl-native:do_populate_sysroot \
			coreutils-native:do_populate_sysroot \
                        virtual/kernel:do_deploy \
                        ${OSTREE_INITRAMFS_IMAGE}:do_image_complete"

export OSTREE_REPO
export OSTREE_BRANCHNAME
OSTREE_KERNEL ??= "${KERNEL_IMAGETYPE}"

RAMDISK_EXT ?= ".${INITRAMFS_FSTYPES}"

export SYSTEMD_USED = "${@oe.utils.ifelse(d.getVar('VIRTUAL-RUNTIME_init_manager', True) == 'systemd', 'true', '')}"
export GRUB_USED = "${@oe.utils.ifelse(d.getVar('OSTREE_BOOTLOADER', True) == 'grub', 'true', '')}"

repo_apache_config () {
    local _repo_path
    local _repo_alias

    cd $OSTREE_REPO && _repo_path=$(pwd) && cd -
    _repo_alias="/${OSTREE_OSNAME}/${MACHINE}/"

    echo "* Generating apache2 config fragment for $OSTREE_REPO..."
    (echo "Alias \"$_repo_alias\" \"$_repo_path/\""
     echo ""
     echo "<Directory $_repo_path>"
     echo "    Options Indexes FollowSymLinks"
     echo "    Require all granted"
     echo "</Directory>") > ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.rootfs.ostree.http.conf
}


IMAGE_CMD_ostree () {
	if [ -z "$OSTREE_REPO" ]; then
		bbfatal "OSTREE_REPO should be set in your local.conf"
	fi

	if [ -z "$OSTREE_BRANCHNAME" ]; then
		bbfatal "OSTREE_BRANCHNAME should be set in your local.conf"
	fi

	OSTREE_ROOTFS=`mktemp -du ${WORKDIR}/ostree-root-XXXXX`
	cp -a ${IMAGE_ROOTFS} ${OSTREE_ROOTFS}
	chmod a+rx ${OSTREE_ROOTFS}
	bash
	sync

	cd ${OSTREE_ROOTFS}

	# Create sysroot directory to which physical sysroot will be mounted
	mkdir sysroot
	ln -sf sysroot/ostree ostree

	rm -rf tmp/*
	ln -sf sysroot/tmp tmp

	mkdir -p usr/rootdirs

	mv etc usr/
	# Implement UsrMove
	dirs="bin sbin lib lib64"

	for dir in ${dirs} ; do
		if [ -d ${dir} ] && [ ! -L ${dir} ] ; then 
			mv ${dir} usr/rootdirs/
			rm -rf ${dir}
			ln -sf usr/rootdirs/${dir} ${dir}
		fi
	done
	
	if [ -n "$SYSTEMD_USED" ]; then
		mkdir -p usr/etc/tmpfiles.d
		tmpfiles_conf=usr/etc/tmpfiles.d/00ostree-tmpfiles.conf
		echo "d /var/rootdirs 0755 root root -" >>${tmpfiles_conf}
		# disable the annoying logs on the console
		echo "w /proc/sys/kernel/printk - - - - 3" >> ${tmpfiles_conf}
	else
		mkdir -p usr/etc/init.d
		tmpfiles_conf=usr/etc/init.d/tmpfiles.sh
		echo '#!/bin/sh' > ${tmpfiles_conf}
		echo "mkdir -p /var/rootdirs; chmod 755 /var/rootdirs" >> ${tmpfiles_conf}

		ln -s ../init.d/tmpfiles.sh usr/etc/rcS.d/S20tmpfiles.sh
	fi

	# Preserve OSTREE_BRANCHNAME for future information
	mkdir -p usr/share/sota/
	echo -n "${OSTREE_BRANCHNAME}" > usr/share/sota/branchname

	# Preserve data in /home to be later copied to /sysroot/home by
	#   sysroot generating procedure
	mkdir -p usr/homedirs
	if [ -d "home" ] && [ ! -L "home" ]; then
		mv home usr/homedirs/home
		mkdir var/home
		ln -sf var/home home
	fi

	echo "d /var/rootdirs/opt 0755 root root -" >>${tmpfiles_conf}
	if [ -d opt ]; then
		mkdir -p usr/rootdirs/opt
		for dir in `ls opt`; do
			mv opt/$dir usr/rootdirs/opt/
			echo "L /opt/$dir - - - - /usr/rootdirs/opt/$dir" >>${tmpfiles_conf}
		done
	fi
	rm -rf opt
	ln -sf var/rootdirs/opt opt

	if [ -d var/lib/rpm ]; then
	    mkdir -p usr/rootdirs/var/lib/
	    mv var/lib/rpm usr/rootdirs/var/lib/
	    echo "L /var/lib/rpm - - - - /usr/rootdirs/var/lib/rpm" >>${tmpfiles_conf}
	fi
	if [ -d var/lib/dnf ]; then
	    mkdir -p usr/rootdirs/var/lib/
	    mv var/lib/dnf usr/rootdirs/var/lib/
	    echo "L /var/lib/dnf - - - - /usr/rootdirs/var/lib/dnf " >>${tmpfiles_conf}
	fi

	# Move persistent directories to /var
	dirs="mnt media srv"

	for dir in ${dirs}; do
		if [ -d ${dir} ] && [ ! -L ${dir} ]; then
			if [ "$(ls -A $dir)" ]; then
				bbwarn "Data in /$dir directory is not preserved by OSTree. Consider moving it under /usr"
			fi

			if [ -n "$SYSTEMD_USED" ]; then
				echo "d /var/rootdirs/${dir} 0755 root root -" >>${tmpfiles_conf}
			else
				echo "mkdir -p /var/rootdirs/${dir}; chown 755 /var/rootdirs/${dir}" >>${tmpfiles_conf}
			fi
			rm -rf ${dir}
			ln -sf var/rootdirs/${dir} ${dir}
		fi
	done

	if [ -d root ] && [ ! -L root ]; then
        	if [ "$(ls -A root)" ]; then
                	bberror "Data in /root directory is not preserved by OSTree."
		fi

		if [ -n "$SYSTEMD_USED" ]; then
                       echo "d /var/rootdirs/root 0755 root root -" >>${tmpfiles_conf}
		else
                       echo "mkdir -p /var/rootdirs/root; chown 755 /var/rootdirs/root" >>${tmpfiles_conf}
		fi

		rm -rf root
		ln -sf var/rootdirs/root root
	fi

	# deploy SOTA credentials
	if [ -n "${SOTA_AUTOPROVISION_CREDENTIALS}" ]; then
		EXPDATE=`openssl pkcs12 -in ${SOTA_AUTOPROVISION_CREDENTIALS} -password "pass:" -nodes 2>/dev/null | openssl x509 -noout -enddate | cut -f2 -d "="`

		if [ `date +%s` -ge `date -d "${EXPDATE}" +%s` ]; then
			bberror "Certificate ${SOTA_AUTOPROVISION_CREDENTIALS} has expired on ${EXPDATE}"
		fi

		mkdir -p var/sota
		cp ${SOTA_AUTOPROVISION_CREDENTIALS} var/sota/sota_provisioning_credentials.p12
		if [ -n "${SOTA_AUTOPROVISION_URL_FILE}" ]; then
			export SOTA_AUTOPROVISION_URL=`cat ${SOTA_AUTOPROVISION_URL_FILE}`
		fi
		echo "SOTA_GATEWAY_URI=${SOTA_AUTOPROVISION_URL}" > var/sota/sota_provisioning_url.env
	fi


	# Creating boot directories is required for "ostree admin deploy"

	mkdir -p boot/loader.0
	mkdir -p boot/loader.1
	ln -sf boot/loader.0 boot/loader
	
	checksum=`sha256sum ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL} | cut -f 1 -d " "`

#	cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL} boot/vmlinuz-${checksum}
#	cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT} boot/initramfs-${checksum}

        #deploy the device tree file 
        mkdir -p usr/lib/ostree-boot
        cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL} usr/lib/ostree-boot/vmlinuz-${checksum}
        cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT} usr/lib/ostree-boot/initramfs-${checksum}
	if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'Y', '', d)}" ]; then
		cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL}.p7b usr/lib/ostree-boot/vmlinuz.p7b
		cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT}.p7b usr/lib/ostree-boot/initramfs.p7b
	fi
#	cp ${DEPLOY_DIR_IMAGE}/${OSTREE_KERNEL}.p7b usr/lib/ostree-boot/vmlinuz.p7b
#	cp ${DEPLOY_DIR_IMAGE}/${OSTREE_INITRAMFS_IMAGE}-${MACHINE}${RAMDISK_EXT}.p7b usr/lib/ostree-boot/initramfs.p7b
        if [ -d boot/efi ]; then
	   	cp -a boot/efi usr/lib/ostree-boot/
	fi

        if [ -f ${DEPLOY_DIR_IMAGE}/uEnv.txt ]; then
            cp ${DEPLOY_DIR_IMAGE}/uEnv.txt usr/lib/ostree-boot/
        fi

        if [ -f ${DEPLOY_DIR_IMAGE}/boot.scr ]; then
            cp ${DEPLOY_DIR_IMAGE}/boot.scr usr/lib/ostree-boot/boot.scr
        fi

        for i in ${KERNEL_DEVICETREE}; do
            if [ -f ${DEPLOY_DIR_IMAGE}/$i ]; then
                cp ${DEPLOY_DIR_IMAGE}/$i usr/lib/ostree-boot/
            fi
        done 

	#deploy the GPG pub key
	if [ -f ${FLATPAK_GPGDIR}/pubring.gpg ]; then
	    cp ${FLATPAK_GPGDIR}/pubring.gpg usr/share/ostree/trusted.gpg.d/
	fi

#        cp ${DEPLOY_DIR_IMAGE}/${MACHINE}.dtb usr/lib/ostree-boot
        touch usr/lib/ostree-boot/.ostree-bootcsumdir-source

	# Copy image manifest
	cat ${IMAGE_MANIFEST} | cut -d " " -f1,3 > usr/package.manifest

	# add the required mount
        if [ -n "${GRUB_UESD}" ]; then
	    echo "LABEL=otaefi     /boot/efi    auto   defaults 0 0" >>usr/etc/fstab
        fi
	echo "LABEL=fluxdata    /var    auto   defaults 0 0" >>usr/etc/fstab

	cd ${WORKDIR}

	# Create a tarball that can be then commited to OSTree repo
	OSTREE_TAR=${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.ostree.tar.bz2 
	tar -C ${OSTREE_ROOTFS} --xattrs --xattrs-include='*' -cjf ${OSTREE_TAR} .
	sync

	rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.rootfs.ostree.tar.bz2
	ln -s ${IMAGE_NAME}.rootfs.ostree.tar.bz2 ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.rootfs.ostree.tar.bz2
	
	if [ ! -d ${OSTREE_REPO} ]; then
		ostree --repo=${OSTREE_REPO} init --mode=archive-z2
	fi

	# Commit the result
	ostree --repo=${OSTREE_REPO} commit \
	       --tree=dir=${OSTREE_ROOTFS} \
	       --skip-if-unchanged \
	       --gpg-sign=${FLATPAK_GPGID} \
	       --gpg-homedir=${FLATPAK_GPGDIR} \
	       --branch=${OSTREE_BRANCHNAME} \
	       --subject="Commit-id: ${IMAGE_NAME}"

	ostree summary -u --repo=${OSTREE_REPO} 
	repo_apache_config

	rm -rf ${OSTREE_ROOTFS}
}

IMAGE_TYPEDEP_ostreepush = "ostree"
do_image_ostreepush[depends] = "sota-tools-native:do_populate_sysroot"

IMAGE_CMD_ostreepush () {
	if [ -n "${OSTREE_PUSH_CREDENTIALS}" ]; then
		garage-push --repo=${OSTREE_REPO} \
			    --ref=${OSTREE_BRANCHNAME} \
			    --credentials=${OSTREE_PUSH_CREDENTIALS} \
			    --cacert=${STAGING_ETCDIR_NATIVE}/ssl/certs/ca-certificates.crt
	fi
}
