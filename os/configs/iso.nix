{ config, lib, pkgs, ... }:

# ISO image configuration

{
  imports = [
    ./common.nix
    ../modules/installer/cd-dvd/channel.nix
    ../modules/iso-image.nix
  ];

  networking.hostName = "vpsadminos";
  networking.lxcbr = true;
  networking.nat = true;
  networking.dhcp = true;
  networking.dhcpd = true;

  vpsadminos.nix = true;

  tty.autologin.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    screen
    strace
  ];

  boot.zfs.pools = lib.mkDefault {
    tank = {
      layout = [
        { devices = [ "sda" ]; }
      ];
      install = true;
    };
  };

  isoImage.makeUsbBootable = true;
  isoImage.makeEfiBootable = true;
}
