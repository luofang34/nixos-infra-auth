{ lib, ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      # Key-only authentication. CI scans for these being flipped back to "yes"
      # or "true" via policy/forbidden-patterns.txt.
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # Root login disabled. Operators have wheel users; emergency access goes
      # through the provider console, not SSH-as-root.
      PermitRootLogin = "no";

      # Restrict legacy features.
      X11Forwarding = false;
    };
  };

  # Production hosts use immutable user definitions. Tests can override with
  # `lib.mkForce true` if the test harness needs to mutate users at runtime.
  users.mutableUsers = lib.mkDefault false;
}
