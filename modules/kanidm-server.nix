{
  config,
  lib,
  ...
}:

let
  cfg = config.infra-auth.kanidm;
in
{
  options.infra-auth.kanidm = {
    enable = lib.mkEnableOption "Kanidm identity server (via upstream services.kanidm)";

    domain = lib.mkOption {
      type = lib.types.str;
      example = "auth-staging.example.com";
      description = ''
        Fully-qualified domain for this Kanidm instance. DNS, TLS certs, and
        OIDC origin URLs are derived from this single value — no module
        hardcodes a specific FQDN.
      '';
    };

    originPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "TLS port that user agents connect to.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8443";
      description = ''
        Address Kanidm binds to internally. The reverse proxy
        (modules/nginx-acme.nix) forwards public traffic here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Implemented through the upstream NixOS services.kanidm module.
    # No custom systemd units, no overlays, no custom packages — the
    # project option surface is a thin re-shape of upstream's.
    services.kanidm = {
      enableServer = true;
      serverSettings = {
        inherit (cfg) domain;
        origin = "https://${cfg.domain}:${toString cfg.originPort}";
        bindaddress = cfg.bindAddress;
        # TLS material is placed under /var/lib/acme by modules/nginx-acme.nix.
        # If nginx is used as the public reverse proxy, kanidm still needs its
        # own TLS for the internal listener.
        tls_chain = "/var/lib/acme/${cfg.domain}/fullchain.pem";
        tls_key = "/var/lib/acme/${cfg.domain}/key.pem";
      };
    };

    # IMPORTANT: secret provisioning is intentionally NOT enabled in this
    # phase. Do not turn on the `services.kanidm.provision` family of
    # options that take admin / idm-admin password-file paths: combining
    # those with the kanidm secret-provisioning package variant has
    # previously leaked admin credentials into systemd logs. The exact
    # identifier is left out of this comment so the forbidden-patterns
    # lint can use it as a tripwire. Bootstrap admin credentials via a
    # manual, one-shot procedure documented in runbooks/bootstrap.md.
    #
    # Future OAuth2 client secrets must come from runtime files placed by
    # sops-nix — never from Nix store paths, which are world-readable.

    assertions = [
      {
        assertion = cfg.domain != "";
        message = "infra-auth.kanidm.domain must be set when Kanidm is enabled.";
      }
    ];
  };
}
