#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/voxtype"
MODEL_DIR="$DATA_DIR/models/parakeet-unified-en-0.6b-int8"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/local.omatype"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
LEGACY_HOOK="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/post-update.d/install-voxtype.hook"
MODEL_BASE_URL="https://huggingface.co/bobNight/parakeet-unified-en-0.6b-onnx/resolve/main"

print_header() { printf "${BOLD}${CYAN}⚡ %s${RESET}\n" "$1"; }
print_success() { printf "${GREEN}✓${RESET} %s\n" "$1"; }
print_status() { printf "${CYAN}→${RESET} %s\n" "$1"; }
print_warning() { printf "${YELLOW}!${RESET} %s\n" "$1"; }
print_dim() { printf "${DIM}%s${RESET}\n" "$1"; }

install_dependencies() {
  local missing=0
  command -v cargo >/dev/null 2>&1 || missing=1
  command -v cmake >/dev/null 2>&1 || missing=1
  command -v pkg-config >/dev/null 2>&1 || missing=1
  command -v clang >/dev/null 2>&1 || missing=1
  command -v wtype >/dev/null 2>&1 || missing=1
  command -v wl-copy >/dev/null 2>&1 || missing=1
  command -v curl >/dev/null 2>&1 || missing=1
  command -v sha256sum >/dev/null 2>&1 || missing=1
  command -v keyd >/dev/null 2>&1 || missing=1

  if [[ "$missing" -eq 1 ]]; then
    if command -v omarchy >/dev/null 2>&1; then
      print_status "Installing build and runtime dependencies"
      omarchy pkg add rust cmake clang pkgconf alsa-lib wtype wl-clipboard keyd
    else
      print_warning "Missing dependencies. Install Rust, CMake, Clang, pkg-config, ALSA headers, wtype, wl-clipboard, and keyd."
      exit 1
    fi
  fi
}

remove_upstream_voxtype() {
  if command -v pacman >/dev/null 2>&1 && pacman -Qq voxtype-bin >/dev/null 2>&1; then
    print_status "Removing the upstream VoxType package"
    if command -v omarchy >/dev/null 2>&1; then
      omarchy pkg drop voxtype-bin
    else
      sudo pacman -Rns --noconfirm voxtype-bin
    fi
  fi
  rm -f -- "$LEGACY_HOOK"
}

download_model_file() {
  local filename="$1"
  local expected_sha="$2"
  local destination="$MODEL_DIR/$filename"

  if [[ -f "$destination" ]] && printf '%s  %s\n' "$expected_sha" "$destination" | sha256sum --check --status; then
    print_success "$filename already verified"
    return
  fi

  print_status "Downloading $filename"
  curl --fail --location --retry 3 --progress-bar "$MODEL_BASE_URL/$filename" --output "$destination.part"
  printf '%s  %s\n' "$expected_sha" "$destination.part" | sha256sum --check --status
  mv "$destination.part" "$destination"
}

install_model() {
  print_header "Parakeet model"
  mkdir -p "$MODEL_DIR"
  download_model_file encoder.int8.onnx c81adfab77634e00c1668a221a14f244c5fb3409e7c14eeebaf6ac963425910f
  download_model_file encoder.int8.onnx.data 3d54dd04646c15677bd2844a84df3770b12cc1ce183481f7b6e0def31c92114a
  download_model_file decoder_joint.int8.onnx 7f76ad5f35035f25630075699c6c942a2c0c05ff42cb398f966f3c256d148e1e
  download_model_file tokenizer.model 07d4e5a63840a53ab2d4d106d2874768143fb3fbdd47938b3910d2da05bfb0a9
  download_model_file vocab.txt ae61c9b743cb47c04ce6fb130444210646ed0f40c953c77ee1855185960af94f
  ln -sfn encoder.int8.onnx "$MODEL_DIR/encoder.onnx"
  ln -sfn encoder.int8.onnx.data "$MODEL_DIR/encoder.onnx.data"
  ln -sfn decoder_joint.int8.onnx "$MODEL_DIR/decoder_joint.onnx"
}

install_binary() {
  print_header "OmaType"
  print_status "Building the optimized Parakeet binary"
  (cd "$ROOT_DIR" && RUSTFLAGS='-C target-cpu=native' cargo build --release --features parakeet --bin voxtype)
  mkdir -p "$BIN_DIR"
  install -m 0755 "$ROOT_DIR/target/release/voxtype" "$BIN_DIR/omatype"
  rm -f -- "$BIN_DIR/voxtype"
  print_success "Installed $BIN_DIR/omatype"
}

install_config() {
  mkdir -p "$CONFIG_DIR"
  if [[ -f "$CONFIG_DIR/config.toml" ]]; then
    print_success "Kept existing $CONFIG_DIR/config.toml"
  else
    install -m 0644 "$ROOT_DIR/contrib/omarchy/config.toml" "$CONFIG_DIR/config.toml"
    print_success "Installed the hybrid Home-key configuration"
  fi
}

install_service() {
  mkdir -p "$SERVICE_DIR"
  local service_file="$SERVICE_DIR/omatype.service"
  systemctl --user disable --now voxtype.service >/dev/null 2>&1 || true
  rm -f -- "$SERVICE_DIR/voxtype.service"
  {
    printf '%s\n' '[Unit]'
    printf '%s\n' 'Description=OmaType local voice-to-text daemon'
    printf '%s\n' 'PartOf=graphical-session.target'
    printf '%s\n' 'After=graphical-session.target'
    printf '\n%s\n' '[Service]'
    printf '%s\n' 'Type=simple'
    printf 'ExecStart=%s daemon\n' "$BIN_DIR/omatype"
    printf '%s\n' 'Restart=on-failure'
    printf '%s\n' 'RestartSec=5'
    printf '%s\n' 'Environment=XDG_RUNTIME_DIR=%t'
    printf '\n%s\n' '[Install]'
    printf '%s\n' 'WantedBy=graphical-session.target'
  } > "$service_file"
  systemctl --user daemon-reload
  systemctl --user enable omatype.service
  systemctl --user restart omatype.service
  print_success "OmaType daemon enabled and started"
}

install_plugin() {
  if ! command -v omarchy >/dev/null 2>&1; then
    print_warning "Omarchy is not installed; skipped the bar plugin"
    return
  fi

  mkdir -p "$PLUGIN_DIR"
  install -m 0644 "$ROOT_DIR/contrib/omarchy/omatype/manifest.json" "$PLUGIN_DIR/manifest.json"
  install -m 0644 "$ROOT_DIR/contrib/omarchy/omatype/Panel.qml" "$PLUGIN_DIR/Panel.qml"
  omarchy plugin validate "$PLUGIN_DIR"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable local.omatype --before omarchy.bluetooth >/dev/null 2>&1 \
    || omarchy bar put local.omatype --before omarchy.bluetooth
  print_success "Added OmaType to the Omarchy bar"
}

print_header "Installing OmaType"
remove_upstream_voxtype
install_dependencies
install_binary
install_model
install_config
install_service
install_plugin

printf '\n'
print_success "OmaType is ready"
print_dim "Tap Home to begin/end an accurate recording. Hold Home for two seconds to type live."
if ! grep -Eq '^[[:space:]]*home[[:space:]]*=[[:space:]]*f13([[:space:]]|$)' /etc/keyd/default.conf 2>/dev/null; then
  print_warning "Map Home to F13 in keyd so the trigger does not also reach focused applications."
  print_dim "Add 'home = f13' under [main] in /etc/keyd/default.conf, then run: sudo keyd reload"
fi
