#!/bin/bash


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

restart_ssh() {
    systemctl daemon-reload
    systemctl restart ssh.socket 2>/dev/null || true
    systemctl restart sshd 2>/dev/null || true
    if ! systemctl is-active --quiet ssh.socket 2>/dev/null &&        ! systemctl is-active --quiet sshd 2>/dev/null &&        ! systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "${RED}[!] SSH-сервис не запустился. Проверь: systemctl status sshd${NC}"
        return 1
    fi
}

ensure_ufw() {
    if ! command -v ufw &>/dev/null; then
        echo -e "${YELLOW}[*] ufw не найден, устанавливаю...${NC}"
        apt-get update -qq && apt-get install -y ufw
    fi
    if ufw status | grep -q "Status: inactive"; then
        echo -e "${YELLOW}[*] ufw неактивен, включаю...${NC}"
        ufw --force enable
    fi
}

open_ports() {
    require_root || return
    ensure_ufw

    echo -e "${CYAN}Протокол: 1) TCP  2) UDP  3) Оба [по умолчанию: 1]:${NC}"
    read -r proto_choice
    proto_choice="${proto_choice:-1}"

    case "$proto_choice" in
        1) local protos=("tcp") ;;
        2) local protos=("udp") ;;
        3) local protos=("tcp" "udp") ;;
        *) echo -e "${RED}[!] Некорректный выбор протокола.${NC}"; return ;;
    esac

    echo -e "${CYAN}Введи порты через запятую [по умолчанию: 80,443]:${NC}"
    read -r input
    local ports="${input:-80,443}"

    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="${port// /}"
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            for proto in "${protos[@]}"; do
                ufw allow "${port}/${proto}" > /dev/null
                echo -e "${GREEN}[+] ${proto^^} ${port} открыт${NC}"
            done
        else
            echo -e "${RED}[!] Пропускаю некорректный порт: '${port}'${NC}"
        fi
    done
    ufw reload > /dev/null
}

open_port_for_ip() {
    require_root || return
    ensure_ufw

    echo -e "${CYAN}IP-адрес источника (например 1.2.3.4 или 1.2.3.4/32):${NC}"
    read -r ip
    ip="${ip// /}"
    if [[ -z "$ip" ]]; then
        echo -e "${RED}[!] IP не может быть пустым.${NC}"; return
    fi

    echo -e "${CYAN}Протокол: 1) TCP  2) UDP  3) Оба [по умолчанию: 1]:${NC}"
    read -r proto_choice
    proto_choice="${proto_choice:-1}"

    case "$proto_choice" in
        1) local protos=("tcp") ;;
        2) local protos=("udp") ;;
        3) local protos=("tcp" "udp") ;;
        *) echo -e "${RED}[!] Некорректный выбор протокола.${NC}"; return ;;
    esac

    echo -e "${CYAN}Введи порты через запятую [по умолчанию: 80,443]:${NC}"
    read -r input
    local ports="${input:-80,443}"

    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="${port// /}"
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            for proto in "${protos[@]}"; do
                ufw allow from "$ip" to any port "$port" proto "$proto" > /dev/null
                echo -e "${GREEN}[+] ${proto^^} ${port} открыт для ${ip}${NC}"
            done
        else
            echo -e "${RED}[!] Пропускаю некорректный порт: '${port}'${NC}"
        fi
    done
    ufw reload > /dev/null
}

close_ports_for_ip() {
    require_root || return
    ensure_ufw

    echo -e "${CYAN}IP-адрес источника (например 1.2.3.4 или 1.2.3.4/32):${NC}"
    read -r ip
    ip="${ip// /}"
    if [[ -z "$ip" ]]; then
        echo -e "${RED}[!] IP не может быть пустым.${NC}"; return
    fi

    echo -e "${CYAN}Протокол: 1) TCP  2) UDP  3) Оба [по умолчанию: 1]:${NC}"
    read -r proto_choice
    proto_choice="${proto_choice:-1}"

    case "$proto_choice" in
        1) local protos=("tcp") ;;
        2) local protos=("udp") ;;
        3) local protos=("tcp" "udp") ;;
        *) echo -e "${RED}[!] Некорректный выбор протокола.${NC}"; return ;;
    esac

    echo -e "${CYAN}Введи порты через запятую [по умолчанию: 80,443]:${NC}"
    read -r input
    local ports="${input:-80,443}"

    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="${port// /}"
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            for proto in "${protos[@]}"; do
                if ufw delete allow from "$ip" to any port "$port" proto "$proto" > /dev/null 2>&1; then
                    echo -e "${GREEN}[+] ${proto^^} ${port} закрыт для ${ip}${NC}"
                else
                    echo -e "${YELLOW}[~] Правило ${proto^^} ${port} для ${ip} не найдено, пропускаю${NC}"
                fi
            done
        else
            echo -e "${RED}[!] Пропускаю некорректный порт: '${port}'${NC}"
        fi
    done
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

    restart_ssh
    echo -e "${GREEN}[+] SSH-порт изменён с ${current_port} на ${new_port}. SSH перезапущен.${NC}"
    echo -e "${YELLOW}[!] Не закрывай текущую сессию — проверь подключение на новом порту!${NC}"
}

block_icmp() {
    require_root || return

    local rules_file="/etc/ufw/before.rules"

    if [[ ! -f "$rules_file" ]]; then
        echo -e "${RED}[!] Файл ${rules_file} не найден. Установлен ли ufw?${NC}"
        return
    fi

    if grep -q "icmp-type echo-request -j DROP" "$rules_file" 2>/dev/null; then
        echo -e "${YELLOW}[~] Блокировка ICMP уже настроена в ${rules_file}${NC}"
        return
    fi

    sed -i 's/-A ufw-before-input -p icmp --icmp-type \(.*\) -j ACCEPT/-A ufw-before-input -p icmp --icmp-type \1 -j DROP/g' "$rules_file"
    sed -i 's/-A ufw-before-forward -p icmp --icmp-type \(.*\) -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type \1 -j DROP/g' "$rules_file"

    if ! grep -q "source-quench" "$rules_file"; then
        sed -i '/# ok icmp codes for INPUT/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$rules_file"
    fi

    echo -e "${GREEN}[+] Все ICMP-правила переключены на DROP в ${rules_file}${NC}"

    echo -e "${CYAN}[*] Перезагружаю ufw (disable && enable)...${NC}"
    ufw disable > /dev/null
    ufw --force enable > /dev/null
    echo -e "${GREEN}[+] ufw перезагружен. Ping на сервер отключён.${NC}"
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

    restart_ssh
    echo -e "${GREEN}[+] Вход по паролю отключён. sshd перезапущен.${NC}"
}

setup_ssl_cert() {
    require_root || return
    ensure_ufw

    # Параметры можно передать напрямую (для авто-сценариев) или ввести интерактивно
    local domain="${1:-}"
    local email="${2:-}"
    local port="${3:-}"

    if [[ -z "$domain" ]]; then
        echo -e "${CYAN}Домен (например node.mydomain.com):${NC}"
        read -r domain
        domain="${domain// /}"
    fi
    if [[ -z "$domain" ]]; then
        echo -e "${RED}[!] Домен не может быть пустым.${NC}"; return 1
    fi

    if [[ -z "$email" ]]; then
        echo -e "${CYAN}Email для уведомлений Let's Encrypt (напр. you@example.com):${NC}"
        read -r email
        email="${email// /}"
    fi
    if [[ -z "$email" || ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        echo -e "${RED}[!] Некорректный email.${NC}"; return 1
    fi

    if [[ -z "$port" ]]; then
        echo -e "${CYAN}Порт для HTTPS [по умолчанию: 8443]:${NC}"
        read -r input_port
        port="${input_port:-8443}"
    fi
    port="${port// /}"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "${RED}[!] Некорректный порт.${NC}"; return 1
    fi

    if ! command -v nginx &>/dev/null || ! command -v certbot &>/dev/null; then
        echo -e "${CYAN}[*] Устанавливаю nginx, certbot...${NC}"
        apt-get update -qq && apt-get install -y nginx certbot python3-certbot-nginx
    fi

    systemctl enable nginx --quiet
    systemctl start nginx

    ufw allow 80/tcp > /dev/null
    ufw reload > /dev/null
    echo -e "${GREEN}[+] Порт 80/tcp открыт (нужен certbot для выдачи и автопродления)${NC}"

    if ! command -v curl &>/dev/null; then apt-get install -y curl -qq; fi
    if ! command -v dig &>/dev/null; then apt-get install -y dnsutils -qq; fi

    echo -e "${CYAN}[*] Проверяю DNS для ${domain}...${NC}"
    local server_ip domain_ip
    server_ip=$(curl -4 -s --max-time 5 ifconfig.me)
    domain_ip=$(dig +short "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)

    if [[ -z "$server_ip" ]]; then
        echo -e "${YELLOW}[!] Не удалось получить внешний IP сервера (ifconfig.me недоступен).${NC}"
        echo -e "${CYAN}    Пропустить DNS-проверку и продолжить? (yes/no):${NC}"
        read -r skip_dns
        if [[ "$skip_dns" != "yes" ]]; then
            return 1
        fi
    elif [[ -z "$domain_ip" ]]; then
        echo -e "${RED}[!] Домен ${domain} не резолвится. Настрой A-запись DNS и повтори.${NC}"
        return 1
    elif [[ "$server_ip" != "$domain_ip" ]]; then
        echo -e "${RED}[!] Домен ${domain} указывает на ${domain_ip}, но IP этого сервера ${server_ip}.${NC}"
        echo -e "${YELLOW}    Настрой A-запись DNS → ${server_ip} и повтори.${NC}"
        return 1
    fi
    echo -e "${GREEN}[+] DNS OK: ${domain} → ${server_ip}${NC}"

    echo -e "${CYAN}[*] Получаю сертификат для ${domain}...${NC}"
    if ! certbot certonly --nginx -d "$domain" --non-interactive --agree-tos -m "$email"; then
        echo -e "${RED}[!] certbot завершился с ошибкой. Проверь что домен указывает на этот сервер и порт 80 доступен снаружи.${NC}"
        return 1
    fi

    local cert_path="/etc/letsencrypt/live/${domain}"
    local nginx_conf="/etc/nginx/sites-available/${domain}"
    local old_port=""
    if [[ -f "$nginx_conf" ]]; then
        old_port=$(grep -E '^\s*listen [0-9]+ ssl' "$nginx_conf" | grep -oE '[0-9]+' | head -1)
    fi

    cat > "$nginx_conf" <<EOF
server {
    listen ${port} ssl;
    server_name ${domain};

    ssl_certificate ${cert_path}/fullchain.pem;
    ssl_certificate_key ${cert_path}/privkey.pem;

    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF

    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/${domain}"

    ufw allow "${port}/tcp" > /dev/null
    ufw reload > /dev/null
    echo -e "${GREEN}[+] Порт ${port}/tcp открыт${NC}"

    if [[ -n "$old_port" && "$old_port" != "$port" ]]; then
        echo -e "${CYAN}Старый порт был ${old_port}. Закрыть его в ufw? (yes/no):${NC}"
        read -r close_old
        if [[ "$close_old" == "yes" ]]; then
            ufw delete allow "${old_port}/tcp" > /dev/null 2>&1
            ufw reload > /dev/null
            echo -e "${GREEN}[+] Порт ${old_port}/tcp закрыт${NC}"
        else
            echo -e "${YELLOW}[i] Порт ${old_port}/tcp оставлен открытым${NC}"
        fi
    fi

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        echo -e "${GREEN}[+] Готово! https://${domain}:${port} — сертификат выпущен и настроен.${NC}"
        echo -e "${YELLOW}[i] Автопродление работает через systemd timer. Порт 80 должен оставаться открытым.${NC}"
    else
        echo -e "${RED}[!] Ошибка в конфиге nginx. Проверь: nginx -t${NC}"
    fi
}

change_ssl_port() {
    require_root || return

    echo -e "${CYAN}Домен (например node.mydomain.com):${NC}"
    read -r domain
    domain="${domain// /}"
    if [[ -z "$domain" ]]; then
        echo -e "${RED}[!] Домен не может быть пустым.${NC}"; return
    fi

    local nginx_conf="/etc/nginx/sites-available/${domain}"
    if [[ ! -f "$nginx_conf" ]]; then
        echo -e "${RED}[!] Конфиг для ${domain} не найден. Сначала выпусти сертификат.${NC}"; return
    fi

    local old_port
    old_port=$(grep -E '^\s*listen [0-9]+ ssl' "$nginx_conf" | grep -oE '[0-9]+' | head -1)

    if [[ -z "$old_port" ]]; then
        echo -e "${YELLOW}[!] Не удалось определить текущий порт из конфига.${NC}"
        echo -e "${CYAN}    Введи текущий порт вручную:${NC}"
        read -r old_port
        old_port="${old_port// /}"
        if ! [[ "$old_port" =~ ^[0-9]+$ ]] || (( old_port < 1 || old_port > 65535 )); then
            echo -e "${RED}[!] Некорректный порт.${NC}"; return
        fi
    fi

    echo -e "${CYAN}Текущий HTTPS-порт: ${BOLD}${old_port}${NC}"

    echo -e "${CYAN}Новый порт для HTTPS:${NC}"
    read -r input_port
    local port="${input_port// /}"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "${RED}[!] Некорректный порт.${NC}"; return
    fi

    if [[ "$port" == "$old_port" ]]; then
        echo -e "${YELLOW}[~] Порт не изменился.${NC}"; return
    fi

    sed -i "s/listen ${old_port} ssl/listen ${port} ssl/" "$nginx_conf"

    ufw allow "${port}/tcp" > /dev/null
    ufw reload > /dev/null
    echo -e "${GREEN}[+] Порт ${port}/tcp открыт${NC}"

    echo -e "${CYAN}Закрыть старый порт ${old_port} в ufw? (yes/no):${NC}"
    read -r close_old
    if [[ "$close_old" == "yes" ]]; then
        ufw delete allow "${old_port}/tcp" > /dev/null 2>&1
        ufw reload > /dev/null
        echo -e "${GREEN}[+] Порт ${old_port}/tcp закрыт${NC}"
    else
        echo -e "${YELLOW}[i] Порт ${old_port}/tcp оставлен открытым${NC}"
    fi

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        echo -e "${GREEN}[+] Готово! Теперь слушаю на https://${domain}:${port}${NC}"
    else
        echo -e "${RED}[!] Ошибка в конфиге nginx. Проверь: nginx -t${NC}"
    fi
}

reset_ssl() {
    require_root || return

    echo -e "${CYAN}Домен (например node.mydomain.com):${NC}"
    read -r domain
    domain="${domain// /}"
    if [[ -z "$domain" ]]; then
        echo -e "${RED}[!] Домен не может быть пустым.${NC}"; return
    fi

    local nginx_conf="/etc/nginx/sites-available/${domain}"
    local old_port=""
    if [[ -f "$nginx_conf" ]]; then
        old_port=$(grep -E '^\s*listen [0-9]+ ssl' "$nginx_conf" | grep -oE '[0-9]+' | head -1)
    fi

    echo -e "${YELLOW}[!] Это удалит nginx-конфиг для ${domain} и отключит сайт.${NC}"
    echo -e "${CYAN}Продолжить? (yes/no):${NC}"
    read -r confirm
    [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}Отменено.${NC}" && return

    rm -f "/etc/nginx/sites-enabled/${domain}"
    rm -f "$nginx_conf"
    echo -e "${GREEN}[+] Nginx-конфиг для ${domain} удалён${NC}"

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
    fi

    if command -v certbot &>/dev/null && certbot certificates 2>/dev/null | grep -qF "${domain}"; then
        echo -e "${CYAN}Удалить сертификат Let's Encrypt для ${domain}? (yes/no):${NC}"
        read -r del_cert
        if [[ "$del_cert" == "yes" ]]; then
            certbot delete --cert-name "$domain" --non-interactive
            echo -e "${GREEN}[+] Сертификат для ${domain} удалён${NC}"
        else
            echo -e "${YELLOW}[i] Сертификат сохранён в /etc/letsencrypt/live/${domain}/${NC}"
        fi
    fi

    if [[ -n "$old_port" ]]; then
        echo -e "${CYAN}Закрыть порт ${old_port} в ufw? (yes/no):${NC}"
        read -r close_port
        if [[ "$close_port" == "yes" ]]; then
            ufw delete allow "${old_port}/tcp" > /dev/null 2>&1
            ufw reload > /dev/null
            echo -e "${GREEN}[+] Порт ${old_port}/tcp закрыт${NC}"
        fi
    fi

    echo -e "${GREEN}[+] SSL для ${domain} сброшен. Можно выпустить заново через пункт 1.${NC}"
}

ssl_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}── Настройка SSL ──────────────────────────${NC}"
        echo -e "  ${CYAN}1.${NC} Выпустить SSL-сертификат"
        echo -e "  ${CYAN}2.${NC} Сменить HTTPS-порт"
        echo -e "  ${CYAN}3.${NC} Сбросить SSL"
        echo -e "  ${CYAN}0.${NC} Назад"
        echo ""
        echo -ne "${BOLD}Выбор: ${NC}"
        read -r ssl_choice
        echo ""
        case "$ssl_choice" in
            1) setup_ssl_cert ;;
            2) change_ssl_port ;;
            3) reset_ssl ;;
            0) return ;;
            *) echo -e "${RED}[!] Неверный выбор.${NC}" ;;
        esac
        echo ""
        echo -ne "${YELLOW}Нажми Enter для возврата...${NC}"
        read -r
    done
}

NODE_DIR="/opt/remnanode"

install_docker() {
    require_root || return

    if command -v docker &>/dev/null; then
        echo -e "${YELLOW}[~] Docker уже установлен: $(docker --version)${NC}"
        return
    fi

    echo -e "${CYAN}[*] Устанавливаю Docker...${NC}"
    if ! command -v curl &>/dev/null; then
        apt-get update -qq && apt-get install -y curl
    fi

    curl -fsSL https://get.docker.com | sh

    if command -v docker &>/dev/null; then
        echo -e "${GREEN}[+] Docker установлен: $(docker --version)${NC}"
    else
        echo -e "${RED}[!] Установка Docker не удалась. Проверь вывод выше.${NC}"
    fi
}

create_compose_config() {
    require_root || return

    mkdir -p "$NODE_DIR"

    local compose_file="${NODE_DIR}/docker-compose.yml"

    if [[ -f "$compose_file" ]]; then
        echo -e "${YELLOW}[~] Файл ${compose_file} уже существует.${NC}"
        echo -e "${CYAN}Перезаписать? (yes/no):${NC}"
        read -r confirm
        [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}Отменено.${NC}" && return
    fi

    local editor=""
    if command -v nano &>/dev/null; then
        editor="nano"
    elif command -v vim &>/dev/null; then
        editor="vim"
    else
        echo -e "${YELLOW}[*] nano и vim не найдены, устанавливаю nano...${NC}"
        apt-get install -y nano -qq
        editor="nano"
    fi

    if [[ "$editor" == "nano" ]]; then
        echo -e "${CYAN}[*] Открываю nano. Вставь содержимое docker-compose.yml из панели и сохрани (Ctrl+X → Y → Enter).${NC}"
    else
        echo -e "${CYAN}[*] Открываю vim. Вставь содержимое docker-compose.yml из панели и сохрани (:wq → Enter).${NC}"
    fi
    sleep 2
    $editor "$compose_file"

    if [[ -s "$compose_file" ]]; then
        echo -e "${GREEN}[+] Конфигурация сохранена в ${compose_file}${NC}"
    else
        echo -e "${RED}[!] Файл пустой или не сохранён.${NC}"
    fi
}

start_node() {
    require_root || return

    local compose_file="${NODE_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        echo -e "${RED}[!] Файл ${compose_file} не найден. Сначала создай конфигурацию (пункт 2).${NC}"
        return
    fi

    if ! command -v docker &>/dev/null; then
        echo -e "${RED}[!] Docker не установлен. Сначала выполни пункт 1.${NC}"
        return
    fi

    local node_port
    node_port=$(grep -E 'NODE_PORT=' "$compose_file" | grep -oE '[0-9]+' | head -1)

    if [[ -n "$node_port" ]]; then
        if ufw status | grep -qE "^${node_port}.*ALLOW"; then
            echo -e "${GREEN}[+] NODE_PORT ${node_port} открыт в ufw${NC}"
        else
            echo -e "${YELLOW}[!] NODE_PORT ${node_port} не найден в правилах ufw.${NC}"
            echo -e "${CYAN}    Открыть порт ${node_port}/tcp? (yes/no):${NC}"
            read -r open_port
            if [[ "$open_port" == "yes" ]]; then
                ufw allow "${node_port}/tcp" > /dev/null
                ufw reload > /dev/null
                echo -e "${GREEN}[+] Порт ${node_port}/tcp открыт${NC}"
            else
                echo -e "${YELLOW}[i] Порт оставлен закрытым. Нода может быть недоступна для панели.${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}[~] NODE_PORT не найден в docker-compose.yml, пропускаю проверку${NC}"
    fi

    echo -e "${CYAN}[*] Запускаю ноду...${NC}"
    docker compose -f "$compose_file" up -d

    echo -e "${GREEN}[+] Нода запущена. Статус контейнеров:${NC}"
    docker compose -f "$compose_file" ps
}

node_logs() {
    require_root || return

    local compose_file="${NODE_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        echo -e "${RED}[!] Файл ${compose_file} не найден.${NC}"
        return
    fi

    echo -e "${CYAN}[*] Логи ноды (Ctrl+C для выхода):${NC}"
    docker compose -f "$compose_file" logs -f -t
}

node_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}── Настройка ноды ─────────────────────────${NC}"
        echo -e "  ${CYAN}1.${NC} Установить Docker"
        echo -e "  ${CYAN}2.${NC} Создать docker-compose.yml"
        echo -e "  ${CYAN}3.${NC} Запустить ноду"
        echo -e "  ${CYAN}4.${NC} Просмотр логов"
        echo -e "  ${CYAN}0.${NC} Назад"
        echo ""
        echo -ne "${BOLD}Выбор: ${NC}"
        read -r node_choice
        echo ""
        case "$node_choice" in
            1) install_docker ;;
            2) create_compose_config ;;
            3) start_node ;;
            4) node_logs ;;
            0) return ;;
            *) echo -e "${RED}[!] Неверный выбор.${NC}" ;;
        esac
        echo ""
        echo -ne "${YELLOW}Нажми Enter для возврата...${NC}"
        read -r
    done
}

auto_setup() {
    require_root || return

    echo ""

    echo -e "${CYAN}IP-адрес панели (необязательно, оставь пустым чтобы открыть 2222 для всех):${NC}"
    read -r panel_ip
    panel_ip="${panel_ip// /}"

    echo -e "${CYAN}Домен для SSL (необязательно, оставь пустым для настройки без SSL):${NC}"
    read -r ss_domain
    ss_domain="${ss_domain// /}"

    local ss_port="" ss_email=""
    if [[ -n "$ss_domain" ]]; then
        echo -e "${CYAN}Порт для HTTPS [по умолчанию: 8443]:${NC}"
        read -r ss_input_port
        ss_port="${ss_input_port:-8443}"
        ss_port="${ss_port// /}"
        if ! [[ "$ss_port" =~ ^[0-9]+$ ]] || (( ss_port < 1 || ss_port > 65535 )); then
            echo -e "${RED}[!] Некорректный порт.${NC}"; return
        fi

        echo -e "${CYAN}Email для Let's Encrypt:${NC}"
        read -r ss_email
        ss_email="${ss_email// /}"
        if [[ -z "$ss_email" || ! "$ss_email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            echo -e "${RED}[!] Некорректный email.${NC}"; return
        fi
    fi

    echo ""
    echo -e "${BOLD}Будет выполнено:${NC}"
    echo -e "  • Открытие SSH-порта (текущий из sshd_config, по умолчанию 22)"
    echo -e "  • Открытие портов 80, 443 (для всех)"
    [[ -n "$panel_ip" ]] \
        && echo -e "  • TCP 2222 открыт для ${panel_ip}" \
        || echo -e "  • TCP 2222 открыт для всех"
    echo -e "  • Включение ufw"
    echo -e "  • Блокировка ICMP (ping)"
    if [[ -n "$ss_domain" ]]; then
        echo -e "  • Выпуск SSL для ${ss_domain}:${ss_port} (${ss_email})"
    fi
    echo -e "  • Установка Docker"
    echo -e "  • Создание docker-compose.yml и запуск ноды"
    echo ""
    echo -e "${CYAN}Продолжить? (yes/no):${NC}"
    read -r confirm
    [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}Отменено.${NC}" && return

    if ! command -v ufw &>/dev/null; then
        echo -e "${YELLOW}[*] Устанавливаю ufw...${NC}"
        apt-get update -qq && apt-get install -y ufw
    fi

    echo ""
    echo -e "${CYAN}[*] Открываю порты...${NC}"

    local ssh_port
    ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    ssh_port="${ssh_port:-22}"
    ufw allow "${ssh_port}/tcp" > /dev/null && echo -e "${GREEN}[+] TCP ${ssh_port} (SSH) открыт${NC}"

    ufw allow 80/tcp > /dev/null && echo -e "${GREEN}[+] TCP 80 открыт${NC}"
    ufw allow 443/tcp > /dev/null && echo -e "${GREEN}[+] TCP 443 открыт${NC}"
    [[ -n "$ss_port" ]] && ufw allow "${ss_port}/tcp" > /dev/null && echo -e "${GREEN}[+] TCP ${ss_port} открыт${NC}"

    if [[ -n "$panel_ip" ]]; then
        ufw allow from "$panel_ip" to any port 2222 proto tcp > /dev/null
        echo -e "${GREEN}[+] TCP 2222 открыт для ${panel_ip}${NC}"
    else
        ufw allow 2222/tcp > /dev/null
        echo -e "${GREEN}[+] TCP 2222 открыт для всех${NC}"
    fi

    if ufw status | grep -q "Status: inactive"; then
        ufw --force enable > /dev/null
        echo -e "${GREEN}[+] ufw включён${NC}"
    else
        ufw reload > /dev/null
        echo -e "${GREEN}[+] ufw перезагружен${NC}"
    fi

    echo ""
    echo -e "${CYAN}[*] Блокирую ICMP...${NC}"
    block_icmp

    if [[ -n "$ss_domain" ]]; then
        echo ""
        echo -e "${CYAN}[*] Выпускаю SSL-сертификат для ${ss_domain}...${NC}"
        if ! setup_ssl_cert "$ss_domain" "$ss_email" "$ss_port"; then
            echo -e "${RED}[!] Не удалось выпустить сертификат. Продолжить без SSL? (yes/no):${NC}"
            read -r skip_ssl
            [[ "$skip_ssl" != "yes" ]] && return
        fi
    fi

    echo ""
    echo -e "${CYAN}[*] Устанавливаю Docker...${NC}"
    install_docker

    echo ""
    echo -e "${CYAN}[*] Создаю конфигурацию ноды...${NC}"
    create_compose_config

    echo ""
    echo -e "${CYAN}[*] Запускаю ноду...${NC}"
    start_node

    echo ""
    echo -e "${GREEN}[+] Автонастройка завершена.${NC}"
    [[ -n "$ss_domain" ]] && echo -e "${YELLOW}[i] Нода доступна по https://${ss_domain}:${ss_port}${NC}"
}

show_menu() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       Server Hardening & Port Setup      ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}1.${NC} Открыть порты (tcp, udp)"
    echo -e "  ${CYAN}2.${NC} Открыть порты для IP"
    echo -e "  ${CYAN}3.${NC} Закрыть порты по IP"
    echo -e "  ${CYAN}4.${NC} Сменить SSH-порт"
    echo -e "  ${CYAN}5.${NC} Заблокировать ICMP (ping)"
    echo -e "  ${CYAN}6.${NC} Закрыть вход по паролю"
    echo -e "  ${CYAN}7.${NC} Настройка SSL"
    echo -e "  ${CYAN}8.${NC} Настройка ноды"
    echo -e "  ${CYAN}9.${NC} Автонастройка сервера"
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
            1) open_ports ;;
            2) open_port_for_ip ;;
            3) close_ports_for_ip ;;
            4) change_ssh_port ;;
            5) block_icmp ;;
            6) disable_password_auth ;;
            7) ssl_menu ;;
            8) node_menu ;;
            9) auto_setup ;;
            0) echo -e "${GREEN}Выход.${NC}"; exit 0 ;;
            *) echo -e "${RED}[!] Неверный выбор.${NC}" ;;
        esac
        echo ""
        echo -ne "${YELLOW}Нажми Enter для возврата в меню...${NC}"
        read -r
    done
}

main