# Blog Post System - Quick Start Guide

**5-Minute Setup Guide**

---

## Prerequisites

✅ Python 3.8+
✅ Anthropic API key (already configured in `.env`)
✅ Galaxy AI tools database

---

## Quick Commands

### Generate Blogs for New Tools

```bash
cd /home/yzhang/biomate/auto_update

# Evaluate and generate blogs for all new tools
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --output ./blog_posts

# Dry run (evaluate only, no blog generation)
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --limit 10 \
  --dry-run

# Generate for specific tools
python3 scripts/generate_blogs_with_review.py \
  --tool-ids auto_foldseek auto_colabfold \
  --output ./blog_posts
```

---

## Understanding the Output

### 1. Terminal Summary

```
================================================================================
EVALUATION SUMMARY
================================================================================
Total tools evaluated: 10
✅ Approved for blog: 5        ← These will get blog posts
❌ Skipped (general libraries): 5    ← Filtered out (e.g., biopython)
⚠️  Needs manual review: 0

✅ APPROVED FOR BLOG POSTS:
   - foldseek (confidence: 0.95)
   - ColabFold (confidence: 0.95)
   ...
```

### 2. Output Files

```
blog_posts/
├── auto_foldseek_blog.md         ← Publish to website
├── auto_foldseek_blog.json       ← For API
├── auto_colabfold_blog.md
├── auto_colabfold_blog.json
└── review/
    ├── evaluation_results_*.json  ← AI decisions (review before publishing)
    └── workflow_summary_*.json    ← Summary stats
```

### 3. Review Files

**Check AI decisions:**
```bash
cat blog_posts/review/workflow_summary_*.json | python3 -m json.tool
```

**What gets skipped:**
- ❌ General libraries (biopython, numpy, pandas)
- ❌ Low-level utilities (htslib, rush)
- ❌ Container frameworks

**What gets approved:**
- ✅ Specific tools (foldseek, MMseqs2)
- ✅ Novel models (ColabFold, AlphaFold)
- ✅ Specialized datasets

---

## Workflow Examples

### Example 1: Daily Blog Generation

```bash
#!/bin/bash
# Run every day at 2 AM

cd /home/yzhang/biomate/auto_update

# Generate blogs for tools added yesterday
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --since $(date -d "yesterday" +%Y-%m-%d) \
  --output ./blog_posts

# Copy to website
rsync -av blog_posts/*.md /path/to/website/blog/
```

### Example 2: Manual Tool Review

```bash
# Step 1: Dry run to see what would be generated
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --limit 20 \
  --dry-run

# Step 2: Review evaluation results
cat blog_posts/review/workflow_summary_*.json

# Step 3: Generate blogs for approved tools
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --limit 20 \
  --output ./blog_posts
```

### Example 3: Regenerate Specific Blog

```bash
# Regenerate blog for a specific tool
python3 scripts/blog_post_generator.py \
  --tool-id auto_foldseek \
  --output ./blog_posts
```

---

## Common Use Cases

### I want to generate blogs for all new tools added in the last week

```bash
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --since $(date -d "7 days ago" +%Y-%m-%d) \
  --output ./blog_posts
```

### I want to test the system without generating blogs

```bash
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --limit 5 \
  --dry-run
```

### I want to see what biopython would evaluate to

```bash
python3 scripts/blog_worthiness_evaluator.py \
  --tool-id auto_biopython
```

**Expected output:**
```
❌ biopython
   Confidence: 0.95
   Reason: General-purpose library, not a specialized tool
   Action: skip
```

### I want to manually evaluate a tool

```bash
python3 scripts/blog_worthiness_evaluator.py \
  --tool-id auto_deepvariant \
  --output ./evaluation_results.json
```

---

## Verification Checklist

Before publishing blogs to production:

1. ✅ Check evaluation results
   ```bash
   cat blog_posts/review/workflow_summary_*.json
   ```

2. ✅ Verify no general libraries approved
   ```bash
   grep -r "biopython\|numpy\|pandas" blog_posts/*.md
   # Should return no results
   ```

3. ✅ Review confidence scores
   ```bash
   cat blog_posts/review/evaluation_results_*.json | \
     python3 -c "import json, sys; \
       data = json.load(sys.stdin); \
       low_conf = [t for t in data if t['confidence'] < 0.7]; \
       print(f'Tools with confidence < 0.7: {len(low_conf)}')"
   ```

4. ✅ Test blog post rendering
   ```bash
   cat blog_posts/auto_foldseek_blog.md
   ```

---

## Troubleshooting

### "Anthropic API key required"

```bash
# Check if API key is set
echo $ANTHROPIC_API_KEY

# If empty, source .env file
source .env
```

### "Tool not found in database"

```bash
# Check tool exists
sqlite3 /home/yzhang/biomate/backend/database/galaxy_ai_tools.db \
  "SELECT tool_id, name FROM tools WHERE tool_id = 'auto_foldseek';"
```

### "All tools are being approved/rejected"

Review and adjust evaluation criteria in:
- `scripts/blog_worthiness_evaluator.py` (lines 42-80)

### "Blog posts are missing sections"

Check database has complete metadata:
```bash
sqlite3 /home/yzhang/biomate/backend/database/galaxy_ai_tools.db \
  "SELECT tool_id, name, description, inputs, outputs, citations \
   FROM tools WHERE tool_id = 'auto_foldseek';"
```

---

## Cost Estimation

**With prompt caching:**
- First evaluation: ~$0.002 per tool
- Subsequent evaluations: ~$0.0005 per tool (90% reduction)

**Example:**
- 100 tools/month = ~$0.20/month
- Very affordable for automated blog generation

---

## Key Files

| File | Purpose |
|------|---------|
| `scripts/generate_blogs_with_review.py` | **Use this for production** |
| `scripts/blog_worthiness_evaluator.py` | AI evaluation only |
| `scripts/blog_post_generator.py` | Blog generation only |
| `.env` | API keys |
| `blog_posts/` | Generated blogs |
| `blog_posts/review/` | AI evaluation results |

---

## Success Indicators

Your system is working correctly if:

1. ✅ Biopython is consistently rejected (confidence > 0.9)
2. ✅ Specific tools like Foldseek are approved (confidence > 0.8)
3. ✅ Evaluation results match expected behavior
4. ✅ Blog posts have complete sections
5. ✅ Review files are generated for audit

---

## Next Steps

1. **Run test batch:**
   ```bash
   python3 scripts/generate_blogs_with_review.py --all-new --limit 5 --dry-run
   ```

2. **Review results:**
   ```bash
   cat blog_posts/review/workflow_summary_*.json
   ```

3. **Generate real blogs:**
   ```bash
   python3 scripts/generate_blogs_with_review.py --all-new --output ./blog_posts
   ```

4. **Publish to website:**
   ```bash
   cp blog_posts/*.md /path/to/website/blog/
   ```

---

## Getting Help

**Full documentation:** See `BLOG_POST_SYSTEM_COMPLETE.md`

**Test a specific tool:**
```bash
python3 scripts/blog_worthiness_evaluator.py --tool-id <tool_id>
```

**Check recent evaluations:**
```bash
find blog_posts/review -name "*.json" -mtime -7 | xargs cat
```

---

**Ready to start? Run your first evaluation:**

```bash
cd /home/yzhang/biomate/auto_update
python3 scripts/generate_blogs_with_review.py --all-new --limit 5 --dry-run
```

✨ **That's it! Your automated blog post system is ready to use.**
