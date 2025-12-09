# =============================================================================
# Gutendex Docker Image
# =============================================================================
# Build modes:
# 1. Default: Small image, downloads catalog on first run
# 2. BUILD_CATALOG=true: Builds catalog during docker build (slow but complete)
# 3. With data/gutendex.db.gz: Uses pre-built database (FAST & complete!)
# =============================================================================

FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /app/wheels -r requirements.txt

# =============================================================================
# Production stage
# =============================================================================
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Default environment variables
ENV DEBUG="false"
ENV ALLOWED_HOSTS="*"
ENV STATIC_ROOT="/app/staticfiles"
ENV MEDIA_ROOT="/app/media"
ENV DATABASE_PATH="/app/data/gutendex.db"
ENV CATALOG_DIR="/app/catalog_files"

# Build argument to optionally populate catalog during build
ARG BUILD_CATALOG=false

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    bzip2 \
    rsync \
    gzip \
    && rm -rf /var/lib/apt/lists/*

# Copy wheels and install
COPY --from=builder /app/wheels /wheels
RUN pip install --no-cache /wheels/* && rm -rf /wheels

# Copy application code
COPY . .

# Make entrypoint executable
RUN chmod +x /app/docker-entrypoint.sh

# Create necessary directories
RUN mkdir -p /app/staticfiles /app/catalog_files /app/media /app/data

# =============================================================================
# DATABASE SETUP - Priority order:
# 1. Pre-built database file (data/gutendex.db.gz) - FASTEST
# 2. BUILD_CATALOG=true - Builds during docker build
# 3. Neither - Downloads on first container start
# =============================================================================

# Check for pre-built database and use it (FASTEST option)
RUN if [ -f /app/data/gutendex.db.gz ]; then \
        echo "=== Found pre-built database! Extracting... ===" && \
        gunzip -c /app/data/gutendex.db.gz > /app/data/gutendex.db && \
        rm /app/data/gutendex.db.gz && \
        echo "Pre-built database ready!" && \
        SECRET_KEY="build-time-key" python manage.py migrate --noinput && \
        SECRET_KEY="build-time-key" python manage.py collectstatic --noinput; \
    elif [ "$BUILD_CATALOG" = "true" ]; then \
        echo "=== Building catalog from source (this takes 20-40 min)... ===" && \
        SECRET_KEY="build-time-key" python manage.py migrate --noinput && \
        SECRET_KEY="build-time-key" python manage.py updatecatalog && \
        SECRET_KEY="build-time-key" python manage.py collectstatic --noinput && \
        rm -rf /app/catalog_files/tmp; \
    else \
        echo "=== No pre-built database. Will download on first run. ==="; \
    fi

# Create non-root user for runtime
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser && \
    chown -R appuser:appgroup /app

USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

# Entrypoint handles migrations, catalog population, and static files
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default command
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "--timeout", "120", "gutendex.wsgi:application"]
