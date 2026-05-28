{
  pkgs,
  infraAuthModules,
}:

# Baseline NixOS VM test. Boots a single machine that imports the infra-auth
# modules with Kanidm/ACME/backup disabled, and asserts the firewall posture
# and basic service state.
#
# The test deliberately does NOT enable Kanidm yet — its purpose is to lock
# in the base policy invariants (ports, sshd, no surprise services) before
# any production-touching options are turned on.

let
  inherit (pkgs) lib;

  policyLines = lib.splitString "\n" (builtins.readFile ../policy/allowed-ports.txt);

  parseProtoPorts =
    proto:
    lib.pipe policyLines [
      (map (line: builtins.match "([0-9]+)/${proto}" line))
      (builtins.filter (m: m != null))
      (map builtins.head)
    ];

  policyTcp = parseProtoPorts "tcp";
  policyUdp = parseProtoPorts "udp";

  pyList = ports: "[" + lib.concatStringsSep ", " ports + "]";
in
pkgs.testers.nixosTest {
  name = "infra-auth-baseline";

  nodes.machine = _: {
    imports = infraAuthModules;

    networking.hostName = "infra-auth-vmtest";

    # No real DNS, no real secrets, no production hostnames inside the test
    # machine. infra-auth.kanidm/acme/backup all stay at their disabled
    # defaults from the host-less skeleton.
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # sshd must be active.
    machine.wait_for_unit("sshd.service")
    machine.succeed("systemctl is-active sshd.service")

    # sshd config must reflect ssh.nix hardening.
    sshd_config = machine.succeed("cat /etc/ssh/sshd_config")
    for needle in (
        "PasswordAuthentication no",
        "KbdInteractiveAuthentication no",
        "PermitRootLogin no",
        "X11Forwarding no",
    ):
        assert needle in sshd_config, (
            f"sshd_config missing expected directive: {needle!r}\n{sshd_config}"
        )

    # Kanidm must NOT be enabled in this baseline.
    machine.fail("systemctl is-active kanidm.service")

    # nginx must NOT be enabled in this baseline either.
    machine.fail("systemctl is-active nginx.service")

    # Coredump storage must be disabled (systemd.coredump.enable = false).
    # When the option is off, NixOS does not register systemd-coredump as
    # the kernel core_pattern handler.
    core_pattern = machine.succeed("cat /proc/sys/kernel/core_pattern").strip()
    assert "systemd-coredump" not in core_pattern, (
        f"systemd-coredump unexpectedly active in core_pattern: {core_pattern!r}"
    )

    # Firewall must be the active service.
    machine.wait_for_unit("firewall.service")

    # Policy-driven port assertions. Both IPv4 and IPv6 chains must allow
    # exactly the policy file's TCP/UDP ports. Explicit type annotation so
    # the test driver's mypy pass accepts an empty UDP list literal.
    allowed_tcp: list[int] = ${pyList policyTcp}
    allowed_udp: list[int] = ${pyList policyUdp}

    for chain_cmd, label in (
        ("iptables -L nixos-fw -n", "iptables"),
        ("ip6tables -L nixos-fw -n", "ip6tables"),
    ):
        rules = machine.succeed(chain_cmd)
        for port in allowed_tcp:
            assert f"dpt:{port}" in rules, (
                f"{label}: TCP port {port} from policy missing:\n{rules}"
            )
        for port in allowed_udp:
            assert f"dpt:{port}" in rules, (
                f"{label}: UDP port {port} from policy missing:\n{rules}"
            )

        # Spot-check that some plausibly-bad ports are NOT open.
        for forbidden in ("dpt:21", "dpt:23", "dpt:3389", "dpt:8443"):
            assert forbidden not in rules, (
                f"{label}: unexpected open port matching {forbidden}:\n{rules}"
            )

  '';
}
