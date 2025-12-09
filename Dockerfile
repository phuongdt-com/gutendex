# =============================================================================
# Gutendex All-in-One Docker Image
# =============================================================================
# This Dockerfile builds a complete, ready-to-run image with:
# - All dependencies installed
# - Database migrated
# - Book catalog populated (~70,000 books from Project Gutenberg)
# - Static files collected
#
# Just run the image and the API is ready to use!
# =============================================================================

FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /app/wheels -r requirements.txt

# =============================================================================
# Production stage with data population
# =============================================================================
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Default environment variables for build
ENV SECRET_KEY="build-time-secret-key-will-be-overridden"
ENV DEBUG="false"
ENV ALLOWED_HOSTS="*"
ENV STATIC_ROOT="/app/staticfiles"
ENV MEDIA_ROOT="/app/media"
ENV DATABASE_PATH="/app/data/gutendex.db"

WORKDIR /app

# Install runtime dependencies (wget for downloading catalog)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copy wheels and install
COPY --from=builder /app/wheels /wheels
RUN pip install --no-cache /wheels/* && rm -rf /wheels

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p /app/staticfiles /app/catalog_files /app/media /app/data

# =============================================================================
# Build Steps: Migrate, Populate, Collect Static
# =============================================================================

# Step 1: Run database migrations
RUN python manage.py migrate --noinput

# Step 2: Populate the database with Project Gutenberg catalog
# This downloads and processes ~70,000 books (takes several minutes)
RUN python manage.py updatecatalog

# Step 3: Collect static files
RUN python manage.py collectstatic --noinput

# Clean up temporary catalog files to reduce image size (keep only db)
RUN rm -rf /app/catalog_files/tmp /app/catalog_files/rdf

# =============================================================================
# Runtime Configuration
# =============================================================================

# Create non-root user for runtime
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser && \
    chown -R appuser:appgroup /app

USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

# Default command
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "--timeout", "120", "gutendex.wsgi:application"]
