{ pkgs }:

{
  # Editor settings - Neovim-like preferences
  "editor.fontFamily" = "JetBrainsMono Nerd Font";
  "editor.fontSize" = 14;
  "editor.lineHeight" = 1.5;
  "editor.fontLigatures" = true;
  "editor.formatOnSave" = false;
  "editor.formatOnPaste" = false;
  "editor.tabSize" = 2;
  "editor.insertSpaces" = true;
  "editor.detectIndentation" = true;
  "editor.renderWhitespace" = "boundary";
  "editor.wordWrap" = "off";
  "editor.minimap.enabled" = false;
  "editor.bracketPairColorization.enabled" = true;
  "editor.guides.bracketPairs" = true;
  "diffEditor.ignoreTrimWhitespace" = false;
  "diffEditor.renderSideBySide" = true;
  "terminal.integrated.copyOnSelection" = true;
  "terminal.integrated.defaultProfile.osx" = "zsh";
  "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font Mono";
  "terminal.integrated.fontSize" = 13;
  "terminal.integrated.lineHeight" = 1.2;
  # These are pretty all pretty nice
  # "workbench.colorTheme" = "Functional Contrast";
  # "workbench.colorTheme" = "Sublime Material Theme - Dark";
  # "workbench.colorTheme" = "Material Dark Soda";
  "workbench.colorTheme" = "monokai-charcoal (purple)";
  # "workbench.colorTheme" = "Broken Moon";
  # "workbench.iconTheme" = "material-icon-theme";
  "workbench.editor.enablePreview" = false;
  "workbench.editor.closeOnFileDelete" = true;
  "workbench.secondarySideBar.defaultVisibility" = "hidden";
  "files.trimTrailingWhitespace" = true;
  "files.insertFinalNewline" = true; # Unix standard
  "files.trimFinalNewlines" = true;
  # "files.autoSave" = "afterDelay";
  # "files.autoSaveDelay" = 1000;
  "search.exclude" = {
    "**/node_modules" = true;
    "**/bower_components" = true;
    "**/*.code-search" = true;
    "**/result" = true;
    "**/.direnv" = true;
  };
  "git.path" = "${pkgs.git}/bin/git";
  "git.enableSmartCommit" = true;
  "git.confirmSync" = false;
  "git.autofetch" = true;
  "[nix]" = {
    "editor.defaultFormatter" = "jnoortheen.nix-ide";
  };
  "remote.SSH.showLoginTerminal" = true;
  "update.mode" = "default";
  "extensions.autoUpdate" = true;
  "extensions.autoCheckUpdates" = true;
  "security.workspace.trust.untrustedFiles" = "open";
  "python.linting.enabled" = true;
  "python.linting.pylintEnabled" = true;
  "python.formatting.provider" = "black";
  "prettier.singleQuote" = true;
  "prettier.trailingComma" = "es5";
  "prettier.tabWidth" = 2;
  "prettier.semi" = true;
  "errorLens.enabledDiagnosticLevels" = [
    "error"
    "warning"
    "info"
  ];
  "errorLens.followCursor" = "allLines";
  "gitlens.currentLine.enabled" = false;
  "gitlens.hovers.currentLine.over" = "line";
  "gitlens.statusBar.enabled" = false;
  "direnv.restart.automatic" = true;
  "editor.experimentalGpuAcceleration" = "on";
  "terminal.integrated.gpuAcceleration" = "on";
}
