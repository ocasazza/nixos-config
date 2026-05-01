# omlx — LLM inference server with continuous batching & SSD KV caching for Apple Silicon.
#
# Because omlx pins many Python deps to git commits (mlx-lm, mlx-vlm, mlx-audio,
# mlx-embeddings, dflash-mlx), a full from-source nix build of every transitive
# dep would be brittle and high-maintenance. Instead we ship a thin wrapper that
# manages a user-local venv in ~/.local/share/omlx/venv (created on first run).
# The venv is installed via pip at runtime, so upstream can bump deps freely.
#
# This is philosophically similar to how nixpkgs handles Steam, Discord, etc.:
# nix owns the launcher/wrapper; the mutable payload lives in the user’s $HOME.
#
# Usage:
#   omlx serve --model-dir ~/models
#   omlx --help
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  fetchFromGitHub,
  # macOS-only: PyObjC is imported at runtime by the menubar app. When the
  # server path is used (omlx serve) these are not needed, but we include
  # them so the full CLI surface works.
}:
let
  version = "0.3.8";

  src = fetchFromGitHub {
    owner = "jundot";
    repo = "omlx";
    rev = "v${version}";
    sha256 = "0ssn161bbkx3wjrl3s43d9vhf9wpyhwsnks4dnzsbsfwx5gbg7j8";
  };
in
stdenvNoCC.mkDerivation {
  pname = "omlx";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/omlx

    # Copy upstream source so pip can install from it later.
    cp -r . $out/share/omlx/src

    # The launcher script.
    cat > $out/bin/omlx <<EOF
    #!${python3}/bin/python3
    import os
    import subprocess
    import sys

    VENV_DIR = os.environ.get("OMLX_VENV_DIR", os.path.expanduser("~/.local/share/omlx/venv"))
    SRC_DIR = "$out/share/omlx/src"
    PYTHON = "${python3}/bin/python3"

    # Create the venv + install omlx on first invocation.
    if not os.path.isfile(os.path.join(VENV_DIR, "bin", "omlx")):
        print("[omlx] First run: creating venv in", VENV_DIR, file=sys.stderr)
        os.makedirs(VENV_DIR, exist_ok=True)
        subprocess.run([PYTHON, "-m", "venv", VENV_DIR], check=True)

        pip = os.path.join(VENV_DIR, "bin", "pip")
        # Upgrade pip/setuptools/wheel so git deps resolve cleanly.
        subprocess.run([pip, "install", "--quiet", "--upgrade", "pip", "setuptools", "wheel"], check=True)

        # Install omlx from the bundled source with all extras.
        # [audio,mcp] enables STT/TTS and MCP support.
        print("[omlx] Installing omlx and extras ...", file=sys.stderr)
        subprocess.run([pip, "install", "--quiet", f"{SRC_DIR}[audio,mcp]"], check=True)
        print("[omlx] Installation complete.", file=sys.stderr)

    # Run the real omlx binary from the venv.
    omlx_bin = os.path.join(VENV_DIR, "bin", "omlx")
    os.execv(omlx_bin, [omlx_bin] + sys.argv[1:])
    EOF

    chmod +x $out/bin/omlx

    runHook postInstall
  '';

  meta = {
    description = "LLM inference server with continuous batching & SSD caching for Apple Silicon";
    homepage = "https://github.com/jundot/omlx";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "omlx";
  };
}
