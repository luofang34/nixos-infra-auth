_:

{
  # Firewall default-deny. The allowed-port set is intentionally narrow and
  # mirrored in policy/allowed-ports.txt so CI can enforce parity.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      80
      443
    ];
    allowedUDPPorts = [ ];
    logRefusedConnections = false;
  };

  # Light sysctl hardening. Expand in a dedicated module if more is needed.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;
  };

  # Disable coredumps by default — identity hosts should not write process
  # memory to disk.
  systemd.coredump.enable = false;
}
