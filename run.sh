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

# === Keyboard layout normalization (ru → en) ===

# Map Russian ЙЦУКЕН letters to their QWERTY position so menu hotkeys
# work regardless of the active keyboard layout. Covers every letter,
# lowercases input, and leaves latin/digits untouched.
normalize_key() {
  local s="${1,,}"
  case "$s" in
    й) s=q ;; ц) s=w ;; у) s=e ;; к) s=r ;; е) s=t ;; н) s=y ;;
    г) s=u ;; ш) s=i ;; щ) s=o ;; з) s=p ;;
    ф) s=a ;; ы) s=s ;; в) s=d ;; а) s=f ;; п) s=g ;; р) s=h ;;
    о) s=j ;; л) s=k ;; д) s=l ;;
    я) s=z ;; ч) s=x ;; с) s=c ;; м) s=v ;; и) s=b ;; т) s=n ;; ь) s=m ;;
  esac
  printf '%s' "$s"
}

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
    export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS="" PROXY_TYPE=""
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
    export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS="" PROXY_TYPE=""
    # Save choice (-1 = no proxy)
    save_assignment "$phone" -1
  else
    local idx=$((choice - 1))
    apply_proxy "$idx" "$phone"
    save_assignment "$phone" "$idx"
  fi
}

check_proxy() {
  local idx="$1"
  if [ "$idx" = "-1" ]; then
    return 0
  fi
  python3 "$PROJECT_DIR/check_proxy.py" "$PROXIES_FILE" "$idx"
}

apply_proxy() {
  local idx="$1"
  local phone="$2"

  if [ "$idx" = "-1" ]; then
    echo "Прокси: прямое подключение"
    export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS="" PROXY_TYPE=""
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
proto = p.get('protocol', 'socks5')
print(f'export PROXY_HOST=\"{ip}\"')
print(f'export PROXY_PORT=\"{port}\"')
print(f'export PROXY_USER=\"{user}\"')
print(f'export PROXY_PASS=\"{passwd}\"')
print(f'export PROXY_TYPE=\"{proto}\"')
print(f'echo \"Прокси: {ip}:{port} [{proto}] ({name})\"')
" 2>/dev/null)"

  # Validate proxy liveness
  if ! check_proxy "$idx"; then
    echo ""
    echo "⚠  Прокси мёртв! Выберите действие:"
    echo "  1) Выбрать другой прокси"
    echo "  2) Продолжить без прокси (прямое подключение)"
    echo "  3) Всё равно использовать этот прокси"
    local action
    while true; do
      read -rp "Ваш выбор (1-3): " action || true
      case "$action" in
        1)
          # Remove saved assignment and re-choose
          python3 -c "
import json
from pathlib import Path
path = Path('$ASSIGNMENTS_FILE')
data = {}
if path.exists():
    try: data = json.load(open(path))
    except: pass
data.pop('$phone', None)
json.dump(data, open(path, 'w'), indent=2)
" 2>/dev/null
          choose_proxy "$phone"
          return
          ;;
        2)
          echo "Продолжаю без прокси."
          export PROXY_HOST="" PROXY_PORT="" PROXY_USER="" PROXY_PASS="" PROXY_TYPE=""
          save_assignment "$phone" -1
          return
          ;;
        3)
          echo "Продолжаю с текущим прокси."
          return
          ;;
        *) echo "Неверный ввод." ;;
      esac
    done
  fi
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
    echo "Прокси: $PROXY_HOST:$PROXY_PORT [${PROXY_TYPE:-socks5}] (весь трафик через прокси)"
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
  echo
  echo "  ── раскладка любая: можно жать д/ы/к/с/з/й ──"
  echo
  read -rp "Выберите действие [l/s/r/c/p/q]: " act || true
  act=$(normalize_key "${act:-}")
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
