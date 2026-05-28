{ lib, ... }:

# Sample consumer of nixos-infra-auth.
#
# This file is documentation-as-code: it shows the option surface that a
# real deployment repository would set per host. It is NOT wired into the
# flake's nixosConfigurations because the public repo intentionally has no
# provisionable hosts of its own. Copy and adapt.
#
# Real integration coverage lives in tests/vm-test.nix.

{
  networking.hostName = "example-auth";
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  system.stateVersion = "25.11";

  # Eval-safe stubs. A real consumer replaces these with hardware.nix +
  # disko config from their deployment repo.
  boot.loader.grub = {
    enable = true;
    devices = [ "nodev" ];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  users.users.placeholder-admin = {
    isNormalUser = true;
    description = "Placeholder — replace before any deploy";
    extraGroups = [ "wheel" ];
    hashedPassword = null;
    openssh.authorizedKeys.keys = [ ];
  };

  users.allowNoPasswordLogin = true;

  # The option surface this module set exposes. Flip enable flags to true
  # only when DNS, ACME email, and a real off-host backup target are wired.
  infra-auth = {
    kanidm = {
      enable = false;
      domain = "auth.example.com";
    };

    acme = {
      enable = false;
      email = "ops@example.com";
    };

    backup = {
      enable = false;
      destination = "restic:b2:example-bucket/kanidm";
    };
  };
}
