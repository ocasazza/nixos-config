# opencode-voice — Voice control for OpenCode via the HTTP API.
#
# Records from the mic using cpal, transcribes with whisper.cpp (local,
# no cloud), and pushes the text into an OpenCode session over its HTTP
# API. Hold space to record, release to transcribe + submit.
#
# Requires running opencode with `--port <n>`; opencode-voice connects to
# the same port. On macOS, Accessibility permission is needed for global
# hotkeys (System Settings → Privacy & Security → Accessibility).
#
# Usage:
#   opencode --port 4096
#   opencode-voice --port 4096
#
# Setup (downloads ~150 MB whisper model):
#   opencode-voice setup --model base.en
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  installShellFiles,
  # Unified Apple SDK (replaces individual framework args in newer nixpkgs)
  apple-sdk,
  # whisper.cpp is vendored in the crate, so no external dep needed.
}:

rustPlatform.buildRustPackage rec {
  pname = "opencode-voice";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "mathew-cf";
    repo = "opencode-voice";
    rev = "v${version}";
    hash = "sha256-WPdID6f72B1e/YsbSsm1LED6mQCGEzEGC2yTt/EeC8Q=";
  };

  cargoHash = "sha256-UOFJmPAx9i7wxcs8W/Jvx4yb2M6IGR/GqD1f47dw98w=";

  nativeBuildInputs = [
    cmake
    pkg-config
    installShellFiles
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk
  ];

  # whisper.cpp is built as part of the crate; cmake handles it.
  # The build.rs for whisper-rs uses cmake.
  dontUseCmakeConfigure = true;

  meta = {
    description = "Voice control for OpenCode using local whisper.cpp STT";
    homepage = "https://github.com/mathew-cf/opencode-voice";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
    mainProgram = "opencode-voice";
  };
}
