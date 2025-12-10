# Step 1: Download Catalog
- Download from: https://gutenberg.org/cache/epub/feeds/rdf-files.tar.zip
- Save to: `data/rdf-files.tar.zip`

# Step 2: Build Database
```powershell
.\scripts\build_database.ps1
```
This creates `data/gutendex.db.gz` (~45MB with 77,000+ books)

# Step 3: Build Docker Image
```bash
docker build -t adamduongit/adam-gutendex:0.0.3 .
```

# Step 4: Push to Docker Hub
```bash
docker push adamduongit/adam-gutendex:0.0.3
```
