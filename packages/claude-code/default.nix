{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  autoPatchelfHook,
  procps,
  ripgrep,
  bubblewrap,
  socat,
  sox,
}:
# Native-binary distribution. Starting at 2.1.113 Anthropic ships
# claude-code as a single ~210MB native binary (bun runtime + bundled
# JS) per platform, replacing the old buildNpmPackage `cli.js` bundle.
# This package mirrors nixpkgs `claude-code-bin` shape — fetch the
# binary from Anthropic's GCS releases bucket and wrap it.
#
# Bumping: change `version` and refresh the four platform `hash =`
# entries below. The upstream manifest lives at:
#   https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/<version>/manifest.json
let
  baseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
  version = "2.1.119";

  # SHA256 hex digests from the upstream manifest.json. fetchurl
  # accepts hex form directly.
  platforms = {
    "aarch64-darwin" = {
      key = "darwin-arm64";
      hash = "31db3444309d5d0f8b85e8782e2dcd86f31f7e48c1a1e83d69b09268c7b4f9a2";
    };
    "x86_64-darwin" = {
      key = "darwin-x64";
      hash = "52b3b75cfe80c626982b2ffb3a6ce1c797824f257dc275cf0a3c32c202b6a3df";
    };
    "aarch64-linux" = {
      key = "linux-arm64";
      hash = "382aa73ea4b07fd8d698e3159b5ef9e1b8739fae7505ba8ddd28b8a6a62819ce";
    };
    "x86_64-linux" = {
      key = "linux-x64";
      hash = "cca43053f062949495596b11b6fd1b59cf79102adb13bacbe66997e6fae41e4a";
    };
  };

  platform =
    platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-code: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "${baseUrl}/${version}/${platform.key}/claude";
    sha256 = platform.hash;
  };

  dontUnpack = true;
  dontBuild = true;
  # The binary is the bun runtime; on darwin the build sandbox can't
  # exec it without chroot escape during the install check.
  __noChroot = stdenvNoCC.hostPlatform.isDarwin;
  # Stripping breaks the embedded bun runtime.
  dontStrip = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/claude

    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            # node-tree-kill needs pgrep(darwin) / ps(linux)
            procps
            # https://code.claude.com/docs/en/troubleshooting#search-and-discovery-issues
            ripgrep
            # /voice command shells out to `sox` for mic capture
            sox
          ]
          ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.attrNames platforms;
  };
}
