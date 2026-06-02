from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App
    app_name: str = "SplitVPN Backend"
    debug: bool = False

    # Database
    database_url: str = "postgresql+asyncpg://splitvpn:splitvpn@db:5432/splitvpn"

    # Redis
    redis_url: str = "redis://cache:6379/0"

    # JWT
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30

    # Domain updater
    domains_primary_url: str = "https://antizapret.prostovpn.org/domains-export.txt"
    domains_fallback_url: str = (
        "https://raw.githubusercontent.com/zapret-info/z-i/master/domains.txt"
    )
    domains_update_interval_hours: int = 6
    domain_fetch_timeout_seconds: int = 60
    # Домены, которые ВСЕГДА проксируем, даже если их нет в antizapret/РКН.
    # YouTube в РФ не заблокирован, а замедлен — его доменов нет в списках, поэтому
    # видео-CDN googlevideo.com шёл напрямую и душился DPI. Мержатся в снимок при
    # каждой публикации (см. _publish_snapshot), переживают обновление из источника.
    extra_blocked_domains: tuple[str, ...] = (
        "googlevideo.com",          # CDN с самим видео — критично
        "youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "ytimg.com",                # превью/статика
        "ggpht.com",                # аватары/превью (yt3/yt4.ggpht.com)
        "youtubei.googleapis.com",  # InnerTube API приложения YouTube
    )
    # Путь к CLI sing-box для компиляции бинарного rule-set (.srs).
    # Версия должна совпадать со сборкой libbox в iOS-расширении (v1.14.0-alpha.26),
    # иначе расширение не прочитает бинарный формат.
    sing_box_bin: str = "/usr/local/bin/sing-box"

    # IP rule-set для сервисов без домена/SNI (Telegram MTProto ходит прямо на IP
    # дата-центров — доменный split его не ловит, маршрутизируем по подсетям).
    telegram_cidr_url: str = "https://core.telegram.org/resources/cidr.txt"
    # Фолбэк, если источник недоступен (подсети меняются крайне редко).
    ip_ruleset_fallback_cidrs: tuple[str, ...] = (
        "91.108.56.0/22", "91.108.4.0/22", "91.108.8.0/22", "91.108.16.0/22",
        "91.108.12.0/22", "149.154.160.0/20", "91.105.192.0/23", "91.108.20.0/22",
        "185.76.151.0/24", "2001:b28:f23d::/48", "2001:b28:f23f::/48",
        "2001:67c:4e8::/48", "2001:b28:f23c::/48", "2a0a:f280::/32",
    )
    ip_ruleset_update_interval_hours: int = 24

    # Proxy checker
    proxy_check_interval_minutes: int = 5
    proxy_check_timeout_seconds: int = 5

    # Redis cache keys
    cache_key_domains_export: str = "domains:export:gz"
    cache_key_domains_srs: str = "domains:export:srs"
    cache_key_domains_count: str = "domains:count"
    cache_key_domains_updated_at: str = "domains:updated_at"
    cache_key_ip_srs: str = "domains:ip:srs"
    cache_key_ip_count: str = "domains:ip:count"
    cache_key_ip_updated_at: str = "domains:ip:updated_at"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
