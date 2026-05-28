{
  config,
  lib,
  ...
}:

let
  cfg = config.infra-auth.backup;
  inherit (config.infra-auth) kanidm;
in
{
  options.infra-auth.backup = {
    enable = lib.mkEnableOption "Periodic Kanidm backup to an off-host store";

    destination = lib.mkOption {
      type = lib.types.str;
      example = "restic:b2:my-bucket/kanidm";
      description = ''
        Encrypted backup destination. Backup names embed the Kanidm version
        because restore is only valid against the same server version.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the backup timer.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/restic-password";
      description = ''
        Path to a file containing the restic repository password. Provided
        out-of-band by sops-nix or equivalent. Required when
        infra-auth.backup.enable is true.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Naming convention enforced by the backup script:
    #   kanidm-<host>-<kanidm-version>-<UTC timestamp>.tar.zst
    #
    # The Kanidm version must be readable from the running server so that the
    # filename and the restore precondition agree. Restoring a backup with a
    # different Kanidm server version is unsupported by upstream.
    #
    # Implementation is intentionally deferred: a real backup needs (a) a
    # tested kanidmd database backup path, (b) restic credentials passed via
    # LoadCredential, and (c) a smoke test that confirms the off-host upload.
    # Until those are in place, fail loudly on enable rather than silently
    # producing no backups for an identity server.

    assertions = [
      {
        assertion = kanidm.enable;
        message = ''
          infra-auth.backup.enable requires infra-auth.kanidm.enable. Backup
          is for the Kanidm database; there is nothing else to back up here.
        '';
      }
      {
        assertion = cfg.destination != "" && cfg.destination != "restic:placeholder-not-yet-configured";
        message = "infra-auth.backup.destination must be set to a real off-host store.";
      }
      {
        assertion = cfg.passwordFile != null;
        message = "infra-auth.backup.passwordFile must point at a file containing the restic repository password.";
      }
      {
        assertion = false;
        message = ''
          infra-auth.backup is reserved but the systemd unit + restic
          integration are NOT YET wired up in this module set. Enabling it
          would silently produce no backups, which is unsafe for an
          identity server. Either:

            - keep infra-auth.backup.enable = false and run backups
              out-of-band, or
            - contribute the implementation (see modules/backup-kanidm.nix
              for the pending design notes).
        '';
      }
    ];
  };
}
