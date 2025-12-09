# =============================================================================
# Build Gutendex Database from Scratch (Native Windows)
# =============================================================================
# This script builds a fresh database natively on Windows.
#
# Prerequisites:
#   - Python 3.10+ installed
#   - Download catalog file manually:
#     https://gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2
#     Save to: data/rdf-files.tar.zip
#
# Usage: .\scripts\build_database.ps1
# Output: data/gutendex.db.gz
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Gutendex Database Builder (Native)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check Python
Write-Host "Checking Python..." -ForegroundColor Yellow
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Python not found. Please install Python 3.10+" -ForegroundColor Red
    exit 1
}

# Check catalog file exists
$catalogFile = "data\rdf-files.tar.zip"
if (-not (Test-Path $catalogFile)) {
    Write-Host ""
    Write-Host "ERROR: Catalog file not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please download it manually:" -ForegroundColor Yellow
    Write-Host "  1. Go to: https://gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2" -ForegroundColor Cyan
    Write-Host "  2. Save to: data\rdf-files.tar.zip" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
$catalogSize = (Get-Item $catalogFile).Length / 1MB
Write-Host "Found catalog: $([math]::Round($catalogSize, 1)) MB" -ForegroundColor Green

# Create directories
Write-Host ""
Write-Host "[1/7] Creating directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "data" -Force | Out-Null
New-Item -ItemType Directory -Path "staticfiles" -Force | Out-Null
New-Item -ItemType Directory -Path "catalog_files" -Force | Out-Null
New-Item -ItemType Directory -Path "media" -Force | Out-Null

# Create virtual environment
Write-Host "[2/7] Setting up virtual environment..." -ForegroundColor Yellow
if (-not (Test-Path "venv")) {
    python -m venv venv
    Write-Host "Virtual environment created!" -ForegroundColor Green
} else {
    Write-Host "Using existing virtual environment" -ForegroundColor Green
}

# Activate virtual environment
Write-Host "      Activating venv..." -ForegroundColor Gray
& .\venv\Scripts\Activate.ps1

# Set environment variables
Write-Host "[3/7] Setting environment variables..." -ForegroundColor Yellow
$env:SECRET_KEY = "build-time-secret-key-for-database-generation"
$env:DEBUG = "false"
$env:ALLOWED_HOSTS = "*"
$env:DATABASE_PATH = "$PWD\data\gutendex.db"
$env:STATIC_ROOT = "$PWD\staticfiles"
$env:MEDIA_ROOT = "$PWD\media"
$env:CATALOG_DIR = "$PWD\catalog_files"
$env:DJANGO_SETTINGS_MODULE = "gutendex.settings"

# Upgrade pip and install dependencies
Write-Host "[4/7] Installing Python dependencies..." -ForegroundColor Yellow
Write-Host "      Upgrading pip..." -ForegroundColor Gray
python -m pip install --upgrade pip -q 2>$null

Write-Host "      Installing requirements..." -ForegroundColor Gray
python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
    exit 1
}
Write-Host "Dependencies installed!" -ForegroundColor Green

# Run migrations
Write-Host ""
Write-Host "[5/7] Running database migrations..." -ForegroundColor Yellow
python manage.py migrate --noinput
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Migration failed" -ForegroundColor Red
    exit 1
}
Write-Host "Migrations complete!" -ForegroundColor Green

# Download and import catalog
Write-Host ""
Write-Host "[6/7] Downloading and importing catalog..." -ForegroundColor Yellow
Write-Host "      This will take 20-40 minutes..." -ForegroundColor Gray
Write-Host ""
python manage.py updatecatalog
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Catalog update failed" -ForegroundColor Red
    exit 1
}
Write-Host "Catalog import complete!" -ForegroundColor Green

# Collect static files
Write-Host ""
Write-Host "[7/7] Collecting static files..." -ForegroundColor Yellow
python manage.py collectstatic --noinput
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Collectstatic failed" -ForegroundColor Red
    exit 1
}

# Verify database
Write-Host ""
Write-Host "Verifying database..." -ForegroundColor Yellow
$bookCount = python -c "import os; os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'gutendex.settings'); import django; django.setup(); from books.models import Book; print(Book.objects.count())"
Write-Host "Total books in database: $bookCount" -ForegroundColor Cyan

# Compress database
Write-Host ""
Write-Host "Compressing database..." -ForegroundColor Yellow

$dbPath = "data\gutendex.db"
$gzPath = "data\gutendex.db.gz"

if (Test-Path $gzPath) {
    Remove-Item $gzPath -Force
}

# Use .NET GZip compression
$sourceFile = [System.IO.File]::OpenRead($dbPath)
$destFile = [System.IO.File]::Create($gzPath)
$gzipStream = New-Object System.IO.Compression.GZipStream($destFile, [System.IO.Compression.CompressionMode]::Compress)

$sourceFile.CopyTo($gzipStream)

$gzipStream.Close()
$destFile.Close()
$sourceFile.Close()

# Deactivate venv
deactivate 2>$null

# Show results
$originalSize = (Get-Item $dbPath).Length / 1MB
$compressedSize = (Get-Item $gzPath).Length / 1MB

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Database file: data\gutendex.db.gz"
Write-Host "Original size: $([math]::Round($originalSize, 1)) MB"
Write-Host "Compressed size: $([math]::Round($compressedSize, 1)) MB"
Write-Host "Books: $bookCount"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. docker build -t gutendex:1.0.0 ."
Write-Host "  2. docker run -p 8000:8000 gutendex:1.0.0"
Write-Host ""
Write-Host "The Docker image will start INSTANTLY with all $bookCount books!"
