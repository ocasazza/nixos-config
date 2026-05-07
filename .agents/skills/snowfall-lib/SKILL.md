---
name: snowfall-lib
description: Organize, extend, or audit a Nix flake that uses Snowfall Lib (`snowfallorg/lib`). Use when adding/moving packages, modules, overlays, systems, homes, shells, checks, templates, or libraries; configuring `mkFlake` (namespace, channels-config, alias, external modules); migrating between v1→v2 or v2→v3; or debugging "where does this file go / why isn't it picked up". Snowfall imposes a strict, directory-driven layout — this skill is the source of truth for that layout and the `lib.snowfall.*` API.
---

# Snowfall Lib

Snowfall Lib (`github:snowfallorg/lib`) generates Nix flake outputs from
an opinionated directory structure. This skill captures the **rules
that are enforced by directory layout** (which agents get wrong most
often) and the `mkFlake` knobs you reach for to override them.

Source documentation: https://snowfall.org/guides/lib +
https://snowfall.org/reference/lib. The verbatim bundle is co-located
in `REFERENCE.md` next to this file — read it only when you need to
quote upstream wording or look up an option not summarized here.

## When to use this skill

Use it whenever you are about to:

- Create or move a package, module, overlay, system, home, shell,
  check, template, or library file.
- Touch `mkFlake` / `mkLib` arguments in `flake.nix` (namespace,
  channels-config, alias, overlays, systems.modules,
  systems.hosts.<host>, homes.modules, homes.users.<user@host>,
  outputs-builder, snowfall.root, snowfall.meta).
- Diagnose "I added a file but the flake output didn't appear" — 95%
  of the time it's a layout/naming/`git add` issue.
- Migrate between major versions (v1→v2, v2→v3).

## The non-negotiable layout

Snowfall reads your tree literally. **Directory names ARE the API.**

```
<snowfall-root>/                  # ./ by default; override with snowfall.root = ./nix
├── flake.nix
├── lib/                          # → flake.lib.${namespace}.*
│   ├── default.nix               #   merged into lib.${namespace}
│   └── <name>/default.nix        #   nested helpers also merged
├── packages/
│   └── <name>/default.nix        # → flake.packages.<system>.<name>; also overlaid onto pkgs
├── overlays/
│   └── <name>/default.nix        # → flake.overlays.<name>; auto-applied to channels
├── modules/
│   ├── nixos/<name>/default.nix  # → flake.nixosModules.<name>;  imported into all NixOS systems
│   ├── darwin/<name>/default.nix # → flake.darwinModules.<name>; imported into all darwin systems
│   └── home/<name>/default.nix   # → flake.homeModules.<name>;   imported into all homes
├── systems/
│   └── <arch>-<format>/<name>/default.nix
│                                 # → nixosConfigurations.<name>     (format=linux)
│                                 #   darwinConfigurations.<name>    (format=darwin, needs `darwin` input)
│                                 #   <format>Configurations.<name>  (any nixos-generators format)
├── homes/
│   └── <arch>-<format>/<user>[@<host>]/default.nix
│                                 # → homeConfigurations."<user>@<host>"          (host-pinned)
│                                 #   homeConfigurations."<user>@<arch>-<format>" (target-wide, v3+)
├── shells/<name>/default.nix     # → flake.devShells.<system>.<name>
├── checks/<name>/default.nix     # → flake.checks.<system>.<name>
└── templates/<name>/             # → flake.templates.<name>; describe in mkFlake.templates
    └── <any files>
```

### Hard rules

1. **Files must be `default.nix`.** Snowfall walks directories and
   imports `default.nix`. A `foo.nix` next to it is silently ignored.
2. **`git add` new files.** Flakes only see git-tracked files. A
   newly-created `default.nix` that isn't staged → "not a function" or
   missing-output errors. This is the #1 footgun.
3. **System dirs encode `<arch>-<format>`.** `x86_64-linux`,
   `aarch64-darwin`, `x86_64-iso`, `aarch64-do`, `x86_64-vmware`, etc.
   The format determines which builder runs (NixOS, nix-darwin, or a
   nixos-generators format). For darwin/generator formats the
   corresponding flake input (`darwin`, `nixos-generators`) **must
   exist**.
4. **Home dir name encodes `<user>` or `<user>@<host>`.** Without
   `@host` (v3+) the home applies to **every** machine of that
   `<arch>-<format>` target — useful for cross-machine user configs,
   easy to do unintentionally.
5. **`snowfall-lib` input MUST be named exactly `snowfall-lib`.**
   Snowfall introspects `inputs` by name to skip itself.
6. **Namespace defaults to `internal`.** Set
   `snowfall.namespace = "<name>"` and your library/packages live
   under `lib.<name>` / `pkgs.<name>`. Changing namespace is a
   **rename** — every consumer must move with it.

## Function arguments by file type

Each file type receives a specific argument set. Memorize these — they
are what makes a Snowfall file "work" without a manual `callPackage`.

| File type           | Arguments                                                                                             |
| ------------------- | ----------------------------------------------------------------------------------------------------- |
| `packages/*/`       | `lib`, `inputs`, `namespace`, `pkgs`, `stdenv`, … (NixPkgs args)                                      |
| `shells/*/`         | `lib`, `inputs`, `namespace`, `pkgs`, `mkShell`, …                                                    |
| `checks/*/`         | `lib`, `inputs`, `namespace`, `pkgs`, …                                                               |
| `overlays/*/`       | `{ inputs, channels, lib, namespace, ... }: final: prev: { ... }`                                     |
| `modules/<plat>/*/` | `lib`, `pkgs`, `inputs`, `namespace`, `system`, `target`, `format`, `virtual`, `systems`, `config`, … |
| `systems/<tgt>/*/`  | same as modules + `systems` (attr map of all defined hosts)                                           |
| `homes/<tgt>/*/`    | `lib`, `pkgs`, `inputs`, `namespace`, `home`, `target`, `format`, `virtual`, `host`, `config`, …      |
| `lib/**/`           | `{ inputs, snowfall-inputs, lib, namespace }`                                                         |
| `templates/*/`      | (no Nix function — just files copied at template instantiation)                                       |

`lib` here is the **merged** instance: nixpkgs.lib + every input's
`lib` namespaced by input name + your own `lib.${namespace}`.

## `mkFlake` — the configuration surface

Single canonical example (combine knobs as needed):

```nix
{
  description = "My Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    snowfall-lib = {
      url = "github:snowfallorg/lib";   # MUST be named "snowfall-lib"
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager     = { url = "github:nix-community/home-manager";    inputs.nixpkgs.follows = "nixpkgs"; };
    darwin           = { url = "github:lnl7/nix-darwin";               inputs.nixpkgs.follows = "nixpkgs"; };
    nixos-generators = { url = "github:nix-community/nixos-generators"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;

      snowfall = {
        root      = ./nix;             # default ./ — move tree into a subdir
        namespace = "my-namespace";    # default "internal"; rules pkgs.<ns>.* and lib.<ns>.*
        meta = {
          name  = "my-flake";          # used in docs / Snowfall Frost
          title = "My Flake";
        };
      };

      # NixPkgs instantiation config — applied to every channel input.
      channels-config = {
        allowUnfree = true;
        permittedInsecurePackages = [ "firefox-100.0.0" ];
        config.firefox.smartcardSupport = true;
      };

      # Apply external overlays to all channels (your overlays/ dir is automatic).
      overlays = with inputs; [
        # foo.overlays.default
      ];

      # Add modules to every system of a platform.
      systems.modules.nixos  = with inputs; [ /* ... */ ];
      systems.modules.darwin = with inputs; [ /* ... */ ];

      # Per-host module/specialArgs additions.
      systems.hosts.my-host.modules     = with inputs; [ /* ... */ ];
      systems.hosts.my-host.specialArgs = { my-custom-value = "x"; };

      # Add modules to every home.
      homes.modules = with inputs; [ /* ... */ ];

      # Per-home module/specialArgs additions.
      homes.users."alice@my-host".modules     = with inputs; [ /* ... */ ];
      homes.users."alice@my-host".specialArgs = { /* ... */ };

      # Default exports — Snowfall does NOT auto-create flake.<output>.default.
      alias = {
        packages.default      = "my-package";
        shells.default        = "my-shell";
        checks.default        = "my-check";
        overlays.default      = "my-overlay";
        templates.default     = "my-template";
        modules.nixos.default = "my-nixos-module";
        modules.darwin.default= "my-darwin-module";
        modules.home.default  = "my-home-module";
      };

      # Generic per-system outputs (formatter, custom checks, …).
      outputs-builder = channels: {
        formatter = channels.nixpkgs.alejandra;
      };

      # Template descriptions.
      templates.my-template.description = "My template";
    }
    # And/or merge in fully-custom outputs (destructive — wins over Snowfall):
    // {
      my-custom-output = "hello";
    };
}
```

## Decision tree: "where do I put this?"

| You want to add…                              | Path                                                    | Output                                                                           |
| --------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| A package buildable on its own                | `packages/<name>/default.nix`                           | `pkgs.<name>` (auto-overlaid) and `flake.packages.<sys>.<name>`                  |
| Modify an existing package from nixpkgs       | `overlays/<name>/default.nix`                           | merged into all channels                                                         |
| Reusable NixOS system module                  | `modules/nixos/<name>/default.nix`                      | imported into every NixOS system; also `flake.nixosModules.<name>`               |
| Reusable Darwin (nix-darwin) module           | `modules/darwin/<name>/default.nix`                     | imported into every darwin system; also `flake.darwinModules.<name>`             |
| Reusable Home Manager module                  | `modules/home/<name>/default.nix`                       | imported into every home; also `flake.homeModules.<name>`                        |
| A NixOS host called `my-box`                  | `systems/x86_64-linux/my-box/default.nix`               | `nixosConfigurations.my-box`                                                     |
| A macOS host                                  | `systems/aarch64-darwin/<name>/default.nix`             | `darwinConfigurations.<name>` (needs `darwin` input)                             |
| An installer ISO                              | `systems/x86_64-iso/<name>/default.nix`                 | `isoConfigurations.<name>` (needs `nixos-generators` input)                      |
| Per-host home (alice on my-box)               | `homes/x86_64-linux/alice@my-box/default.nix`           | `homeConfigurations."alice@my-box"`                                              |
| Per-target home (alice on every x86_64-linux) | `homes/x86_64-linux/alice/default.nix`                  | `homeConfigurations."alice@x86_64-linux"` + auto-applied to all matching systems |
| A devShell                                    | `shells/<name>/default.nix`                             | `flake.devShells.<sys>.<name>`                                                   |
| A flake check                                 | `checks/<name>/default.nix`                             | `flake.checks.<sys>.<name>`                                                      |
| A flake template                              | `templates/<name>/<files>`                              | `flake.templates.<name>` — set `templates.<name>.description` in `mkFlake`       |
| A custom helper function                      | `lib/<name>/default.nix`                                | `lib.<namespace>.<name>.*` (and passed in as `lib` everywhere)                   |
| A default for one of the above                | `mkFlake.alias.<output>.default = "<name>"`             | adds the `default` alias without mutating originals                              |
| Custom NixPkgs config (`allowUnfree`, etc.)   | `mkFlake.channels-config = { ... }`                     | applied to every NixPkgs channel input                                           |
| A flake output Snowfall doesn't manage        | `mkFlake.outputs-builder = ch: { ... }` or `// { ... }` | per-system or top-level merge                                                    |

## Snowfall-injected NixOS/Darwin options

Snowfall v3 adds modules to your systems. These options control its
home-manager integration:

| Option                                 | Type  | Default                                       | What it does                                                                                                       |
| -------------------------------------- | ----- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `snowfallorg.users.<name>.create`      | bool  | `true`                                        | Auto-create `users.users.<name>` from `homes/`                                                                     |
| `snowfallorg.users.<name>.admin`       | bool  | `true`                                        | Add user to `wheel` (linux) / `admin` (macOS)                                                                      |
| `snowfallorg.users.<name>.home.enable` | bool  | `true`                                        | Wire `home-manager.users.<name>` automatically                                                                     |
| `snowfallorg.users.<name>.home.path`   | str   | `/home/<name>` (linux), `/Users/<name>` (mac) | Override home dir                                                                                                  |
| `snowfallorg.users.<name>.home.config` | attrs | `{}`                                          | **In v3+, ALL home-manager config for a user must go here**, NOT in `home-manager.users.<name>` (see migration v3) |

And inside any home (auto-set by Snowfall, used by your modules):

- `snowfallorg.user.name` — the user's name (read with `config.snowfallorg.user.name`)
- `snowfallorg.user.home` — the user's home directory
- `snowfallorg.user.enable` — `true` when used inside a Snowfall-created system/home

## `lib.snowfall.*` reference (when you actually need it)

Most of `lib.snowfall.*` is internal — you call `mkFlake`/`mkLib` and
forget about it. Reach for it only when extending Snowfall, debugging
discovery, or doing custom flake plumbing.

**Flake helpers** (`lib.snowfall.flake.*`):

- `without-self`, `without-src`, `without-snowfall-inputs` — strip
  attributes from an attrset.
- `get-libs` — `{ x = nixpkgs; }` → `{ x = nixpkgs.lib; }`.

**Path** (`lib.snowfall.path.*`):

- `split-file-extension`, `get-file-extension`, `has-file-extension`,
  `has-any-file-extension`, `get-file-name-without-extension`,
  `get-parent-directory`.

**Filesystem** (`lib.snowfall.fs.*`):

- Kind matchers: `is-file-kind`, `is-symlink-kind`, `is-directory-kind`, `is-unknown-kind`.
- Path getters: `get-file` (relative to flake root), `get-snowfall-file`
  (relative to `snowfall.root`), `internal-get-file` (snowfall-lib
  source — don't use).
- Discovery: `safe-read-directory`, `get-directories`, `get-files`,
  `get-files-recursive`, `get-nix-files{,-recursive}`,
  `get-default-nix-files{,-recursive}`,
  `get-non-default-nix-files{,-recursive}`. These are how Snowfall
  walks your tree — useful for writing your own discovery rules.

**Attrs** (`lib.snowfall.attrs.*`):

- `merge-deep`, `merge-shallow`, `merge-shallow-packages` (allows one
  level of nesting — used for namespaced packages),
  `map-concat-attrs-to-list`.

**System** (`lib.snowfall.system.*`):

- Predicates: `is-darwin`, `is-linux`, `is-virtual`.
- Resolvers: `get-virtual-system-type` (`x86_64-iso` → `iso`),
  `get-resolved-system-target` (`x86_64-iso` → `x86_64-linux`),
  `get-system-output` (`aarch64-darwin` → `darwinConfigurations`),
  `get-inferred-system-name` (path → name),
  `get-target-systems-metadata`, `get-system-builder`.
- Builders: `create-system`, `create-systems`.

**Home** (`lib.snowfall.home.*`):

- `split-user-and-host` (`"alice@box"` → `{ user = "alice"; host = "box"; }`).
- `create-home`, `create-homes`, `get-target-homes-metadata`,
  `create-home-system-modules` (the bridge that wires HM into systems).

**Per-output factories**:

- `lib.snowfall.module.create-modules`,
  `lib.snowfall.package.create-packages`,
  `lib.snowfall.shell.create-shell`,
  `lib.snowfall.overlay.create-overlays{,-builder}`,
  `lib.snowfall.template.create-templates`.

All factories accept `{ src; overrides; alias; ... }` (and `channels`
where relevant). Use them to create one-off outputs from a custom
location without restructuring the whole flake.

## Migration cheat sheets

### v1 → v2

- `overlay-package-namespace` → `snowfall.namespace`.
- Internal pkgs/lib now live under the namespace: use
  `pkgs.${namespace}.*` and `lib.${namespace}.*`.
- `outputs-builder` no longer auto-aliases default outputs — set
  defaults via `alias.<output>.default = "<name>"`.
- Flat `modules/` → `modules/nixos/` (and `modules/darwin/`,
  `modules/home-manager/`).
- `systems.modules` → `systems.modules.nixos` /
  `systems.modules.darwin`. Still per-host via
  `systems.hosts.<host>.modules`.

### v2 → v3

- **`home-manager.users.<u>.*` no longer works inside system config.**
  Move it under `snowfallorg.users.<u>.home.config`. v3 sets
  `home-manager.useGlobalPkgs = true` by default, so internal packages
  reach HM properly.
- `homes/<arch>/<user>` (no `@host`) is now a **target-wide** home
  applied to every host of that arch — exported as
  `homeConfigurations."<user>@<arch>"`.
- Overlays now receive `{ inputs, channels, lib, ... }`. The old
  `{ my-input, channels, ... }` named-input form still works but is
  deprecated; use `inputs.my-input` instead.
- `namespace` is passed to every Snowfall-managed file (defaults to
  `internal`).
- New auto-injected modules expose `snowfallorg.user.*` /
  `snowfallorg.users.<name>.*` — see options table above.

## Common failure modes (and what to check)

1. **"My new <thing> doesn't appear in flake outputs."**
   - `git status` — is `default.nix` tracked?
   - File is `default.nix`, not `<name>.nix`?
   - Directory in the right place (`packages/`, not `package/`)?
   - For systems/homes: `<arch>-<format>` segment correct? Format
     requires its input (`darwin`, `nixos-generators`)?
   - `nix flake show` to confirm what Snowfall actually generated.

2. **`infinite recursion` on flake eval.**
   - Often `snowfall.namespace` clashing with an input named the same
     thing, or your `lib/` calling something it imports back.
   - Inputs that depend on `nixpkgs` should `inputs.nixpkgs.follows = "nixpkgs"`.

3. **Home Manager configuration is silently ignored (post-v3).**
   - You're using `home-manager.users.<u>.<opt>` instead of
     `snowfallorg.users.<u>.home.config.<opt>`.

4. **Dependency on a darwin/iso/etc. system fails.**
   - Missing the matching flake input. `darwin` for `*-darwin`,
     `nixos-generators` for `*-iso`/`*-do`/etc.

5. **Internal package not visible to a module.**
   - You set `snowfall.namespace`, so it lives at
     `pkgs.${namespace}.<name>`, not `pkgs.<name>`. Adjust the
     consumer or skip the namespace.

6. **A home applies to hosts you didn't intend.**
   - Directory name lacks `@<host>` — that's a v3 target-wide home.
     Rename to `<user>@<host>` to scope it.

7. **`snowfall-lib` input renamed.**
   - Snowfall introspects inputs by name — must be the literal
     `snowfall-lib`. Rename it back.

## Working method

When asked to add or move something:

1. Identify the target output (package/module/system/etc.).
2. Look up the canonical path in the decision-tree table.
3. Confirm the surrounding repo follows Snowfall conventions
   (`flake.nix` calls `mkFlake`; `snowfall.namespace` set; existing
   directories present). If the repo isn't Snowfall, stop and say so.
4. Create the file, scaffolded with the correct argument set from the
   "Function arguments by file type" table.
5. **`git add` the new file.** Always. Even before testing.
6. Verify with `nix flake show` (or `nix flake check` for stricter
   validation) — confirm the new output appears under the expected
   key.
7. If a default is desired, add to `mkFlake.alias.<output>.default`.

When migrating between versions, follow the migration cheat sheet
linearly — don't try to mix v1 and v2 conventions in the same tree.

## Reference

Full upstream docs are bundled in `REFERENCE.md` co-located with this
file (~88 KB, regenerated by curl-fetching the 16
`snowfall.org/guides/lib/*` and `/reference/lib/` pages and piping
through `html2text`). Live source: https://snowfall.org/guides/lib +
https://snowfall.org/reference/lib. Prefer the tables in this SKILL.md
for everyday lookups — only crack open `REFERENCE.md` when you need
verbatim wording or an option this file doesn't summarize.
