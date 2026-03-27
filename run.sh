#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

SHARED_DIR="$PROJECT_DIR/shared"
DOWNLOADS_DIR="$PROJECT_DIR/Downloads"
PROXIES_FILE="$PROJECT_DIR/proxies.json"
ASSIGNMENTS_FILE="$PROJECT_DIR/proxy_assignments.json"

mkdir -p "$SHARED_DIR"
mkdir -p "$DOWNLOADS_DIR"

if command -v xhost >/dev/null 2>&1; then
  xhost +local:docker >/dev/null 2>&1 || true
fi

# === tdata selection ===

list_tdata() {
  mapfile -t TDATA_DIRS < <(find "$PWD" -type d -name 'tdata*' 2>/dev/null | sort -V)
  if [ "${#TDATA_DIRS[@]}" -eq 0 ]; then
    echo "Не найдено папок tdata*. Создаю: $PWD/tdata1"
    mkdir -p "$PWD/tdata1"
    TDATA_DIRS=("$PWD/tdata1")
  fi
}

# Extract phone number from tdata path (parent directory name)
get_phone_from_tdata() {
  local tdata_path="$1"
  basename "$(dirname "$tdata_path")"
}

choose_tdata() {
  list_tdata
  echo "Выберите tdata для запуска:"
  local idx=1
  for d in "${TDATA_DIRS[@]}"; do
    local phone
    phone=$(get_phone_from_tdata "$d")
    echo "  $idx) $phone  ($d)"
    idx=$((idx+1))
  done
  local choice
  while true; do
    read -rp "Введите номер (1-${#TDATA_DIRS[@]}): " choice || true
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#TDATA_DIRS[@]}" ]; then
      break
    fi
    echo "Неверный ввод."
  done
  local selected="${TDATA_DIRS[$((choice-1))]}"
  export TDATA_HOST="$selected"
  CURRENT_PHONE=$(get_phone_from_tdata "$selected")
  echo "Выбрано: $CURRENT_PHONE ($selected)"
}

# === Proxy selection ===

choose_proxy() {
  local phone="$1"

  # No proxies file → direct
  if [ ! -f "$PROXIES_FILE" ]; then
    echo "proxies.json не найден → прямое подключение"
    export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS=""
    return
  fi

  # Check saved assignment
  if [ -f "$ASSIGNMENTS_FILE" ]; then
    local saved_idx
    saved_idx=$(python3 -c "
import json, sys
try:
    a = json.load(open('$ASSIGNMENTS_FILE'))
    idx = a.get('$phone')
    if idx is not None: print(idx)
except: pass
" 2>/dev/null || true)
    if [ -n "$saved_idx" ]; then
      apply_proxy "$saved_idx" "$phone"
      return
    fi
  fi

  # Interactive selection
  local count
  count=$(python3 -c "import json; print(len(json.load(open('$PROXIES_FILE'))))" 2>/dev/null)

  echo ""
  echo "Выберите прокси для $phone:"
  echo "  0) Без прокси (прямое подключение)"
  python3 -c "
import json
proxies = json.load(open('$PROXIES_FILE'))
for i, p in enumerate(proxies):
    ip = p.get('ip') or p.get('host') or '?'
    name = p.get('name', '')
    print(f'  {i+1}) {ip}:{p[\"port\"]}  {name}')
" 2>/dev/null

  local choice
  while true; do
    read -rp "Введите номер (0-$count): " choice || true
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "$count" ]; then
      break
    fi
    echo "Неверный ввод."
  done

  if [ "$choice" -eq 0 ]; then
    echo "Без прокси"
    export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS=""
    # Save choice (-1 = no proxy)
    save_assignment "$phone" -1
  else
    local idx=$((choice - 1))
    apply_proxy "$idx" "$phone"
    save_assignment "$phone" "$idx"
  fi
}

apply_proxy() {
  local idx="$1"
  local phone="$2"

  if [ "$idx" = "-1" ]; then
    echo "Прокси: прямое подключение"
    export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS=""
    return
  fi

  eval "$(python3 -c "
import json
proxies = json.load(open('$PROXIES_FILE'))
p = proxies[$idx]
ip = p.get('ip') or p.get('host') or ''
port = p.get('port', '')
user = p.get('login') or p.get('username') or ''
passwd = p.get('password', '')
name = p.get('name', '')
print(f'export PROXY_HOST=\"{ip}\"')
print(f'export PROXY_PORT=\"{port}\"')
print(f'export PROXY_USER=\"{user}\"')
print(f'export PROXY_PASS=\"{passwd}\"')
print(f'echo \"Прокси: {ip}:{port} ({name})\"')
" 2>/dev/null)"
}

save_assignment() {
  local phone="$1"
  local idx="$2"
  python3 -c "
import json
from pathlib import Path
path = Path('$ASSIGNMENTS_FILE')
data = {}
if path.exists():
    try: data = json.load(open(path))
    except: pass
data['$phone'] = $idx
json.dump(data, open(path, 'w'), indent=2)
" 2>/dev/null
}

# === Docker ===

bring_up() {
  : "${DISPLAY:=${DISPLAY:-:0}}"
  export SHARED_HOST="${SHARED_DIR}"
  export DOWNLOADS_HOST="${DOWNLOADS_DIR}"

  if [ -d "/media/user" ]; then
    cat > docker-compose.override.yml <<EOF
services:
  telegram:
    volumes:
      - /media/user:/media/user
EOF
  else
    rm -f docker-compose.override.yml
  fi

  echo "Запуск Telegram (в фоне) с tdata: $TDATA_HOST"
  if [ -n "${PROXY_HOST:-}" ]; then
    echo "Прокси: $PROXY_HOST:$PROXY_PORT (весь трафик через SOCKS5)"
  else
    echo "Прокси: нет (прямое подключение)"
  fi

  DOCKER_BUILDKIT=0 docker compose up -d --build
  echo "Контейнер запущен: telegram-multiacc"
}

bring_down() {
  echo "Остановка контейнера..."
  docker compose down || true
}

# === Main ===

choose_tdata
choose_proxy "$CURRENT_PHONE"
bring_up

while true; do
  echo
  echo "Действия:"
  echo "  [l] Показать логи (прервать Ctrl+C)"
  echo "  [s] Остановить (docker compose down)"
  echo "  [r] Перезапустить с текущим tdata"
  echo "  [c] Переключить tdata и запустить"
  echo "  [p] Сменить прокси для текущего аккаунта"
  echo "  [q] Выйти из скрипта (контейнер останется работать)"
  read -rp "Выберите действие [l/s/r/c/p/q]: " act || true
  case "${act:-}" in
    l|L)
      docker compose logs -f || true
      ;;
    s|S)
      bring_down
      ;;
    r|R)
      bring_down
      bring_up
      ;;
    c|C)
      bring_down
      choose_tdata
      choose_proxy "$CURRENT_PHONE"
      bring_up
      ;;
    p|P)
      bring_down
      # Force re-choose (delete saved assignment)
      python3 -c "
import json
from pathlib import Path
path = Path('$ASSIGNMENTS_FILE')
data = {}
if path.exists():
    try: data = json.load(open(path))
    except: pass
data.pop('$CURRENT_PHONE', None)
json.dump(data, open(path, 'w'), indent=2)
" 2>/dev/null
      choose_proxy "$CURRENT_PHONE"
      bring_up
      ;;
    q|Q)
      echo "Выход. Контейнер (если запущен) продолжит работу."
      exit 0
      ;;
    *)
      echo "Неизвестная команда."
      ;;
  esac
done
