#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

SHARED_DIR="$PROJECT_DIR/shared"
DOWNLOADS_DIR="$PROJECT_DIR/Downloads"
mkdir -p "$SHARED_DIR"
mkdir -p "$DOWNLOADS_DIR"

if command -v xhost >/dev/null 2>&1; then
  xhost +local:docker >/dev/null 2>&1 || true
fi

list_tdata() {
  # Ищем папки tdata* рекурсивно относительно корня проекта
  mapfile -t TDATA_DIRS < <(find "$PWD" -type d -name 'tdata*' 2>/dev/null | sort -V)

  if [ "${#TDATA_DIRS[@]}" -eq 0 ]; then
    echo "Не найдено папок tdata* (рекурсивный поиск). Создаю: $PWD/tdata1"
    mkdir -p "$PWD/tdata1"
    TDATA_DIRS=("$PWD/tdata1")
  fi
}

choose_tdata() {
  list_tdata
  echo "Выберите tdata для запуска:"
  local idx=1
  for d in "${TDATA_DIRS[@]}"; do
    echo "  $idx) $d"
    idx=$((idx+1))
  done
  local choice
  while true; do
    read -rp "Введите номер (1-${#TDATA_DIRS[@]}): " choice || true
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#TDATA_DIRS[@]}" ]; then
      break
    fi
    echo "Неверный ввод. Попробуйте еще раз."
  done
  local selected="${TDATA_DIRS[$((choice-1))]}"
  export TDATA_HOST="$selected"
  echo "Выбрано: $selected"
}

bring_up() {
  : "${DISPLAY:=${DISPLAY:-:0}}"
  export SHARED_HOST="${SHARED_DIR}"
  export DOWNLOADS_HOST="${DOWNLOADS_DIR}"
  echo "Запуск Telegram (в фоне) с tdata: $TDATA_HOST"
  DOCKER_BUILDKIT=0 TDATA_HOST="$TDATA_HOST" SHARED_HOST="$SHARED_HOST" DOWNLOADS_HOST="$DOWNLOADS_HOST" DISPLAY="$DISPLAY" docker compose up -d
  echo "Контейнер запущен: telegram-multiacc"
}

bring_down() {
  echo "Остановка контейнера..."
  docker compose down || true
}

choose_tdata
bring_up

while true; do
  echo
  echo "Действия:"
  echo "  [l] Показать логи (прервать Ctrl+C)"
  echo "  [s] Остановить (docker compose down)"
  echo "  [r] Перезапустить с текущим tdata"
  echo "  [c] Переключить tdata и запустить"
  echo "  [q] Выйти из скрипта (контейнер останется работать)"
  read -rp "Выберите действие [l/s/r/c/q]: " act || true
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


