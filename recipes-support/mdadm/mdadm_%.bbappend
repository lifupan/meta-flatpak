#
# Use a "here" document, as it saves the SRC_URI and FILES_PN
# stuff for something otherwise so simple.
#

do_install_append() {
    if [ -n "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', 'y', '', d)}" ]; then
       cp -a ${D}/lib ${D}/usr/
       rm -rf ${D}/lib
    fi
}
