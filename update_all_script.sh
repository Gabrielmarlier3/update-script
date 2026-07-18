#!/usr/bin/env bash

set -u -o pipefail

CLEAN=0
FIRMWARE=0
RESULTS=()

if [[ -t 1 ]] && tput setaf 1 >/dev/null 2>&1; then
    BOLD=$(tput bold) RED=$(tput setaf 1) GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3) BLUE=$(tput setaf 4) RESET=$(tput sgr0)
else
    BOLD='' RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

usage() {
    cat <<EOF
Uso: ${0##*/} [opções]

Atualiza tudo: sistema (nala/apt), flatpak, snap, brew, asdf, rustup,
uv tools, oh-my-zsh, Discord, Docker Desktop, Bruno, Insomnia, Calibre
e AWS CLI.

Opções:
  --clean      limpeza (autoremove do apt, runtimes flatpak sem uso,
               brew cleanup, revisões antigas de snap)
  --firmware   inclui atualização de firmware (fwupd)
  -h, --help   mostra esta ajuda
EOF
}

has() { command -v "$1" >/dev/null 2>&1; }

run_step() {
    local name=$1 fn=$2 req=${3-} start dur
    if [[ -n $req ]]; then
        if [[ $req == /* ]]; then
            [[ -e $req ]] || { RESULTS+=("PULADO|$name"); return 0; }
        else
            has "$req" || { RESULTS+=("PULADO|$name"); return 0; }
        fi
    fi
    printf '\n%s==> %s%s\n' "${BOLD}${BLUE}" "$name" "$RESET"
    start=$SECONDS
    if "$fn"; then
        dur=$((SECONDS - start))
        RESULTS+=("OK|$name|${dur}s")
    else
        dur=$((SECONDS - start))
        RESULTS+=("FALHOU|$name|${dur}s")
    fi
}

install_deb() {
    local url=$1 deb rc
    deb=$(mktemp --suffix=.deb)
    curl -fSL --progress-bar -o "$deb" "$url" && sudo apt install -y "$deb"
    rc=$?
    rm -f "$deb"
    return "$rc"
}

update_deb_app() {
    local pkg=$1 latest=$2 url=$3 installed
    installed=$(dpkg-query -W -f '${Version}' "$pkg" 2>/dev/null) || return 1
    if dpkg --compare-versions "$installed" ge "$latest"; then
        echo "$pkg já está na versão mais recente ($installed)."
        return 0
    fi
    echo "Atualizando $pkg $installed -> $latest"
    install_deb "$url"
}

system_updates() {
    if has nala; then
        sudo nala upgrade --full -y
        return
    fi
    { sudo apt update && sudo apt dist-upgrade -y; } || return 1
    ((CLEAN)) || return 0
    sudo apt autoremove --purge -y
}

flatpak_updates() {
    flatpak update -y || return 1
    ((CLEAN)) || return 0
    flatpak uninstall --unused -y
}

snap_updates() {
    sudo snap refresh || return 1
    ((CLEAN)) || return 0
    local name rev
    while read -r name rev; do
        sudo snap remove "$name" --revision="$rev" || return 1
    done < <(LC_ALL=C snap list --all | awk '/disabled/{print $1, $3}')
}

brew_updates() {
    { brew update && brew upgrade; } || return 1
    ((CLEAN)) || return 0
    brew cleanup --prune=all
}

asdf_updates() {
    asdf plugin update --all
}

asdf_report() {
    "$HOME/bin/asdf_plugins_updates"
}

rustup_updates() {
    rustup update
}

uv_tool_updates() {
    uv tool upgrade --all
}

omz_update() {
    ZSH="$HOME/.oh-my-zsh" zsh "$HOME/.oh-my-zsh/tools/upgrade.sh"
}

discord_update() {
    local redirect latest
    redirect=$(curl -fsSI -o /dev/null -w '%{redirect_url}' --max-time 15 \
        'https://discord.com/api/download?platform=linux&format=deb') || return 1
    latest=$(grep -oPm1 'discord-\K[0-9.]+(?=\.deb)' <<<"$redirect") || return 1
    update_deb_app discord "$latest" "$redirect"
}

docker_desktop_update() {
    local appcast latest url
    appcast=$(curl -fsSL --max-time 15 \
        'https://desktop.docker.com/linux/main/amd64/appcast.xml') || return 1
    latest=$(grep -oPm1 'sparkle:shortVersionString="\K[0-9.]+' <<<"$appcast") || return 1
    url=$(grep -oPm1 'enclosure url="\K[^"]+' <<<"$appcast") || return 1
    update_deb_app docker-desktop "$latest" "$url"
}

bruno_update() {
    local api latest url
    api=$(curl -fsS --max-time 15 \
        'https://api.github.com/repos/usebruno/bruno/releases/latest') || return 1
    latest=$(grep -oPm1 '"tag_name":\s*"v\K[0-9.]+' <<<"$api") || return 1
    url=$(grep -oPm1 '"browser_download_url":\s*"\K[^"]+_amd64_linux\.deb' <<<"$api") || return 1
    update_deb_app bruno "$latest" "$url"
}

insomnia_update() {
    local redirect latest
    redirect=$(curl -fsSI -o /dev/null -w '%{redirect_url}' --max-time 15 \
        'https://github.com/Kong/insomnia/releases/latest') || return 1
    latest=${redirect##*core@}
    [[ $latest =~ ^[0-9][0-9.]*$ ]] || return 1
    update_deb_app insomnia "$latest" \
        "https://github.com/Kong/insomnia/releases/download/core%40${latest}/Insomnia.Core-${latest}.deb"
}

calibre_update() {
    local installed latest
    installed=$(/opt/calibre/calibre --version 2>/dev/null | grep -oPm1 '\d+(\.\d+)+') || return 1
    latest=$(curl -fsSI --max-time 15 'https://github.com/kovidgoyal/calibre/releases/latest' \
        | grep -oiPm1 'location:.*?/tag/v\K[0-9.]+') || return 1
    if dpkg --compare-versions "$installed" ge "$latest"; then
        echo "Calibre já está na versão mais recente ($installed)."
        return 0
    fi
    echo "Atualizando Calibre $installed -> $latest"
    curl -fsSL --max-time 600 'https://download.calibre-ebook.com/linux-installer.sh' | sudo sh /dev/stdin
}

aws_cli_update() {
    local installed latest tmp rc
    installed=$("$HOME/.local/bin/aws" --version 2>/dev/null | grep -oPm1 'aws-cli/\K[0-9.]+') || return 1
    latest=$(curl -fsS --max-time 15 'https://api.github.com/repos/aws/aws-cli/tags?per_page=1' \
        | grep -oPm1 '"name":\s*"\K[0-9.]+') || return 1
    if dpkg --compare-versions "$installed" ge "$latest"; then
        echo "AWS CLI já está na versão mais recente ($installed)."
        return 0
    fi
    echo "Atualizando AWS CLI $installed -> $latest"
    tmp=$(mktemp -d)
    curl -fSL --progress-bar -o "$tmp/awscliv2.zip" \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${latest}.zip" \
        && unzip -q "$tmp/awscliv2.zip" -d "$tmp" \
        && "$tmp/aws/install" --update --install-dir "$HOME/.local/aws-cli" --bin-dir "$HOME/.local/bin"
    rc=$?
    rm -rf "$tmp"
    return "$rc"
}

firmware_updates() {
    sudo fwupdmgr refresh --force
    sudo fwupdmgr update -y --no-reboot-check
    local rc=$?
    # fwupdmgr retorna 2 quando não há updates
    [[ $rc -eq 2 ]] && rc=0
    return "$rc"
}

summary() {
    local r status name dur color falhas=0
    printf '\n%s==> Resumo%s\n' "${BOLD}${BLUE}" "$RESET"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r status name dur <<<"$r"
        case $status in
            OK) color=$GREEN ;;
            FALHOU) color=$RED; falhas=$((falhas + 1)) ;;
            *) color=$YELLOW ;;
        esac
        printf '  %s%-7s%s %s %s\n' "$color" "$status" "$RESET" "$name" "${dur:+($dur)}"
    done
    ((falhas == 0))
}

main() {
    while (($#)); do
        case $1 in
            --clean) CLEAN=1 ;;
            --firmware) FIRMWARE=1 ;;
            -h|--help) usage; exit 0 ;;
            *) printf 'Opção desconhecida: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done

    sudo -v || exit 1
    { while sudo -n true 2>/dev/null; do sleep 50; done; } &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
    trap 'exit 130' INT

    run_step "Sistema (nala/apt)" system_updates apt
    run_step "Flatpak" flatpak_updates flatpak
    run_step "Snap" snap_updates snap
    run_step "Homebrew" brew_updates brew
    run_step "asdf" asdf_updates asdf
    run_step "Rustup" rustup_updates rustup
    run_step "uv tools" uv_tool_updates uv
    run_step "Oh My Zsh" omz_update "$HOME/.oh-my-zsh/tools/upgrade.sh"
    run_step "Discord" discord_update discord
    run_step "Docker Desktop" docker_desktop_update /opt/docker-desktop
    run_step "Bruno" bruno_update bruno
    run_step "Insomnia" insomnia_update insomnia
    run_step "Calibre" calibre_update /opt/calibre
    run_step "AWS CLI" aws_cli_update "$HOME/.local/aws-cli"
    if ((FIRMWARE)); then
        run_step "Firmware (fwupd)" firmware_updates fwupdmgr
    fi
    run_step "asdf: versões disponíveis" asdf_report "$HOME/bin/asdf_plugins_updates"

    summary
}

main "$@"
