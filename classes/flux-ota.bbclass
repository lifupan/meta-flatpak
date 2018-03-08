IMAGE_INSTALL_append = " ostree os-release flux-filesystem-expand wic"
IMAGE_CLASSES += "image_types_ostree image_types_ota"
IMAGE_FSTYPES += "ostreepush otaimg wic"

IMAGE_TYPEDEP_wic += "otaimg"

WKS_FILE = "${IMAGE_BASENAME}-${MACHINE}.wks"
WKS_FILE_DEPENDS = "mtools-native dosfstools-native e2fsprogs-native parted-native"
