FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.10.3 /uv /uvx /bin/

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY . .
RUN uv sync --frozen --no-dev

RUN groupadd --system app && useradd --system --gid app --home-dir /app app \
    && mkdir -p /app/data /app/staticfiles \
    && chown -R app:app /app

USER app

CMD ["daphne", "-b", "0.0.0.0", "-p", "8000", "core.asgi:application"]
