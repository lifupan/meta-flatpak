SUMMARY = "Flux systemd mount services"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = " \
    file://var-lib-flatpak.mount \
    "

S = "${WORKDIR}"

inherit systemd allarch

PACKAGES = "${PN}"

SYSTEMD_SERVICE_${PN} = " \
    var-lib-flatpak.mount \
    "

FILES_${PN} += " \
    ${sysconfdir} \
    ${systemd_unitdir} \
    "
do_install () {
    install -d ${D}${systemd_unitdir}/system
    install -d  ${D}${sysconfdir}/systemd/system/flux-bind.target.wants

    if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -c -m 0644 \
            ${WORKDIR}/var-lib-flatpak.mount \
            ${D}${systemd_unitdir}/system
        ln -sf ${systemd_unitdir}/system/var-lib-flatpak.mount ${D}${sysconfdir}/systemd/system/flux-bind.target.wants
    fi
}

