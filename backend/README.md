# SplitVPN Backend

FastAPI-бекенд для SplitVPN — управление списками заблокированных доменов,
аутентификация пользователей и каталог прокси-серверов.

## Стек

- FastAPI 0.110 + Uvicorn
- PostgreSQL 16 (async SQLAlchemy 2.0 + asyncpg)
- Redis 7 (атомарный gzip-снимок доменов)
- Alembic (миграции)
- APScheduler (обновление доменов каждые 6 ч, проверка прокси)
- JWT (access + refresh), bcrypt, rate limiting

## Запуск через Docker

```bash
cp .env.example .env          # при желании поменяйте JWT_SECRET / пароли
docker compose up --build
```

Поднимаются три сервиса: `db` (Postgres), `cache` (Redis), `api` (FastAPI).
Миграции применяются автоматически при старте контейнера `api`.

- API: http://localhost:8080
- Swagger: http://localhost:8080/docs
- Health: http://localhost:8080/health

### Создать администратора

```bash
docker compose exec api python -m scripts.create_admin admin@example.com SuperSecret123
```

### Первое наполнение доменов

```bash
# получить токен админа через /auth/login, затем:
curl -X POST http://localhost:8080/admin/domains/refresh \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

Дальше домены обновляются автоматически каждые 6 часов.

## API (кратко)

| Метод | Endpoint | Авторизация |
|-------|----------|-------------|
| POST | `/auth/register` | — |
| POST | `/auth/login` | — |
| POST | `/auth/refresh` | — |
| GET | `/domains/list` | JWT |
| GET | `/domains/export` | JWT (gzip) |
| GET | `/domains/updated_at` | JWT |
| GET | `/proxy/list` | JWT |
| GET | `/proxy/best` | JWT |
| GET | `/stats/me` | JWT |
| POST | `/admin/domains/refresh` | Admin |
| POST | `/admin/proxy/add` | Admin |

## Как устроено атомарное обновление доменов

1. APScheduler (или admin) запускает `update_domains()`.
2. Скачивается список (antizapret → fallback РКН), нормализуется.
3. Таблица `domains` заменяется **в транзакции** — читатели видят старые данные до коммита.
4. Собирается gzip-снимок полного списка и **одной операцией** публикуется в Redis.
5. `/domains/export` всегда отдаёт цельный готовый снимок — никаких пустых
   или наполовину обновлённых списков, без обрывов VPN у клиентов.

## Тесты

```bash
pip install -r requirements.txt
pytest
```

Тесты используют in-memory SQLite и fakeredis — внешние сервисы не нужны.

## Миграции

```bash
# создать новую миграцию по изменениям моделей
alembic revision --autogenerate -m "описание"
# применить
alembic upgrade head
```
