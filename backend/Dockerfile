# Production image: non-root, no reload, migrations on start, rembg model baked in.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    U2NET_HOME=/opt/models PORT=8000 WEB_CONCURRENCY=2

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt gunicorn==23.*

# Fetch the background-removal model at build time so first uploads aren't slow.
RUN mkdir -p /opt/models && python -c "from rembg import new_session; new_session('u2net')"

COPY . .
RUN useradd --create-home --uid 10001 drape \
    && mkdir -p /app/uploads && chown -R drape:drape /app /opt/models
USER drape

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
    CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1
CMD ["sh", "-c", "alembic upgrade head && exec gunicorn app.main:app -k uvicorn.workers.UvicornWorker -w ${WEB_CONCURRENCY} -b 0.0.0.0:${PORT} --timeout 180 --graceful-timeout 30"]
