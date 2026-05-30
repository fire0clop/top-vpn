FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# CLI sing-box для компиляции бинарного rule-set (.srs). Версия должна совпадать
# со сборкой libbox в iOS-расширении (v1.14.0-alpha.26), иначе расширение не
# прочитает бинарный формат rule-set.
ARG SING_BOX_VERSION=1.14.0-alpha.26
RUN arch="$(dpkg --print-architecture)" \
    && pkg="sing-box-${SING_BOX_VERSION}-linux-${arch}" \
    && curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${pkg}.tar.gz" -o /tmp/sing-box.tar.gz \
    && tar -xzf /tmp/sing-box.tar.gz -C /tmp \
    && install -m 0755 "/tmp/${pkg}/sing-box" /usr/local/bin/sing-box \
    && rm -rf /tmp/sing-box.tar.gz "/tmp/${pkg}" \
    && sing-box version

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["./entrypoint.sh"]
