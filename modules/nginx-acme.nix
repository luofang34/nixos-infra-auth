{
  config,
  lib,
  ...
}:

let
  cfg = config.infra-auth.acme;
  inherit (config.infra-auth) kanidm;
in
{
  options.infra-auth.acme = {
    enable = lib.mkEnableOption "nginx + ACME for the Kanidm domain";

    email = lib.mkOption {
      type = lib.types.str;
      example = "ops@example.com";
      description = "Email Let's Encrypt should associate with this account.";
    };
  };

  config = lib.mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
      certs.${kanidm.domain} = {
        # nginx's enableACME below installs the cert with group=nginx. We
        # extend reloadServices so kanidm picks up renewals via the shared
        # group membership configured further down.
        reloadServices = [ "kanidm.service" ];
      };
    };

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      virtualHosts.${kanidm.domain} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          # Kanidm terminates TLS on its internal listener using the same
          # ACME cert. proxy_ssl_verify is off by default in nginx; that is
          # acceptable here because the upstream is a loopback bind and the
          # cert sharing is already handled.
          proxyPass = "https://${kanidm.bindAddress}";
          proxyWebsockets = true;
        };
      };
    };

    # Both nginx and kanidm need read access to the cert files. enableACME
    # places them under nginx's group; add kanidm to that group so its
    # internal TLS listener can load the chain.
    users.users.kanidm.extraGroups = [ "nginx" ];

    # Delay kanidm startup until the cert exists. On first boot ACME has not
    # issued yet; without this ordering kanidm crash-loops trying to read
    # missing TLS files.
    systemd.services.kanidm = {
      after = [ "acme-finished-${kanidm.domain}.target" ];
      wants = [ "acme-finished-${kanidm.domain}.target" ];
    };

    assertions = [
      {
        assertion = kanidm.enable;
        message = ''
          infra-auth.acme.enable requires infra-auth.kanidm.enable. ACME is
          provisioned for the Kanidm FQDN; enabling it without a target
          domain is not supported.
        '';
      }
      {
        assertion = cfg.email != "";
        message = "infra-auth.acme.email must be set when ACME is enabled.";
      }
    ];
  };
}
