let
  readDefconfig = import ./util/read_defconfig.nix;
  kernelSrcUrl = v : "https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${v}.tar.xz";
  majmin = version :
    let el = n : builtins.toString (builtins.elemAt version n);
    in (el 0) + "." + (el 1);
  mmp = version :
    let el = n : builtins.toString (builtins.elemAt version n);
    in (el 0) + "." + (el 1) + "." + (el 2);
  uimage = callPackage : vmlinux : cfg : fdt :
            (callPackage ./kernel/uimage.nix) {
              inherit vmlinux;
              inherit fdt;
              inherit (cfg) commandLine loadAddress entryPoint;
            };
in rec {

  # generic config for boards/products based on the mt7620, which uses
  # the "ramips" soc family in Linux.  Board-specific config for
  # systems based on this (at least, all the ones I've seen so far) is
  # based on device tree, so they need .dts files
  mt7620 = rec {
    endian= "little";
    openwrtSrc =  {
      owner = "openwrt";
      repo = "openwrt";
      name = "openwrt-source" ;
      rev = "430b66bbe8726a096b5db04dc34915ae9be1eaeb";
      sha256 = "0h7mzq2055548060vmvyl5dkvbbfzyasa79rsn2i15nhsmmgc0ri";
    };
    socFamily = "ramips";
    hwModule = {dtsPath, soc ? "mt7620" } : nixpkgs: self: super:
      with nixpkgs;
      let version = [4 14 113];
          kernelSrc = pkgs.fetchurl {
            url = (kernelSrcUrl (mmp version));
            sha256 = "1hnsmlpfbcy52dax7g194ksr9179kpigj1y5k44jkwmagziz4kdj";
          };
          readconf = readDefconfig nixpkgs;
          kconfig = {
            "BLK_DEV_INITRD" = "n";
            "CFG80211" = "y";
            "MAC80211" = "y";
            "CLKSRC_MMIO" = "y";
            "CMDLINE_PARTITION" = "y";
            "CPU_LITTLE_ENDIAN" = "y";
            "DEBUG_INFO" = "y";
            "DEVTMPFS" = "y";
            "EARLY_PRINTK" = "y";
            "IMAGE_CMDLINE_HACK" = "n";
            "IP_PNP" = "y";
            "JFFS2_FS" = "n";
            "MIPS_RAW_APPENDED_DTB" = "y";
            "MTD_CMDLINE_PARTS" = "y";
            "NETFILTER"= "y";   # mtk_eth_soc.c won't build without this
            "NET_MEDIATEK_GSW_MT7620" = "y";
            "NET_MEDIATEK_MT7620" = "y";
            "PARTITION_ADVANCED" = "y";
            "PHY_RALINK_USB" = "y";
            "PRINTK_TIME" = "y";
            "SQUASHFS" = "y";
            "SQUASHFS_XZ" = "y";
            "WLAN_VENDOR_MEDIATEK" = "y";
            "WLAN_VENDOR_RALINK" = "y";
            "RT2X00" = "y";
            "RT2X00_DEBUG" = "y";
            "RT2800PCI" = "y";
            "RT2800PCI_RT53XX" = "y";
            "RT2800SOC" = "y";
            "SOC_MT7620" = "y";
          };
      p = "${pkgs.fetchFromGitHub openwrtSrc}/target/linux/";
      socPatches = [
        "${p}ramips/patches-4.14/"
      ];
      socFiles = [
        "${p}ramips/files-4.14/*"
      ];
      ksrc = (callPackage ./kernel/prepare-source.nix) {
        ledeSrc = pkgs.fetchFromGitHub  openwrtSrc;
        inherit version kernelSrc socFamily socPatches socFiles;
      };
      in lib.attrsets.recursiveUpdate super {
        kernel.config = (readconf "${p}generic/config-${majmin version}") //
                        (readconf "${p}${socFamily}/${soc}/config-${majmin version}") //
                        kconfig;
        kernel.loadAddress = "0x80000000";
        kernel.entryPoint = "0x80000000";
        kernel.commandLine = "earlyprintk=serial,ttyS0 console=ttyS0,115200 panic=10 oops=panic init=/bin/init loglevel=8 rootfstype=squashfs";
        kernel.dts = dtsPath;
        kernel.source = ksrc;
        kernel.package =
          let
            fdt = (callPackage ./kernel/build-fdt.nix) {
              dts = dtsPath;
              inherit (self.kernel) commandLine;
              includes = [
                "${p}/ramips/dts"
                "${ksrc}/arch/mips/boot/dts"
                "${ksrc}/arch/mips/boot/dts/include"
                "${ksrc}/include/"];
            };
            vmlinux = (callPackage ./kernel/default.nix) {
              inherit (self.kernel) config source;
              checkedConfig = kconfig;
            };
          in uimage callPackage vmlinux self.kernel fdt;
      };
  };

  # GL-Inet GL-MT300A

  # The GL-Inet pocket router range makes nice cheap hardware for
  # playing with NixWRT or similar projects. The manufacturers seem
  # open to the DIY market, and the devices have a reasonable amount
  # of RAM and are much easier to get serial connections than many
  # COTS routers. GL-MT300A is my current platform for NixWRT
  # development.

  # Wire up the serial connection: this probably involves opening
  # the box, locating the serial header pins (TX, RX and GND) and
  # connecting a USB TTL converter - e.g. a PL2303 based device - to
  # it. The defunct OpenWRT wiki has a guide with some pictures. (If
  # you don't have a USB TTL converter to hand, other options are
  # available. For example, use the GPIO pins on a Raspberry Pi)

  # Run a terminal emulator such as Minicom on whatever is on the
  # other end of the link. I use 115200 8N1 and find it also helps
  # to set "Character tx delay" to 1ms, "backspace sends DEL" and
  # "lineWrap on".

  # When you turn the router on you should be greeted with some
  # messages from U-Boot and a little bit of ASCII art, followed by
  # the instruction to hit SPACE to stop autoboot. Do this and you
  # will get a gl-mt300a> prompt.

  # For flashing from uboot, the firmware partition is from
  # 0xbc050000 to 0xbcfd0000

  # For more details refer to https://ww.telent.net/2018/4/16/flash_ah_ah

  mt300a = mt7620 // rec {
      name = "glinet-mt300a";
      hwModule = nixpkgs: self: super:
        with nixpkgs;
        let dtsPath = "${pkgs.fetchFromGitHub mt7620.openwrtSrc}/target/linux/ramips/dts/GL-MT300A.dts";
        in mt7620.hwModule {inherit dtsPath;} nixpkgs self super;
    };

  # Another GL-Inet product: the MT300N v2 has a slightly different
  # chipset than the 300A, and comes in a yellow case not a blue one.
  # It's different again to the v1, which has only half the RAM.
  # At the time I bought it it was a tenner cheaper than the A
  # variant.

  mt300n_v2 = mt7620 // rec {
      name = "glinet-mt300n_v2";
      hwModule = nixpkgs: self: super:
        with nixpkgs;
        let dtsPath = "${pkgs.fetchFromGitHub mt7620.openwrtSrc}/target/linux/ramips/dts/GL-MT300N-V2.dts";
        in mt7620.hwModule {inherit dtsPath; soc="mt76x8"; } nixpkgs self super;
    };

  # generic config for boards/products based on Atheros AR7x and AR9x
  # SoCs, ("ath79" designator in Linux kernel).  This is for
  # boards/socs/targets that have been updated to use a device tree

  ath79 = rec {
    endian= "big";
    socFamily = "ath79";
    openwrtSrc = {
      owner = "openwrt";
      repo = "openwrt";
      name = "openwrt-source" ;
      rev = "a724095c68c4fc66195f7c4885171e4f1d9e5c5e6";
      sha256 = "1kk4qvrp5wbrci541bjvb6lld60n003w12dkpwl18bxs9ygpnzlq";
    };
    hwModule = {dtsPath } : nixpkgs: self: super:
      with nixpkgs;
      let version = [4 19 84];
          kernelSrc = pkgs.fetchurl {
            url = (kernelSrcUrl (mmp version));
            sha256 = "868b4a92619cb00ab142a20a67f000525b9605820d1b66faa4a183133eac0660";
          };
          readconf = readDefconfig nixpkgs;
          kconfig = {
            "ATH9K" = "y";
            "ATH9K_AHB" = "y";
            "ATH9K_DEBUGFS" = "y";
            "ATH_DEBUG" = "y";
            "ATH10K" = "y";
            "ATH10K_PCI" = "y";
            "ATH10K_DEBUG" = "y";
            "BLK_DEV_INITRD" = "n";
            "CFG80211" = "y";
            # can't get signed regdb to work rn, it just gives me
            # "loaded regulatory.db is malformed or signature is
            # missing/invalid"
            "CFG80211_REQUIRE_SIGNED_REGDB" = "n";
            "CFG80211_DEBUGFS" = "y";
            # I am reluctant to have to enable this but can't transmit on
            # 5GHz bands without it (they are all marked NO-IR)
            "CFG80211_CERTIFICATION_ONUS" = "y";
            # We don't need userspace agent (requires udev), we bake the
            # db into the kernel as firmware
            "CFG80211_CRDA_SUPPORT" = "n";
            "CMDLINE_PARTITION" = "y";
            "DEBUG_INFO" = "y";
            "DEVTMPFS" = "y";
            "EARLY_PRINTK" = "y";
            # we don't have a user helper, so we get multiple 60s pauses
            # at boot time unless we disable trying to call it
            "FW_LOADER_USER_HELPER" = "n";
            "IMAGE_CMDLINE_HACK" = "n";
            "IP_PNP" = "y";
            "JFFS2_FS" = "n";
            "MAC80211" = "y";
            "MIPS_RAW_APPENDED_DTB" = "y";
            "MODULE_SIG" = "n";
            "MTD_CMDLINE_PARTS" = "y";
            "MTD_SPLIT_FIRMWARE" = "y";
            "PARTITION_ADVANCED" = "y";
            "PRINTK_TIME" = "y";
            "SQUASHFS" = "y";
            "SQUASHFS_XZ" = "y";
          };
          p = "${pkgs.fetchFromGitHub openwrtSrc}/target/linux/";
          socFiles = [
            "${p}ath79/files/*"
          ];
          socPatches = [
            "${p}ath79/patches-4.19/"
          ];
          ksrc = (callPackage ./kernel/prepare-source.nix) {
            ledeSrc = pkgs.fetchFromGitHub openwrtSrc;
            inherit version kernelSrc socFamily socFiles socPatches;
          };
          firmwareBlobs = pkgs.fetchFromGitHub {
            owner = "kvalo";
            repo = "ath10k-firmware";
            rev = "5d63529ffc6e24974bc7c45b28fd1c34573126eb";
            sha256 = "1bwpifrwl5mvsmbmc81k8l22hmkwk05v7xs8dxag7fgv2kd6lv2r";
          };
          fwDir = stdenv.mkDerivation rec {
            name = "firmare";
            phases = ["buildPhase"];
            buildPhase = ''
mkdir -p $out/firmware/ath10k/QCA9887/hw1.0/
cp ${pkgs.wireless-regdb}/lib/firmware/regulatory.db* $out/firmware
blobdir=${firmwareBlobs}/QCA9887/hw1.0
cp $blobdir/10.2.4-1.0/firmware-5.bin_10.2.4-1.0-00047 $out/firmware/ath10k/QCA9887/hw1.0/firmware-5.bin
cp $blobdir/board.bin  $out/firmware/ath10k/QCA9887/hw1.0/
'';
          };
      in lib.attrsets.recursiveUpdate super {
        kernel.config =
          (readconf "${p}/generic/config-${majmin version}") //
          (readconf "${p}/ath79/config-4.19") //
          { "EXTRA_FIRMWARE_DIR" = builtins.toJSON "${fwDir}/firmware";
            "EXTRA_FIRMWARE" = builtins.toJSON "regulatory.db regulatory.db.p7s ath10k/QCA9887/hw1.0/firmware-5.bin ath10k/QCA9887/hw1.0/board.bin"; } //
          kconfig;
        kernel.loadAddress = "0x80060000";
        kernel.entryPoint = "0x80060000";
        #        kernel.commandLine = "earlyprintk=serial,ttyATH0 console=ttyS0,115200 panic=10 oops=panic init=/bin/init loglevel=8 rootfstype=squashfs  ath10k_pci.debug_mask=0x432 ath10k_core.debug_mask=0x432";
        kernel.commandLine = "earlyprintk=serial,ttyATH0 console=ttyS0,115200 panic=10 oops=panic init=/bin/init loglevel=8 rootfstype=squashfs";
        kernel.source = ksrc;
        kernel.package =
          let
            fdt = (callPackage ./kernel/build-fdt.nix) {
              dts = dtsPath;
              inherit (self.kernel) commandLine;
              includes = [
                "${p}/ath79/dts"
                "${ksrc}/arch/mips/boot/dts"
                "${ksrc}/arch/mips/boot/dts/include"
                "${ksrc}/include/"];
            };
            vmlinux = (callPackage ./kernel/default.nix) {
              inherit (self.kernel) config source;
              checkedConfig = kconfig;
            };
          in uimage callPackage vmlinux self.kernel fdt;
      };
  };
  ar750 = ath79 //rec {
      name = "glinet-ar750";
      hwModule = nixpkgs: self: super:
        with nixpkgs;
        let owrtDtsPath = "${pkgs.fetchFromGitHub ath79.openwrtSrc}/target/linux/ath79/dts/qca9531_glinet_gl-ar750.dts";
            cal = ./ar750-ath10k-cal.bin;
            dtsPath = stdenv.mkDerivation {
              name = "dts";
              phases = [ "buildPhase" ];
              buildPhase = ''
cat ${owrtDtsPath} > tmp.dts
echo "&pcie0 { wifi@0,0 { qcom,ath10k-calibration-data = [ " >> tmp.dts
od -A n -v -t x1 ${cal}   >> tmp.dts
echo "] ; };};" >> tmp.dts
cp tmp.dts $out
               '';
            };
        in ath79.hwModule {inherit dtsPath; } nixpkgs self super;
  };


  # generic config for boards/products based on Atheros AR7x and AR9x
  # SoCs, which have _not_ been updated to use DTS but instead use the
  # older configuration style that requires a board-specific kconfig
  # option.  This is the "ar71xx" designator

  ar71xx = rec {
    socFamily = "ar71xx";
    endian = "big";
    openwrtSrc =  {
      owner = "openwrt";
      repo = "openwrt";
      name = "openwrt-source" ;
      rev = "430b66bbe8726a096b5db04dc34915ae9be1eaeb";
      sha256 = "0h7mzq2055548060vmvyl5dkvbbfzyasa79rsn2i15nhsmmgc0ri";
    };
    hwModule = {dtsPath ? null }: nixpkgs: self: super:
      with nixpkgs;
      let version = [4 14 113];
          kernelSrc = pkgs.fetchurl {
            url = (kernelSrcUrl (mmp version));
            sha256 = "1hnsmlpfbcy52dax7g194ksr9179kpigj1y5k44jkwmagziz4kdj";
          };
          readconf = readDefconfig nixpkgs;
          p = "${ledeSrc}/target/linux/";
          stripOpts = prefix: c: lib.filterAttrs (n: v: !(lib.hasPrefix prefix n)) c;
          kconfig = stripOpts "ATH79_MACH"
                      (stripOpts "XZ_DEC_"
                       (stripOpts "WLAN_VENDOR_"
                        ((readconf "${p}/generic/config-${majmin version}") //
                         (readconf "${p}/${socFamily}/config-${majmin version}")))) // {
                           "ATH9K" = "y";
                           "ATH9K_AHB" = "y";
                           "BLK_DEV_INITRD" = "n";
                           "CFG80211" = "y";
                           "CMDLINE_PARTITION" = "y";
                           "CRASHLOG" = "n";
                           "DEBUG_FS" = "n";
                           "DEBUG_KERNEL" = "n";
                           "DEVTMPFS" = "y";
                           "IMAGE_CMDLINE_HACK" = "y";
                           "INPUT_MOUSE" = "n";
                           "INPUT_MOUSEDEV" = "n";
                           "JFFS2_FS" = "n";
                           "KALLSYMS" = "n";
                           "MAC80211" = "y";
                           "MSDOS_PARTITION" = "n";
                           "MTD_CMDLINE_PARTS" = "y";
                           "MOUSE_PS2" = "n";
                           "OVERLAY_FS" = "n";
                           "PARTITION_ADVANCED" = "y";
                           "SCHED_DEBUG" = "n";
                           "SLOB" = "y";
                           "SLUB" = "n";
                           "SQUASHFS_ZLIB" = "n";
                           "SUSPEND" = "n";
                           "SWAP" = "n";
                           "TMPFS" = "y";
                           "VT" = "n";
                           "WLAN_VENDOR_ATH" = "y";
                         };
      in lib.attrsets.recursiveUpdate super {
        kernel.config = kconfig;
        kernel.loadAddress = "0x80060000";
        kernel.entryPoint = "0x80060000";
        kernel.dts = null;
        kernel.source = (callPackage ./kernel/prepare-source.nix) {
          ledeSrc = pkgs.fetchFromGitHub openwrtSrc;
          inherit version kernelSrc socFamily;
        };
        kernel.package = let vmlinux = (callPackage ./kernel/default.nix) {
            inherit (self.kernel) config source;
          };
          in uimage self.callPackage vmlinux self.kernel null;
      };
  };
  # The Arduino Yun is a handy (although pricey) way to get an AR9331
  # target without any soldering: it's a MIPS SoC glued to an Arduino,
  # so you can use Arduino tools to talk to it.

  # In order to talk to the Atheros over a serial connection, upload
  # https://www.arduino.cc/en/Tutorial/YunSerialTerminal to your
  # Yun using the standard Arduino IDE. Once the sketch is
  # running, rather than using the Arduino serial monitor as it
  # suggests, I run Minicom on /dev/ttyACM0

  # On a serial connection to the Yun, to get into the U-Boot monitor
  # you hit YUN RST button, then press RET a couple of times - or in
  # newer U-Boot versions you need to type ard very quickly.
  # https://www.arduino.cc/en/Tutorial/YunUBootReflash may help

  # The output most probably will change to gibberish partway through
  # bootup. This is because the kernel serial driver is running at a
  # different speed to U-Boot, and you need to change it (if using the
  # YunSerialTerminal sketch, by pressing ~1 or something along those
  # lines).

  yun =
    ar71xx // rec {
      name = "arduino-yun";
      hwModule = nixpkgs: self: super:
      let super' = (ar71xx.hwModule {} nixpkgs self super);
        in nixpkgs.lib.recursiveUpdate super' {
          kernel.config."ATH79_MACH_ARDUINO_YUN" = "y";
          kernel.commandLine = "earlyprintk=serial,ttyATH0 console=ttyATH0,115200 panic=10 oops=panic init=/bin/init rootfstype=squashfs board=Yun machtype=Yun";
        };
    };

  # The TrendNET TEW712BR is another Atheros AR9330 device, but has
  # only 4MB of flash.  In 2018 this means it has essentially nothing
  # to recommend it as a NixWRT or OpenWRT target, but I happened to
  # have one lying around and wanted to use it.

  tew712br =
    ar71xx // rec {
      name = "trendnet-tew712br";
      hwModule = nixpkgs: self: super:
      let super' = (ar71xx.hwModule {} nixpkgs self super);
        in nixpkgs.lib.recursiveUpdate super' {
          kernel.config."ATH79_MACH_TEW_712BR" = "y";
          kernel.commandLine = "earlyprintk=serial,ttyATH0 console=ttyATH0,115200 panic=10 oops=panic init=/bin/init rootfstype=squashfs board=TEW-712BR machtype=TEW-712BR";
        };
    };
}
