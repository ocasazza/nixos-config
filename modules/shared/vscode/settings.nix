{ pkgs, lib }:

{
  "workbench.startupEditor" = "none";
  # Editor settings - Neovim-like preferences
  "editor.fontFamily" = "JetBrains Mono";
  "editor.fontSize" = 14;
  "editor.lineHeight" = 1.5;
  "editor.fontLigatures" = true;
  "editor.formatOnSave" = false;  # Manual formatting control like Neovim
  "editor.formatOnPaste" = false;
  "editor.tabSize" = 2;
  "editor.insertSpaces" = true;
  "editor.detectIndentation" = true;
  "editor.renderWhitespace" = "boundary";
  "editor.wordWrap" = "on";
  "editor.minimap.enabled" = false;  # Cleaner, terminal-like experience
  "editor.bracketPairColorization.enabled" = true;
  "editor.guides.bracketPairs" = true;

  # Diff editor settings
  "diffEditor.ignoreTrimWhitespace" = false;
  "diffEditor.renderSideBySide" = true;

  # Terminal settings - Starship compatible
  "terminal.integrated.copyOnSelection" = true;
  "terminal.integrated.defaultProfile.osx" = "zsh";  # Works well with Starship
  # "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font Mono";  # Supports Starship icons
  "terminal.integrated.fontSize" = 13;
  "terminal.integrated.lineHeight" = 1.2;

  # These are pretty all pretty nice
  # "workbench.colorTheme" = "Functional Contrast";
  # "workbench.colorTheme" = "Sublime Material Theme - Dark";
  # "workbench.colorTheme" = "Material Dark Soda";
  # "workbench.colorTheme" = "monokai-charcoal (purple)",

  "workbench.colorTheme"= "Broken Moon";

  # "workbench.iconTheme" = "material-icon-theme";
  "workbench.editor.enablePreview" = false;  # More decisive file opening like Neovim
  "workbench.editor.closeOnFileDelete" = true;
  "workbench.secondarySideBar.defaultVisibility" = "hidden";

  # File settings - Neovim-style
  "files.trimTrailingWhitespace" = true;  # Common in Neovim configs
  "files.insertFinalNewline" = true;  # Unix standard
  "files.trimFinalNewlines" = true;
  # "files.autoSave" = "afterDelay";  # Disabled for manual save control like Neovim
  # "files.autoSaveDelay" = 1000;

  # Search settings
  "search.exclude" = {
    "**/node_modules" = true;
    "**/bower_components" = true;
    "**/*.code-search" = true;
    "**/result" = true;
    "**/.direnv" = true;
  };

  # Git settings - Complements terminal git workflow
  "git.enableSmartCommit" = true;
  "git.confirmSync" = false;
  "git.autofetch" = true;

  # Language-specific settings
  "[nix]" = {
    "editor.defaultFormatter" = "jnoortheen.nix-ide";
  };
  "[python]" = {
    "editor.defaultFormatter" = "ms-python.black-formatter";
    "editor.formatOnSave" = true;
  };
  "[javascript]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[typescript]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[json]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[markdown]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };

  # Remote SSH settings
  "remote.SSH.showLoginTerminal" = true;

  # Update settings - Enable automatic updates
  "update.mode" = "default";
  "extensions.autoUpdate" = true;
  "extensions.autoCheckUpdates" = true;

  # Security settings
  "security.workspace.trust.untrustedFiles" = "open";

  # Python settings
  "python.linting.enabled" = true;
  "python.linting.pylintEnabled" = true;
  "python.formatting.provider" = "black";

  # Prettier settings
  "prettier.singleQuote" = true;
  "prettier.trailingComma" = "es5";
  "prettier.tabWidth" = 2;
  "prettier.semi" = true;

  # Error Lens settings
  "errorLens.enabledDiagnosticLevels" = [ "error" "warning" "info" ];
  "errorLens.followCursor" = "allLines";

  # GitLens settings - Enhanced git for terminal workflow
  "gitlens.currentLine.enabled" = false;
  "gitlens.hovers.currentLine.over" = "line";
  "gitlens.statusBar.enabled" = false;

  # Direnv integration - autoreload extension when direnv detects reload
  "direnv.restart.automatic" = true;
  # "editor.experimentalGpuAcceleration"= "on";
  # "terminal.integrated.gpuAcceleration"= "on";

}
