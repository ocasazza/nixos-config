# Draft: Zellij/SSH Disconnect Fix

## Problem Analysis

- SSH `serverAliveInterval = 0` means no keepalives → hangs forever on server reboot
- Zellij has no session serialization → dumps internal buffer codes on disconnect
- zsh EXIT trap lacks graceful Zellij detach for SSH sessions
- Result: terminal gibberish leaks into chat/SPA on reload

## SSH Fixes (modules/home/ssh/default.nix)

- Change `serverAliveInterval` from `0` to `60`
- Keep `serverAliveCountMax = 3` → dead connection detected in ~3 min
- Prevents indefinite hangs that lead to buffer corruption

## Zellij Fixes (modules/home/zellij/default.nix)

- Add `session_serialization = true`
- Add `serialize_pane_viewport = true`
- Add `scrollback_lines = 10000` (prevents unbounded memory, but enough for context)
- Ensures sessions survive crashes/disconnects and can be reattached cleanly

## Zsh Fixes (modules/home/zsh/default.nix)

- For SSH sessions only: if in zellij, detach on shell EXIT
- Prevents Zellij from dumping buffer state when SSH connection drops

## Scope

- IN: SSH client config, Zellij config, Zsh config
- OUT: Server-side changes, Zellij layout changes, Ghostty config changes

## Files to Modify

1. modules/home/ssh/default.nix
2. modules/home/zellij/default.nix
3. modules/home/zsh/default.nix
