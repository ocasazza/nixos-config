# Snowfall Lib — Full Documentation Bundle

Source: https://snowfall.org/guides/lib + /reference/lib
Fetched: 2026-05-07T01:57:45Z

=========================================================================

# quickstart

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
_ Create_a_flake_if_you_don’t_have_one_already
_ Add_Snowfall_Lib_to_your_flake
_ Create_your_flake_outputs
_ Configure_Snowfall_Lib
**\*** On this page **\***
_ Overview
_ Create_a_flake_if_you_don’t_have_one_already
_ Add_Snowfall_Lib_to_your_flake
_ Create_your_flake_outputs \* Configure_Snowfall_Lib
**\*\*** Quickstart **\*\***
Snowfall Lib is a library that makes it easy to manage your Nix flake by
imposing an opinionated file structure.
**\*** Create a flake if you don’t have one already **\***
Snowfall Lib generates your Nix flake outputs for you. If you don’t already
have a Nix flake, you can create one using the following command.
Terminal window

# Create a flake in the current directory.

nix flake init
**\*** Add Snowfall Lib to your flake **\***
To start using Snowfall Lib, import the library in your Nix flake by adding it
to your flake’s inputs.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        # The name "snowfall-lib" is required due to how Snowfall Lib processes

your # flake's inputs.
snowfall-lib = {
url = "github:snowfallorg/lib";
inputs.nixpkgs.follows = "nixpkgs";
};
};

    # We will handle this in the next section.
    outputs = inputs: {};

}
**\*** Create your flake outputs **\***
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            # You must provide our flake inputs to Snowfall Lib.
            inherit inputs;

            # The `src` must be the root of the flake. See configuration
            # in the next section for information on how you can move your
            # Nix files to a separate directory.
            src = ./.;
        };

}
**\*** Configure Snowfall Lib **\***
Snowfall Lib offers some customization options. The following example details a
few popular settings. For a full list see Snowfall_Lib_Reference.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;

            # Configure Snowfall Lib, all of these settings are optional.
            snowfall = {
                # Tell Snowfall Lib to look in the `./nix/` directory for your
                # Nix files.
                root = ./nix;

                # Choose a namespace to use for your flake's packages, library,
                # and overlays.
                namespace = "my-namespace";

                # Add flake metadata that can be processed by tools like

Snowfall Frost.
meta = { # A slug to use in documentation when displaying things
like file paths.
name = "my-awesome-flake";

                    # A title to show for your flake, typically the name.
                    title = "My Awesome Flake";
                };
            };
        };

}
Now that Snowfall Lib is set up in your Flake, you can begin adding Nix files!
From here, you can follow one of the other guides for Snowfall Lib like
creating*packages, creating_overlays, or creating_modules. You can also look at
the reference_documentation for Snowfall Lib for more technical information.
Next*
Packages

=========================================================================

# packages

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Packages **\*\***
Snowfall Lib automatically exports your packages on your flake and makes them
available to all other parts of your flake. This includes making these packages
available to other packages in your flake, NixOS systems, Darwin systems, Home
Manager, modules, and overlays.
To create a new package, add a new directory your packages directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `packages` directory for a new package.

mkdir -p ./packages/my-package
Now create the Nix file for the package at packages/my-package/default.nix.
{ # Snowfall Lib provides a customized `lib` instance with access to your
flake's library # as well as the libraries available from your flake's inputs.
lib, # You also have access to your flake's inputs.
inputs,

    # The namespace used for your flake, defaulting to "internal" if not set.
    namespace,

    # All other arguments come from NixPkgs. You can use `pkgs` to pull

packages or helpers # programmatically or you may add the named attributes as arguments here.
pkgs,
stdenv,
...
}:

stdenv.mkDerivation { # Create your package
}
This package will be made available on your flake’s packages output with the
same name as the directory that you created.
Previous*
Quickstart_Next*
Overlays

=========================================================================

# overlays

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Overlays **\*\***
Snowfall Lib automatically exports your overlays and applies them to your
NixPkgs instance used within your flake. This includes making the overlaid
packages available to packages in your flake, NixOS systems, Darwin systems,
Home Manager, modules, and overlays.
To create a new overlay, add a new directory to your overlays directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `overlays` directory for a new overlay.

mkdir -p ./overlays/my-overlay
Now create the Nix file for the overlay at overlays/my-overlay/default.nix.

# Snowfall Lib provides access to additional information via a primary argument

of

# your overlay.

{

# Channels are named after NixPkgs instances in your flake inputs. For example,

# with the input `nixpkgs` there will be a channel available at

`channels.nixpkgs`.

# These channels are system-specific instances of NixPkgs that can be used to

quickly

# pull packages into your overlay.

channels,

# The namespace used for your Flake, defaulting to "internal" if not set.

namespace,

# Inputs from your flake.

inputs,
... }:

final: prev: { # For example, to pull a package from unstable NixPkgs make sure you have
the # input `unstable = "github:nixos/nixpkgs/nixos-unstable"` in your flake.
inherit (channels.unstable) chromium;

    my-package = inputs.my-input.packages.${prev.system}.my-package;

}
This overlay will be made available on your flake’s overlays output with the
same name as the directory that you created.
Previous*
Packages_Next*
Modules

=========================================================================

# modules

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Modules **\*\***
Snowfall Lib automatically applies all of your modules to your systems. This
means that all NixOS modules will be imported for your NixOS systems, all
Darwin modules will be imported for your Darwin systems, and all Home Manager
modules will be imported for your Home configurations.
To create a new module, add a new directory to your modules directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `modules/nixos`, `modules/darwin`, or `modules/

home`

# directory for a new module.

mkdir -p ./modules/nixos/my-module
Now create the Nix file for the module at modules/nixos/my-module/default.nix.
{ # Snowfall Lib provides a customized `lib` instance with access to your
flake's library # as well as the libraries available from your flake's inputs.
lib, # An instance of `pkgs` with your overlays and packages applied is also
available.
pkgs, # You also have access to your flake's inputs.
inputs,

    # Additional metadata is provided by Snowfall Lib.
    namespace, # The namespace used for your flake, defaulting to "internal" if

not set.
system, # The system architecture for this host (eg. `x86_64-linux`).
target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
format, # A normalized name for the system target (eg. `iso`).
virtual, # A boolean to determine whether this system is a virtual target
using nixos-generators.
systems, # An attribute map of your defined hosts.

    # All other arguments come from the module system.
    config,
    ...

}:
{ # Your configuration.
}
This module will be made available on your flake’s nixosModules, darwinModules,
or homeModules output with the same name as the directory that you created.
Previous*
Overlays_Next*
Systems

=========================================================================

# systems

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview \* Options
o snowfallorg.users.<name>
o snowfallorg.users.<name>.create
o snowfallorg.users.<name>.admin
o snowfallorg.users.<name>.home.enable
o snowfallorg.users.<name>.home.path
o snowfallorg.users.<name>.home.config
**\*** On this page **\***
_ Overview
_ Options
o snowfallorg.users.<name>
o snowfallorg.users.<name>.create
o snowfallorg.users.<name>.admin
o snowfallorg.users.<name>.home.enable
o snowfallorg.users.<name>.home.path
o snowfallorg.users.<name>.home.config
**\*\*** Systems **\*\***
To create a new system, add a new directory to your systems directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `systems` directory for a new system. This should

follow

# Snowfall Lib's required system target format to ensure that the correct

architecture

# and output are used.

mkdir -p ./systems/x86_64-linux/my-system
Now create the Nix file for the system at systems/x86_64-linux/my-system/
default.nix.
{ # Snowfall Lib provides a customized `lib` instance with access to your
flake's library # as well as the libraries available from your flake's inputs.
lib, # An instance of `pkgs` with your overlays and packages applied is also
available.
pkgs, # You also have access to your flake's inputs.
inputs,

    # Additional metadata is provided by Snowfall Lib.
    namespace, # The namespace used for your flake, defaulting to "internal" if

not set.
system, # The system architecture for this host (eg. `x86_64-linux`).
target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
format, # A normalized name for the system target (eg. `iso`).
virtual, # A boolean to determine whether this system is a virtual target
using nixos-generators.
systems, # An attribute map of your defined hosts.

    # All other arguments come from the system system.
    config,
    ...

}:
{ # Your configuration.
}
This system will be made available on your flake’s nixosConfigurations,
darwinConfigurations, or one of Snowfall Lib’s virtual \*Configurations outputs
with the same name as the directory that you created.
Systems can have additional specialArgs and modules configured within your call
to mkFlake. See the following for an example which adds a NixOS module to a
specific host and sets a custom value in specialArgs.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs:
inputs.snowfall-lib.mkFlake {
inherit inputs;
src = ./.;

            # Add modules to all NixOS systems.
            systems.modules.nixos = with inputs; [
                # my-input.nixosModules.my-module
            ];

            # If you wanted to configure a Darwin (macOS) system.
            # systems.modules.darwin = with inputs; [
            #   my-input.darwinModules.my-module
            # ];

            # Add a module to a specific host.
            systems.hosts.my-host.modules = with inputs; [
                # my-input.nixosModules.my-module
            ];

            # Add a custom value to `specialArgs`.
            systems.hosts.my-host.specialArgs = {
                my-custom-value = "my-value";
            };
        };

}
**\*** Options **\***
When creating systems using Snowfall Lib, an additional module is added to your
configuration that allows for better integration of the library and its feature
set. The following options can be used in your NixOS or Darwin configurations
and modules. \***\* snowfallorg.users.<name> \*\***
This option allows for the configuration of different users that have been
specified using Snowfall Lib’s homes/ directory.
Type: Attribute Set
Example:
{
snowfallorg.users.my-user = {
create = true;
admin = false;

        home = {
            enable = true;
            path = "/mnt/home/my-user";

            config = {};
        };
    };

} \***\* snowfallorg.users.<name>.create \*\***
By default, Snowfall Lib will configure your system’s users.users option to
match the users declared in homes/. This means that users will be automatically
created for each home entry available. If you do not want to create a user
automatically, this value can be set to false.
Type: Boolean
Default: true
Example:
{
snowfallorg.users.my-user = {
create = false;
};
} \***\* snowfallorg.users.<name>.admin \*\***
This option determines whether the user is automatically added to the wheel
(linux) or admin (macOS) group to enable sudo privileges. You probably want to
enable this for at least one user, but other users may not require this level
of access.
Type: Boolean
Default: true
Example:
{
snowfallorg.users.my-user = {
admin = false;
};
} \***\* snowfallorg.users.<name>.home.enable \*\***
Snowfall Lib defaults to integrating home-manager for each user. This includes
the setting of home-manager.users.<name> and providing any existing home
modules for use. If you do not want home-manager enabled for a specific user by
default, then this setting can be turned off.
Type: Boolean
Default: true
Example:
{
snowfallorg.users.my-user = {
home = {
enable = false;
};
};
} \***\* snowfallorg.users.<name>.home.path \*\***
This option allows for the customization of the home directory for a user. By
default, it will match the platform’s typical location. For Linux this defaults
to /home/<name> and for macOS this is /Users/<name>. This value only needs to
be changed if your user’s home is in a non-standard location such as a separate
drive that is not mounted to /home.
Type: String
Default: /home/<name> (Linux), /Users/<name> (macOS)
Example:
{
snowfallorg.users.my-user = {
home = {
path = "/mnt/home/my-user";
};
};
} \***\* snowfallorg.users.<name>.home.config \*\***
Due to Snowfall Lib’s management of home-manager, in order to set configuration
options for home-manager within your system configuration you must use this
option instead of home-manager.users.<name>. The values provided are passed
directly to home-manager for the given user.
Type: Attribute Set
Default: {}
Example:
{
snowfallorg.users.my-user = {
home = {
config = { # Everything in here is home-manager configuration.
gtk.theme.package = pkgs.gnome.gnome-themes-extra;

                home.packages = with pkgs; [
                    my-package
                ];
            };
        };
    };

}
Previous*
Modules_Next*
Homes

=========================================================================

# homes

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview \* Options
o snowfallorg.user.enable
o snowfallorg.user.name
o snowfallorg.user.home
**\*** On this page **\***
_ Overview
_ Options
o snowfallorg.user.enable
o snowfallorg.user.name
o snowfallorg.user.home
**\*\*** Homes **\*\***
To create a new home, add a new directory to your homes directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `homes` directory for a new home. This should

follow

# Snowfall Lib's required home target format to ensure that the correct

architecture

# and output are used.

mkdir -p ./homes/x86_64-linux/user@my-home
Now create the Nix file for the home at homes/x86_64-linux/user@my-home/
default.nix.
{ # Snowfall Lib provides a customized `lib` instance with access to your
flake's library # as well as the libraries available from your flake's inputs.
lib, # An instance of `pkgs` with your overlays and packages applied is also
available.
pkgs, # You also have access to your flake's inputs.
inputs,

    # Additional metadata is provided by Snowfall Lib.
    namespace, # The namespace used for your flake, defaulting to "internal" if

not set.
home, # The home architecture for this host (eg. `x86_64-linux`).
target, # The Snowfall Lib target for this home (eg. `x86_64-home`).
format, # A normalized name for the home target (eg. `home`).
virtual, # A boolean to determine whether this home is a virtual target
using nixos-generators.
host, # The host name for this home.

    # All other arguments come from the home home.
    config,
    ...

}:
{ # Your configuration.
}
This home will be made available on your flake’s homeConfigurations output with
the same name as the directory that you created.
Homes can have additional specialArgs and modules configured within your call
to mkFlake. See the following for an example which adds a Home Manager module
to a specific host and sets a custom value in specialArgs.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs:
inputs.snowfall-lib.mkFlake {
inherit inputs;
src = ./.;

            # Add modules to all homes.
            homes.modules = with inputs; [
                # my-input.homeModules.my-module
            ];

            # Add modules to a specific home.
            homes.users."my-user@my-host".modules = with inputs; [
                # my-input.homeModules.my-module
            ];

            # Add modules to a specific home.
            homes.users."my-user@my-host".specialArgs = {
                my-custom-value = "my-value";
            };
        };

}
**\*** Options **\***
For convenience, Snowfall Lib adds an additional set of configuration with
context about the current user. These values can be used to avoid having to
hard code them or duplicate the things that Snowfall Lib already knows about. \***\* snowfallorg.user.enable \*\***
This option determines whether the user’s common, required options are
automatically set. The default value is false when used outside of Snowfall
Lib, but is set to true when you use a system or home created by Snowfall Lib.
Type: Boolean
Default: false (unless used in a system or home created by Snowfall Lib)
Example:
{
snowfallorg.user.enable = true;
} \***\* snowfallorg.user.name \*\***
The name of the user. This value is provided to home-manager’s home.username
option during automatic configuration. This option does not have a default
value, but one is set automatically by Snowfall Lib for each user. Most
commonly this value can be accessed by other modules with
config.snowfallorg.user.name to get the current user’s name;
Type: String
Example:
{
snowfallorg.user.name = "my-user";
} \***\* snowfallorg.user.home \*\***
By default, the user’s home directory will be calculated based on the platform
and provided username. However, this can still be customized if your user’s
home directory is in a non-standard location.
Type: String
Default: /home/${config.snowfallorg.user.name} (Linux), /Users/$
{config.snowfallorg.user.name} (macOS)
Example:
{
snowfallorg.user.home = "/mnt/home/my-user";
}
Previous*
Systems_Next*
Library

=========================================================================

# library

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Library **\*\***
Snowfall Lib automatically passes your merged library to all other parts of
your flake. This means that you can access your own library with lib.my-
namespace or any library from your flake inputs with lib.my-input. The
namespace for your library and packages can be configured with
snowfall.namespace.
To create a library, add a new directory to your lib directory or use the base
lib directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `lib` directory for library methods that will be

merged.
mkdir -p ./lib/my-lib
Now create the Nix file for the lib at lib/my-lib/default.nix (or lib/
default.nix).
{ # This is the merged library containing your namespaced library as well as
all libraries from # your flake's inputs.
lib,

    # Your flake inputs are also available.
    inputs,

    # The namespace used for your flake, defaulting to "internal" if not set.
    namespace,

    # Additionally, Snowfall Lib's own inputs are passed. You probably don't

need to use this!
snowfall-inputs,
}:
{ # This will be available as `lib.my-namespace.my-helper-function`.
my-helper-function = x: x;

    my-scope = {
        # This will be available as `lib.my-namespace.my-scope.my-scoped-

helper-function`.
my-scoped-helper-function = x: x;
};
}
This library will be made available on your flake’s lib output.
Previous*
Homes_Next*
Shells

=========================================================================

# shells

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Shells **\*\***
To create a new shell, add a new directory your shells directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `shells` directory for a new shell.

mkdir -p ./shells/my-shell
Now create the Nix file for the shell at shells/my-shell/default.nix.
{ # Snowfall Lib provides a customized `lib` instance with access to your
flake's library # as well as the libraries available from your flake's inputs.
lib, # You also have access to your flake's inputs.
inputs,

    # The namespace used for your flake, defaulting to "internal" if not set.
    namespace,

    # All other arguments come from NixPkgs. You can use `pkgs` to pull shells

or helpers # programmatically or you may add the named attributes as arguments here.
pkgs,
mkShell,
...
}:

mkShell { # Create your shell
packages = with pkgs; [
];
}
This shell will be made available on your flake’s devShells output with the
same name as the directory that you created.
Previous*
Library_Next*
Checks

=========================================================================

# checks

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Checks **\*\***
To create a new check, add a new directory your checks directory.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `checks` directory for a new check.

mkdir -p ./checks/my-checks
Now create the Nix file for the check at checks/my-check/default.nix.
{ # Snowfall Lib provides a customized `lib` instance with access to your
flake's library # as well as the libraries available from your flake's inputs.
lib, # You also have access to your flake's inputs.
inputs,

    # The namespace used for your flake, defaulting to "internal" if not set.
    namespace,

    # All other arguments come from NixPkgs. You can use `pkgs` to pull checks

or helpers # programmatically or you may add the named attributes as arguments here.
pkgs,
...
}:

# Create your check

pkgs.runCommand "my-check" { src = ./.; } ''
make test
This check will be made available on your flake’s checks output with the same
name as the directory that you created.
Previous*
Shells_Next*
Templates

=========================================================================

# templates

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Templates **\*\***
To create a new template, add a new directory your templates directory. This
directory will be used when the template is consumed by users of your flake.
Note
Remember to run git add when creating new files!
Terminal window

# Create a directory in the `templates` directory for a new template.

mkdir -p ./templates/my-templates
Now place any files inside of your template that you would like to provide to
users. Once you are ready, it is also a good idea to update your flake to set
descriptions for your templates.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;

            templates = {
                my-template.description = "This is my template created with

Snowfall Lib!";
};
};
}
This template will be made available on your flake’s templates output with the
same name as the directory that you created.
Previous*
Checks_Next*
Generic

=========================================================================

# generic

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
_ Outputs_Builder
_ Custom
**\*** On this page **\***
_ Overview
_ Outputs_Builder \* Custom
**\*\*** Generic **\*\***
Sometimes you want to put something on your flake output that isn’t fully
managed by Snowfall Lib. See the following two sections for the best ways to
handle generic flake outputs.
**\*** Outputs Builder **\***
Snowfall Lib extends flake-utils-plus which means you can make use of outputs-
builder to construct flake outputs for each supported system.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;

            # The outputs builder receives an attribute set of your available

NixPkgs channels. # These are every input that points to a NixPkgs instance (even
forks). In this # case, the only channel available in this flake is
`channels.nixpkgs`.
outputs-builder = channels: { # Outputs in the outputs builder are transformed to support
each system. This # entry will be turned into multiple different outputs like
`formatter.x86_64-linux.*`.
formatter = channels.nixpkgs.alejandra;
};
};
}
**\*** Custom **\***
If you can’t use outputs-builder then it is also possible to merge your flake
outputs with another attribute set to provide custom entries.
Merging in this way is destructive and will overwrite things generated by
Snowfall Lib that share the same names as the attributes you add.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        # Generate outputs from Snowfall Lib.
        (inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;
        })
        # And merge some attributes with it.
        // {
            my-custom-output = "hello world";
        };

}
Previous*
Templates_Next*
Channels

=========================================================================

# channels

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Channels **\*\***
Snowfall Lib makes use of a core package set to build systems, packages, and
more. This package set is taken from the input on your flake named nixpkgs.
However, it is common to provide additional configuration for NixPkgs before
using it. In order to do this, you can use the channels-config option.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;

            # The attribute set specified here will be passed directly to

NixPkgs when # instantiating the package set.
channels-config = { # Allow unfree packages.
allowUnfree = true;

                # Allow certain insecure packages
                permittedInsecurePackages = [
                    "firefox-100.0.0"
                ];

                # Additional configuration for specific packages.
                config = {
                    # For example, enable smartcard support in Firefox.
                    firefox.smartcardSupport = true;
                };
            };
        };

}
Previous*
Generic_Next*
Aliases

=========================================================================

# alias

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
**\*** On this page **\*** \* Overview
**\*\*** Aliases **\*\***
It is common for flakes to provide a default package, shell, overlay, etc.
However, by default Snowfall Lib will only create exports matching your
directory structure. You can inform Snowfall Lib to create an alias export by
setting alias in your call to mkFlake. Aliasing does not affect the original
export, but creates a new export.
{
inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

        snowfall-lib = {
            url = "github:snowfallorg/lib";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;

            alias = {
                # Create an alias to export a default package.
                packages.default = "my-package";

                # Create an alias to export a default shell.
                shells.default = "my-shell";

                # Create an alias to export a default overlay.
                overlays.default = "my-overlay";

                # Create an alias to export a default template.
                templates.default = "my-template";

                # Create an alias to export a default NixOS module.
                modules.nixos.default = "my-nixos-module";

                # Create an alias to export a default Darwin module.
                modules.darwin.default = "my-nixos-module";

                # Create an alias to export a default Home module.
                modules.home.default = "my-nixos-module";
            };
        };

}
Previous*
Channels_Next*
Reference

=========================================================================

# migration_v2

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
_ Namespace
_ Aliases
_ Modules
_ External_Modules
_ lib.snowfall._
**\*** On this page **\***
_ Overview
_ Namespace
_ Aliases
_ Modules
_ External_Modules
_ lib.snowfall.\*
**\*\*** Snowfall Lib v2 Migration **\*\***
Snowfall Lib v2 adds a large amount of features and has made a few breaking
changes that are in the benefit of overall user experience. To migrate from v1
to v2, see the following steps.
**\*** Namespace **\***
The overlay-package-namespace option has been removed in favor of using
snowfall.namespace.
inputs.snowfall-lib.mkFlake { # Before: # overlay-package-namespace = "my-namespace";

    # After:
    snowfall.namespace = "my-namespace";

}
In addition, packages and your flake library now default to the internal
namespace. This means that any internal flake packages or library helpers must
be accessed via this namespace.
let
my-lib = lib.${namespace};
    my-pkgs = pkgs.${namespace};
in
...
**\*** Aliases **\***
Output aliases are no longer automatically remapped from strings returned from
outputs-builder. Instead, use the new alias option to configure aliases.
inputs.snowfall-lib.mkFlake { # Before: # outputs-builder = channels: { # packages.default = "my-package"; # };

    # After:
    alias.packages.default = "my-package";

}
**\*** Modules **\***
Multiple types of modules are now supported, including nix-darwin and Home-
Manager. When upgrading to Snowfall Lib v2, you will need to move your existing
modules into modules/nixos in order to continue using them. Darwin and Home-
Manager modules can be placed in modules/darwin and modules/home-manager
respectively.
**\*** External Modules **\***
Modules must now be added to a specific system or system type. Previously
Snowfall Lib assumed modules were all compatible NixOS modules. This has been
extended to also support Darwin modules.
Note
Modules may still be added to specific systems via systems.hosts.<my-
host>.modules.
my-input.nixosModules.my-module
inputs.snowfall-lib.mkFlake { # Before: # systems.modules = with inputs; [ # };

    # After:
    systems.modules.nixos = with inputs; [
        my-input.nixosModules.my-module
    };
    systems.modules.darwin = with inputs; [
        my-input.darwinModules.my-module
    };

}
**\*** lib.snowfall.\* **\***
The default arguments for many functions (particularly modules and system) have
been updated to support multiple different platforms like Darwin and Home
Manager. Please verify that you are now expecting to use the most recent, new
structure imposed by Snowfall Lib.
Previous*
Reference_Next*
v3

=========================================================================

# migration_v3

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
_ Home-Manager_Within_NixOS
_ Target_Wide_Home-Manager
_ Overlays
_ First-Class_Namespace_Support \* Snowfall_Modules
**\*** On this page **\***
_ Overview
_ Home-Manager_Within_NixOS
_ Target_Wide_Home-Manager
_ Overlays
_ First-Class_Namespace_Support
_ Snowfall_Modules
**\*\*** Snowfall Lib v3 Migration **\*\***
Snowfall Lib v3 improves Home-Manager integration and introduces some quality
of life improvements to the library. To migrate from v2 to v3, follow the steps
below.
**\*** Home-Manager Within NixOS **\***
Changes have been made to the way that Snowfall Lib works with Home-Manager and
its modules. In previous versions homeModules were often not loaded correctly
and certain features like imports and internal packages were unavailable in
different circumstances.
With Snowfall Lib v3, home-manager.useGlobalPkgs is now defaulted to true which
will result in the same package set (including internal packages) being used in
your user homes. In order to resolve the issue with home-manager modules and
imports, all home-manager configuration must now be performed through the
options in snowfallorg.user.${user-name}.home.config. This is an attribute set
which maps directly to your home configuration.
{ # Before
home-manager.users.my-user.packages = with pkgs; [
my-package
];
}
{ # After
snowfallorg.users.my-user.home.config.packages = with pkgs; [
my-package
];
}
In addition, specialArgs are now passed to Home-Manager modules even when used
within your NixOS configuration. This previously only worked standalone.
**\*** Target Wide Home-Manager **\***
Snowfall Lib v3 now supports declaring home-manager configurations for a user
that will be added to every system of the same target. To use this feature,
create or move an existing configuration to homes/<target>/<user>. If a @<host>
suffix is not included in the name, the configuration will be included for
every host of the matching target. Homes created this way are also exported
using the special generated name <user>@<target>.
For example, if you created a home homes/x86_64-linux/jake/default.nix, the
home will be included for every x86_64-linux machine and will be exported on
your Flake as homeConfigurations."jake@x86_64-linux".
**\*** Overlays **\***
Overlay inputs have been reworked to be more useful and less surprising. Now
overlays are passed lib and inputs arguments in addition to channels.

# Before

{ my-input, channels, ... }:
final: prev: { # ...
}

# After

{ inputs, channels, lib, ... }:
let
my-input = inputs.my-input;
in
final: prev: { # ...
}
Inputs are still available as named arguments, but this usage is deprecated and
will be removed in a future release.
**\*** First-Class Namespace Support **\***
As of v3, all Snowfall Lib manged files will now be provided a namespace
argument. This argument is the value of snowfall.namespace used in your Flake’s
call to mkFlake. If not set, the value is defaulted to internal.
**\*** Snowfall Modules **\***
Starting with this version of Snowfall Lib, additional modules are now
automatically added to systems and homes to provide additional context and
functionality. For more information, see the options available in Systems and
Homes.
Previous\_
v2

=========================================================================

# reference_lib

=========================================================================

Skip_to_content
Snowfall
Search
Cancel
GitHub
Select theme[One of: Dark/Light/Auto]
_ Lib
o Quickstart
o Guides # Packages # Overlays # Modules # Systems # Homes # Library # Shells # Checks # Templates # Generic # Channels # Aliases
o Reference
o Migration # v2 # v3
GitHub
Select theme[One of: Dark/Light/Auto]
On this page
_ Overview
_ Usage
o mkLib
o mkFlake
_ lib
o lib.mkFlake # Flake_Structure # Default_Flake # Snowfall_Configuration # External_Overlays_And_Modules # Internal_Packages_And_Outputs # Default_Packages_And_Shells # Darwin_And_NixOS_Generators # Home_Manager
o lib.snowfall.flake # lib.snowfall.flake.without-self # lib.snowfall.flake.without-src # lib.snowfall.flake.without-snowfall-inputs # lib.snowfall.flake.get-libs
o lib.snowfall.path # lib.snowfall.path.split-file-extension # lib.snowfall.path.has-any-file-extension # lib.snowfall.path.get-file-extension # lib.snowfall.path.has-file-extension # lib.snowfall.path.get-parent-directory # lib.snowfall.path.get-file-name-without-extension
o lib.snowfall.fs # lib.snowfall.fs.is-file-kind # lib.snowfall.fs.is-symlink-kind # lib.snowfall.fs.is-directory-kind # lib.snowfall.fs.is-unknown-kind # lib.snowfall.fs.get-file # lib.snowfall.fs.get-snowfall-file # lib.snowfall.fs.internal-get-file # lib.snowfall.fs.safe-read-directory # lib.snowfall.fs.get-directories # lib.snowfall.fs.get-files # lib.snowfall.fs.get-files-recursive # lib.snowfall.fs.get-nix-files # lib.snowfall.fs.get-nix-files-recursive # lib.snowfall.fs.get-default-nix-files # lib.snowfall.fs.get-default-nix-files-recursive # lib.snowfall.fs.get-non-default-nix-files # lib.snowfall.fs.get-non-default-nix-files-recursive
o lib.snowfall.module # lib.snowfall.module.create-modules
o lib.snowfall.attrs # lib.snowfall.attrs.map-concat-attrs-to-list # lib.snowfall.attrs.merge-deep # lib.snowfall.attrs.merge-shallow # lib.snowfall.attrs.merge-shallow-packages
o lib.snowfall.system # lib.snowfall.system.is-darwin # lib.snowfall.system.is-linux # lib.snowfall.system.is-virtual # lib.snowfall.system.get-virtual-system-type # lib.snowfall.system.get-inferred-system-name # lib.snowfall.system.get-target-systems-metadata # lib.snowfall.system.get-system-builder # lib.snowfall.system.get-system-output # lib.snowfall.system.get-resolved-system-target # lib.snowfall.system.create-system # lib.snowfall.system.create-systems
o lib.snowfall.home # lib.snowfall.home.split-user-and-host # lib.snowfall.home.create-home # lib.snowfall.home.create-homes # lib.snowfall.home.get-target-homes-metadata # lib.snowfall.home.create-home-system-modules
o lib.snowfall.package # lib.snowfall.package.create-packages
o lib.snowfall.shell # lib.snowfall.shell.create-shell
o lib.snowfall.overlay # lib.snowfall.overlay.create-overlays-builder # lib.snowfall.overlay.create-overlays
o lib.snowfall.template # lib.snowfall.template.create-templates
**\*** On this page **\***
_ Overview
_ Usage
o mkLib
o mkFlake \* lib
o lib.mkFlake # Flake_Structure # Default_Flake # Snowfall_Configuration # External_Overlays_And_Modules # Internal_Packages_And_Outputs # Default_Packages_And_Shells # Darwin_And_NixOS_Generators # Home_Manager
o lib.snowfall.flake # lib.snowfall.flake.without-self # lib.snowfall.flake.without-src # lib.snowfall.flake.without-snowfall-inputs # lib.snowfall.flake.get-libs
o lib.snowfall.path # lib.snowfall.path.split-file-extension # lib.snowfall.path.has-any-file-extension # lib.snowfall.path.get-file-extension # lib.snowfall.path.has-file-extension # lib.snowfall.path.get-parent-directory # lib.snowfall.path.get-file-name-without-extension
o lib.snowfall.fs # lib.snowfall.fs.is-file-kind # lib.snowfall.fs.is-symlink-kind # lib.snowfall.fs.is-directory-kind # lib.snowfall.fs.is-unknown-kind # lib.snowfall.fs.get-file # lib.snowfall.fs.get-snowfall-file # lib.snowfall.fs.internal-get-file # lib.snowfall.fs.safe-read-directory # lib.snowfall.fs.get-directories # lib.snowfall.fs.get-files # lib.snowfall.fs.get-files-recursive # lib.snowfall.fs.get-nix-files # lib.snowfall.fs.get-nix-files-recursive # lib.snowfall.fs.get-default-nix-files # lib.snowfall.fs.get-default-nix-files-recursive # lib.snowfall.fs.get-non-default-nix-files # lib.snowfall.fs.get-non-default-nix-files-recursive
o lib.snowfall.module # lib.snowfall.module.create-modules
o lib.snowfall.attrs # lib.snowfall.attrs.map-concat-attrs-to-list # lib.snowfall.attrs.merge-deep # lib.snowfall.attrs.merge-shallow # lib.snowfall.attrs.merge-shallow-packages
o lib.snowfall.system # lib.snowfall.system.is-darwin # lib.snowfall.system.is-linux # lib.snowfall.system.is-virtual # lib.snowfall.system.get-virtual-system-type # lib.snowfall.system.get-inferred-system-name # lib.snowfall.system.get-target-systems-metadata # lib.snowfall.system.get-system-builder # lib.snowfall.system.get-system-output # lib.snowfall.system.get-resolved-system-target # lib.snowfall.system.create-system # lib.snowfall.system.create-systems
o lib.snowfall.home # lib.snowfall.home.split-user-and-host # lib.snowfall.home.create-home # lib.snowfall.home.create-homes # lib.snowfall.home.get-target-homes-metadata # lib.snowfall.home.create-home-system-modules
o lib.snowfall.package # lib.snowfall.package.create-packages
o lib.snowfall.shell # lib.snowfall.shell.create-shell
o lib.snowfall.overlay # lib.snowfall.overlay.create-overlays-builder # lib.snowfall.overlay.create-overlays
o lib.snowfall.template # lib.snowfall.template.create-templates
**\*\*** Lib **\*\***
**\*** Usage **\***
snowfall-lib provides two utilities directly on the flake itself. \***\* mkLib \*\***
The library generator function. This is the entrypoint for snowfall-lib and is
how you access all of its features. See the following Nix Flake example for how
to create a library instance with mkLib.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs:
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;

        # You can optionally place your Snowfall-related files in another
        # directory.
        snowfall.root = ./nix;
      };
    in
    # We'll cover what to do here next.
    { };

}
For information on how to use lib, see the lib section. Or skip directly to
lib.mkFlake to see how to configure your flake’s outputs. \***\* mkFlake \*\***
A convenience wrapper for writing the following.
let
lib = inputs.snowfall-lib.mkLib {
inherit inputs;
src = ./.;

    # You can optionally place your Snowfall-related files in another
    # directory.
    snowfall.root = ./nix;

};
in lib.mkFlake {
}
Instead, with mkFlake you can combine these calls into one like the following.
inputs.snowfall-lib.mkFlake {
inherit inputs;
src = ./.;
};
See lib.mkFlake for information on how to configure your flake’s outputs.
**\*** lib **\***
Snowfall Lib provides utilities for creating flake outputs as well as some
necessary helpers. In addition, lib is an extension of nixpkgs.lib and every
flake input that contains a lib attribute. This means that you can use lib
directly for all of your needs, whether they’re Snowfall-related, NixPkgs-
related, or for one of the other flake inputs.
The way that mkLib merges libraries is by starting with the base nixpkgs.lib
and then merge each flake input’s lib attribute, namespaced by the name of the
input. For example, if you have the input flake-utils-plus then you will be
able to use lib.flake-utils-plus instead of having to keep a reference to the
input’s lib at inputs.flake-utils-plus.lib.
If you have your own library in a lib/ directory at your flake’s root,
definitions in there will automatically be imported and merged as well.
When producing flake outputs with mkFlake or another Snowfall lib utility, lib
will be passed in as an input. All of this together gives you easy access to a
common library of utilities and easy access to the libraries of flake inputs or
your own custom library. \***\* lib.mkFlake \*\***
The lib.mkFlake function creates full flake outputs. For most cases you will
only need to use this helper and the Snowfall lib will take care of everything
else.
**_ Flake Structure _**
Snowfall Lib has opinions about how a flake’s files are laid out. This lets lib
do all of the busy work for you and allows you to focus on creating. Here is
the structure that lib expects to find at the root of your flake.
snowfall-root/
│ The Snowfall root defaults to "src", but can be changed by setting
"snowfall.root".
│ This is useful if you want to add a flake to a project, but don't want to
clutter the
│ root of the repository with directories.
│
│ Your Nix flake.
├─ flake.nix
│
│ An optional custom library.
├─ lib/
│ │
│ │ A Nix function called with `inputs`, `snowfall-inputs`, and `lib`.
│ │ The function should return an attribute set to merge with `lib`.
│ ├─ default.nix
│ │
│ │ Any (nestable) directory name.
│ └─ **/
│ │
│ │ A Nix function called with `inputs`, `snowfall-inputs`, and `lib`.
│ │ The function should return an attribute set to merge with `lib`.
│ └─ default.nix
│
│ An optional set of packages to export.
├─ packages/
│ │
│ │ Any (nestable) directory name. The name of the directory will be the
│ │ name of the package.
│ └─ **/
│ │
│ │ A Nix package to be instantiated with `callPackage`. This file
│ │ should contain a function that takes an attribute set of packages
│ │ and _required_ `lib` and returns a derivation.
│ └─ default.nix
│
│
├─ modules/ (optional modules)
│ │
│ │ A directory named after the `platform` type that will be used for modules
within.
│ │
│ │ Supported platforms are:
│ │ - nixos
│ │ - darwin
│ │ - home
│ └─ <platform>/
│ │
│ │ Any (nestable) directory name. The name of the directory will be the
│ │ name of the module.
│ └─ **/
│ │
│ │ A NixOS module.
│ └─ default.nix
│
├─ overlays/ (optional overlays)
│ │
│ │ Any (nestable) directory name.
│ └─ **/
│ │
│ │ A custom overlay. This file should contain a function that takes three
arguments:
│ │ - An attribute set of your flake's inputs and a `channels` attribute
containing
│ │ all of your available channels (eg. nixpkgs, unstable).
│ │ - The final set of `pkgs`.
│ │ - The previous set of `pkgs`.
│ │
│ │ This function should return an attribute set to merge onto `pkgs`.
│ └─ default.nix
│
├─ systems/ (optional system configurations)
│ │
│ │ A directory named after the `system` type that will be used for all
machines within.
│ │
│ │ The architecture is any supported architecture of NixPkgs, for example:
│ │ - x86_64
│ │ - aarch64
│ │ - i686
│ │
│ │ The format is any supported NixPkgs format _or_ a format provided by
either nix-darwin
│ │ or nixos-generators. However, in order to build systems with nix-darwin or
nixos-generators,
│ │ you must add `darwin` and `nixos-generators` inputs to your flake
respectively. Here
│ │ are some example formats:
│ │ - linux
│ │ - darwin
│ │ - iso
│ │ - install-iso
│ │ - do
│ │ - vmware
│ │
│ │ With the architecture and format together (joined by a hyphen), you get
the name of the
│ │ directory for the system type.
│ └─ <architecture>-<format>/
│ │
│ │ A directory that contains a single system's configuration. The
directory name
│ │ will be the name of the system.
│ └─ <system-name>/
│ │
│ │ A NixOS module for your system's configuration.
│ └─ default.nix
│
├─ homes/ (optional homes configurations)
│ │
│ │ A directory named after the `home` type that will be used for all homes
within.
│ │
│ │ The architecture is any supported architecture of NixPkgs, for example:
│ │ - x86_64
│ │ - aarch64
│ │ - i686
│ │
│ │ The format is any supported NixPkgs format _or_ a format provided by
either nix-darwin
│ │ or nixos-generators. However, in order to build systems with nix-darwin or
nixos-generators,
│ │ you must add `darwin` and `nixos-generators` inputs to your flake
respectively. Here
│ │ are some example formats:
│ │ - linux
│ │ - darwin
│ │ - iso
│ │ - install-iso
│ │ - do
│ │ - vmware
│ │
│ │ With the architecture and format together (joined by a hyphen), you get
the name of the
│ │ directory for the home type.
│ └─ <architecture>-<format>/
│ │
│ │ A directory that contains a single home's configuration. The directory
name
│ │ will be the name of the home.
│ └─ <home-name>/
│ │
│ │ A NixOS module for your home's configuration.
│ └─ default.nix
**_ Default Flake _**
Without any extra input, lib.mkFlake will generate outputs for all systems,
modules, packages, overlays, and shells specified by the Flake_Structure
section.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;
};
in
lib.mkFlake { };
}
**_ Snowfall Configuration _**
Snowfall Lib supports configuring some functionality and interopability with
other tools via the snowfall attribute passed to mkLib.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;

        snowfall = {
        namespace = "my-namespace";
          meta = {
            # Your flake's preferred name in the flake registry.
            name = "my-flake";
            # A pretty name for your flake.
            title = "My Flake";
          };
        };
      };
    in
      lib.mkFlake { };

}
**_ External Overlays And Modules _**
You can apply overlays and modules from your flake’s inputs with the following
options.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;
};
in
lib.mkFlake { # Add overlays for the `nixpkgs` channel.
overlays = with inputs; [
# my-inputs.overlays.my-overlay
];

        # Add modules to all NixOS systems.
        systems.modules.nixos = with inputs; [
          # my-input.nixosModules.my-module
        ];

        # Add modules to all Darwin systems.
        systems.modules.darwin = with inputs; [
          # my-input.darwinModules.my-module
        ];

        # Add modules to a specific system.
        systems.hosts.my-host = with inputs; [
          # my-input.nixosModules.my-module
        ];

        # Add modules to all homes.
        homes.modules = with inputs; [
          # my-input.homeModules.my-module
        ];

        # Add modules to a specific home.
        homes.users."my-user@my-host".modules = with inputs; [
          # my-input.homeModules.my-module
        ];
      };

}
**_ Internal Packages And Outputs _**
Packages created from your packages/ directory are automatically made available
via an overlay for your nixpkgs channel. System configurations can access these
packages directly on pkgs and consumers of your flake can use the generated
<your-flake>.overlays attributes.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    comma = {
      url = "github:nix-community/comma";
      inputs.nixpkgs.follows = "unstable";
    };

};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;
};
in
lib.mkFlake { # Optionally place all packages under a namespace when used in an
overlay. # Instead of accessing packages with `pkgs.<name>`, your internal
packages # will be available at `pkgs.<namespace>.<name>`.
snowfall.namespace = "my-namespace";

        # You can also pass through external packages or dynamically create new

ones # in addition to the ones that `lib` will create from your `packages/
` directory.
outputs-builder = channels: {
packages = {
comma = inputs.comma.packages.${channels.nixpkgs.system}.comma;
};
};
};
}
**_ Default Packages And Shells _**
Snowfall Lib will create packages and shells based on your packages/ and shells
directories. However, it is common to additionally map one of those packages or
shells to be their respective default. This can be achieved by setting an alias
and mapping the default package or shell to the name of the one you want.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;
};
in
lib.mkFlake {
alias = {
packages = {
default = "my-package";
};

          shells = {
            default = "my-shell";
          };

          checks = {
            default = "my-check";
          };

          modules = {
            nixos.default = "my-nixos-module";
            darwin.default = "my-darwin-module";
            home.default = "my-home-module";
          };

          templates = {
            default = "my-template";
          };
        };
      };

}
**_ Darwin And NixOS Generators _**
Snowfall Lib has support for configuring macOS systems and building any output
supported by NixOS Generators. In order to use these features, your flake must
include darwin and/or nixos-generators as inputs.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # In order to configure macOS systems.
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # In order to build system images and artifacts supported by nixos-

generators.
nixos-generators = {
url = "github:nix-community/nixos-generators";
inputs.nixpkgs.follows = "nixpkgs";
};
};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;
};
in # No additional configuration is required to use this feature, you only # have to add darwin or nixos-generators to your flake inputs.
lib.mkFlake { };
}
Any macOS systems will be available on your flake at darwinConfigurations for
use with darwin-rebuild. Any system type supported by NixOS Generators will be
available on your flake at <format>Configurations where <format> is the name of
the generator type. See the following table for a list of supported formats
from NixOS Generators.
format description
amazon Amazon EC2 image
azure Microsoft azure image (Generation 1 / VHD)
cloudstack qcow2 image for cloudstack
do Digital Ocean image
gce Google Compute image
hyperv Hyper-V Image (Generation 2 / VHDX)
install-iso Installer ISO
install-iso-hyperv Installer ISO with enabled hyper-v support
iso ISO
kexec kexec tarball (extract to / and run /kexec_nixos)
kexec-bundle Same as before, but it’s just an executable
kubevirt KubeVirt image
lxc Create a tarball which is importable as an lxc container,
use together with lxc-metadata
lxc-metadata The necessary metadata for the lxc image to start
openstack qcow2 image for openstack
proxmox VMA file for proxmox
qcow qcow2 image
raw Raw image with bios/mbr
raw-efi Raw image with efi support
sd-aarch64 Like sd-aarch64-installer, but does not use default
installer image config.
sd-aarch64-installer create an installer sd card for aarch64
vagrant-virtualbox VirtualBox image for Vagrant
virtualbox virtualbox VM
vm Only used as a qemu-kvm runner
vm-bootloader Same as vm, but uses a real bootloader instead of
netbooting
vm-nogui Same as vm, but without a GUI
vmware VMWare image (VMDK)
**_ Home Manager _**
Snowfall Lib supports configuring Home_Manager for both standalone use and for
use as a module with NixOS or nix-darwin. To use this feature, your flake must
include home-manager as an input.
{
description = "My Flake";

inputs = {
nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # In order to use Home Manager.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

};

outputs = inputs: # This is an example and in your actual flake you can use `snowfall-
lib.mkFlake` # directly unless you explicitly need a feature of `lib`.
let
lib = inputs.snowfall-lib.mkLib { # You must pass in both your flake's inputs and the root directory of # your flake.
inherit inputs;
src = ./.;
};
in # No additional configuration is required to use this feature, you only # have to add home-manager to your flake inputs.
lib.mkFlake { };
} \***\* lib.snowfall.flake \*\***
Helpers related to Nix flakes.
**_ lib.snowfall.flake.without-self _**
Remove the self attribute from an attribute set.
Type: Attrs -> Attrs
Usage:
without-self { self = {}; x = true; }
Result:
{ x = true; }
**_ lib.snowfall.flake.without-src _**
Remove the src attribute from an attribute set.
Type: Attrs -> Attrs
Usage:
without-src { src = {}; x = true; }
Result:
{ x = true; }
**_ lib.snowfall.flake.without-snowfall-inputs _**
Remove the src and self attributes from an attribute set.
Type: Attrs -> Attrs
Usage:
without-snowfall-inputs { self = {}; src = {}; x = true; }
Result:
{ x = true; }
**_ lib.snowfall.flake.get-libs _**
Transform an attribute set of inputs into an attribute set where the values are
the inputs’ lib attribute. Entries without a lib attribute are removed.
Type: Attrs -> Attrs
Usage:
get-lib { x = nixpkgs; y = {}; }
Result:
{ x = nixpkgs.lib; } \***\* lib.snowfall.path \*\***
**_ lib.snowfall.path.split-file-extension _**
Split a file name and its extension.
Type: String -> [String]
Usage:
split-file-extension "my-file.md"
Result:
[ "my-file" "md" ]
**_ lib.snowfall.path.has-any-file-extension _**
Check if a file name has a file extension.
Type: String -> Bool
Usage:
has-any-file-extension "my-file.txt"
Result:
true
**_ lib.snowfall.path.get-file-extension _**
Get the file extension of a file name.
Type: String -> String Usage:
get-file-extension "my-file.final.txt"
Result:
"txt"
**_ lib.snowfall.path.has-file-extension _**
Check if a file name has a specific file extension.
Type: String -> String -> Bool
Usage:
has-file-extension "txt" "my-file.txt"
Result:
true
**_ lib.snowfall.path.get-parent-directory _**
Get the parent directory for a given path.
Type: Path -> Path
Usage:
get-parent-directory "/a/b/c"
Result:
"/a/b"
**_ lib.snowfall.path.get-file-name-without-extension _**
Get the file name of a path without its extension.
Type: Path -> String
Usage:
get-file-name-without-extension ./some-directory/my-file.pdf
Result:
"my-file" \***\* lib.snowfall.fs \*\***
File system utilities.
**_ lib.snowfall.fs.is-file-kind _**
**_ lib.snowfall.fs.is-symlink-kind _**
**_ lib.snowfall.fs.is-directory-kind _**
**_ lib.snowfall.fs.is-unknown-kind _**
Matchers for file kinds. These are often used with readDir.
Type: String -> Bool
Usage:
is-file-kind "directory"
Result:
false
**_ lib.snowfall.fs.get-file _**
Get a file path relative to the user’s flake.
Type: Path -> Path
Usage:
get-file "systems"
Result:
"/user-source/systems"
**_ lib.snowfall.fs.get-snowfall-file _**
Get a file path relative to the user’s snowfall directory.
Type: Path -> Path
Usage:
get-snowfall-file "systems"
Result:
"/user-source/snowfall-dir/systems"
**_ lib.snowfall.fs.internal-get-file _**
Get a file relative to the Snowfall Lib flake. You probably shouldn’t use this!
Type: Path -> Path
Usage:
get-file "systems"
Result:
"/snowfall-lib-source/systems"
**_ lib.snowfall.fs.safe-read-directory _**
Safely read from a directory if it exists.
Type: Path -> Attrs
Usage:
safe-read-directory ./some/path
Result:
{ "my-file.txt" = "regular"; }
**_ lib.snowfall.fs.get-directories _**
Get directories at a given path.
Type: Path -> [Path]
Usage:
get-directories ./something
Result:
[ "./something/a-directory" ]
**_ lib.snowfall.fs.get-files _**
Get files at a given path.
Type: Path -> [Path]
Usage:
get-files ./something
Result:
[ "./something/a-file" ]
**_ lib.snowfall.fs.get-files-recursive _**
Get files at a given path, traversing any directories within.
Type: Path -> [Path]
Usage:
get-files-recursive ./something
Result:
[ "./something/some-directory/a-file" ]
**_ lib.snowfall.fs.get-nix-files _**
Get nix files at a given path.
Type: Path -> [Path]
Usage:
get-nix-files "./something"
Result:
[ "./something/a.nix" ]
**_ lib.snowfall.fs.get-nix-files-recursive _**
Get nix files at a given path, traversing any directories within.
Type: Path -> [Path]
Usage:
get-nix-files "./something"
Result:
[ "./something/a.nix" ]
**_ lib.snowfall.fs.get-default-nix-files _**
Get nix files at a given path named “default.nix”.
Type: Path -> [Path]
Usage:
get-default-nix-files "./something"
Result:
[ "./something/default.nix" ]
**_ lib.snowfall.fs.get-default-nix-files-recursive _**
Get nix files at a given path named “default.nix”, traversing any directories
within.
Type: Path -> [Path]
Usage:
get-default-nix-files-recursive "./something"
Result:
[ "./something/some-directory/default.nix" ]
**_ lib.snowfall.fs.get-non-default-nix-files _**
Get nix files at a given path not named “default.nix”.
Type: Path -> [Path]
Usage:
get-non-default-nix-files "./something"
Result:
[ "./something/a.nix" ]
**_ lib.snowfall.fs.get-non-default-nix-files-recursive _**
Get nix files at a given path not named “default.nix”, traversing any
directories within.
Type: Path -> [Path]
Usage:
get-non-default-nix-files-recursive "./something"
Result:
[ "./something/some-directory/a.nix" ] \***\* lib.snowfall.module \*\***
Utilities for working with NixOS modules.
**_ lib.snowfall.module.create-modules _**
Create flake output modules.
Type: Attrs -> Attrs
Usage:
create-modules { src = ./my-modules; overrides = { inherit another-module; };
alias = { default = "another-module" }; }
Result:
{ another-module = ...; my-module = ...; default = ...; } \***\* lib.snowfall.attrs \*\***
Utilities for working with attribute sets.
**_ lib.snowfall.attrs.map-concat-attrs-to-list _**
Map and flatten an attribute set into a list.
Type: (a -> b -> [c]) -> Attrs -> [c]
Usage:
map-concat-attrs-to-list (name: value: [name value]) { x = 1; y = 2; }
Result:
[ "x" 1 "y" 2 ]
**_ lib.snowfall.attrs.merge-deep _**
Recursively merge a list of attribute sets.
Type: [Attrs] -> Attrs
Usage:
merge-deep [{ x = 1; } { x = 2; }]
Result:
{ x = 2; }
**_ lib.snowfall.attrs.merge-shallow _**
Merge the root of a list of attribute sets.
Type: [Attrs] -> Attrs
Usage:
merge-shallow [{ x = 1; } { x = 2; }]
Result:
{ x = 2; }
**_ lib.snowfall.attrs.merge-shallow-packages _**
Merge shallow for packages, but allow one deeper layer of attributes sets.
Type: [Attrs] -> Attrs
Usage:
merge-shallow-packages [
{
inherit (pkgs) vim;
namespace.first = 1;
}
{
inherit (unstable) vim;
namespace.second = 2;
}
]
Result:
{
vim = {/_ the vim package from the last entry _/};
namespace = {
first = 1;
second = 2;
};
} \***\* lib.snowfall.system \*\***
**_ lib.snowfall.system.is-darwin _**
Check whether a named system is macOS.
Type: String -> Bool
Usage:
is-darwin "x86*64-linux"
Result:
false
*** lib.snowfall.system.is-linux ***
Check whether a named system is Linux.
Type: String -> Bool
Usage:
is-linux "x86_64-linux"
Result:
false
*** lib.snowfall.system.is-virtual ***
Check whether a named system is virtual.
Type: String -> Bool
Usage:
is-linux "x86_64-iso"
Result:
true
*** lib.snowfall.system.get-virtual-system-type ***
Get the virtual system type of a system target.
Type: String -> String
Usage:
get-virtual-system-type "x86_64-iso"
Result:
"iso"
*** lib.snowfall.system.get-inferred-system-name ***
Get the name of a system based on its file path.
Type: Path -> String
Usage:
get-inferred-system-name "/systems/my-system/default.nix"
Result:
"my-system"
*** lib.snowfall.system.get-target-systems-metadata ***
Get structured data about all systems for a given target.
Type: String -> [Attrs]
Usage:
get-target-systems-metadata "x86_64-linux"
Result:
[ { target = "x86_64-linux"; name = "my-machine"; path = "/systems/x86_64-
linux/my-machine"; } ]
*** lib.snowfall.system.get-system-builder ***
Get the system builder for a given target.
Type: String -> Function
Usage:
get-system-builder "x86_64-iso"
Result:
(args: <system>)
*** lib.snowfall.system.get-system-output ***
Get the flake output attribute for a system target.
Type: String -> String
Usage:
get-system-output "aarch64-darwin"
Result:
"darwinConfigurations"
*** lib.snowfall.system.get-resolved-system-target ***
Get the resolved (non-virtual) system target.
Type: String -> String
Usage:
get-resolved-system-target "x86_64-iso"
Result:
"x86_64-linux"
*** lib.snowfall.system.create-system ***
Create a system.
Type: Attrs -> Attrs
Usage:
create-system { path = ./systems/my-system; }
Result:
<flake-utils-plus-system-configuration>
*** lib.snowfall.system.create-systems ***
Create all available systems.
Type: Attrs -> Attrs
Usage:
create-systems { hosts.my-host.specialArgs.x = true; modules.nixos = [ my-
shared-module ]; }
Result:
{ my-host = <flake-utils-plus-system-configuration>; } \***\* lib.snowfall.home \*\***
*** lib.snowfall.home.split-user-and-host ***
Get the user and host from a combined string.
Type: String -> Attrs
Usage:
split-user-and-host "myuser@myhost"
Result:
{ user = "myuser"; host = "myhost"; }
*** lib.snowfall.home.create-home ***
Create a home.
Type: Attrs -> Attrs
Usage:
create-home { path = ./homes/my-home; }
Result:
<flake-utils-plus-home-configuration>
*** lib.snowfall.home.create-homes ***
Create all available homes.
Type: Attrs -> Attrs
Usage:
create-homes { users."my-user@my-system".specialArgs.x = true; modules = [ my-
shared-module ]; }
Result:
{ "my-user@my-system" = <flake-utils-plus-home-configuration>; }
*** lib.snowfall.home.get-target-homes-metadata ***
Get structured data about all homes for a given target.
Type: String -> [Attrs]
Usage:
get-target-homes-metadata ./homes
Result:
[ { system = "x86_64-linux"; name = "my-home"; path = "/homes/x86_64-linux/my-
home";} ]
*** lib.snowfall.home.create-home-system-modules ***
Create system modules for home-manager integration.
Type: Attrs -> [Module]
Usage:
create-home-system-modules { users."my-user@my-system".specialArgs.x = true;
modules = [ my-shared-module ]; }
Result:
[Module] \***\* lib.snowfall.package \*\***
Utilities for working with flake packages.
*** lib.snowfall.package.create-packages ***
Create flake output packages.
Type: Attrs -> Attrs
Usage:
create-packages { inherit channels; src = ./my-packages; overrides = { inherit
another-package; }; alias = { default = "another-package"; }; }
Result:
{ another-package = ...; my-package = ...; default = ...; } \***\* lib.snowfall.shell \*\***
Utilities for working with flake dev shells.
*** lib.snowfall.shell.create-shell ***
Create flake output packages.
Type: Attrs -> Attrs
Usage:
create-shells { inherit channels; src = ./my-shells; overrides = { inherit
another-shell; }; alias = { default = "another-shell"; }; }
Result:
{ another-shell = ...; my-shell = ...; default = ...; } \***\* lib.snowfall.overlay \*\***
Utilities for working with channel overlays.
*** lib.snowfall.overlay.create-overlays-builder ***
Create a flake-utils-plus overlays builder.
Type: Attrs -> Attrs -> [(a -> b -> c)]
Usage:
create-overlays-builder { src = ./my-overlays; namespace = "my-namespace";
extra-overlays = []; }
Result:
(channels: [ ... ])
*** lib.snowfall.overlay.create-overlays ***
Create overlays to be used for flake outputs.
Type: Attrs -> Attrs
Usage:
create-overlays {
src = ./my-overlays;
packages-src = ./my-packages;
namespace = "my-namespace";
extra-overlays = {
my-example = final: prev: {};
};
}
Result:
{
default = final: prev: {};
my-example = final: prev: {};
some-overlay = final: prev: {};
} \***\* lib.snowfall.template \*\***
Utilities for working with flake templates.
*** lib.snowfall.template.create-templates ***
Create flake templates.
Type: Attrs -> Attrs
Usage:
create-templates { src = ./my-templates; overrides = { inherit another-
template; }; alias = { default = "another-template"; }; }
Result:
{ another-template = ...; my-template = ...; default = ...; }
Previous*
Aliases*Next*
v2
