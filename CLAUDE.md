# CLAUDE.md — Agent guidance for nixos-infra-auth

This repository provides reusable NixOS modules for self-hosted identity
infrastructure (Kanidm + nginx/ACME + restic backup). It is consumed as a
flake input by deployment repositories that hold the actual host configs,
FQDNs, and secrets.

**This repo is public.** Treat anything committed here as world-readable.
Operational details (FQDNs, operator pubkeys, runbooks describing break-glass
procedures) belong in the consuming private repo, not here.

## What this repo is

- NixOS modules that expose options under `infra-auth.*`.
- A VM-based integration test (`tests/vm-test.nix`) that locks in the
  disabled-by-default invariants (firewall posture, no surprise services).
- Helper smoke scripts (`tests/*.sh`) consumers run against deployed hosts.
- Lint scaffolding (fmt, deadnix, statix, forbidden-patterns).

## What this repo is NOT

- No FQDNs, no operator pubkeys, no per-environment configuration.
- No deployment workflows. Those live in the consuming repo.
- No secrets. Modules accept secret *paths* (e.g. sops-decrypted runtime
  files); they never embed literal credentials.

## Design constraints

These are non-negotiable. They take precedence over apparent shortcuts.

1. **Domain decoupled.** No module hardcodes a specific FQDN. Hosts inject
   the domain via `infra-auth.kanidm.domain`. DNS records, ACME email, and
   OIDC origins are derived from that single source.

2. **Upstream-friendly.** Modules wrap upstream NixOS modules
   (`services.kanidm`, `services.nginx`, `security.acme`, ...). No custom
   systemd units, no overlays, no parallel `nixpkgs` trees. Bumping a
   consumer's `nixpkgs` should propagate cleanly.

3. **Cross-architecture.** Both `aarch64-linux` and `x86_64-linux` are
   first-class. The vmTest runs on Linux; lint runs on every supported
   system including Darwin.

## Adding a new module

1. Add `modules/<name>.nix` with options under `infra-auth.<name>.*`.
2. Add it to `moduleFiles` in `flake.nix`.
3. Extend `tests/vm-test.nix` to cover its disabled-by-default invariants.
4. If it opens a new TCP port, add it to `policy/allowed-ports.txt` and the
   vmTest firewall assertions.

## Kanidm-specific notes

- Do **not** enable `services.kanidm.provision` options that take
  `adminPasswordFile` / `idmAdminPasswordFile`. Combined with
  `kanidmWithSecretProvisioning` they have previously leaked admin
  credentials into systemd logs. Consumers bootstrap admin credentials
  manually on the host, one-shot.
- Backups embed the Kanidm version in the filename; restore is only valid
  against a server running the same version.

## Agent boundaries

Bots and AI agents working in this repo **may**:

- Open PRs for module changes, vmTest expansions, lint additions.
- Bump `flake.lock` in one-input-per-PR.
- Run `nix flake check` to verify changes.

Bots and AI agents **must not**:

- Add a host-specific FQDN, key, or address anywhere in this repo.
- Add a module that has not been requested or designed in advance.
- Add a dependency on a private or internal-only resource (URL, package).

## What belongs in `lib`

`lib` is the consumer extension surface. Things that belong:
`mkLintChecks`, policy file paths, system-list utilities — anything
reusable that wraps the modules' surrounding scaffolding.

Things that don't: host FQDNs, runner labels, operator paths, anything
that serves exactly one consumer. Adding to `lib` constrains every future
consumer; removing is a breaking change.

## When in doubt

Stop and surface the question. Identity systems punish quiet improvisation,
even at the module-design layer.
