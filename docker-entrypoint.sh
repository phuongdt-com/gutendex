#!/bin/sh
set -e

# Set Django settings module
export DJANGO_SETTINGS_MODULE=gutendex.settings

echo "=========================================="
echo "Gutendex Container Starting"
echo "=========================================="

# =============================================================================
# STEP 1: Check for pre-built database bundled in image
# =============================================================================
echo "[1/4] Checking for pre-built database..."

PREBUILT_DB="/app/prebuilt/gutendex.db.gz"

if [ -f "$PREBUILT_DB" ] && [ ! -f "$DATABASE_PATH" ]; then
    echo "Found pre-built database in image!"
    echo "Extracting to $DATABASE_PATH..."
    gunzip -c "$PREBUILT_DB" > "$DATABASE_PATH"
    echo "Pre-built database ready!"
elif [ -f "$PREBUILT_DB" ]; then
    echo "Pre-built database available, but database already exists."
elif [ -f "$DATABASE_PATH" ]; then
    echo "Using existing database at $DATABASE_PATH"
else
    echo "No pre-built database found. Will download if needed."
fi

# =============================================================================
# STEP 2: Run migrations
# =============================================================================
echo "[2/4] Running database migrations..."
python manage.py migrate --noinput

# =============================================================================
# STEP 3: Check catalog completeness
# =============================================================================
echo "[3/4] Checking catalog status..."
BOOK_COUNT=$(python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'gutendex.settings')
import django
django.setup()
from books.models import Book
print(Book.objects.count())
" 2>/dev/null || echo "0")

echo "Current book count: $BOOK_COUNT"

# Need at least 50,000 books for a complete catalog
if [ "$BOOK_COUNT" -lt 50000 ]; then
    echo ""
    echo "Catalog incomplete ($BOOK_COUNT books, need 50,000+)"
    echo ""
    echo "Building catalog from Project Gutenberg..."
    echo "This downloads 77k+ books and takes 20-40 minutes."
    echo ""
    
    # Retry up to 3 times
    MAX_ATTEMPTS=3
    ATTEMPT=1
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo "===== Build attempt $ATTEMPT/$MAX_ATTEMPTS ====="
        
        if python manage.py updatecatalog; then
            echo "Catalog build successful!"
            break
        else
            echo "Catalog build failed on attempt $ATTEMPT"
            
            if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
                echo "Waiting 30 seconds before retry..."
                sleep 30
            else
                echo "ERROR: All attempts failed."
                echo "Starting server anyway with partial data."
            fi
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
    done
else
    echo "Catalog complete ($BOOK_COUNT books). Skipping download."
fi

# Collect static files
echo "[4/4] Collecting static files..."
python manage.py collectstatic --noinput

echo "=========================================="
echo "Initialization complete! Starting server..."
echo "=========================================="

# Execute the main command
exec "$@"
