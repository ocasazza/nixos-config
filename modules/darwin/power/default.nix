# Prevent sleep, hibernate, and power-off on cluster nodes.
# Keeps machines awake even with the lid closed (clamshell mode)
# so they remain available as distributed Nix builders and exo peers.
{ ... }:
{
  # nix-darwin native power options
  power = {
    restartAfterFreeze = true;
    # restartAfterPowerFailure: not supported on all Macs (e.g. laptops)
    # restartAfterPowerFailure = true;
    sleep = {
      computer = "never";
      display = "never";
      harddisk = "never";
      allowSleepByPowerButton = false;
    };
  };

  system.defaults.loginwindow = {
    PowerOffDisabledWhileLoggedIn = true;
    SleepDisabled = true;
  };

  # nix-darwin's power module doesn't cover all pmset flags.
  # Use an activation script for the remaining settings:
  #   - lidwake: wake on lid open
  #   - acwake: wake when power source changes
  #   - standby / autopoweroff / hibernatemode: disable all hibernation
  system.activationScripts.postActivation.text = ''
    echo "Configuring power management for always-on cluster node..." >&2
    sudo pmset -a disablesleep 1
    sudo pmset -a lidwake 1
    sudo pmset -a acwake 1
    sudo pmset -a standby 0
    sudo pmset -a standbydelayhigh 0
    sudo pmset -a standbydelaylow 0
    sudo pmset -a autopoweroff 0
    sudo pmset -a hibernatemode 0
    sudo pmset -a womp 1
    sudo pmset -a networkoversleep 0
    sudo pmset -a tcpkeepalive 1
    sudo pmset -a ttyskeepawake 1
    sudo pmset -a proximitywake 0
  '';
}
