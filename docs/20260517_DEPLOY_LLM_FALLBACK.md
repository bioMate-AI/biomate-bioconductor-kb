# Deploy LLM Fallback to dev-public - Quick Guide

**Date:** 2026-05-17
**Status:** Ready to deploy
**GOOGLE_API_KEY:** `AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI`

---

## What Was Done

✅ **Code changes completed:**
1. Created `backend/config/llm_providers.yml` - Provider priority configuration
2. Created `backend/lib/galaxy/ai/llm_client_fallback_implementation.py` - Fallback logic
3. Modified `backend/lib/galaxy/ai/llm_client.py` - Integrated fallback (lines 15-18, 111, 174-186)
4. Added `PyYAML>=6.0` to `backend/requirements.txt`

✅ **New priority order:**
```
1. Gemini 3.1 Pro Preview (primary)
2. Gemini 3.0 Flash Preview (fallback 1)
3. Claude Sonnet 4.5 (fallback 2)
4. OpenAI GPT-4o (fallback 3)
5. Local Qwen3 32B (fallback 4)
```

---

## Deployment Steps (20 minutes)

### Step 1: Add GOOGLE_API_KEY to dev-public

```bash
ssh ubuntu@52.42.49.175

# Add to .env file
echo 'GOOGLE_API_KEY=AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI' >> /opt/biomate/.env

# Verify it's set
grep GOOGLE_API_KEY /opt/biomate/.env
```

### Step 2: Sync code to dev

```bash
# On local machine
cd /Users/kky/biomate
bash scripts/sync_to_dev.sh
```

This will:
- Copy new files: `llm_providers.yml`, `llm_client_fallback_implementation.py`
- Update modified files: `llm_client.py`, `requirements.txt`
- Install PyYAML in the container
- Restart Galaxy backend

### Step 3: Verify deployment

```bash
ssh ubuntu@52.42.49.175

# Check logs for successful provider loading
docker logs biomate-galaxy-dev 2>&1 | grep "Loaded LLM fallback config"

# Expected output:
# INFO: Loaded LLM fallback config: primary=gemini-3.1-pro-preview, fallbacks=[gemini-3.0-flash-preview, claude-sonnet-4-5, gpt-4o, qwen3:32b]

# Check container is healthy
curl http://localhost:3000/api/health
```

### Step 4: Test on dev-public

```bash
# Make a test workflow generation request
curl -X POST https://dev-public.biomate.ai/api/ai_assistant/chat \
  -H "Content-Type: application/json" \
  -H "Cookie: session=YOUR_SESSION_COOKIE" \
  -d '{"message": "Generate a simple RNA-seq workflow for mouse samples"}'

# Check which provider was used
ssh ubuntu@52.42.49.175 "docker logs biomate-galaxy-dev 2>&1 | tail -50 | grep 'LLM call with'"

# Expected: "Attempting LLM call with gemini:gemini-3.1-pro-preview"
```

### Step 5: Test fallback (optional)

```bash
ssh ubuntu@52.42.49.175

# Temporarily break Gemini key to test fallback
sudo sed -i.bak 's/^GOOGLE_API_KEY=.*/GOOGLE_API_KEY=invalid/' /opt/biomate/.env
docker restart biomate-galaxy-dev

# Wait for container to be healthy (~60 seconds)
sleep 60

# Make request (should fallback to Claude)
curl -X POST https://dev-public.biomate.ai/api/ai_assistant/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Generate RNA-seq workflow"}'

# Check logs for fallback
docker logs biomate-galaxy-dev 2>&1 | tail -100 | grep -A 5 "Fallback to"

# Expected:
# ❌ gemini:gemini-3.1-pro-preview: 401
# ❌ gemini:gemini-3.0-flash-preview: 401
# Attempting LLM call with anthropic:claude-sonnet-4-5...
# ✅ Fallback to anthropic:claude-sonnet-4-5 succeeded

# Restore real key
sudo mv /opt/biomate/.env.bak /opt/biomate/.env
docker restart biomate-galaxy-dev
```

---

## Success Criteria

✅ **Container starts without errors**
✅ **Logs show "Loaded LLM fallback config"**
✅ **Workflow generation succeeds**
✅ **Logs show "gemini:gemini-3.1-pro-preview" as primary**
✅ **Fallback works when Gemini fails (test optional)**

---

## Rollback Plan (if something breaks)

```bash
ssh ubuntu@52.42.49.175
cd /opt/biomate

# Revert to previous code
git checkout HEAD~1 backend/lib/galaxy/ai/llm_client.py
git checkout HEAD~1 backend/requirements.txt

# Remove new files
rm -f backend/lib/galaxy/ai/llm_client_fallback_implementation.py
rm -f backend/config/llm_providers.yml

# Restart
docker restart biomate-galaxy-dev
```

---

## Monitoring (after deployment)

Monitor these for 48 hours:

```bash
# Provider usage distribution (should be ~95% Gemini)
ssh ubuntu@52.42.49.175 "docker logs biomate-galaxy-dev 2>&1 | grep 'LLM call with' | awk '{print \$NF}' | sort | uniq -c"

# Fallback rate (should be <5%)
ssh ubuntu@52.42.49.175 "docker logs biomate-galaxy-dev 2>&1 | grep 'Fallback to' | wc -l"

# Complete failures (should be 0)
ssh ubuntu@52.42.49.175 "docker logs biomate-galaxy-dev 2>&1 | grep 'All LLM providers failed' | wc -l"
```

---

## Files Changed

| File | Status | Lines Changed |
|------|--------|---------------|
| `backend/config/llm_providers.yml` | NEW | +180 |
| `backend/lib/galaxy/ai/llm_client_fallback_implementation.py` | NEW | +300 |
| `backend/lib/galaxy/ai/llm_client.py` | MODIFIED | +15 / -73 |
| `backend/requirements.txt` | MODIFIED | +1 |

**Total:** +423 lines added, -73 lines removed

---

## Next Steps

1. Deploy to dev-public (Steps 1-4 above)
2. Monitor for 48 hours
3. If stable, deploy to production
4. Update user-facing docs with new LLM priority order

---

## Questions?

See full implementation guide: `docs/20260517_LLM_PRIORITY_AND_FALLBACK_IMPLEMENTATION.md`

**Ready to deploy!**
