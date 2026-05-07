{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  autoPatchelfHook,
}:
# TWG (Teamwork Graph) CLI - Atlassian's tool for interacting with Jira,
# Confluence, and Bitbucket. Provides agent skills that allow AI assistants
# like Claude Code to use natural language to query and manipulate Atlassian
# products.
#
# Bumping: change `version` and refresh the platform `hash =` entries below.
# Checksums are published at:
#   https://teamwork-graph.atlassian.com/cli/SHA256SUMS-v${version}
let
  baseUrl = "https://teamwork-graph.atlassian.com/cli";
  version = "0.9.7";

  # SHA256 hex digests from the upstream SHA256SUMS file
  platforms = {
    "aarch64-darwin" = {
      key = "twg-darwin-arm64-v${version}";
      hash = "edc59b7299daae6d25a3fdde5bb739ffe33fe78fb642dc59b3b7d62a68368de3";
    };
    "x86_64-darwin" = {
      key = "twg-darwin-x64-v${version}";
      hash = "7e0a4f9b8bae025a457fb2970a4d0767957f3217bb78b5ad76c8b96bbbcc6d30";
    };
    "aarch64-linux" = {
      key = "twg-linux-arm64-v${version}";
      hash = "070f0a170fccd605ac0d8da4fa33255425ae4371166d6ec1b6ea96aa08299c82";
    };
    "x86_64-linux" = {
      key = "twg-linux-x64-v${version}";
      hash = "27847b6bcb2ae17e17f60750f20cf11e655752be96f7ecb2600f8efbb2738ac3";
    };
  };

  platform =
    platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "twg: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "twg";
  inherit version;

  src = fetchurl {
    url = "${baseUrl}/${platform.key}";
    sha256 = platform.hash;
  };

  dontUnpack = true;
  dontBuild = true;
  # Binary is likely a bun/deno runtime; darwin build sandbox can't exec it
  __noChroot = stdenvNoCC.hostPlatform.isDarwin;
  dontStrip = true;

  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/twg

    runHook postInstall
  '';

  meta = {
    description = "Atlassian Teamwork Graph CLI - interact with Jira, Confluence, and Bitbucket";
    homepage = "https://developer.atlassian.com/cloud/twg-cli/";
    license = lib.licenses.unfree;
    mainProgram = "twg";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.attrNames platforms;
  };
}
