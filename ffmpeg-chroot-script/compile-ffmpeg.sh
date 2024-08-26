#!/bin/bash

browser_version="$1"

rm -rf ffmpeg
mkdir ffmpeg
cd ffmpeg
# https://chromium.googlesource.com/chromium/src.git/+/refs/tags/121.0.6167.139/DEPS
ffmpeg_commit="$(wget -qO- https://chromium.googlesource.com/chromium/src.git/+/refs/tags/$browser_version/DEPS?format=TEXT | base64 --decode | grep "'ffmpeg_revision': " | sed "s/'ffmpeg_revision': //g" | tr -d ",'" | awk ' { print $1 }')"
echo "ffmpeg commit hash: $ffmpeg_commit"
wget https://chromium.googlesource.com/chromium/third_party/ffmpeg/+archive/$ffmpeg_commit.tar.gz -O ffmpeg.tar.gz
tar -xvf ffmpeg.tar.gz
rm -f ffmpeg.tar.gz

# patch ffmpeg
patch -p1 -i ../nvv4l2-chrome-125.0-dynamic.patch
git apply ../0001-nvv4l2-Change-linking-from-static-to-dynamic.patch

chmod +x ./build_for_chrome.sh
./build_for_chrome.sh
strip libffmpeg.so

