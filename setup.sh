#!/bin/bash


set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Этот пункт требует прав root. Запусти скрипт через sudo.${NC}"
        return 1
    fi
}

ensure_ufw() {
    if ! command -v ufw &>/dev/null; then
        echo -e "${YELLOW}[*] ufw не найден, устанавливаю...${NC}"
        apt-get update -qq && apt-get install -y ufw
    fi
    # Включить ufw если выключен
    if ufw status | grep -q "Status: inactive"; then
        echo -e "${YELLOW}[*] ufw неактивен, включаю...${NC}"
        ufw --force enable
    fi
}

open_tcp_ports() {
    require_root || return
    ensure_ufw

    echo -e "${CYAN}Введи порты через запятую без пробелов [по умолчанию: 443,80,2222,2002]:${NC}"
    read -r input
    local ports="${input:-443,80,2222,2002}"

    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="${port// /}"
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            ufw allow "${port}/tcp" > /dev/null
            echo -e "${GREEN}[+] TCP ${port} открыт${NC}"
        else
            echo -e "${RED}[!] Пропускаю некорректный порт: '${port}'${NC}"
        fi
    done
    ufw reload > /dev/null
}

open_udp_ports() {
    require_root || return
    ensure_ufw

    echo -e "${CYAN}Введи порты через запятую без пробелов [по умолчанию: 443,80,2222,2002]:${NC}"
    read -r input
    local ports="${input:-443,80,2222,2002}"

    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="${port// /}"
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            ufw allow "${port}/udp" > /dev/null
            echo -e "${GREEN}[+] UDP ${port} открыт${NC}"
        else
            echo -e "${RED}[!] Пропускаю некорректный порт: '${port}'${NC}"
        fi
    done
    ufw reload > /dev/null
}

open_port_for_ip() {
    require_root || return
    ensure_ufw

    echo -e "${CYAN}Порт (например 8443):${NC}"
    read -r port
    port="${port// /}"

    echo -e "${CYAN}IP-адрес источника (например 1.2.3.4 или 1.2.3.4/32):${NC}"
    read -r ip

    echo -e "${CYAN}Протокол: 1) tcp  2) udp  3) оба${NC}"
    read -r proto_choice

    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "${RED}[!] Некорректный порт.${NC}"; return
    fi

    case "$proto_choice" in
        1)
            ufw allow from "$ip" to any port "$port" proto tcp > /dev/null
            echo -e "${GREEN}[+] TCP ${port} открыт для ${ip}${NC}"
            ;;
        2)
            ufw allow from "$ip" to any port "$port" proto udp > /dev/null
            echo -e "${GREEN}[+] UDP ${port} открыт для ${ip}${NC}"
            ;;
        3)
            ufw allow from "$ip" to any port "$port" proto tcp > /dev/null
            ufw allow from "$ip" to any port "$port" proto udp > /dev/null
            echo -e "${GREEN}[+] TCP+UDP ${port} открыт для ${ip}${NC}"
            ;;
        *)
            echo -e "${RED}[!] Некорректный выбор протокола.${NC}"; return
            ;;
    esac
    ufw reload > /dev/null
}

change_ssh_port() {
    require_root || return

    local sshd_config="/etc/ssh/sshd_config"
    local current_port
    current_port=$(grep -E "^Port " "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "22")

    echo -e "${CYAN}Текущий SSH-порт: ${BOLD}${current_port}${NC}"
    echo -e "${CYAN}Введи новый порт:${NC}"
    read -r new_port
    new_port="${new_port// /}"

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
        echo -e "${RED}[!] Некорректный порт.${NC}"; return
    fi

    # Обновить sshd_config
    if grep -qE "^#?Port " "$sshd_config"; then
        sed -i "s/^#\?Port .*/Port ${new_port}/" "$sshd_config"
    else
        echo "Port ${new_port}" >> "$sshd_config"
    fi

    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "${new_port}/tcp" > /dev/null
        ufw delete allow "${current_port}/tcp" > /dev/null 2>&1 || true
        ufw reload > /dev/null
        echo -e "${GREEN}[+] ufw: TCP ${new_port} открыт, TCP ${current_port} закрыт${NC}"
    fi

    systemctl restart sshd
    echo -e "${GREEN}[+] SSH-порт изменён с ${current_port} на ${new_port}. sshd перезапущен.${NC}"
    echo -e "${YELLOW}[!] Не закрывай текущую сессию — проверь подключение на новом порту!${NC}"
}

block_icmp() {
    require_root || return

    local rules_file="/etc/ufw/before.rules"

    if grep -q "drop ICMP echo-request" "$rules_file" 2>/dev/null; then
        echo -e "${YELLOW}[~] Блокировка ICMP уже настроена в ${rules_file}${NC}"
    else
        sed -i '/^COMMIT$/i # drop ICMP echo-request\n-A ufw-before-input -p icmp --icmp-type echo-request -j DROP' "$rules_file"
        echo -e "${GREEN}[+] ICMP echo-request заблокирован в before.rules${NC}"
    fi

    sysctl -w net.ipv4.icmp_echo_ignore_all=1 > /dev/null
    if ! grep -q "icmp_echo_ignore_all" /etc/sysctl.conf; then
        echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf
    else
        sed -i 's/^net.ipv4.icmp_echo_ignore_all.*/net.ipv4.icmp_echo_ignore_all = 1/' /etc/sysctl.conf
    fi

    if command -v ufw &>/dev/null; then
        ufw reload > /dev/null 2>&1 || true
    fi

    echo -e "${GREEN}[+] Ping на сервер отключён (sysctl + ufw before.rules)${NC}"
}

disable_password_auth() {
    require_root || return

    local sshd_config="/etc/ssh/sshd_config"

    echo -e "${YELLOW}[!] Убедись, что у тебя настроен SSH-ключ, иначе потеряешь доступ!${NC}"
    echo -e "${CYAN}Продолжить? (yes/no):${NC}"
    read -r confirm
    [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}Отменено.${NC}" && return

    declare -A directives=(
        ["PasswordAuthentication"]="no"
        ["ChallengeResponseAuthentication"]="no"
        ["UsePAM"]="no"
        ["PermitRootLogin"]="prohibit-password"
    )

    for key in "${!directives[@]}"; do
        val="${directives[$key]}"
        if grep -qE "^#?${key} " "$sshd_config"; then
            sed -i "s/^#\?${key} .*/${key} ${val}/" "$sshd_config"
        else
            echo "${key} ${val}" >> "$sshd_config"
        fi
        echo -e "${GREEN}[+] ${key} = ${val}${NC}"
    done

    systemctl restart sshd
    echo -e "${GREEN}[+] Вход по паролю отключён. sshd перезапущен.${NC}"
}

run_realitlscanner() {
    require_root || return

    local bin_path="/usr/local/bin/RealityScanner"
    local tmp_dir="/tmp/realitlscanner_install"

    if [[ ! -x "$bin_path" ]]; then
        echo -e "${YELLOW}[*] RealityScanner не найден. Устанавливаю...${NC}"

        local arch
        arch=$(uname -m)
        case "$arch" in
            x86_64)   arch_tag="amd64" ;;
            aarch64)  arch_tag="arm64" ;;
            *)        echo -e "${RED}[!] Неподдерживаемая архитектура: ${arch}${NC}"; return ;;
        esac

        echo -e "${CYAN}[*] Получаю последний релиз...${NC}"
        local latest_url
        latest_url=$(curl -fsSL \
            "https://api.github.com/repos/XTLS/RealiTLScanner/releases/latest" \
            | grep "browser_download_url" \
            | grep -i "linux.*${arch_tag}" \
            | head -1 \
            | cut -d '"' -f4)

        if [[ -z "$latest_url" ]]; then
            echo -e "${RED}[!] Не удалось получить URL релиза. Проверь: https://github.com/XTLS/RealiTLScanner/releases${NC}"
            return
        fi

        mkdir -p "$tmp_dir"
        echo -e "${CYAN}[*] Загружаю: ${latest_url}${NC}"
        curl -fsSL -o "${tmp_dir}/scanner" "$latest_url"
        chmod +x "${tmp_dir}/scanner"
        mv "${tmp_dir}/scanner" "$bin_path"
        rm -rf "$tmp_dir"
        echo -e "${GREEN}[+] RealityScanner установлен в ${bin_path}${NC}"
    else
        echo -e "${GREEN}[*] RealityScanner уже установлен.${NC}"
    fi

    echo -e "${CYAN}Введи адрес для сканирования (например: example.com:443):${NC}"
    read -r target
    [[ -z "$target" ]] && echo -e "${RED}[!] Адрес не введён.${NC}" && return

    echo -e "${CYAN}[*] Запускаю сканирование...${NC}"
    "$bin_path" -addr "$target"
}

show_menu() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       Server Hardening & Port Setup      ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}1.${NC} Открыть порты TCP"
    echo -e "  ${CYAN}2.${NC} Открыть порты UDP"
    echo -e "  ${CYAN}3.${NC} Открыть порт для IP"
    echo -e "  ${CYAN}4.${NC} Сменить SSH-порт"
    echo -e "  ${CYAN}5.${NC} Заблокировать ICMP (ping)"
    echo -e "  ${CYAN}6.${NC} Закрыть вход по паролю"
    echo -e "  ${CYAN}7.${NC} Запустить RealiTLScanner"
    echo -e "  ${CYAN}0.${NC} Выход"
    echo ""
    echo -ne "${BOLD}Выбор: ${NC}"
}

main() {
    while true; do
        show_menu
        read -r choice
        echo ""
        case "$choice" in
            1) open_tcp_ports ;;
            2) open_udp_ports ;;
            3) open_port_for_ip ;;
            4) change_ssh_port ;;
            5) block_icmp ;;
            6) disable_password_auth ;;
            7) run_realitlscanner ;;
            0) echo -e "${GREEN}Выход.${NC}"; exit 0 ;;
            *) echo -e "${RED}[!] Неверный выбор.${NC}" ;;
        esac
        echo ""
        echo -ne "${YELLOW}Нажми Enter для возврата в меню...${NC}"
        read -r
    done
}

main