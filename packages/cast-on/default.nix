# cast-on — deploy this nixos-config to one or more cluster nodes in
# parallel, using consortium's `claw` (rust ClusterShell fork) for the
# fan-out + ssh transport.
#
# The name is a knitting nod: "cast on" is how you start a knitting
# project — analogously, this is how you start a deploy.
#
# Usage:
#   nix run .#cast-on                 # deploy to all-deploy group
#   nix run .#cast-on -- luna         # deploy only to luna
#   nix run .#cast-on -- @darwin      # deploy to the darwin claw group
#   nix run .#cast-on -- --dry-run luna
#
# Targets are resolved by claw, so any group/pattern from
# ~/.config/clustershell/groups.d/cluster.cfg works.
#
# Per-target activation is dispatched on the OS:
#   * Darwin nodes  -> `darwin-rebuild switch --flake .#<host>`
#   * NixOS nodes   -> `nixos-rebuild switch --flake .#<host> --use-remote-sudo`
#
# Build closures locally (we have a fat workstation + binary cache),
# then `nix copy` push to each remote, then activate. This avoids
# spinning up a build on every laptop in the cluster.
{
  lib,
  stdenv,
  system,
  writeShellApplication,
  git,
  nh,
  openssh,
  nix,
  inputs,
  ...
}:

let
  # `consortium` ships its rust CLI under packages.<system>.consortium-cli.
  # The binary is `claw`. We pull it from the consortium flake input so
  # we don't depend on whatever's in nixpkgs.
  consortium-cli = inputs.consortium.packages.${system}.consortium-cli;
in
writeShellApplication {
  name = "cast-on";
  runtimeInputs = [
    git
    nh
    openssh
    consortium-cli
    nix
  ];

  text = ''
    # cast-on — parallel deploys using consortium claw.
    #
    # Targets default to the `all-deploy` claw group when no args given.
    # Any claw-supported syntax works:
    #   cast-on luna
    #   cast-on @darwin
    #   cast-on @gpu
    #   cast-on luna,GN9CFLM92K-MBP.local

    DRY_RUN=0
    SKIP_GIT=0
    TARGETS=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --skip-git)   SKIP_GIT=1; shift ;;
        --help|-h)
          cat <<'EOF'
    cast-on — fan-out NixOS/nix-darwin deploys via consortium claw

    Usage: cast-on [OPTIONS] [TARGET...]

    Options:
      -n, --dry-run     Build closures and copy them, but skip activation
          --skip-git    Don't auto-commit/push uncommitted changes
      -h, --help        Show this help

    Targets:
      Any claw-resolvable host or @group. Defaults to `@all-deploy`.

    Examples:
      cast-on                 # all hosts in the all-deploy group
      cast-on luna            # just luna
      cast-on @darwin         # the darwin group
      cast-on @gpu --dry-run  # build for GPU nodes, don't activate
    EOF
          exit 0
          ;;
        --) shift; TARGETS+=("$@"); break ;;
        -*)
          echo "cast-on: unknown option: $1" >&2
          exit 64
          ;;
        *) TARGETS+=("$1"); shift ;;
      esac
    done

    if [[ ''${#TARGETS[@]} -eq 0 ]]; then
      TARGETS=("@all-deploy")
    fi

    # ── Repo root ─────────────────────────────────────────────────────
    if [[ -n ''${REPO_DIR:-} ]]; then
      :
    elif git -C "$PWD" rev-parse --show-toplevel &>/dev/null; then
      REPO_DIR="$(git -C "$PWD" rev-parse --show-toplevel)"
    else
      echo "cast-on: cannot find nixos-config repo. Run from the repo root or set REPO_DIR." >&2
      exit 1
    fi
    cd "$REPO_DIR"

    LOCAL_HOSTNAME="$(hostname -s)"
    SSH_USER="''${CAST_ON_SSH_USER:-casazza}"

    # Resolve claw targets to a flat list of hostnames so we can
    # dispatch per-host (claw -w expands @groups, the `nodeset` tool
    # would do the same but we don't need it for simple groups).
    #
    # claw -w "$pat" --pick=0 prints the resolved nodeset; safer to
    # use claw with a no-op so we get exit-coded resolution.
    resolve_targets() {
      local out=""
      for pat in "$@"; do
        if [[ $pat == @* ]]; then
          local group="''${pat#@}"
          # groups.d/cluster.cfg is space-separated values
          local hosts
          hosts=$(grep "^''${group}:" ~/.config/clustershell/groups.d/cluster.cfg 2>/dev/null \
                  | head -1 \
                  | cut -d: -f2- \
                  | tr -s ' ')
          if [[ -z $hosts ]]; then
            echo "cast-on: claw group '$group' not found in cluster.cfg" >&2
            exit 1
          fi
          out+=" $hosts"
        else
          out+=" $pat"
        fi
      done
      # shellcheck disable=SC2001
      echo "$out" | sed 's/^ *//;s/ *$//' | tr -s ' '
    }

    RESOLVED="$(resolve_targets "''${TARGETS[@]}")"
    read -r -a HOSTS <<<"$RESOLVED"

    echo "==> Targets: ''${HOSTS[*]}"

    # ── 1. Commit/push if dirty (so remotes can pull a real ref) ──────
    if [[ $SKIP_GIT -eq 0 ]]; then
      if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "==> Committing local changes..."
        git add -A
        git commit -m "chore: cast-on deploy $(date '+%Y-%m-%d %H:%M')"
      fi
      if git remote get-url origin &>/dev/null; then
        echo "==> Pushing..."
        git push
      fi
    fi

    # ── 2. Per-host classify (darwin vs nixos) ─────────────────────────
    # Strip .local / .tb / .schrodinger.com etc to get the bare hostname
    # that snowfall used as the system attribute name.
    bare_attr() {
      local h="$1"
      # Drop trailing domain
      h="''${h%%.*}"
      echo "$h"
    }

    # NixOS hosts (luna and friends) get the darwin-only inputs stubbed
    # out so we don't pull private schrodinger repos from a Linux box
    # (and from a Mac driving fleet deploys, so `is_nixos_attr` below
    # doesn't trip on a dead darwin-only input). See
    # modules/_stubs/empty/flake.nix.
    NIXOS_OVERRIDES=(
      --override-input opencode          path:./modules/_stubs/empty
      --override-input hermes            path:./modules/_stubs/empty
      --override-input git-fleet         path:./modules/_stubs/empty
      --override-input git-fleet-runner  path:./modules/_stubs/empty
    )

    is_darwin_attr() {
      nix eval --raw ".#darwinConfigurations.\"$1\".config.system.build.toplevel.outPath" \
        &>/dev/null
    }
    is_nixos_attr() {
      # Apply NIXOS_OVERRIDES so darwin-private inputs don't fail the
      # probe when cast-on is driven from a Mac evaluating a nixos host.
      nix eval --raw ".#nixosConfigurations.\"$1\".config.system.build.toplevel.outPath" \
        "''${NIXOS_OVERRIDES[@]}" \
        &>/dev/null
    }

    # ── 3. Build all closures locally first ────────────────────────────

    echo "==> Building closures"
    for h in "''${HOSTS[@]}"; do
      attr="$(bare_attr "$h")"
      if is_darwin_attr "$attr"; then
        echo "  build darwin: $attr"
        nix build --no-link ".#darwinConfigurations.''${attr}.system" \
          --print-out-paths > "/tmp/cast-on.''${attr}.out"
      elif is_nixos_attr "$attr"; then
        echo "  build nixos:  $attr (with stubbed darwin inputs)"
        nix build --no-link ".#nixosConfigurations.''${attr}.config.system.build.toplevel" \
          "''${NIXOS_OVERRIDES[@]}" \
          --print-out-paths > "/tmp/cast-on.''${attr}.out"
      else
        echo "cast-on: $h (attr '$attr') has neither a darwin nor nixos configuration" >&2
        exit 1
      fi
    done

    if [[ $DRY_RUN -eq 1 ]]; then
      echo "==> Dry run: skipping copy + activation"
      for h in "''${HOSTS[@]}"; do
        attr="$(bare_attr "$h")"
        echo "  $h -> $(cat "/tmp/cast-on.''${attr}.out")"
      done
      exit 0
    fi

    # ── 4. Copy closures + activate per-host (parallel via claw) ───────
    # We build a small per-host wrapper script that:
    #   - runs `nix copy` from the local builder to the target
    #   - then activates with the right tool for the OS
    # claw handles fan-out + per-host log gathering.
    #
    # Skip self (don't ssh-loop into the local box).
    REMOTE_HOSTS=()
    LOCAL_HOSTS=()
    for h in "''${HOSTS[@]}"; do
      bare="$(bare_attr "$h")"
      if [[ "$bare" == "$LOCAL_HOSTNAME" ]]; then
        LOCAL_HOSTS+=("$h")
      else
        REMOTE_HOSTS+=("$h")
      fi
    done

    activate_local() {
      local attr="$1"
      local out
      out="$(cat "/tmp/cast-on.''${attr}.out")"
      if is_darwin_attr "$attr"; then
        echo "==> Activating local darwin ($attr)"
        sudo "$out/sw/bin/darwin-rebuild" activate
      else
        echo "==> Activating local nixos ($attr)"
        sudo nixos-rebuild switch --flake ".#''${attr}"
      fi
    }

    for h in "''${LOCAL_HOSTS[@]}"; do
      activate_local "$(bare_attr "$h")"
    done

    if [[ ''${#REMOTE_HOSTS[@]} -gt 0 ]]; then
      for h in "''${REMOTE_HOSTS[@]}"; do
        attr="$(bare_attr "$h")"
        out="$(cat "/tmp/cast-on.''${attr}.out")"
        echo "==> Copying $attr closure to $h"
        nix copy --to "ssh-ng://''${SSH_USER}@$h" "$out"
      done

      echo "==> Activating remote hosts in parallel via claw"
      # Build a per-host activation command. claw resolves -w hosts,
      # but we want to send a different command per host (each gets
      # its own out path), so we loop.
      for h in "''${REMOTE_HOSTS[@]}"; do
        attr="$(bare_attr "$h")"
        out="$(cat "/tmp/cast-on.''${attr}.out")"
        if is_darwin_attr "$attr"; then
          cmd="sudo $out/sw/bin/darwin-rebuild activate"
        else
          # NixOS: switch-to-configuration is the right entry point
          # when we already have the system closure on-disk (we just
          # nix-copied it). darwin-rebuild on macOS does the same.
          cmd="sudo $out/bin/switch-to-configuration switch"
        fi
        echo "  $h: $cmd"
        # claw -t: connect timeout, -w: nodes, -l: ssh user
        claw -t 10 -l "$SSH_USER" -w "$h" "$cmd"
      done
    fi

    echo "==> cast-on complete"
  '';

  meta = {
    description = "Parallel NixOS/nix-darwin deploys across the cluster via claw";
    mainProgram = "cast-on";
  };
}
