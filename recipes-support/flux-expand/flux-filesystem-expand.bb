DESCRIPTION = "Flux data partition filesystem expander"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = " \
    file://flux-filesystem-expand \
    file://flux-filesystem-expand.service \
    "
S = "${WORKDIR}"

inherit allarch systemd

SYSTEMD_SERVICE_${PN} = "flux-filesystem-expand.service"

RDEPENDS_${PN} = " \
    bash \
    coreutils \
    e2fsprogs-resize2fs \
    "

do_install() {
    install -d ${D}${bindir}
    install -m 0775 ${WORKDIR}/flux-filesystem-expand ${D}${bindir}

    if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -c -m 0644 ${WORKDIR}/flux-filesystem-expand.service ${D}${systemd_unitdir}/system
        sed -i -e 's,@BASE_BINDIR@,${base_bindir},g' \
            -e 's,@SBINDIR@,${sbindir},g' \
            -e 's,@BINDIR@,${bindir},g' \
            ${D}${systemd_unitdir}/system/*.service
    fi
}
