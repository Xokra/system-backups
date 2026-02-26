
#!/bin/bash

set -euo pipefail


RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'


log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }

log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

detect_platform() {
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || { [[ -f /proc/version ]] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; }; then
        echo "wsl"
    elif [[ $(uname) == "Darwin" ]]; then
        echo "mac"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

translate_package() {
    local platform=$1 package=$2
    local arch_only="alsa-utils pulsemixer brightnessctl polybar feh xsel xclip xorg-xrandr i3-wm i3status i3lock dmenu dex xss-lock network-manager-applet mlocate autotiling picom"
    if [[ "$platform" != "arch" ]]; then
        for ap in $arch_only; do

            [[ "$ap" == "$package" ]] && echo "" && return

        done

    fi

    case "$platform-$package" in

        "wsl-python-pip")   echo "python3-pip" ;;

        "arch-python-pip")  echo "python-pip" ;;

        "mac-python-pip")   echo "python" ;;
        "wsl-nodejs")       echo "nodejs npm" ;;
        "mac-nodejs")       echo "node" ;;
        "arch-nodejs")      echo "nodejs npm" ;;
        "wsl-fd")           echo "fd-find" ;;
        "mac-fd"|"arch-fd") echo "fd" ;;
        "wsl-lazygit")      echo "__lazygit_manual__" ;;
        "wsl-discord"|"wsl-anki") echo "" ;;
        "arch-libreoffice") echo "libreoffice-fresh" ;;
        "wsl-libreoffice"|"mac-libreoffice") echo "libreoffice" ;;
        "wsl-rustup"|"mac-rustup"|"arch-rustup") echo "__rustup_manual__" ;;
        *) echo "$package" ;;
    esac
}

bootstrap_package_managers() {
    local platform=$1
    case $platform in
        "mac")
            if ! command -v brew >/dev/null 2>&1; then
                log_info "🍺 Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { log_error "Homebrew install failed"; return 1; }

                eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
            fi ;;
        "arch")
            if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
                log_info "🏗️ Installing yay..."
                sudo pacman -S --noconfirm git base-devel
                local orig=$(pwd) tmp="/tmp/yay-install-$$"
                mkdir -p "$tmp" && cd "$tmp"
                if git clone https://aur.archlinux.org/yay.git && cd "$tmp/yay"; then
                    makepkg -si --noconfirm || { cd "$orig"; rm -rf "$tmp"; return 1; }

                else
                    cd "$orig"; rm -rf "$tmp"; return 1
                fi
                cd "$orig"; rm -rf "$tmp"
                log_success "✅ yay installed"

            fi ;;
        "wsl") log_info "🐧 Using apt" ;;

    esac
}


install_nerd_fonts() {

    local platform=$1
    case $platform in
        "wsl")  fc-list 2>/dev/null | grep -qi "meslo" && { log_success "✅ Meslo already installed"; return 0; } ;;

        "mac")  ls ~/Library/Fonts/Meslo* 2>/dev/null | grep -q . && { log_success "✅ Meslo already installed"; return 0; } ;;
        "arch") fc-list 2>/dev/null | grep -qi "meslo" && { log_success "✅ Meslo already installed"; return 0; } ;;

    esac
    log_info "Installing Meslo Nerd Font..."

    local version; version=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true)
    version="${version:-v3.2.1}"
    local tmp="/tmp/nerd-fonts-$$"
    mkdir -p "$tmp" && cd "$tmp"

    if curl -fsSL -o "$tmp/Meslo.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/$version/Meslo.zip" 2>/dev/null; then
        case $platform in
            "wsl")
                unzip -q Meslo.zip "*.ttf" 2>/dev/null && ls *.ttf >/dev/null 2>&1 || true
                local font_ok=false
                for win_dir in "/mnt/c/Windows/Fonts" "/mnt/c/Users/$USER/AppData/Local/Microsoft/Windows/Fonts"; do
                    mkdir -p "$win_dir" 2>/dev/null && cp *.ttf "$win_dir/" 2>/dev/null && log_success "✅ Fonts → $win_dir" && font_ok=true && break
                done
                if [[ "$font_ok" != true ]]; then
                    mkdir -p ~/.local/share/fonts && cp *.ttf ~/.local/share/fonts/ && fc-cache -fv >/dev/null 2>&1 || true

                    log_warning "⚠️ Fonts installed locally. Install manually to Windows for Alacritty."
                fi ;;
            "mac")
                unzip -q Meslo.zip "*.ttf" 2>/dev/null && mkdir -p ~/Library/Fonts && cp *.ttf ~/Library/Fonts/
                log_success "✅ Fonts → ~/Library/Fonts" ;;

            "arch")
                mkdir -p ~/.local/share/fonts && unzip -q Meslo.zip -d ~/.local/share/fonts/ && fc-cache -fv >/dev/null 2>&1
                log_success "✅ Fonts installed + cache updated" ;;
        esac
    else
        log_error "❌ Could not download font archive"
    fi
    cd - >/dev/null && rm -rf "$tmp" 2>/dev/null || true
}


configure_zsh() {
    command -v zsh >/dev/null 2>&1 || { log_warning "⚠️ zsh not found"; return 0; }

    local zsh_path; zsh_path=$(which zsh)

    grep -q "^$zsh_path$" /etc/shells 2>/dev/null || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    local cur; cur=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || grep "^$USER:" /etc/passwd | cut -d: -f7)
    if [[ "$cur" == "$zsh_path" ]]; then
        log_success "✅ zsh already default"; return 0

    fi

    sudo chsh -s "$zsh_path" "$USER" && log_success "✅ Default shell set to zsh" || log_error "❌ Could not change shell"
}

install_all_packages() {
    local platform=$1
    local all_sys_packages=()

    local all_lang_packages=()


    # Load packages from backup files
    for file in config/packages.{curated,dotfile-deps,brew,aur}; do
        [[ -f "$file" && -s "$file" ]] || continue

        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue
            all_sys_packages+=("$pkg")

        done < "$file"
    done


    # ─────────────────────────────────────────────────────────────────────
    # FIX: Add current-platform tools that are ALWAYS needed on this OS.
    # This matters when restoring from a backup made on a DIFFERENT platform.
    # e.g. restoring on Arch from a WSL backup — Arch tools were never in

    # packages.curated because that file was built on WSL.

    # ─────────────────────────────────────────────────────────────────────
    local always_platform_tools=""

    case $platform in
        "arch")
            always_platform_tools="alsa-utils pulsemixer brightnessctl polybar feh alacritty xsel xclip firefox xorg-xrandr fontconfig i3-wm i3status i3lock dmenu dex xss-lock network-manager-applet mlocate discord anki libreoffice-fresh autotiling"
            ;;

        "wsl")
            always_platform_tools="fontconfig less libreoffice"
            ;;
        "mac")
            always_platform_tools="less"
            ;;
    esac
    for pkg in $always_platform_tools; do

        all_sys_packages+=("$pkg")
    done

    # ─────────────────────────────────────────────────────────────────────


    for file in config/packages.{cargo,pip,npm}; do
        [[ -f "$file" && -s "$file" ]] || continue
        local lang; lang=$(basename "$file" | cut -d. -f2)
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue
            all_lang_packages+=("$lang:$pkg")
        done < "$file"
    done


    # Translate + deduplicate system packages
    local translated_packages=() seen_packages=()
    local needs_lazygit_manual=false needs_rustup_manual=false

    for pkg in "${all_sys_packages[@]+"${all_sys_packages[@]}"}"; do
        local translated; translated=$(translate_package "$platform" "$pkg")
        [[ "$translated" == "__lazygit_manual__" ]] && { needs_lazygit_manual=true; continue; }

        [[ "$translated" == "__rustup_manual__"  ]] && { needs_rustup_manual=true;  continue; }
        [[ -z "$translated" ]] && continue
        for t_pkg in $translated; do
            if [[ ! " ${seen_packages[*]+"${seen_packages[*]}"} " =~ " ${t_pkg} " ]]; then
                translated_packages+=("$t_pkg")
                seen_packages+=("$t_pkg")

            fi

        done

    done

    if [[ ${#translated_packages[@]} -gt 0 ]]; then
        log_info "🔧 Checking and installing ${#translated_packages[@]} system packages..."
        local sys_failed=()
        case $platform in

            "arch")

                for pkg in "${translated_packages[@]}"; do
                    if pacman -Qi "$pkg" >/dev/null 2>&1; then
                        log_info "✓ Already installed: $pkg"
                    elif ! sudo pacman -S --noconfirm "$pkg" >/dev/null 2>&1; then
                        command -v yay  >/dev/null 2>&1 && yay  -S --noconfirm "$pkg" 2>/dev/null || \
                        command -v paru >/dev/null 2>&1 && paru -S --noconfirm "$pkg" 2>/dev/null || \

                        sys_failed+=("$pkg")
                    fi

                done ;;
            "mac")
                for pkg in "${translated_packages[@]}"; do
                    brew list "$pkg" >/dev/null 2>&1 && log_info "✓ Already installed: $pkg" || \
                    brew install "$pkg" 2>/dev/null || sys_failed+=("$pkg")
                done ;;
            "wsl")
                for pkg in "${translated_packages[@]}"; do
                    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && log_info "✓ Already installed: $pkg" || \
                    sudo apt install -y "$pkg" >/dev/null 2>&1 || sys_failed+=("$pkg")
                done ;;
        esac
        [[ ${#sys_failed[@]} -gt 0 ]] && log_warning "Failed: ${sys_failed[*]+"${sys_failed[*]}"}"
    fi

    # lazygit manual install (WSL)
    if [[ "$needs_lazygit_manual" == true ]]; then
        if ! command -v lazygit >/dev/null 2>&1; then

            local v; v=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | sed 's/^v//' || true)
            [[ -z "$v" ]] && { log_warning "⚠️ Could not get lazygit version"; } || {
                curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${v}/lazygit_${v}_Linux_x86_64.tar.gz"
                tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
                sudo install /tmp/lazygit /usr/local/bin
                log_success "✅ lazygit installed"
            }
        else
            log_info "✓ lazygit already installed"
        fi
    fi

    # rustup manual install
    if [[ "$needs_rustup_manual" == true ]] && ! command -v rustup >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

        source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
        log_success "✅ rustup installed"
    fi

    # fd symlink on WSL
    if [[ "$platform" == "wsl" ]] && command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        log_success "✅ fd symlinked from fdfind"
    fi


    # Rust

    if [[ -f config/packages.cargo && -s config/packages.cargo ]]; then
        if ! command -v cargo >/dev/null 2>&1; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source ~/.cargo/env 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
        else

            rustup update stable --no-self-update 2>/dev/null || true
        fi

    fi

    hash -r 2>/dev/null || true

    # Language packages
    if [[ ${#all_lang_packages[@]} -gt 0 ]]; then
        log_info "📦 Installing ${#all_lang_packages[@]} language packages..."

        local lang_failed=()
        for lang_pkg in "${all_lang_packages[@]+"${all_lang_packages[@]}"}"; do
            local lang="${lang_pkg%%:*}" pkg="${lang_pkg#*:}"

            case $lang in
                "cargo") command -v cargo >/dev/null 2>&1 && {

                    cargo install --list 2>/dev/null | grep -q "^$pkg " && log_info "✓ Already: cargo:$pkg" || \
                    cargo install "$pkg" 2>/dev/null || lang_failed+=("cargo:$pkg")

                } ;;
                "pip") command -v pip3 >/dev/null 2>&1 && {
                    pip3 show "$pkg" >/dev/null 2>&1 && log_info "✓ Already: pip:$pkg" || \
                    pip3 install --user "$pkg" 2>/dev/null || lang_failed+=("pip:$pkg")
                } ;;
                "npm") command -v npm >/dev/null 2>&1 && [[ "$pkg" != "lib" ]] && {
                    npm list -g "$pkg" >/dev/null 2>&1 && log_info "✓ Already: npm:$pkg" || \
                    npm install -g "$pkg" 2>/dev/null || lang_failed+=("npm:$pkg")

                } ;;

            esac
        done
        [[ ${#lang_failed[@]} -gt 0 ]] && log_warning "Failed lang packages: ${lang_failed[*]+"${lang_failed[*]}"}"
    fi

    # macOS cask/mas

    if [[ $platform == "mac" ]]; then
        for file in config/packages.{cask,mas}; do
            [[ -f "$file" && -s "$file" ]] || continue
            local type; type=$(basename "$file" | cut -d. -f2)
            while IFS= read -r pkg; do
                [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue
                case $type in
                    "cask") brew list --cask "$pkg" >/dev/null 2>&1 || brew install --cask "$pkg" 2>/dev/null || log_warning "Failed: $pkg" ;;
                    "mas")  command -v mas >/dev/null 2>&1 && { mas list 2>/dev/null | grep -q "^$pkg" || mas install "$pkg" 2>/dev/null || log_warning "Failed: $pkg"; } ;;
                esac

            done < "$file"
        done

    fi
}

main() {

    local script_dir; script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    cd "$script_dir" || { log_error "❌ Cannot cd to backup dir"; exit 1; }

    local platform; platform=$(detect_platform)
    [[ "$platform" == "unknown" ]] && { log_error "❌ Unsupported platform!"; exit 1; }

    log_info "🚀 Restoring system on platform: $platform"

    [[ -f config/system-info.txt ]] && { log_info "📋 Backup info:"; cat config/system-info.txt; echo; }

    bootstrap_package_managers "$platform" || { log_error "❌ Package manager bootstrap failed"; exit 1; }


    log_info "📦 Updating system packages..."
    case $platform in

        "wsl")  DEBIAN_FRONTEND=noninteractive sudo apt update >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive sudo apt upgrade -y >/dev/null 2>&1 || log_warning "⚠️ Update failed, continuing..." ;;
        "mac")  command -v brew >/dev/null && { brew update >/dev/null 2>&1 && brew upgrade >/dev/null 2>&1; } || log_warning "⚠️ brew update failed" ;;
        "arch") sudo pacman -Syu --noconfirm >/dev/null 2>&1 || log_warning "⚠️ Update failed, continuing..." ;;
    esac


    [[ $platform == "mac" ]] && ! command -v mas >/dev/null 2>&1 && brew install mas || true

    install_all_packages "$platform"

    # Restore zsh history from backup if present
    if [[ -f config/zsh_history && -s config/zsh_history ]]; then
        log_info "📜 Restoring zsh history..."

        if [[ -f "$HOME/.zsh_history" && -s "$HOME/.zsh_history" ]]; then
            sort -u config/zsh_history "$HOME/.zsh_history" > /tmp/merged_hist
            cp /tmp/merged_hist "$HOME/.zsh_history"
            rm -f /tmp/merged_hist

        else
            cp config/zsh_history "$HOME/.zsh_history"

        fi
        log_success "✅ History restored ($(wc -l < "$HOME/.zsh_history") lines)"
    fi

    log_info "🎨 Configuring fonts and shell..."
    install_nerd_fonts "$platform"
    configure_zsh


    echo
    log_success "✅ System restore completed!"

    echo
    log_info "📋 Manual steps remaining:"
    echo -e "${BLUE}  1.${NC} Restart terminal to apply changes"
    echo -e "${BLUE}  2.${NC} Restore your dotfiles"
    echo -e "${BLUE}  3.${NC} Verify shell: ${GREEN}echo \$SHELL${NC}"

    echo -e "${BLUE}  4.${NC} Install Mason deps: ${GREEN}:MasonInstall <package>${NC}"
    [[ "$platform" == "wsl" ]] && echo -e "${YELLOW}  WSL: Use 'MesloLGLDZ Nerd Font' in Alacritty config${NC}"
}


main "$@"
