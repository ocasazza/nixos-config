# Autopkg Server Configuration

## Nix-Darwin Setup

### Flake Inputs

```nix
# flake.nix
git-fleet = {
  url = "git+ssh://git@github.com/schrodinger/git-fleet";
};
git-fleet-runner = {
  url = "git+ssh://git@github.com/schrodinger/git-fleet-runner";
};
```

- `git-fleet`: Fleet GitOps configuration and package recipes
- `git-fleet-runner`: Provides `darwinModules.autopkgserver` (includes fleet-recipes internally)

### System Configuration

```nix
# hosts/darwin/default.nix
services.autopkgserver = {
  enable = true;
  recipeOverrideDirs = "/Users/${user.name}/Repositories/schrodinger/git-fleet/lib/software";
};
```

```nix
# flake.nix darwinConfigurations
darwinConfigurations = {
  macos = darwin.lib.darwinSystem {
    modules = [
      git-fleet-runner.darwinModules.autopkgserver
      ./hosts/darwin
    ];
  };
};
```

### Apply Configuration

```bash
nh darwin switch
```

### Verify Service

```bash
sudo launchctl list | grep autopkg
# Should show: com.github.autopkg.autopkgserver
```

## Documentation

See git-fleet repository for complete documentation:

- Package development: `git-fleet/docs/development/autopkg.md`
- Bootstrap packages: `git-fleet/docs/development/specifications/bootstrap-packages.md`
