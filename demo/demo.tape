# vhs tape for the nix-why demo GIF.
#
# Regenerate (from the repo root): build the four CLIs and jq, put them on
# PATH, then run vhs. Building inside the tape would leak async output into
# the recording, so it is done up front:
#
#   bindir=$(mktemp -d)
#   ln -s $(nix build .#nix-why-option   --no-link --print-out-paths)/bin/nix-why-option   $bindir/
#   ln -s $(nix build .#nix-why-conflict --no-link --print-out-paths)/bin/nix-why-conflict $bindir/
#   ln -s "$(command -v jq)" $bindir/
#   PATH="$bindir:$PATH" nix run nixpkgs#vhs -- demo/demo.tape

Output "demo/nix-why.gif"

Set Shell "bash"
Set FontSize 17
Set Width 1180
Set Height 940
Set Padding 22
Set Theme "Catppuccin Mocha"
Set TypingSpeed 35ms

# Enter the demo flake; tools are already on PATH (see header).
Hide
Type "cd demo"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# nix-why: why does a NixOS / home-manager / nix-darwin option have its value?"
Sleep 800ms
Enter
Sleep 1200ms

# 1. resolve: who set it, who lost, at what priority.
Type "nix-why-option --full .#demo services.webapp.enable"
Sleep 500ms
Enter
Sleep 3.5s

# 2. a merge conflict, pinned to the two definitions that collide.
Type "nix-why-conflict .#demo services.webapp.port"
Sleep 500ms
Enter
Sleep 3.5s

# 3. why-not: the definition that would set it, and the condition it needs.
Type "nix-why-option --full why-not .#demo services.webapp.workers"
Sleep 500ms
Enter
Sleep 4s

# 4. stable JSON for tooling.
Type "nix-why-option --json .#demo services.webapp.enable | jq '{value, winningPriority, winningPriorityKind}'"
Sleep 500ms
Enter
Sleep 3.5s
