#!/bin/sh
set -e

# Set Django settings module
export DJANGO_SETTINGS_MODULE=gutendex.settings

echo "=========================================="
echo "Gutendex Container Starting"
echo "=========================================="

# Run migrations
echo "[1/3] Running database migrations..."
python manage.py migrate --noinput

# Check if database has books
echo "Checking if catalog needs to be downloaded..."
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
    echo "[2/3] Catalog incomplete ($BOOK_COUNT books). Downloading from Project Gutenberg..."
    echo "      This may take 10-15 minutes on first run..."
    
    # Retry up to 3 times at container level
    MAX_ATTEMPTS=3
    ATTEMPT=1
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo ""
        echo "===== Container-level attempt $ATTEMPT/$MAX_ATTEMPTS ====="
        
        if python manage.py updatecatalog; then
            echo "Catalog update successful!"
            break
        else
            echo "Catalog update failed on attempt $ATTEMPT"
            
            if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
                echo "Waiting 30 seconds before retry..."
                sleep 30
            else
                echo "ERROR: All attempts failed. Starting server anyway with partial data."
                echo "You can manually run: python manage.py updatecatalog"
            fi
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
    done
else
    echo "[2/3] Catalog complete ($BOOK_COUNT books). Skipping download."
fi

# Collect static files
echo "[3/3] Collecting static files..."
python manage.py collectstatic --noinput

echo "=========================================="
echo "Initialization complete! Starting server..."
echo "=========================================="

# Execute the main command
exec "$@"
