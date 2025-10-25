# BioMate Database Files Setup

This document explains how to set up the required database files for BioMate.

## Required Files

BioMate requires two large database files that are not included in the git repository:

### 1. galaxy_ai_tools.db (130 MB)
- **Purpose:** Contains indexed information for 7000+ Galaxy tools
- **Location:** `backend/galaxy_ai_tools.db`
- **Contents:** Tool IDs, names, descriptions, parameters, help text

### 2. all_unique_tools.json (69 MB)
- **Purpose:** Complete tool definitions from Galaxy
- **Location:** `backend/database/all_unique_tools.json`
- **Contents:** Full tool XML schemas, input/output specs, parameter definitions

**Total download size:** ~199 MB

---

## Method 1: Automated Download (Recommended)

We provide a download script that automatically fetches these files from AWS S3.

### Prerequisites

- AWS CLI installed
- Internet connection

### Installation Steps

```bash
# 1. Navigate to backend directory
cd backend

# 2. Run the download script
./download_databases.sh

# The script will:
# - Check for AWS CLI
# - Download both database files from S3
# - Verify downloads
# - Show next steps
```

### Installing AWS CLI

If you don't have AWS CLI installed:

**macOS:**
```bash
brew install awscli
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install awscli
```

**Windows:**
Download from: https://aws.amazon.com/cli/

---

## Method 2: Manual Download

If you prefer to download manually or the script doesn't work:

### Using AWS CLI

```bash
cd backend

# Download galaxy_ai_tools.db
aws s3 cp s3://galaxy-cloud-data-1760241377/biomate/galaxy_ai_tools.db ./galaxy_ai_tools.db

# Download all_unique_tools.json
mkdir -p database
aws s3 cp s3://galaxy-cloud-data-1760241377/biomate/all_unique_tools.json ./database/all_unique_tools.json
```

### Using Direct URLs (Valid for 1 year)

If you don't have AWS CLI, use these presigned URLs:

**galaxy_ai_tools.db:**
```bash
curl -L -o backend/galaxy_ai_tools.db \
  "https://galaxy-cloud-data-1760241377.s3.us-west-2.amazonaws.com/biomate/galaxy_ai_tools.db?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAV2DX3XSKGYVKVDET%2F20251025%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20251025T163159Z&X-Amz-Expires=31536000&X-Amz-SignedHeaders=host&X-Amz-Signature=f3784fa4d6a011d545aba66c39b803f7cf3c7fe319ea2d0c823e270647c81afe"
```

**all_unique_tools.json:**
```bash
mkdir -p backend/database
curl -L -o backend/database/all_unique_tools.json \
  "https://galaxy-cloud-data-1760241377.s3.us-west-2.amazonaws.com/biomate/all_unique_tools.json?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAV2DX3XSKGYVKVDET%2F20251025%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20251025T163200Z&X-Amz-Expires=31536000&X-Amz-SignedHeaders=host&X-Amz-Signature=3b370599dfc419dc103d5255d32958b52b248d26eaee1fc8909a751005491e51"
```

**Note:** These URLs expire on **October 25, 2026**. After that, use AWS CLI or contact the maintainer.

---

## Method 3: Access via AWS Console

If you have AWS access to the BioMate account:

1. Open AWS Console: https://console.aws.amazon.com/s3/
2. Navigate to bucket: `galaxy-cloud-data-1760241377`
3. Go to folder: `biomate/`
4. Download both files:
   - `galaxy_ai_tools.db`
   - `all_unique_tools.json`
5. Place them in the correct locations:
   - `backend/galaxy_ai_tools.db`
   - `backend/database/all_unique_tools.json`

---

## Verification

After downloading, verify the files exist and have the correct sizes:

```bash
cd backend

# Check galaxy_ai_tools.db
ls -lh galaxy_ai_tools.db
# Should show ~130 MB

# Check all_unique_tools.json
ls -lh database/all_unique_tools.json
# Should show ~69 MB

# Verify database can be read
sqlite3 galaxy_ai_tools.db "SELECT COUNT(*) FROM tools;"
# Should return a number (e.g., 7000+)
```

---

## Troubleshooting

### "AWS CLI not found"

Install AWS CLI as shown above. You don't need AWS credentials for the public bucket.

### "Access Denied" error

The presigned URLs may have expired. Contact the maintainer for updated URLs or use AWS CLI with configured credentials.

### Database file corrupted

Re-download the file. If the issue persists, the file may be corrupted in S3. Contact the maintainer.

### "No such table: tools" error

This means the database file is not in the correct location or is corrupted. Check:
```bash
cd backend
ls -lh galaxy_ai_tools.db  # Should exist and be ~130 MB
```

### Files download but app still fails

Make sure files are in the exact locations:
- `backend/galaxy_ai_tools.db` (NOT in database/ subdirectory)
- `backend/database/all_unique_tools.json` (IN database/ subdirectory)

---

## S3 Bucket Information

**Bucket:** `galaxy-cloud-data-1760241377`
**Region:** `us-west-2` (US West - Oregon)
**Path:** `s3://galaxy-cloud-data-1760241377/biomate/`

**Files:**
- `galaxy_ai_tools.db` (130.3 MiB)
- `all_unique_tools.json` (68.7 MiB)

---

## Next Steps

After successfully downloading the database files:

1. **Configure environment:**
   ```bash
   cd backend
   cp .env.template .env
   # Edit .env and add your Anthropic API key
   ```

2. **Configure Galaxy:**
   ```bash
   cp config/galaxy.yml.template config/galaxy.yml
   # The config will use environment variables from .env
   ```

3. **Start the application:**
   ```bash
   # Terminal 1 - Backend
   cd backend
   ./run.sh

   # Terminal 2 - Frontend
   cd frontend
   npm install
   npm run dev
   ```

4. **Test workflow generation:**
   - Open http://localhost:5173
   - Try generating a workflow: "Analyze DIA LC-MS data"

---

## Need Help?

If you encounter issues:

1. Check the main [README.md](README.md) for full setup instructions
2. Review [MISSING_FILES_AND_SETUP.md](MISSING_FILES_AND_SETUP.md) for detailed analysis
3. Open an issue on GitHub
4. Contact the maintainer

---

**Last Updated:** October 25, 2025
**S3 URLs Valid Until:** October 25, 2026
