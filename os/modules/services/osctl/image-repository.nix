{ config, pkgs, lib, ... }:
with lib;
let
  repository = {
    options = {
      path = mkOption {
        type = types.str;
        description = ''
          Path to the generated image repository.
        '';
      };

      cacheDir = mkOption {
        type = types.str;
        description = ''
          Path to directory where built images are cached before added to the
          repository.
        '';
      };

      buildScriptDir = mkOption {
        type = types.str;
        description = ''
          Path to directory with image build scripts for use with osctl-image
        '';
      };

      buildDataset = mkOption {
        type = types.str;
        description = ''
          Name of a dataset used to build images
        '';
      };

      rebuildAll = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Rebuild all images, even when they're found in cacheDir
        '';
      };

      buildInterval = mkOption {
        default = "0 4 * * *";
        type = types.nullOr types.str;
        description = ''
          Date and time expression for when to build images in a crontab
          format, i.e. minute, hour, day of month, month and day of month
          separated by spaces.
        '';
      };

      postBuild = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Shell commands run after all images were built, or attempted to be built
        '';
      };

      vendors = mkOption {
        type = types.attrsOf (types.submodule vendor);
        default = {};
        example = {
          vpsadminos = { defaultVariant = "minimal"; };
        };
        description = ''
          Vendors
        '';
      };

      defaultVendor = mkOption {
        type = types.str;
        example = "vpsadminos";
        description = ''
          Name of the default image vendor
        '';
      };

      images = mkOption {
        type = types.attrsOf (types.attrsOf (types.submodule image));
        default = {};
        description = ''
          Configure container images
        '';
      };
    };
  };

  vendor = {
    options = {
      defaultVariant = mkOption {
        type = types.str;
        example = "minimal";
        description = ''
          Name of the default image variant
        '';
      };
    };
  };

  image = {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional image name
        '';
      };

      tags = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Image tags
        '';
      };

      rebuild = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Rebuild the image even if it is found in cacheDir
        '';
      };
    };
  };

  createRepositories = cfg: mapAttrsToList createRepository cfg;

  createRepository = repo: cfg: rec {
    buildScript = createBuildScript repo cfg;
    buildScriptBin = "${buildScript}/bin/build-image-repository-${repo}";
    buildInterval = cfg.buildInterval;
  };

  createBuildScript = repo: cfg: pkgs.writeScriptBin "build-image-repository-${repo}" ''
    #!${pkgs.bash}/bin/bash

    repoDir="${cfg.path}"
    repoCache="${cfg.cacheDir}"
    buildDataset="${cfg.buildDataset}"
    buildScriptDir="${cfg.buildScriptDir}"
    osctlRepo="${pkgs.osctl-repo}/bin/osctl-repo"
    osctlImage="${pkgs.osctl-image}/bin/osctl-image"

    if [ ! -d "$repoDir" ] || [ -z "$(ls -A "$repoDir")" ] ; then
      mkdir -p "$repoDir"
      cd "$repoDir"
      $osctlRepo local init
    else
      cd "$repoDir"
    fi

    mkdir -p "$repoCache"

    ${concatStringsSep "\n\n" (buildImages cfg cfg.images)}

    cd "$repoDir"
    ${concatStringsSep "\n" (setDefaultVariants cfg.vendors)}
    $osctlRepo local default ${cfg.defaultVendor}

    ${cfg.postBuild}
  '';

  buildImages = repoCfg: images: flatten (mapAttrsToList (name: versions:
    mapAttrsToList (version: cfg: ''
      pushd "$buildScriptDir"
      $osctlImage deploy \
        --build-dataset $buildDataset \
        --output-dir "$repoCache" \
        ${optionalString (rebuildImage repoCfg cfg) "--rebuild"} \
        ${concatStringsSep "\\\n  " (imageTagArgs cfg.tags)} \
        ${imageName { inherit name version; customName = cfg.name; }} \
        "$repoDir"
      popd
    '') versions
    ) images);

  imageName = { name, version, customName }:
    if customName == null then
      "${name}-${version}"
    else customName;

  imageTagArgs = tags: map (v: "--tag \"${v}\"") tags;

  rebuildImage = repoCfg: imageCfg: repoCfg.rebuildAll || imageCfg.rebuild;

  setDefaultVariants = vendors: mapAttrsToList (name: cfg:
    "$osctlRepo local default ${name} ${cfg.defaultVariant}"
  ) vendors;
in
{
  options = {
    services.osctl.image-repository = mkOption {
      type = types.attrsOf (types.submodule repository);
      default = {};
      description = ''
        Configure container image repositories
      '';
    };
  };

  config =
    let
      repos = createRepositories config.services.osctl.image-repository;
      packages = map (repo: repo.buildScript) repos;
      cronjobs = map (repo: "${repo.buildInterval} root ${repo.buildScriptBin}") repos;
    in {
      environment.systemPackages = packages;
      services.cron.systemCronJobs = cronjobs;
    };
}
