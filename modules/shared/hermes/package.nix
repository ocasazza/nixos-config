{
  pkgs,
  lib,
  hermes,
  system,
  cfg,
  ...
}:

let
  isDarwin = builtins.elem system [
    "aarch64-darwin"
    "x86_64-darwin"
  ];

  # On Darwin, rebuild hermes venv from the fork source.
  # The fork (~/Repositories/schrodinger/hermes-agent, schrodinger branch) carries
  # all Schrodinger changes as proper commits — no patches needed here.
  #
  # Two wheel overrides are still required because uv.lock doesn't include
  # macOS ARM64 variants for these packages:
  #   - onnxruntime: missing macosx_14_0_arm64 wheel
  #   - cffi: 2.0.0 regresses callback thread-safety on macOS (segfault in
  #     CoreAudio callback); pinned to 1.17.1
  hermesVenvDarwin = pkgs.callPackage (
    {
      python311,
      lib,
      callPackage,
    }:
    let
      workspace = hermes.inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = hermes.outPath;
      };
      projectOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      onnxruntimeOverlay = _final: prev: {
        onnxruntime = prev.onnxruntime.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/60/69/6c40720201012c6af9aa7d4ecdd620e521bd806dc6269d636fdd5c5aeebe/onnxruntime-1.24.4-cp311-cp311-macosx_14_0_arm64.whl";
            hash = "sha256-C9/Ojppkl87FhKq0B7cb9pfaxeG3t5dK3FC/dTO9s6I=";
          };
        });
      };
      cffiOverlay = _final: prev: {
        cffi = prev.cffi.overrideAttrs (_old: {
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/6c/f5/6c3a8efe5f503175aaddcbea6ad0d2c96dad6f5abb205750d1b3df44ef29/cffi-1.17.1-cp311-cp311-macosx_11_0_arm64.whl";
            hash = "sha256-MMXgy1rkk8BMi0KRblLKOAefGyNcL4rl9FJ7ljxAHK8=";
          };
        });
      };
      # Several alibabacloud packages don't declare setuptools as a build
      # dependency in their pyproject.toml. Add it to nativeBuildInputs so
      # uv2nix can build the source distributions.
      setuptoolsOverlay = final: prev: {
        alibabacloud-tea = prev.alibabacloud-tea.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-credentials = prev.alibabacloud-credentials.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-credentials-api = prev.alibabacloud-credentials-api.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-dingtalk = prev.alibabacloud-dingtalk.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-endpoint-util = prev.alibabacloud-endpoint-util.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-gateway-dingtalk = prev.alibabacloud-gateway-dingtalk.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-gateway-spi = prev.alibabacloud-gateway-spi.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-openapi-util = prev.alibabacloud-openapi-util.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-tea-openapi = prev.alibabacloud-tea-openapi.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        alibabacloud-tea-util = prev.alibabacloud-tea-util.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
        darabonba-core = prev.darabonba-core.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
        });
      };
      pythonSet =
        (callPackage hermes.inputs.pyproject-nix.build.packages {
          python = python311;
        }).overrideScope
          (
            lib.composeManyExtensions [
              hermes.inputs.pyproject-build-systems.overlays.default
              projectOverlay
              onnxruntimeOverlay
              cffiOverlay
              setuptoolsOverlay
            ]
          );
    in
    pythonSet.mkVirtualEnv "hermes-agent-env" {
      hermes-agent = [ "all" ];
    }
  ) { };

  # Repackage hermes from the Schrodinger fork with the rebuilt venv on Darwin.
  # pname includes -schrodinger for FleetDM build identification (ITHELP-46694).
  hermesPackageDarwin =
    let
      skillsSrc = "${hermes.outPath}/skills";
      # Runtime tools — base + skill-dependent
      runtimeDeps =
        with pkgs;
        [
          nodejs_20
          ripgrep
          git
          openssh
          ffmpeg
          jq
          curl
        ]
        ++ lib.optionals (builtins.elem "github" cfg.skills) [ gh ];
      runtimePath = lib.makeBinPath runtimeDeps;
    in
    pkgs.stdenv.mkDerivation {
      pname = "hermes-agent-schrodinger";
      version = "0.1.0";
      dontUnpack = true;
      dontBuild = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hermes-agent/skills $out/bin
        # Copy only the enabled skill categories from upstream
        # TODO: Copy any skill that exists in an explicitly defined skill list
      ''
      + lib.concatMapStringsSep "\n" (cat: ''
        if [ -d "${skillsSrc}/${cat}" ]; then
          cp -r "${skillsSrc}/${cat}" "$out/share/hermes-agent/skills/${cat}"
        fi
      '') cfg.skills
      + lib.optionalString (cfg.extraSkillsDir != null) ''

        # Merge extra custom skills into the skills dir
        for dir in ${cfg.extraSkillsDir}/*/; do
          cat_name="$(basename "$dir")"
          if [ ! -d "$out/share/hermes-agent/skills/$cat_name" ]; then
            cp -r "$dir" "$out/share/hermes-agent/skills/$cat_name"
          else
            # Merge individual skills into existing category
            cp -rn "$dir"/* "$out/share/hermes-agent/skills/$cat_name/" 2>/dev/null || true
          fi
        done
      ''
      + ''

        ${lib.concatMapStringsSep "\n"
          (name: ''
            makeWrapper ${hermesVenvDarwin}/bin/${name} $out/bin/${name} \
              --suffix PATH : "${runtimePath}" \
              --set HERMES_BUNDLED_SKILLS $out/share/hermes-agent/skills
          '')
          [
            "hermes"
            "hermes-agent"
            "hermes-acp"
          ]
        }
        runHook postInstall
      '';
      meta = with lib; {
        description = "AI agent with advanced tool-calling capabilities";
        homepage = "https://github.com/NousResearch/hermes-agent";
        mainProgram = "hermes";
        license = licenses.mit;
        platforms = platforms.unix;
      };
    };
in
if isDarwin then hermesPackageDarwin else hermes.packages.${system}.default
