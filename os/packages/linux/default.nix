{ pkgs, fetchpatch, ... }:
let
  kernelPatches = pkgs.kernelPatches;
in
  pkgs.callPackage ./linux-5.3.nix {
    kernelPatches =
      [ kernelPatches.bridge_stp_helper
        # See pkgs/os-specific/linux/kernel/cpu-cgroup-v2-patches/README.md
        # when adding a new linux version
        # kernelPatches.cpu-cgroup-v2."4.11"

        {
          name = "vpsadminos-kernel-config";
          patch = null;
          extraConfig = ''
            EXPERT y
            CHECKPOINT_RESTORE y
            CFS_BANDWIDTH y
            MEMCG_32BIT_IDS y
            CGROUP_CGLIMIT y
            SYSLOG_NS y
            AUFS_FS y
            AUFS_BRANCH_MAX_127 y
            AUFS_SBILIST y
            AUFS_HNOTIFY y
            AUFS_HFSNOTIFY y
            AUFS_EXPORT y
            AUFS_INO_T_64 y
            AUFS_XATTR y
            AUFS_FHSM y
            AUFS_RDU y
            AUFS_DIRREN y
            AUFS_SHWH y
            AUFS_BR_RAMFS y
            AUFS_BR_FUSE y
            AUFS_POLL y
            AUFS_BR_HFSPLUS y
            AUFS_BDEV_LOOP y
          '';
        }
      ];
  }
