SUMMARY = "Wic installer script"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=751419260aa954499f7abaabaa882bbe"

SRCREV = "${AUTOREV}"
PV = "1.0+git${SRCPV}"

RDEPENDS_${PN} += "mtools"

SRC_URI = " \
    git://github.com/lifupan/wic.git;branch=master \
    file://git/COPYING \
    file://installer.service \
"

S = "${WORKDIR}/git"

inherit setuptools3 systemd

SYSTEMD_SERVICE_${PN} = "installer.service"

do_install_append() {
    install -d ${D}${systemd_unitdir}/system/
    install -m 0644 ${WORKDIR}/installer.service ${D}${systemd_unitdir}/system/
}

