#!/bin/bash

error() { #red text and exit 1
  echo -e "\e[91m$1\e[0m" 1>&2
  exit 1
}

# move to current script directory regardless of where the script was run from
cd `dirname $0` || exit 1
SCRIPTS_DIR="$(pwd)"

# this script expects that you have an exiting chromium repository checkout in the src directory
# it also expects that you have depot_tools cloned somewhere and available in the system PATH
cd "$SCRIPTS_DIR"/src/ || error "Could not move to source directory"
export PATH="$SCRIPTS_DIR"/../depot_tools/:$PATH

# Make sure to revert any patches applied in current branch
git reset --hard
# Make sure you have all the release tag information in your checkout.
git fetch --tags || error "Git fetch failed"
# get latest stable Linux version
#version=$(curl "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux" | jq -r '.[0].version')
# get latest extended version
version=$(curl "https://chromiumdash.appspot.com/fetch_releases?channel=Extended&platform=Windows" | jq -r '.[0].version')
# Checkout whatever version you need (known versions can be seen with
# 'git show-ref --tags')
git checkout tags/$version || error "Git checkout failed"

# use lacros arm64 PGO target for better optimized builds
shopt -s globstar
sed -i 's/--target=linux/--target=lacros-arm64/g' ./DEPS
sed -i -e 's/_pgo_target = "linux"/_pgo_target = "lacros-arm64"/g' ./**/BUILD.gn

gclient sync --with_branch_heads --with_tags || error "Could not sync"

# Revert removal of VP8 through FFmpeg patch
git apply -R ../patches/0001-Remove-support-for-Theora-and-VP8-through-FFmpeg-v2.patch
# apply tegra hw accelerated decoding through ffmpeg patches
git apply ../patches/multi-patch-v10.patch || error "Could not apply patches"

# build chromium
autoninja -C out/arm64-build chrome || error "Could not build"
# log build time stats
python3 ../../depot_tools/post_build_ninja_summary.py -C out/arm64-build > /tmp/chromium-build-stats.txt
# make default chromium package
autoninja -C out/arm64-build "chrome/installer/linux:stable_deb" || error "Failed to package"

# repackage with switchroot ffmpeg and modifications

# move back to script directory
cd "$SCRIPTS_DIR"

# compile L4T FFmpeg
schroot -d /home/"$USER" -c bionic-arm64 -u gman -- bash -c "./compile-ffmpeg.sh $version" || error "Failed to compile ffmpeg"

# re-package chromium with new ffmpeg and unnecessary things removed

rm -rf chromium-repack
mkdir chromium-repack
cd chromium-repack

setup_patched() {
        mkdir -p $1
        case "$1" in
        chromium-browser)
          cp "$SCRIPTS_DIR"/src/out/arm64-build/chromium-browser-stable_$version-1_arm64.deb chromium-browser_$version-1_arm64.deb
          ;;
        esac
        mv $1_*.deb $1
}

extract() {
        cd $1
        ar x $1_*.deb
        rm $1_*.deb
        tar xf data.tar.xz
        mkdir DEBIAN
        tar xf control.tar.xz -C DEBIAN
        rm -rf control.tar.xz \
                data.tar.xz \
                debian-binary \
                DEBIAN/md5sums \
                DEBIAN/archives \
                DEBIAN/conffiles \
                DEBIAN/postinst \
                DEBIAN/postrm \
                DEBIAN/prerm \
                etc/cron.daily || true
}

repack() {
        sed -i 's/'${deb_version}'/9:'${deb_version}'/g' DEBIAN/control
        #sed -i 's/-1$/-2/g' DEBIAN/control
        sed -i 's/Package: chromium-browser-stable/Package: chromium-browser/g' DEBIAN/control
        # First version with merged locales and ffmpeg is 9:119.0.6045.105-1. No need to bump the versions below in the future.
        echo 'Breaks: chromium-browser-l10n (<< 9:119.0.6045.105-1), chromium-chromedriver (<< 9:119.0.6045.105-1), chromium-codecs-ffmpeg-extra (<< 9:119.0.6045.105-1), chromium-codecs-ffmpeg (<< 9:119.0.6045.105-1)' >> DEBIAN/control
        echo 'Replaces: chromium-browser-l10n (<< 9:119.0.6045.105-1), chromium-chromedriver (<< 9:119.0.6045.105-1), chromium-codecs-ffmpeg-extra (<< 9:119.0.6045.105-1), chromium-codecs-ffmpeg (<< 9:119.0.6045.105-1)' >> DEBIAN/control
        sed -i '/Provides:/d' DEBIAN/control
        sed -i '/Maintainer:/d' DEBIAN/control
        echo 'Provides: www-browser, chromium-browser-l10n, chromium-codecs-ffmpeg-extra' >> DEBIAN/control
        echo 'Maintainer: theofficialgman <dofficialgman@gmail.com>' >> DEBIAN/control
        # ultra chromium deb compression method https://source.chromium.org/chromium/chromium/src/+/refs/tags/122.0.6261.57:chrome/installer/linux/debian/build.sh;l=120-129;bpv=0
        # reduces size from ~93 MB via standard methods to ~82 MB
        mkdir ../$1-ultra-compressed
        dpkg-deb --root-owner-group -Znone -b . ../$1-ultra-compressed/$1_9:${deb_version}_arm64.deb
        cd ../$1-ultra-compressed
        ar -x $1_9:${deb_version}_arm64.deb
        xz -z9 -T0 --lzma2='dict=256MiB' data.tar
        xz -z0 control.tar
        ar -d $1_9:${deb_version}_arm64.deb control.tar data.tar
        ar -r $1_9:${deb_version}_arm64.deb control.tar.xz data.tar.xz
        mv $1_9:${deb_version}_arm64.deb ../
        cd ..
        rm -rf $1 $1-ultra-compressed
}

# chromium-browser
setup_patched chromium-browser
extract chromium-browser

export deb_version=$(grep "^Version: .*$" DEBIAN/control | sed 's/Version: //g')

mkdir -p usr/ opt/ etc/ DEBIAN/
cp -r "$SCRIPTS_DIR"/assets/usr/* usr/
cp -r "$SCRIPTS_DIR"/assets/opt/* opt/
cp -r "$SCRIPTS_DIR"/assets/etc/* etc/
cp -r "$SCRIPTS_DIR"/assets/DEBIAN/* DEBIAN/

# add widevine binary
WD="$(pwd)"
cd opt/chromium.org/chromium/
wget https://github.com/theofficialgman/testing/releases/download/gmans-releases/WidevineCdm-2.36.tar.gz
tar -xvf WidevineCdm-2.36.tar.gz || error "Failed to extract widevine"
rm WidevineCdm-2.36.tar.gz
cd "$WD"

# add ffmpeg binary
cp /srv/chroot/bionic-arm64/home/gman/ffmpeg/libffmpeg.so opt/chromium.org/chromium/ || error "Failed to copy ffmpeg"

repack chromium-browser

cd "$SCRIPTS_DIR"
