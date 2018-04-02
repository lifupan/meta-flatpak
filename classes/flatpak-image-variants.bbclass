IMAGE_FEATURES[validitems] += " \
    flatpak \
    tools-sdk \
    dev-pkgs \
    tools-debug \
    tools-develop \
    tools-profile \
"

FEATURE_PACKAGES_flatpak = " \
    packagegroup-flatpak \
    ${@bb.utils.contains('DISTRO_FEATURES', 'flatpak-session', \
           'packagegroup-flatpak-session', '', d)} \
"

FEATURE_PACKAGES_tools-develop = "packagegroup-core-buildessential git"

#
# Define two flatpak-related image variants.
#
# - flatpak runtime image variant 'ostree-runtime':
#     This variant corresponds to a flatpak BasePlatform runtime. In
#     addition to the content of its base image, this variant has the
#     necessary runtime bits for flatpak. Using this image on a device
#     enables one to pull in, update and run applications as flatpaks
#     from flatpak remotes/repositories.
#
# - flatpak SDK image variant 'ostree-sdk':
#     This variant corresponds to a flatpak BaseSdk runtime. It has the
#     necessary bits for compiling applications and publishing them as
#     flatpaks in flatpak repositories.
#
# When building these images variants, a flatpak repository will also be
# populated with the contents of these images. This repository can be used
# to flatpak-install the runtime and SDK runtimes on a development machine
# for generating flatpaks for the ostree-runtime image variant.

# 'ostree-runtime' variant (runtime image for a device)
IMAGE_VARIANT[ostree-runtime] = "flatpak"

# 'ostree-sdk' variant (SDK image for a development host)
IMAGE_VARIANT[ostree-sdk] = "flatpak tools-develop tools-debug dev-pkgs"

BBCLASSEXTEND += "imagevariant:ostree-runtime imagevariant:ostree-sdk"
