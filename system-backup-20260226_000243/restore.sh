#!/bin/bash
set -euo pipefail


RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }


detect_platform() {
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/version ]] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        echo "wsl"

    elif [[ $(uname) == "Darwin" ]]; then

        echo "mac"
    elif [[ -f /etc/arch-release ]]; then

        echo "arch"

    else
        echo "unknown"

    fi
}


# Cross-platform package name translation

translate_package() {
    local platform=$1 package=$2

    # Arch-only packages — skip entirely on WSL and macOS

    local arch_only="alsa-utils pulsemixer brightnessctl polybar feh xsel xclip xorg-xrandr i3-wm i3status i3lock dmenu dex xss-lock network-manager-applet mlocate autotiling picom xss-lock"
    if [[ "$platform" != "arch" ]]; then
        for ap in $arch_only; do
            if [[ "$ap" == "$package" ]]; then

                echo ""
                return
            fi
        done
    fi

    case "$platform-$package" in
        # Python pip differences
        "wsl-python-pip") echo "python3-pip" ;;
        "arch-python-pip") echo "python-pip" ;;
        "mac-python-pip") echo "python" ;;


        # Node.js differences
        "wsl-nodejs") echo "nodejs npm" ;;
        "mac-nodejs") echo "node" ;;

        "arch-nodejs") echo "nodejs npm" ;;

        # fd differences (fd-find on Ubuntu/Debian)
        "wsl-fd") echo "fd-find" ;;
        "mac-fd") echo "fd" ;;
        "arch-fd") echo "fd" ;;

        # lazygit not in apt — flag for special handling

        "wsl-lazygit") echo "__lazygit_manual__" ;;


        # ripgrep differences
        "wsl-ripgrep") echo "ripgrep" ;;

        # discord not available on WSL meaningfully
        "wsl-discord") echo "" ;;
        "wsl-anki") echo "" ;;

        # libreoffice name differences
        "arch-libreoffice") echo "libreoffice-fresh" ;;
        "wsl-libreoffice") echo "libreoffice" ;;
        "mac-libreoffice") echo "libreoffice" ;;


        # rustup — handled separately via curl installer
        "wsl-rustup") echo "__rustup_manual__" ;;
        "mac-rustup") echo "__rustup_manual__" ;;

        "arch-rustup") echo "__rustup_manual__" ;;

        # Default: return original
        *) echo "$package" ;;
    esac
}


# FIXED: Ensure package managers are installed before using them
bootstrap_package_managers() {
    local platform=$1

    
    case $platform in

        "mac")
            # Install Homebrew if not present
            if ! command -v brew >/dev/null 2>&1; then

                log_info "🍺 Installing Homebrew..."


                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                    log_error "Failed to install Homebrew"
                    return 1


                }
                # Add to PATH for current session
                eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true

            fi
            ;;
            
        "arch")
            # Install AUR helper if not present
            if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
                log_info "🏗️ Installing yay (AUR helper)..."
                sudo pacman -S --noconfirm git base-devel || {
                    log_error "Failed to install AUR dependencies"
                    return 1
                }

                

                # FIXED: Save current directory and use absolute paths
                local original_dir=$(pwd)
                local temp_dir="/tmp/yay-install-$$"


                
                mkdir -p "$temp_dir" && cd "$temp_dir" || {
                    log_error "Failed to create temp directory"
                    return 1
                }


                
                if git clone https://aur.archlinux.org/yay.git && cd yay; then
                    makepkg -si --noconfirm || {

                        log_error "Failed to build yay"
                        cd "$original_dir"

                        rm -rf "$temp_dir"

                        return 1
                    }


                else

                    log_error "Failed to clone yay repository"
                    cd "$original_dir"
                    rm -rf "$temp_dir"

                    return 1
                fi
                

                # Return to original directory and cleanup
                cd "$original_dir"
                rm -rf "$temp_dir"

                log_success "✅ yay installed successfully"

            fi

            ;;


        "wsl")
            # WSL uses apt, which should be available by default
            log_info "🐧 Using apt package manager"
            ;;
    esac
}

install_nerd_fonts() {

    local platform=$1


    # Check if font already installed
    case $platform in
        "wsl")
            if fc-list 2>/dev/null | grep -qi "meslo" || ls /mnt/c/Windows/Fonts/Meslo* 2>/dev/null | grep -q .; then
                log_success "✅ Meslo Nerd Font already installed"

                return 0
            fi ;;
        "mac")
            if ls ~/Library/Fonts/Meslo* 2>/dev/null | grep -q .; then
                log_success "✅ Meslo Nerd Font already installed"
                return 0

            fi ;;
        "arch")
            if fc-list 2>/dev/null | grep -qi "meslo"; then
                log_success "✅ Meslo Nerd Font already installed"
                return 0

            fi ;;
    esac


    log_info "Installing Meslo Nerd Font..."


    

    local version=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' 2>/dev/null || echo "v3.2.1")
    local temp_dir="/tmp/nerd-fonts-$$"
    local font_installed=false
    
    mkdir -p "$temp_dir" && cd "$temp_dir" || { log_error "Failed to create temp directory"; return 1; }

    

    if wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/$version/Meslo.zip" 2>/dev/null; then

        case $platform in
            "wsl")
                if unzip -q Meslo.zip "*.ttf" 2>/dev/null && ls *.ttf >/dev/null 2>&1; then


                    # Try Windows directories first
                    for win_dir in "/mnt/c/Windows/Fonts" "/mnt/c/Users/$USER/AppData/Local/Microsoft/Windows/Fonts"; do

                        if [[ -d "$(dirname "$win_dir" 2>/dev/null)" ]]; then

                            mkdir -p "$win_dir" 2>/dev/null || true
                            if cp *.ttf "$win_dir/" 2>/dev/null; then

                                log_success "✅ Fonts installed to Windows: $win_dir"
                                font_installed=true
                                break
                            fi
                        fi

                    done
                    

                    if [[ "$font_installed" != true ]]; then
                        mkdir -p ~/.local/share/fonts 2>/dev/null && cp *.ttf ~/.local/share/fonts/ 2>/dev/null && fc-cache -fv >/dev/null 2>&1 && {
                            log_warning "⚠️ Fonts installed locally. For Windows Alacritty, install manually to Windows fonts."
                            font_installed=true


                        }
                    fi
                fi
                ;;

            "mac")


                if unzip -q Meslo.zip "*.ttf" 2>/dev/null && ls *.ttf >/dev/null 2>&1; then
                    mkdir -p ~/Library/Fonts && cp *.ttf ~/Library/Fonts/ && {
                        log_success "✅ Fonts installed to ~/Library/Fonts"
                        font_installed=true
                    }
                fi


                ;;
            "arch")

                mkdir -p ~/.local/share/fonts 2>/dev/null && unzip -q Meslo.zip -d ~/.local/share/fonts/ 2>/dev/null && fc-cache -fv >/dev/null 2>&1 && {

                    log_success "✅ Fonts installed and font cache updated"
                    font_installed=true
                }

                ;;
        esac
    else

        log_error "❌ Failed to download font archive"
    fi
    
    cd - >/dev/null 2>&1 && rm -rf "$temp_dir" 2>/dev/null || true
    
    if [[ "$font_installed" != true ]]; then
        log_error "❌ Font installation failed"
        return 1

    fi
}

configure_zsh() {
    log_info "Configuring Zsh as default shell..."

    if ! command -v zsh >/dev/null 2>&1; then

        log_warning "⚠️ Zsh not found, skipping shell configuration"
        return 0
    fi
    
    local zsh_path=$(which zsh)
    
    # Add zsh to /etc/shells if not present
    if ! grep -q "^$zsh_path$" /etc/shells 2>/dev/null; then

        echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null || {

            log_error "❌ Failed to add zsh to /etc/shells"

            return 1


        }
    fi
    
    # Change default shell if not already zsh — check /etc/passwd not $SHELL (env var won't update until re-login)
    local current_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || grep "^$USER:" /etc/passwd | cut -d: -f7)

    if [[ "$current_shell" == "$zsh_path" ]]; then
        log_success "✅ zsh is already the default shell"
        return 0
    fi

    log_info "Changing default shell to zsh (may require password)..."

    if sudo chsh -s "$zsh_path" "$USER" 2>/dev/null; then

        log_success "✅ Default shell changed to zsh. Restart terminal to apply."

    else
        log_error "❌ Failed to change default shell to zsh"


        return 1

        fi
    else

        log_success "✅ Zsh is already the default shell"

    fi

}



# FIXED: Collect, translate, dedupe and install in proper order
install_all_packages() {
    local platform=$1
    
    # Step 1: Collect all system packages from all sources
    local all_sys_packages=()
    local all_lang_packages=()
    
    # Collect system packages (curated + dotfile-deps + brew/aur)
    for file in config/packages.{curated,dotfile-deps,brew,aur}; do
        [[ -f "$file" && -s "$file" ]] || continue
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue
            all_sys_packages+=("$pkg")
        done < "$file"


    done
    
    # Collect language packages separately

    for file in config/packages.{cargo,pip,npm}; do

        [[ -f "$file" && -s "$file" ]] || continue


        local lang=$(basename "$file" | cut -d. -f2)
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue
            all_lang_packages+=("$lang:$pkg")
        done < "$file"
    done
    

    # Step 2: Translate and deduplicate system packages
    local translated_packages=()
    local seen_packages=()
    local needs_lazygit_manual=false
    local needs_rustup_manual=false

    for pkg in "${all_sys_packages[@]}"; do
        local translated=$(translate_package "$platform" "$pkg")
        # Handle special tokens

        if [[ "$translated" == "__lazygit_manual__" ]]; then

            needs_lazygit_manual=true
            continue
        fi
        if [[ "$translated" == "__rustup_manual__" ]]; then
            needs_rustup_manual=true

            continue
        fi
        # Skip empty (arch-only packages on other platforms)
        [[ -z "$translated" ]] && continue

        for t_pkg in $translated; do
            if [[ ! " ${seen_packages[*]} " =~ " ${t_pkg} " ]]; then

                translated_packages+=("$t_pkg")
                seen_packages+=("$t_pkg")
            fi
        done
    done


    # Step 3: Install system packages — check first, only install if missing
    if [[ ${#translated_packages[@]} -gt 0 ]]; then
        log_info "🔧 Checking and installing ${#translated_packages[@]} system packages..."
        local sys_failed=()

        case $platform in
            "arch")
                for pkg in "${translated_packages[@]}"; do

                    if pacman -Qi "$pkg" >/dev/null 2>&1; then

                        log_info "✓ Already installed: $pkg"
                    elif ! sudo pacman -S --noconfirm "$pkg" 2>/dev/null; then
                        if command -v yay >/dev/null && ! yay -S --noconfirm "$pkg" 2>/dev/null; then
                            command -v paru >/dev/null && ! paru -S --noconfirm "$pkg" 2>/dev/null && sys_failed+=("$pkg")
                        fi
                    fi
                done ;;
            "mac")
                for pkg in "${translated_packages[@]}"; do

                    if brew list "$pkg" >/dev/null 2>&1; then
                        log_info "✓ Already installed: $pkg"
                    else
                        brew install "$pkg" 2>/dev/null || sys_failed+=("$pkg")
                    fi
                done ;;

            "wsl")

                for pkg in "${translated_packages[@]}"; do
                    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                        log_info "✓ Already installed: $pkg"
                    else
                        sudo apt install -y "$pkg" 2>/dev/null || sys_failed+=("$pkg")
                    fi
                done ;;

        esac

        [[ ${#sys_failed[@]} -gt 0 ]] && log_warning "Failed system packages: ${sys_failed[*]}"
    fi

    # Handle lazygit manual install on WSL
    if [[ "$needs_lazygit_manual" == true ]] && ! command -v lazygit >/dev/null 2>&1; then
        log_info "📦 Installing lazygit manually..."
        local lg_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')
        curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${lg_version}/lazygit_${lg_version}_Linux_x86_64.tar.gz"
        tar xf /tmp/lazygit.tar.gz -C /tmp lazygit

        sudo install /tmp/lazygit /usr/local/bin
        log_success "✅ lazygit installed"
    elif [[ "$needs_lazygit_manual" == true ]]; then
        # Check if update needed
        local lg_latest=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')

        local lg_current=$(lazygit --version 2>/dev/null | grep -o 'version=[^,]*' | cut -d= -f2)
        if [[ -n "$lg_latest" && "$lg_latest" != "$lg_current" ]]; then
            log_info "📦 Updating lazygit $lg_current → $lg_latest..."

            curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${lg_latest}/lazygit_${lg_latest}_Linux_x86_64.tar.gz"
            tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
            sudo install /tmp/lazygit /usr/local/bin

            log_success "✅ lazygit updated to v${lg_latest}"
        else
            log_info "✓ lazygit already up to date (v${lg_current})"
        fi
    fi

    # Handle rustup manual install
    if [[ "$needs_rustup_manual" == true ]] && ! command -v rustup >/dev/null 2>&1; then
        log_info "🦀 Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        log_success "✅ rustup installed"
    elif [[ "$needs_rustup_manual" == true ]]; then
        log_info "✓ rustup already installed"

    fi

    # Handle fd symlink on WSL (fd-find → fd)
    if [[ "$platform" == "wsl" ]] && command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"

        log_success "✅ fd symlinked from fdfind"
    fi
    
    # Step 4: Verify and setup language package managers
    log_info "🔧 Verifying package managers..."
    

    # Install or update Rust if cargo packages exist

    if [[ -f config/packages.cargo && -s config/packages.cargo ]]; then
        if ! command -v cargo >/dev/null 2>&1; then
            log_info "🦀 Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source ~/.cargo/env 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
        else
            log_info "🦀 Rust already installed — updating..."
            rustup update stable --no-self-update 2>/dev/null || true
        fi
    fi

    


    # Refresh PATH to pick up newly installed tools
    hash -r 2>/dev/null || true

    
    # Step 5: Install language packages
    if [[ ${#all_lang_packages[@]} -gt 0 ]]; then


        log_info "📦 Installing ${#all_lang_packages[@]} language packages..."
        local lang_failed=()


        
        for lang_pkg in "${all_lang_packages[@]}"; do
            local lang="${lang_pkg%%:*}"

            local pkg="${lang_pkg#*:}"
            
            case $lang in
                "cargo")

                    if command -v cargo >/dev/null 2>&1; then
                        if cargo install --list 2>/dev/null | grep -q "^$pkg "; then

                            log_info "✓ Already installed: cargo:$pkg"

                        else

                            cargo install "$pkg" 2>/dev/null || lang_failed+=("cargo:$pkg")
                        fi

                    fi ;;
                "pip")

                    if command -v pip3 >/dev/null 2>&1; then
                        if pip3 show "$pkg" >/dev/null 2>&1; then
                            log_info "✓ Already installed: pip:$pkg"
                        else
                            pip3 install --user "$pkg" 2>/dev/null || lang_failed+=("pip:$pkg")
                        fi
                    fi ;;
                "npm")
                    if command -v npm >/dev/null 2>&1 && [[ "$pkg" != "lib" ]]; then

                        if npm list -g "$pkg" >/dev/null 2>&1; then
                            log_info "✓ Already installed: npm:$pkg"
                        else
                            npm install -g "$pkg" 2>/dev/null || lang_failed+=("npm:$pkg")
                        fi
                    fi ;;
            esac

        done

        
        [[ ${#lang_failed[@]} -gt 0 ]] && log_warning "Failed language packages: ${lang_failed[*]}"
    fi

    
    # Step 6: Install cask/mas packages (macOS only)
    if [[ $platform == "mac" ]]; then


        for file in config/packages.{cask,mas}; do

            [[ -f "$file" && -s "$file" ]] || continue

            local type=$(basename "$file" | cut -d. -f2)
            log_info "🍺 Installing $type packages..."
            
            while IFS= read -r pkg; do
                [[ -z "$pkg" || "$pkg" =~ ^[[:space:]]*# ]] && continue

                case $type in

                    "cask")
                        if brew list --cask "$pkg" >/dev/null 2>&1; then
                            log_info "✓ Already installed: $pkg"
                        else
                            brew install --cask "$pkg" 2>/dev/null || log_warning "Failed: $pkg"
                        fi ;;
                    "mas")
                        if command -v mas >/dev/null 2>&1; then
                            if mas list 2>/dev/null | grep -q "^$pkg"; then
                                log_info "✓ Already installed: mas:$pkg"
                            else
                                mas install "$pkg" 2>/dev/null || log_warning "Failed: $pkg"
                            fi
                        fi ;;
                esac
            done < "$file"
        done
    fi
}



main() {

    local platform=$(detect_platform)
    [[ "$platform" == "unknown" ]] && { log_error "❌ Unsupported platform!"; exit 1; }
    
    log_info "🚀 Restoring system on platform: $platform"
    [[ -f config/system-info.txt ]] && { log_info "📋 Backup info:"; cat config/system-info.txt; echo; }

    
    # FIXED: Bootstrap package managers FIRST
    log_info "🔧 Bootstrapping package managers..."


    if ! bootstrap_package_managers "$platform"; then
        log_error "❌ Failed to bootstrap package managers"

        exit 1


    fi


    

    # Update system

    log_info "📦 Updating system packages..."
    case $platform in
        "wsl") 

            sudo apt update >/dev/null 2>&1 && sudo apt upgrade -y >/dev/null 2>&1 || { log_warning "⚠️ System update failed, continuing..."; }
            ;;
        "mac") 

            if command -v brew >/dev/null; then
                brew update >/dev/null 2>&1 && brew upgrade >/dev/null 2>&1 || { log_warning "⚠️ Homebrew update failed, continuing..."; }

            fi

            ;;
        "arch") 
            sudo pacman -Syu --noconfirm >/dev/null 2>&1 || { log_warning "⚠️ System update failed, continuing..."; }
            ;;
    esac

    

    # Install mas early on macOS

    if [[ $platform == "mac" ]] && ! command -v mas >/dev/null 2>&1; then
        log_info "🏪 Installing mas (Mac App Store CLI)..."

        brew install mas || log_warning "Failed to install mas"
    fi


    
    # FIXED: Install all packages in proper order
    install_all_packages "$platform"
    
    # Post-install configuration
    log_info "🎨 Configuring fonts and shell..."
    local config_failed=0
    
    if ! install_nerd_fonts "$platform"; then

        ((config_failed++))


    fi

    


    if ! configure_zsh "$platform"; then

        ((config_failed++))
    fi
    
    # Final summary
    echo


    if [[ $config_failed -eq 0 ]]; then
        log_success "✅ System restore completed successfully!"
    else
        log_warning "⚠️ System restore completed with some issues"
    fi


    
    echo
    log_info "📋 Manual steps remaining:"
    echo -e "${BLUE}  1.${NC} Restart terminal/Alacritty to apply changes"

    echo -e "${BLUE}  2.${NC} Restore your dotfiles"
    echo -e "${BLUE}  3.${NC} Firefox: Settings > General > Startup > 'Open previous windows and tabs'"
    echo -e "${BLUE}  4.${NC} Verify shell: ${GREEN}echo \$SHELL${NC} (should show zsh path)"
    echo -e "${BLUE}  5.${NC} Install Mason dependencies: ${GREEN}:MasonInstall <package>${NC}"


    

    if [[ "$platform" == "wsl" ]]; then
        echo
        log_info "💡 WSL + Alacritty Notes:"
        echo -e "${YELLOW}  - If fonts don't appear, install manually to Windows fonts directory${NC}"
        echo -e "${YELLOW}  - Use 'MesloLGLDZ Nerd Font' in Alacritty config${NC}"


    fi
}

main "$@"
