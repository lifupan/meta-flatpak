do_install_append () {
   if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', 'y', '', d)}" ]; then
	if [ ! -d ${D}/usr/sbin ]; then
	    install -d ${D}/usr/sbin
	fi
        cp -a ${D}/sbin/* ${D}/usr/sbin/
        rm -rf ${D}/sbin
    fi
	
}


