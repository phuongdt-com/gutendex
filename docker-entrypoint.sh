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

if [ "$BOOK_COUNT" = "0" ] || [ -z "$BOOK_COUNT" ]; then
    echo "[2/3] No books found. Populating catalog from Project Gutenberg..."
    echo "      This may take 5-10 minutes on first run..."
    python manage.py updatecatalog
else
    echo "[2/3] Database has $BOOK_COUNT books. Skipping catalog download."
fi

# Collect static files
echo "[3/3] Collecting static files..."
python manage.py collectstatic --noinput

echo "=========================================="
echo "Initialization complete! Starting server..."
echo "=========================================="

# Execute the main command
exec "$@"
