# BioMate Setup Checklist for New Machines

## Critical Files Created ✅

- ✅ `MISSING_FILES_AND_SETUP.md` - Comprehensive analysis
- ✅ `README.md` - Complete setup documentation
- ✅ `backend/config/galaxy.yml.template` - Config template without secrets
- ✅ `backend/.env.template` - Environment variables template
- ✅ `backend/.gitignore` - Updated to exclude secrets

## Immediate Actions Required 🔴

### 1. Security: Remove API Keys from Git

**Current Status:** API keys are exposed in `backend/config/galaxy.yml`

```bash
# Anthropic: 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
# OpenAI: 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
```

**Action Steps:**
```bash
cd /Users/jingqiwang/biomate

# 1. Remove from current commit (will be in next commit)
git rm --cached backend/config/galaxy.yml

# 2. Revoke exposed keys
# - Anthropic: https://console.anthropic.com/settings/keys
# - OpenAI: https://platform.openai.com/api-keys

# 3. Generate new keys and add to .env (not in git)
cat > backend/.env << EOF
ANTHROPIC_API_KEY=your-new-key-here
OPENAI_API_KEY=your-new-key-here
EOF

# 4. Update galaxy.yml from template
cp backend/config/galaxy.yml.template backend/config/galaxy.yml
# Edit to use environment variables if needed
```

### 2. Database Files Distribution 🔴

**Required Files Not in Git:**
- `backend/galaxy_ai_tools.db` (144 MB)
- `backend/database/all_unique_tools.json` (69 MB)

**Choose One Approach:**

**Option A: Git LFS (Recommended)**
```bash
# Install Git LFS
brew install git-lfs  # macOS
# or: sudo apt-get install git-lfs  # Linux

# Initialize
git lfs install

# Track large files
git lfs track "backend/galaxy_ai_tools.db"
git lfs track "backend/database/all_unique_tools.json"

# Add and commit
git add .gitattributes
git add backend/galaxy_ai_tools.db
git add backend/database/all_unique_tools.json
git commit -m "Add database files with Git LFS"
git push
```

**Option B: Cloud Storage**
```bash
# Upload to cloud (S3, Google Cloud, Dropbox, etc.)
# Add download instructions to README
# Create download script:

cat > backend/download_databases.sh << 'EOF'
#!/bin/bash
echo "Downloading database files..."
curl -L -o backend/galaxy_ai_tools.db "YOUR_CLOUD_URL/galaxy_ai_tools.db"
curl -L -o backend/database/all_unique_tools.json "YOUR_CLOUD_URL/all_unique_tools.json"
echo "Done!"
EOF

chmod +x backend/download_databases.sh
```

**Option C: Database Generation Script**
```bash
# Create script to rebuild database from source
# Requires Galaxy tool metadata to be regenerated
```

## Next Steps for New Machines 📋

### 1. First Time Setup

```bash
# Clone repository
git clone https://github.com/bioMate-AI/biomate.git
cd biomate

# If using Git LFS
git lfs pull

# If using cloud storage
./backend/download_databases.sh

# Setup environment
cp backend/.env.template backend/.env
# Edit backend/.env with your API keys

# Setup config
cp backend/config/galaxy.yml.template backend/config/galaxy.yml
```

### 2. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Verify database exists
ls -lh galaxy_ai_tools.db  # Should be 144 MB

# Start backend
./run.sh

# Verify (in another terminal)
curl http://localhost:8080/api/version
```

### 3. Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Start dev server
npm run dev

# Verify
curl http://localhost:5173
```

### 4. Test the Application

```bash
# Open browser
open http://localhost:5173

# Try workflow generation
# Enter: "Analyze DIA LC-MS data for protein identification"
# Should generate Galaxy workflow within 30 seconds
```

## Files Modified/Created Summary

### New Files
- `README.md` - Main documentation
- `MISSING_FILES_AND_SETUP.md` - Detailed analysis
- `SETUP_CHECKLIST.md` - This file
- `backend/.env.template` - Environment template
- `backend/config/galaxy.yml.template` - Config template

### Modified Files
- `backend/.gitignore` - Added secrets exclusions

### Files to Remove from Git
- `backend/config/galaxy.yml` - Contains secrets (use template instead)

### Files Not in Git (Need Distribution Strategy)
- `backend/galaxy_ai_tools.db` (144 MB)
- `backend/database/all_unique_tools.json` (69 MB)
- `backend/database/universe.sqlite` (5 MB, runtime generated)
- `backend/database/control.sqlite` (128 KB, runtime generated)

## Commit and Push Changes

```bash
cd /Users/jingqiwang/biomate

# Stage new files
git add README.md
git add MISSING_FILES_AND_SETUP.md
git add SETUP_CHECKLIST.md
git add backend/.env.template
git add backend/config/galaxy.yml.template
git add backend/.gitignore

# Remove secrets from git (keeps local file)
git rm --cached backend/config/galaxy.yml

# Commit
git commit -m "Add setup documentation and security fixes

- Add comprehensive README with setup instructions
- Add .env.template for environment configuration
- Add galaxy.yml.template without API keys
- Update .gitignore to exclude secrets
- Document missing database files and distribution options
- Remove galaxy.yml with exposed API keys from git

⚠️ SECURITY: API keys in previous commits must be revoked!

🤖 Generated with Claude Code"

# Push to branch
git push origin frontend_backend_connection
```

## Post-Commit Actions

1. **Revoke Exposed API Keys**
   - [ ] Anthropic console: https://console.anthropic.com/settings/keys
   - [ ] OpenAI console: https://platform.openai.com/api-keys

2. **Generate New Keys**
   - [ ] Create new Anthropic key
   - [ ] Create new OpenAI key
   - [ ] Add to local `backend/.env`

3. **Setup Database Distribution**
   - [ ] Choose: Git LFS, Cloud Storage, or Generation Script
   - [ ] Implement chosen approach
   - [ ] Test on clean clone

4. **Update Documentation**
   - [ ] Add database download instructions to README
   - [ ] Document required environment variables
   - [ ] Add troubleshooting section

5. **Test New Machine Setup**
   - [ ] Clone on another machine
   - [ ] Follow README instructions
   - [ ] Document any issues

## Quick Reference

### File Locations
- **README:** `/Users/jingqiwang/biomate/README.md`
- **Setup Guide:** `/Users/jingqiwang/biomate/MISSING_FILES_AND_SETUP.md`
- **This Checklist:** `/Users/jingqiwang/biomate/SETUP_CHECKLIST.md`
- **Config Template:** `/Users/jingqiwang/biomate/backend/config/galaxy.yml.template`
- **Env Template:** `/Users/jingqiwang/biomate/backend/.env.template`

### Key Commands
```bash
# Start backend
cd backend && ./run.sh

# Start frontend
cd frontend && npm run dev

# Run tests
cd backend/tests/e2e_ui && pytest test_cases/test_01_dia_lcms.py -v

# Check backend
curl http://localhost:8080/api/version

# Check frontend
curl http://localhost:5173
```

## Status

- ✅ Documentation created
- ✅ Template files created
- ✅ .gitignore updated
- ⏳ Secrets still in git (need to commit removal)
- ⏳ Database files not tracked (need distribution strategy)
- ❌ API keys not yet revoked
- ❌ New API keys not generated
