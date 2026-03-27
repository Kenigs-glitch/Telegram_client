#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Останавливаю telegram-multiacc..."
docker compose down 2>/dev/null || true
docker rm -f telegram-multiacc 2>/dev/null || true
rm -f docker-compose.override.yml
echo "Готово."
