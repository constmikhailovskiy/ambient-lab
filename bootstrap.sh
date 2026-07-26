#!/usr/bin/env bash
# ============================================================
# ambient-lab :: macOS bootstrap
#
#   ./bootstrap.sh              check only — installs nothing, prints a report
#   ./bootstrap.sh --install    install whatever is missing
#   ./bootstrap.sh --help
#
# Safe to re-run. Every step checks before acting.
# ============================================================

set -uo pipefail

LAB="${LAB:-$HOME/ambient-lab}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="check"
MISSING=()

case "${1:-}" in
  --install) MODE="install" ;;
  --help|-h)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  "") ;;
  *) echo "unknown flag: $1  (try --help)"; exit 1 ;;
esac

# ---- output helpers ----------------------------------------
if [[ -t 1 ]]; then
  G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[34m'; DIM=$'\e[2m'; N=$'\e[0m'
else
  G=""; Y=""; R=""; B=""; DIM=""; N=""
fi
ok()   { printf "  %s✓%s %s\n" "$G" "$N" "$*"; }
miss() { local key="$1"; shift; printf "  %s✗%s %s\n" "$R" "$N" "${*:-$key}"; MISSING+=("$key"); }
warn() { printf "  %s!%s %s\n" "$Y" "$N" "$*"; }
info() { printf "    %s%s%s\n" "$DIM" "$*" "$N"; }
head_() { printf "\n%s== %s ==%s\n" "$B" "$*" "$N"; }
run() {
  if [[ "$MODE" == "install" ]]; then
    printf "    %s\$ %s%s\n" "$DIM" "$*" "$N"
    "$@"
  else
    printf "    %swould run: %s%s\n" "$Y" "$*" "$N"
  fi
}

# ============================================================
head_ "platform"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is macOS-only. Aborting."; exit 1
fi
ARCH="$(uname -m)"
ok "macOS $(sw_vers -productVersion) on $ARCH"

if [[ "$ARCH" == "arm64" ]]; then BREW_PREFIX="/opt/homebrew"; else BREW_PREFIX="/usr/local"; fi

# ---- Xcode command line tools ------------------------------
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode command line tools"
else
  miss "clt" "Xcode command line tools missing"
  run xcode-select --install
  info "Finish the GUI installer, then re-run this script."
  [[ "$MODE" == "install" ]] && exit 0
fi

# ---- Homebrew ----------------------------------------------
if command -v brew >/dev/null 2>&1; then
  ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
elif [[ -x "$BREW_PREFIX/bin/brew" ]]; then
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  ok "Homebrew (added to PATH for this session)"
  info "Add to your shell profile: eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
else
  miss "brew" "Homebrew missing"
  info 'Install with: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  info "Then re-run this script. (Not automated — it needs your password interactively.)"
  exit 1
fi

# ============================================================
head_ "audio engine"

SC_APP="/Applications/SuperCollider.app"
SCLANG="$SC_APP/Contents/MacOS/sclang"
if [[ -d "$SC_APP" ]]; then
  SC_VER="$("$SC_APP/Contents/Resources/scsynth" -v 2>/dev/null | head -1 | awk '{print $3}')"
  ok "SuperCollider ${SC_VER:-installed}"
else
  miss "supercollider" "SuperCollider missing"
  run brew install --cask supercollider
fi

# ---- Quarks: SuperDirt + Dirt-Samples ----------------------
QUARKS="$HOME/Library/Application Support/SuperCollider/downloaded-quarks"
need_superdirt=0
if [[ -d "$QUARKS/SuperDirt" ]]; then ok "SuperDirt quark"; else
  miss "superdirt" "SuperDirt quark missing"; need_superdirt=1; fi
if [[ -d "$QUARKS/Dirt-Samples" ]]; then
  ok "Dirt-Samples ($(find "$QUARKS/Dirt-Samples" -name '*.wav' 2>/dev/null | wc -l | tr -d ' ') wav files)"
else
  miss "dirt-samples" "Dirt-Samples missing"; need_superdirt=1; fi

if [[ "$need_superdirt" == "1" && -x "$SCLANG" ]]; then
  if [[ "$MODE" == "install" ]]; then
    TMP="$(mktemp -t installquarks).scd"
    cat > "$TMP" <<'EOF'
Quarks.install("SuperDirt");   // pulls Dirt-Samples and Vowel as dependencies
"QUARK-INSTALL-DONE".postln;
0.exit;
EOF
    info "running sclang headless to install quarks (this clones a few hundred MB of samples)"
    "$SCLANG" -D "$TMP"
    rm -f "$TMP"
  else
    info "would install via sclang: Quarks.install(\"SuperDirt\")"
    info "or do it in the SuperCollider IDE: Quarks.install(\"SuperDirt\"); thisProcess.recompile();"
  fi
fi

info "sc3-plugins is NOT required — nothing in ambient-lab uses it. Skip it."

# ============================================================
head_ "haskell + tidal"

[[ -f "$HOME/.ghcup/env" ]] && source "$HOME/.ghcup/env"

if command -v ghcup >/dev/null 2>&1; then ok "ghcup $(ghcup --numeric-version 2>/dev/null)"; else
  miss "ghcup" "ghcup missing"; run brew install ghcup; fi

if command -v ghc >/dev/null 2>&1; then
  ok "ghc $(ghc --numeric-version)"
else
  miss "ghc" "ghc missing"
  run ghcup install ghc --set recommended
fi

if command -v cabal >/dev/null 2>&1; then ok "cabal $(cabal --numeric-version)"; else
  miss "cabal" "cabal missing"; run ghcup install cabal --set recommended; fi

TIDAL_VER=""
if command -v ghc-pkg >/dev/null 2>&1; then
  TIDAL_VER="$(ghc-pkg list --simple-output 2>/dev/null | tr ' ' '\n' | grep '^tidal-[0-9]' | head -1)"
fi
if [[ -n "$TIDAL_VER" ]]; then
  ok "$TIDAL_VER"
else
  miss "tidal" "tidal library not found in the ghc package db"
  run cabal v1-update
  run cabal v1-install tidal
  info "note: 'cabal v1-install' (not 'cabal install') is what Tidal's docs require"
fi

# ---- BootTidal.hs: copy into the repo, append our prelude ---
BOOT_LOCAL="$REPO/tidal/BootTidal.hs"
if [[ -f "$BOOT_LOCAL" ]] && grep -q "ambient-lab" "$BOOT_LOCAL"; then
  ok "tidal/BootTidal.hs present and patched with the ambient prelude"
else
  BOOT_SRC=""
  if command -v ghc-pkg >/dev/null 2>&1; then
    DD="$(ghc-pkg field tidal data-dir 2>/dev/null | awk '{print $2}' | head -1)"
    [[ -n "$DD" && -f "$DD/BootTidal.hs" ]] && BOOT_SRC="$DD/BootTidal.hs"
  fi
  if [[ -z "$BOOT_SRC" ]]; then
    BOOT_SRC="$(find "$HOME/.cabal" -name BootTidal.hs 2>/dev/null | head -1)"
  fi
  if [[ -z "$BOOT_SRC" ]]; then
    warn "couldn't locate the stock BootTidal.hs (install tidal first, then re-run)"
  else
    ok "found stock boot file: $BOOT_SRC"
    if [[ "$MODE" == "install" ]]; then
      cp "$BOOT_SRC" "$BOOT_LOCAL"
      printf '\n\n' >> "$BOOT_LOCAL"
      cat "$REPO/tidal/prelude.hs" >> "$BOOT_LOCAL"
      ok "wrote $BOOT_LOCAL (stock boot + ambient prelude)"
    else
      info "would copy it to $BOOT_LOCAL and append tidal/prelude.hs"
    fi
  fi
fi

# ============================================================
head_ "editor"

VSCODE="/Applications/Visual Studio Code.app"
if [[ -d "$VSCODE" ]]; then
  ok "VS Code"
  if command -v code >/dev/null 2>&1; then
    if code --list-extensions 2>/dev/null | grep -qi 'tidalcycles'; then
      ok "VS Code TidalCycles extension"
    else
      miss "vscode-tidal" "VS Code TidalCycles extension missing"
      run code --install-extension tidalcycles.vscode-tidalcycles
      info "if that ID 404s, search the marketplace for 'TidalCycles'"
    fi
  else
    warn "the 'code' shell command isn't on PATH"
    info "VS Code: Cmd+Shift+P > 'Shell Command: Install code command in PATH'"
  fi
elif [[ -d "/Applications/Pulsar.app" ]]; then
  ok "Pulsar"
  info "install the tidalcycles package via Pulsar's Package Manager (or: ppm install tidalcycles)"
else
  miss "editor" "no Tidal-capable editor found"
  info "recommended for you: VS Code + TidalCycles extension"
  run brew install --cask visual-studio-code
fi

# ============================================================
head_ "ableton routing"

if compgen -G "/Library/Audio/Plug-Ins/HAL/BlackHole*.driver" > /dev/null; then
  for d in /Library/Audio/Plug-Ins/HAL/BlackHole*.driver; do ok "$(basename "$d")"; done
else
  miss "blackhole" "BlackHole virtual audio driver missing"
  run brew install --cask blackhole-16ch
  info "needs your password, and a logout/restart (or: sudo killall coreaudiod) before it appears"
fi

if compgen -G "/Applications/Ableton Live*.app" > /dev/null; then
  for a in /Applications/Ableton\ Live*.app; do ok "$(basename "$a" .app)"; done
else
  warn "Ableton Live not found in /Applications (fine if it lives elsewhere)"
fi

warn "IAC Driver (MIDI from SuperCollider to Live) must be enabled by hand — see MACOS-SETUP.md step 4"

# ============================================================
head_ "repo layout"

for f in sc/startup.scd sc/drones.scd sc/beds.scd tidal/prelude.hs \
         tidal/sketches/01-drones.tidal tidal/sketches/02-noise.tidal \
         tidal/sketches/03-chords.tidal; do
  [[ -f "$REPO/$f" ]] && ok "$f" || miss "file:$f" "$f missing"
done

mkdir -p "$REPO/takes" "$REPO/tools"
ok "takes/ and tools/ present"

# patch the ~lab path inside startup.scd so it points at this checkout
if [[ -f "$REPO/sc/startup.scd" ]]; then
  WANT="~lab = \"$REPO/sc\";"
  if grep -qF "$WANT" "$REPO/sc/startup.scd"; then
    ok "startup.scd ~lab path is correct"
  else
    if [[ "$MODE" == "install" ]]; then
      /usr/bin/sed -i '' "s|^~lab = .*|$WANT|" "$REPO/sc/startup.scd"
      ok "patched ~lab -> $REPO/sc"
    else
      info "would patch ~lab in sc/startup.scd to $REPO/sc"
    fi
  fi
fi

if [[ ! -d "$REPO/.git" ]]; then
  warn "not a git repo — you will want history on these files"
  run git -C "$REPO" init -q
fi

# ============================================================
head_ "summary"

if [[ ${#MISSING[@]} -eq 0 ]]; then
  printf "  %sEverything is in place.%s\n" "$G" "$N"
else
  printf "  %d item(s) need attention: %s\n" "${#MISSING[@]}" "${MISSING[*]}"
  if [[ "$MODE" == "check" ]]; then
    printf "  Re-run with %s--install%s to fix what can be fixed automatically.\n" "$B" "$N"
  fi
fi

cat <<EOF

Manual steps that cannot be scripted (see MACOS-SETUP.md):
  1. Enable the IAC Driver in Audio MIDI Setup    (for Tidal -> Live MIDI)
  2. Point your editor's boot file setting at:
       $REPO/tidal/BootTidal.hs
  3. In Ableton: Audio Input Device = BlackHole 16ch, Output = your interface
  4. Arm four stereo tracks on inputs 1/2, 3/4, 5/6, 7/8

First session:
  open -a SuperCollider $REPO/sc/startup.scd
  # evaluate the ( ... ) block, wait for "--- ambient-lab ready ---"
  # then open tidal/sketches/01-drones.tidal in your editor, boot Tidal, go
EOF
