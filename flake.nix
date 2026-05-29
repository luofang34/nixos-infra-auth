{
  description = "nixos-infra-auth: portable NixOS modules for self-hosted identity (Kanidm + nginx/ACME + restic backup)";

  inputs = {
    # Single source of truth for nixpkgs. Pinned to the current stable channel.
    # Consumers may override via inputs.nixos-infra-auth.inputs.nixpkgs.follows.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      linuxSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      forEachSystem =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});

      # The five auth-specific modules consumers may import individually.
      # Generic baseline (nix settings, locale, baseline pkgs, sshd defaults)
      # is delegated to `nixos-infra-common`'s `base` module — consumers are
      # expected to import that alongside this flake's `default`.
      moduleFiles = {
        ssh = ./modules/ssh.nix;
        security = ./modules/security.nix;
        kanidm-server = ./modules/kanidm-server.nix;
        nginx-acme = ./modules/nginx-acme.nix;
        backup-kanidm = ./modules/backup-kanidm.nix;
      };

      # The vmTest needs the modules as a list, in import-order.
      infraAuthModules = builtins.attrValues moduleFiles;

      forbiddenPatternsFile = ./policy/forbidden-patterns.txt;
      allowedPortsFile = ./policy/allowed-ports.txt;

      # Consumers pass `extraPatternsFile` to overlay additional forbidden
      # patterns onto the base set.
      mkLintChecks =
        {
          pkgs,
          src,
          extraPatternsFile ? null,
        }:
        let
          nixFiles = "$(find . -name '*.nix' -not -path './.git/*' -not -path './result*')";

          mergedPatterns = pkgs.writeText "forbidden-patterns-merged" (
            builtins.readFile forbiddenPatternsFile
            + (if extraPatternsFile != null then "\n" + builtins.readFile extraPatternsFile else "")
          );
        in
        {
          fmt = pkgs.runCommand "fmt-check" { inherit src; } ''
            cp -r $src ./repo
            chmod -R +w ./repo
            cd ./repo
            ${pkgs.nixfmt-rfc-style}/bin/nixfmt --check ${nixFiles}
            touch $out
          '';

          deadnix = pkgs.runCommand "deadnix-check" { inherit src; } ''
            ${pkgs.deadnix}/bin/deadnix --fail $src
            touch $out
          '';

          statix = pkgs.runCommand "statix-check" { inherit src; } ''
            ${pkgs.statix}/bin/statix check $src
            touch $out
          '';

          forbidden-patterns =
            pkgs.runCommand "forbidden-patterns-check"
              {
                inherit src;
                patterns = mergedPatterns;
              }
              ''
                set -u
                # Strip blank lines so grep -f doesn't match-everything.
                patternsFile=$(mktemp)
                grep -v '^[[:space:]]*$' $patterns > $patternsFile

                matches=$(
                  grep -rEn -f $patternsFile \
                    --include='*.nix' \
                    --include='*.sh' \
                    --include='*.yaml' \
                    --include='*.yaml.example' \
                    --include='*.yml' \
                    --include='*.toml' \
                    --exclude='forbidden-patterns*.txt' \
                    $src || true
                )

                if [ -n "$matches" ]; then
                  echo "Forbidden patterns detected:"
                  echo "$matches"
                  exit 1
                fi
                touch $out
              '';
        };

      # Repo-internal: not exposed via lib.mkLintChecks because the policy
      # file and the security module are this repo's own contract.
      mkPortsParityCheck =
        pkgs:
        pkgs.runCommand "ports-parity-check"
          {
            policyFile = allowedPortsFile;
            securityModule = ./modules/security.nix;
            nativeBuildInputs = [ pkgs.gawk ];
          }
          ''
            set -euo pipefail

            # Extract numeric tokens that appear inside a `key = [ ... ];`
            # attribute in a NixOS module. Handles both single-line empty
            # lists (`allowedUDPPorts = [ ];`) and multi-line lists.
            extract_ports() {
              local key="$1" file="$2"
              awk -v key="$key" '
                # Find start: line containing `<key> = [`. Strip everything
                # up to and including the [, then process the remainder.
                $0 ~ ("\\<" key "[[:space:]]*=[[:space:]]*\\[") {
                  inblock = 1
                  sub(/.*\[/, "")
                }
                inblock {
                  line = $0
                  if (match(line, /\]/)) {
                    inblock = 0
                    line = substr(line, 1, RSTART - 1)
                  }
                  while (match(line, /[0-9]+/)) {
                    print substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                  }
                  next
                }
              ' "$file" | sort -n -u
            }

            policy_tcp=$(grep -E '^[0-9]+/tcp$' "$policyFile" | sed 's|/tcp||' | sort -n -u)
            policy_udp=$(grep -E '^[0-9]+/udp$' "$policyFile" | sed 's|/udp||' | sort -n -u || true)

            module_tcp=$(extract_ports allowedTCPPorts "$securityModule")
            module_udp=$(extract_ports allowedUDPPorts "$securityModule")

            fail=0
            if [ "$policy_tcp" != "$module_tcp" ]; then
              echo "TCP port list mismatch between policy/allowed-ports.txt and modules/security.nix:"
              ${pkgs.diffutils}/bin/diff <(echo "$policy_tcp") <(echo "$module_tcp") || true
              fail=1
            fi
            if [ "$policy_udp" != "$module_udp" ]; then
              echo "UDP port list mismatch between policy/allowed-ports.txt and modules/security.nix:"
              ${pkgs.diffutils}/bin/diff <(echo "$policy_udp") <(echo "$module_udp") || true
              fail=1
            fi
            [ "$fail" -eq 0 ] || exit 1
            touch $out
          '';

      # Linux-only: pkgs.testers.nixosTest runs the test driver in QEMU/KVM.
      mkVmTest = pkgs: {
        vmTest = import ./tests/vm-test.nix {
          inherit pkgs infraAuthModules;
        };
      };

      # `nix run .#smoke-test -- <fqdn>` runs reachability + OIDC checks.
      # writeShellApplication bundles bash/curl/jq into PATH so the entry
      # point works on any host with Nix, not just hosts that already have
      # those tools installed. It also runs shellcheck at build time.
      mkApps = pkgs: {
        smoke-test = {
          type = "app";
          meta = {
            description = "Run reachability + OIDC-discovery smoke tests against a deployed host";
          };
          program = "${
            pkgs.writeShellApplication {
              name = "smoke-test";
              runtimeInputs = [
                pkgs.bash
                pkgs.curl
                pkgs.jq
              ];
              text = ''
                if [ $# -lt 1 ]; then
                  echo "usage: nix run .#smoke-test -- <fqdn>" >&2
                  exit 2
                fi
                host="$1"
                bash ${./tests/reachability-smoke.sh} "$host"
                bash ${./tests/oidc-discovery-smoke.sh} "$host"
              '';
            }
          }/bin/smoke-test";
        };
      };
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-rfc-style);

      nixosModules = moduleFiles // {
        default = {
          imports = infraAuthModules;
        };
      };

      lib = {
        inherit
          mkLintChecks
          forbiddenPatternsFile
          allowedPortsFile
          supportedSystems
          linuxSystems
          forEachSystem
          ;
      };

      checks = nixpkgs.lib.genAttrs supportedSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lint = mkLintChecks {
            inherit pkgs;
            src = self;
          };
          portsParity = {
            ports-parity = mkPortsParityCheck pkgs;
          };
          vm = if nixpkgs.lib.elem system linuxSystems then mkVmTest pkgs else { };
        in
        lint // portsParity // vm
      );

      apps = forEachSystem mkApps;

      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nix
            pkgs.git
            pkgs.nixfmt-rfc-style
            pkgs.deadnix
            pkgs.statix
          ];
        };
      });
    };
}
