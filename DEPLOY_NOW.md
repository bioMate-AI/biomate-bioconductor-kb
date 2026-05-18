# Deploy LLM Fallback + Critical Optimizations

**Ready to deploy:** All code tested locally ✅

---

## Pre-Deployment Checklist

✅ LLM fallback implemented and tested locally
✅ GOOGLE_API_KEY obtained: `AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI`
✅ PyYAML added to requirements.txt
✅ All tests passed

---

## Deployment Steps (15 minutes)

### Step 1: Add GOOGLE_API_KEY to dev-public

```bash
# SSH to EC2
ssh ubuntu@52.42.49.175

# Backup current .env
sudo cp /opt/biomate/.env /opt/biomate/.env.backup

# Add Google API key
echo 'GOOGLE_API_KEY=AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI' | sudo tee -a /opt/biomate/.env

# Verify it was added
grep GOOGLE_API_KEY /opt/biomate/.env

# Exit SSH
exit
```

### Step 2: Sync code to dev-public

```bash
# On local machine
cd /Users/kky/biomate

# Run sync script (will take ~5 minutes)
bash scripts/sync_to_dev.sh
```

**What this does:**
- Copies new files: `llm_providers.yml`, `llm_client_fallback_implementation.py`
- Updates modified: `llm_client.py`, `requirements.txt`
- Installs PyYAML in container
- Restarts Galaxy backend

### Step 3: Verify deployment

```bash
# SSH back to EC2
ssh ubuntu@52.42.49.175

# Check Galaxy logs for successful startup
docker logs biomate-galaxy-dev 2>&1 | tail -50

# Look for this line:
# "INFO: Loaded LLM fallback config: primary=gemini-3.1-pro-preview, fallbacks=[...]"

# Check container is healthy
docker ps | grep biomate-galaxy-dev
# Should show "Up X minutes (healthy)"

# Test health endpoint
curl http://localhost:3000/api/health

# Exit
exit
```

### Step 4: Test LLM fallback in production

```bash
# From your local machine, test workflow generation
curl -X POST https://dev-public.biomate.ai/api/ai_assistant/chat \
  -H "Content-Type: application/json" \
  -H "Cookie: session=YOUR_SESSION_COOKIE" \
  -d '{"message": "Generate a simple RNA-seq workflow"}'

# Should return workflow JSON using Gemini
```

### Step 5: Monitor logs

```bash
ssh ubuntu@52.42.49.175

# Watch logs for LLM provider usage
docker logs -f biomate-galaxy-dev 2>&1 | grep "LLM call with"

# Should see: "Attempting LLM call with gemini:gemini-3.1-pro-preview"

# Leave this running for a few minutes to confirm it's working
# Ctrl+C to stop
```

---

## Expected Results

✅ Container starts successfully
✅ Logs show "Loaded LLM fallback config"
✅ Workflow generation uses Gemini (primary)
✅ If Gemini fails → auto-fallback to Claude
✅ No errors in logs

---

## Rollback (if needed)

```bash
ssh ubuntu@52.42.49.175

# Restore backup .env
sudo cp /opt/biomate/.env.backup /opt/biomate/.env

# Revert code (from git)
cd /opt/biomate
git checkout HEAD~1 backend/lib/galaxy/ai/llm_client.py
git checkout HEAD~1 backend/requirements.txt
rm -f backend/lib/galaxy/ai/llm_client_fallback_implementation.py
rm -f backend/config/llm_providers.yml

# Restart
docker restart biomate-galaxy-dev
```

---

## Next Steps After Deployment

Once LLM fallback is stable:

1. **Connection pooling** (1 hour)
2. **Worker recycling** (30 min)
3. **Health endpoint** (1 hour)

Total: ~2.5 hours for full Week 1 optimizations

---

**Ready to deploy? Run the commands above!**
