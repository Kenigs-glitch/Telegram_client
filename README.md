# Telegram Multi-Account (Desktop GUI via Docker)

Запуск Telegram Desktop в Docker с изоляцией аккаунтов и опциональным SOCKS5 прокси (весь трафик контейнера).

## Требования

- Docker, Docker Compose
- X11 (Linux desktop)
- Python 3 (для выбора прокси)

## Установка и запуск

```bash
chmod +x ./run.sh
./run.sh
```

1. Выберите аккаунт (tdata) из списка
2. Выберите прокси (или `0` для прямого подключения)
3. Telegram Desktop запустится с GUI

Для отправки файлов кладите их в папку `shared` — внутри контейнера она доступна по тому же абсолютному пути.

## Команды в меню

| Клавиша | Действие |
|---------|----------|
| `l` | Логи контейнера |
| `s` | Остановить |
| `r` | Перезапустить |
| `c` | Сменить аккаунт |
| `p` | Сменить прокси |
| `q` | Выйти (контейнер работает) |

## Прокси

При наличии `proxies.json` скрипт предлагает выбрать прокси при первом запуске аккаунта. **Весь TCP-трафик** контейнера прозрачно проксируется через SOCKS5 (redsocks + iptables).

Привязка аккаунт → прокси сохраняется в `proxy_assignments.json` — при повторном запуске подхватывается автоматически. Формат совместим с `leadator-tg-channel-manager`.

Без `proxies.json` — прямое подключение без вопросов.

### Формат proxies.json

```json
[
  {
    "ip": "1.2.3.4",
    "port": 9999,
    "login": "user",
    "password": "pass",
    "name": "Description"
  }
]
```

Поддерживается формат asocks (с `template_string`, `refresh_link` и т.д.).

## Структура аккаунтов

Каждый аккаунт в папке с именем = номер телефона:

```
mega_folders/5511965175152/
├── tdata/                          # Telegram Desktop data
├── 5511965175152.json              # Метаданные (app_id, device, etc.)
└── 5511965175152.session           # Telethon session (опционально)
```

Источник бинарного архива Telegram: https://telegram.org/dl/desktop/linux
