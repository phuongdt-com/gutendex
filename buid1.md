Build Database from Scratch
On Windows (PowerShell):
.\scripts\build_database.ps1
On Linux/Mac:
bash scripts/build_database.sh
Or manually:
# Step 1: Build the database builder imagedocker build -f Dockerfile.builddb -t gutendex-builder .# Step 2: Run it to generate data/gutendex.db.gzdocker run --rm -v ${PWD}/data:/output gutendex-builder
What Happens
[1/3] Building database builder image...      (compiles dependencies)[2/3] Building database (20-40 minutes)...      - Runs migrations      - Downloads 77,000+ books from Project Gutenberg      - Verifies count > 50,000      - Compresses to .gz[3/3] Output: data/gutendex.db.gz
Then Build Final Image
# Now build the main image - it will use data/gutendex.db.gzdocker build -t gutendex:1.0.0 .# Run - starts INSTANTLY!docker run -p 8000:8000 gutendex:1.0.0
File Flow
Dockerfile.builddb          → Builds database from scratch       ↓data/gutendex.db.gz         → Clean, verified database (77k+ books)       ↓Dockerfile                  → Includes database in final image       ↓gutendex:1.0.0             → Ready to run instantly!