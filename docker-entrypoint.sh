#!/bin/sh
set -e

# Set Django settings module
export DJANGO_SETTINGS_MODULE=gutendex.settings

echo "=========================================="
echo "Gutendex Container Starting"
echo "=========================================="

# Run migrations
echo "[1/4] Running database migrations..."
python manage.py migrate --noinput

# Check if database has books
echo "[2/4] Checking catalog status..."
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
    
    # Option 1: Download pre-built database (FAST - recommended!)
    if [ -n "$PREBUILT_DATABASE_URL" ]; then
        echo ""
        echo "[3/4] Downloading pre-built database (FAST method)..."
        echo "      URL: $PREBUILT_DATABASE_URL"
        
        # Download compressed database
        TEMP_DB="/tmp/gutendex-prebuilt.db.gz"
        
        if wget -c -t 10 --timeout=60 --progress=dot:mega -O "$TEMP_DB" "$PREBUILT_DATABASE_URL"; then
            echo "Decompressing database..."
            
            # Backup current db if exists
            if [ -f "$DATABASE_PATH" ]; then
                mv "$DATABASE_PATH" "${DATABASE_PATH}.bak"
            fi
            
            # Decompress
            gunzip -c "$TEMP_DB" > "$DATABASE_PATH"
            rm -f "$TEMP_DB"
            
            # Re-run migrations in case schema changed
            python manage.py migrate --noinput
            
            # Verify
            NEW_COUNT=$(python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'gutendex.settings')
import django
django.setup()
from books.models import Book
print(Book.objects.count())
" 2>/dev/null || echo "0")
            
            echo "Pre-built database imported: $NEW_COUNT books"
            
            if [ "$NEW_COUNT" -ge 50000 ]; then
                echo "SUCCESS! Database ready."
                rm -f "${DATABASE_PATH}.bak"
            else
                echo "WARNING: Imported database seems incomplete"
                # Restore backup if import failed
                if [ -f "${DATABASE_PATH}.bak" ]; then
                    mv "${DATABASE_PATH}.bak" "$DATABASE_PATH"
                fi
            fi
        else
            echo "WARNING: Failed to download pre-built database"
            echo "Falling back to building from source..."
        fi
    fi
    
    # Re-check book count after potential import
    BOOK_COUNT=$(python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'gutendex.settings')
import django
django.setup()
from books.models import Book
print(Book.objects.count())
" 2>/dev/null || echo "0")
    
    # Option 2: Build from source (SLOW - only if no pre-built available)
    if [ "$BOOK_COUNT" -lt 50000 ]; then
        echo ""
        echo "[3/4] Building catalog from Project Gutenberg (SLOW method)..."
        echo "      This downloads 77k+ books and takes 20-40 minutes."
        echo "      TIP: Set PREBUILT_DATABASE_URL for faster startup!"
        echo ""
        
        # Retry up to 3 times at container level
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
    fi
else
    echo "[3/4] Catalog complete ($BOOK_COUNT books). Skipping download."
fi

# Collect static files
echo "[4/4] Collecting static files..."
python manage.py collectstatic --noinput

echo "=========================================="
echo "Initialization complete! Starting server..."
echo "=========================================="

# Execute the main command
exec "$@"
