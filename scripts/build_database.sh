#!/bin/bash
# =============================================================================
# Build Gutendex Database from Scratch (Bash)
# =============================================================================
# This script builds a fresh database and exports it for the Docker image.
#
# Usage: bash scripts/build_database.sh
# Log:   build_log.txt
# =============================================================================

set -e

echo "=========================================="
echo "Gutendex Database Builder"
echo "=========================================="
echo ""

# Create data directory if not exists
mkdir -p data

# Step 1: Build the database builder image
echo "[1/3] Building database builder image..."
echo "      Log: build_log.txt"
echo ""

docker build --progress=plain -f Dockerfile.builddb -t gutendex-builder . > build_log.txt 2>&1

echo ""
echo "[2/3] Running builder to export database..."
echo "      This copies the database to data/gutendex.db.gz"
echo ""

# Step 2: Run the builder to export the database
docker run --rm -v "$(pwd)/data:/output" gutendex-builder >> build_log.txt 2>&1

# Step 3: Verify output
echo ""
echo "[3/3] Verifying output..."

if [ -f "data/gutendex.db.gz" ]; then
    SIZE=$(ls -lh data/gutendex.db.gz | awk '{print $5}')
    echo ""
    echo "=========================================="
    echo "SUCCESS!"
    echo "=========================================="
    echo "Database file: data/gutendex.db.gz"
    echo "Size: $SIZE"
    echo "Log: build_log.txt"
    echo ""
    echo "Next steps:"
    echo "  1. docker build -t gutendex:1.0.0 ."
    echo "  2. docker run -p 8000:8000 gutendex:1.0.0"
    echo ""
    echo "The image will start INSTANTLY with all books!"
else
    echo "ERROR: Database file not found!"
    echo "Check build_log.txt for details"
    exit 1
fi
