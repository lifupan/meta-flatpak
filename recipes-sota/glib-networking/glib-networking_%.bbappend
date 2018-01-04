BBCLASSEXTEND_append = " native"

FILES_${PN} += "/usr/lib/pkgconfig"

do_install_append(){
	rm -rf  ${D}${libdir}/pkgconfig
}
