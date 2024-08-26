# chromium-tegra-scripts

This repository is the public archive of the scripts previously used to create the Switchroot Ubuntu Noble and Jammy chromium builds. Due to continued google/chromium changes this is no longer feasible for me maintain. There will be no further updates to the scripts and patch files in this repository.

The scripts assume that you have an existing bionic arm64 chroot setup, google depot_tools available in the system PATH, and an existing chromium repo clone. Refer to the script `chromium/build_and_pack.sh` and `ffmpeg-chroot-script/compile-ffmpeg.sh` for further information.

FFmpeg patchfiles are derived from https://github.com/theofficialgman/FFmpeg with local modifications as necessary.