{ hmLib, ... }:

{
  home.activation.installOpencodePlugins = hmLib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if command -v bun >/dev/null 2>&1 && [[ -f "$HOME/.config/opencode/package.json" ]]; then
      cd "$HOME/.config/opencode"
      if [[ ! -d node_modules ]] || [[ package.json -nt node_modules/.package-lock ]]; then
        $DRY_RUN_CMD bun install --no-summary $VERBOSE_ARG
      fi
    fi
  '';
}
