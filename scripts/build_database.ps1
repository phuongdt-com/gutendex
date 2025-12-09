# =============================================================================
# Build Gutendex Database from Scratch (PowerShell)
# =============================================================================
# This script builds a fresh database and exports it for the Docker image.
#
# Usage: .\scripts\build_database.ps1
# Log:   build_log.txt
# =============================================================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Gutendex Database Builder" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Create data directory if not exists
if (-not (Test-Path "data")) {
    New-Item -ItemType Directory -Path "data" | Out-Null
}

# Step 1: Build the database builder image
Write-Host "[1/3] Building database builder image..." -ForegroundColor Yellow
Write-Host "      Log: build_log.txt"
Write-Host ""

docker build --progress=plain -f Dockerfile.builddb -t gutendex-builder . > build_log.txt 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to build database builder image" -ForegroundColor Red
    Write-Host "Check build_log.txt for details" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "[2/3] Running builder to export database..." -ForegroundColor Yellow
Write-Host "      This copies the database to data/gutendex.db.gz"
Write-Host ""

# Step 2: Run the builder to export the database
docker run --rm -v "${PWD}/data:/output" gutendex-builder >> build_log.txt 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Database export failed" -ForegroundColor Red
    Write-Host "Check build_log.txt for details" -ForegroundColor Yellow
    exit 1
}

# Step 3: Verify output
Write-Host ""
Write-Host "[3/3] Verifying output..." -ForegroundColor Yellow

if (Test-Path "data/gutendex.db.gz") {
    $size = (Get-Item "data/gutendex.db.gz").Length / 1MB
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Database file: data/gutendex.db.gz"
    Write-Host "Size: $([math]::Round($size, 1)) MB"
    Write-Host "Log: build_log.txt"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. docker build -t gutendex:1.0.0 ."
    Write-Host "  2. docker run -p 8000:8000 gutendex:1.0.0"
    Write-Host ""
    Write-Host "The image will start INSTANTLY with all books!"
} else {
    Write-Host "ERROR: Database file not found!" -ForegroundColor Red
    Write-Host "Check build_log.txt for details" -ForegroundColor Yellow
    exit 1
}
