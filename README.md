# nixos-infra-auth

NixOS modules for self-hosted identity (Kanidm + nginx/ACME + restic
backup). Domain-decoupled — modules take the FQDN as an option, not a
hardcoded string — so one module set drives both staging and production.

**Status: experimental, built primarily for the author's own deployment.**
Contributions and audit are welcome; no promises about stability, API
compatibility, or support.

## Usage

```nix
# flake.nix in your deployment repository
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    infra-auth-modules = {
      url = "github:luofang34/nixos-infra-auth";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, infra-auth-modules, ... }: {
    nixosConfigurations.my-auth = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        infra-auth-modules.nixosModules.default
        ./hosts/my-auth/default.nix
      ];
    };
  };
}
```

```nix
# hosts/my-auth/default.nix
{
  infra-auth = {
    kanidm = { enable = true; domain = "auth.example.com"; };
    acme   = { enable = true; email = "ops@example.com"; };
    backup = { enable = true; destination = "restic:b2:my-bucket/kanidm"; };
  };
}
```

See `hosts/example/default.nix` for the full option surface.

## Modules

Each importable individually as `nixosModules.<name>`, or all together as
`nixosModules.default`.

| Module | Wraps |
|---|---|
| `base` | Nix settings, GC, locale, baseline pkgs |
| `ssh` | `services.openssh` — key-only, no root |
| `security` | Firewall (22/80/443), sysctl, coredumps off |
| `kanidm-server` | `services.kanidm` (via `infra-auth.kanidm.*`) |
| `nginx-acme` | `services.nginx` + `security.acme` (via `infra-auth.acme.*`) |
| `backup-kanidm` | systemd timer for restic-style backups (via `infra-auth.backup.*`) |

## Also exposed

```
lib.mkLintChecks          # consumer flake.checks builder (fmt/deadnix/statix/forbidden-patterns)
lib.forbiddenPatternsFile # path
lib.allowedPortsFile      # path
apps.<sys>.smoke-test     # `nix run .#smoke-test -- <fqdn>` after deploy
.github/workflows/nix-flake-check.yml  # reusable workflow (workflow_call)
```

## Development

```sh
nix flake check        # fmt + deadnix + statix + forbidden-patterns + vmTest (Linux)
nix develop            # devShell
```

CI runs lint + vmTest on `ubuntu-24.04-arm`.

## Design constraints

See [CLAUDE.md](./CLAUDE.md). The short version: domain-decoupled,
upstream-friendly, no host-specific anything in this repo.

## License

AGPL-3.0. See [LICENSE](./LICENSE).
