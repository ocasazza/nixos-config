# Skip nix-darwin's `ensureAppManagement` check so SSH-driven activations
# (cast-on / claw) stop dying on the `tccutil reset SystemPolicyAppBundles`
# dance every activation.
#
# Background:
#   nix-darwin's `modules/system/applications.nix` contributes two things
#   to a darwin switch:
#     1. A `system.checks.text` block that `touch`-tests each
#        `/Applications/Nix Apps/*.app/.DS_Store` to verify the activating
#        process has macOS TCC App Management permission
#        (`kTCCServiceSystemPolicyAppBundles`). If the probe fails AND the
#        launchd session is non-Aqua, it emits the "over SSH" error and
#        exits; if it's Aqua, it calls `tccutil reset SystemPolicyAppBundles`
#        to force a fresh GUI prompt, then re-tests.
#     2. A `system.activationScripts.applications.text` block that rsyncs
#        Nix-provided .app bundles into /Applications/Nix Apps.
#
#   Problem: (1) breaks every non-interactive activation. Granting App
#   Management to Terminal.app via a local click doesn't help over SSH
#   because TCC grants are per-process — `sshd-keygen-wrapper` needs its
#   own grant, and there's no nix-darwin option to pre-seed that grant
#   (no MDM → no profile-based TCC push).
#
#   We want (2) (the rsync) but not (1) (the check). `disabledModules`
#   drops the whole upstream module, so we re-inline the rsync verbatim
#   below. The TCC check's only job was emitting a helpful error
#   pre-flight — dropping it means the rsync itself will fail loudly
#   if a bundle can't be mutated, which is a clearer failure mode for
#   fleet deploys than the interactive tccutil-reset prompt anyway.
#
# One-time manual grants recommended for smooth SSH fan-out:
#   System Settings → Privacy & Security → App Management → +
#     /usr/libexec/sshd-keygen-wrapper   (for `cast-on` over SSH)
#     (your terminal emulator)           (for local `nh darwin switch`)
{
  config,
  lib,
  pkgs,
  ...
}:

{
  disabledModules = [ "system/applications.nix" ];

  config = {
    # Re-inlined verbatim from nix-darwin's applications.nix. Kept
    # intact so future upstream rsync-logic changes are easy to diff.
    system.build.applications = pkgs.buildEnv {
      name = "system-applications";
      paths = config.environment.systemPackages;
      pathsToLink = [ "/Applications" ];
    };

    system.activationScripts.applications.text = ''
      # Set up applications.
      echo "setting up /Applications/Nix Apps..." >&2

      ourLink () {
        local link
        link=$(readlink "$1")
        [ -L "$1" ] && [ "''${link#*-}" = 'system-applications/Applications' ]
      }

      ${lib.optionalString (config.system.primaryUser != null) ''
        # Clean up for links created at the old location in HOME.
        if ourLink ~${config.system.primaryUser}/Applications; then
          rm ~${config.system.primaryUser}/Applications
        elif ourLink ~${config.system.primaryUser}/Applications/'Nix Apps'; then
          rm ~${config.system.primaryUser}/Applications/'Nix Apps'
        fi
      ''}

      targetFolder='/Applications/Nix Apps'

      # Clean up old style symlink to nix store
      if [ -e "$targetFolder" ] && ourLink "$targetFolder"; then
        rm "$targetFolder"
      fi

      mkdir -p "$targetFolder"

      rsyncFlags=(
        # mtime is standardized in the nix store, which would leave only
        # file size to distinguish files. Thus we need checksums, despite
        # the speed penalty.
        --checksum
        # Converts all symlinks pointing outside of the copied tree (thus
        # unsafe) into real files and directories. This neatly converts all
        # the symlinks pointing to application bundles in the nix store
        # into real directories, without breaking any relative symlinks
        # inside of application bundles.
        --copy-unsafe-links
        --archive
        --delete
        --chmod=-w
        --no-group
        --no-owner
      )

      ${lib.getExe pkgs.rsync} "''${rsyncFlags[@]}" ${config.system.build.applications}/Applications/ "$targetFolder"
    '';
  };
}
