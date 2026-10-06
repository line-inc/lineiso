#!/bin/sh
rm -rf "work" "out"
rm airootfs/root/packages/*.pkg.tar.zst
rm airootfs/root/packages/*.pkg.tar.zst.sig
rm -rf airootfs/root/lineos-skel-liveuser/pkg
rm airootfs/root/lineos-wallpaper.png
rm airootfs/root/lineos-skel-liveuser/*.pkg.tar.zst
rm -rf airootfs/etc/pacman.d/
rm eosiso*.log
mv airootfs/root/livewall-original.png airootfs/root/livewall.png
