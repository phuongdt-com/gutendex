# =============================================================================
# Gutendex Docker Image
# =============================================================================
# This Dockerfile builds the Gutendex application image.
# 
# Features:
# - Auto-initializes database on first run
# - Downloads and populates book catalog from Project Gutenberg
# - Serves static files via WhiteNoise
# - Daily catalog sync via Kubernetes CronJob (when deployed with Helm)
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

WORKDIR /app

# Install runtime dependencies required for catalog sync:
# - wget: for downloading files
# - tar + bzip2: for extracting rdf-files.tar.bz2
# - rsync: for syncing catalog files
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    bzip2 \
    rsync \
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
