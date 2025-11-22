# Auto-Update System Setup Guide

**Quick Start:** Get the GitHub tool detector running in 5 minutes.

---

## Prerequisites

- Python 3.8+
- GitHub account with API token
- Git

---

## Installation

### 1. Install Dependencies

```bash
cd /home/yzhang/biomate/auto_update

# Install Python packages
pip install -r requirements.txt
```

### 2. Configure GitHub Token

```bash
# Copy credentials template
cp config/credentials.yaml.example config/credentials.yaml

# Edit and add your GitHub token
nano config/credentials.yaml
```

**How to get a GitHub token:**
1. Go to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `public_repo`
4. Copy the token
5. Paste into `config/credentials.yaml`

```yaml
github:
  token: ghp_YOUR_ACTUAL_TOKEN_HERE
```

### 3. Verify Setup

```bash
# Test the detector (dry run, no API calls)
python scripts/detect_github_tools.py --help
```

You should see the help message.

---

## First Run

### Basic Detection

```bash
# Detect tools from last 90 days with 50+ stars
python scripts/detect_github_tools.py --days 90 --min-stars 50
```

**What happens:**
1. Searches GitHub for bioinformatics repos
2. Filters by quality signals (tests, CI/CD, docs)
3. Calculates quality scores (0.0 - 1.0)
4. Saves results to `data/discoveries/github_tools_YYYYMMDD_HHMMSS.json`
5. Prints summary report

**Example output:**
```
================================================================================
Discovery Summary
================================================================================

Total repositories found: 47

Quality Distribution:
  High quality (>0.8): 12 (auto-add)
  Medium quality (0.5-0.8): 23 (review queue)
  Low quality (<0.5): 12 (reject)

Top 10 Tools by Quality Score:

 1. awesome-bio-tool (650 ⭐) - Score: 0.92
    A cutting-edge protein structure prediction tool with AI...
    https://github.com/user/awesome-bio-tool

 2. ...
```

### Custom Search

```bash
# Search specific topics
python scripts/detect_github_tools.py --topics genomics,proteomics --days 30

# Higher quality threshold
python scripts/detect_github_tools.py --min-stars 100 --days 180

# Verbose output for debugging
python scripts/detect_github_tools.py --verbose
```

---

## Review Results

### View Discoveries

```bash
# View the latest discovery file
cat data/discoveries/github_tools_*.json | jq '.[] | select(.classification == "high")'
```

### High-Quality Tools (Auto-Add Candidates)

```bash
# Extract high-quality tools
cat data/discoveries/github_tools_*.json | jq '.[] | select(.quality_score > 0.8)'
```

### Medium-Quality Tools (Review Queue)

```bash
# Extract medium-quality tools for manual review
cat data/discoveries/github_tools_*.json | jq '.[] | select(.quality_score > 0.5 and .quality_score <= 0.8)'
```

---

## Configuration

### Modify Search Parameters

Edit `config/sources.yaml`:

```yaml
github:
  min_stars: 100  # Raise quality bar
  lookback_days: 30  # More recent tools only
  topics:
    - single-cell  # Add specific topics
    - rna-seq
```

### Adjust Quality Scoring

Edit `config/filters.yaml`:

```yaml
scoring_weights:
  popularity: 0.2      # Reduce weight of popularity
  code_quality: 0.4    # Increase weight of code quality
  scientific: 0.4      # Prioritize tools with papers
```

---

## Automation

### Schedule Daily Runs

Add to crontab:

```bash
# Edit crontab
crontab -e

# Add daily detection at 6 AM
0 6 * * * cd /home/yzhang/biomate/auto_update && python scripts/detect_github_tools.py >> logs/daily.log 2>&1
```

### Email Notifications

```bash
# Add to cron for email on completion
0 6 * * * cd /home/yzhang/biomate/auto_update && python scripts/detect_github_tools.py && mail -s "Tools Detected" you@example.com < data/discoveries/latest.json
```

---

## Troubleshooting

### Issue: "GitHub token not found"

**Solution:**
- Check `config/credentials.yaml` exists
- Verify token is correctly pasted (no extra spaces)
- Ensure file is named `credentials.yaml` not `credentials.yaml.example`

### Issue: API rate limit hit

**Solution:**
- GitHub free tier: 60 requests/hour unauthenticated, 5000/hour authenticated
- Reduce `lookback_days` to search fewer repos
- Add delays between searches

### Issue: No tools found

**Solution:**
- Lower `min_stars` threshold (try 20 instead of 50)
- Increase `lookback_days` (try 180 instead of 90)
- Check topics are correct (use `--topics bioinformatics`)

### Issue: All tools scored low

**Solution:**
- Check `config/filters.yaml` weights
- Lower `quality_thresholds.auto_approve` to 0.7
- Verify scoring algorithm in `scripts/detect_github_tools.py`

---

## Directory Structure After Setup

```
auto_update/
├── README.md
├── SETUP.md                    # This file
├── requirements.txt
├── .gitignore
├── docs/
│   ├── ANALYSIS.md
│   ├── ARCHITECTURE.md
│   └── API_USAGE.md
├── config/
│   ├── sources.yaml           # Search parameters
│   ├── filters.yaml           # Quality scoring
│   ├── credentials.yaml       # YOUR API TOKENS (gitignored)
│   └── credentials.yaml.example
├── scripts/
│   └── detect_github_tools.py # Main detector script
├── data/
│   ├── discoveries/           # Daily discovery results
│   ├── review_queue/          # Tools awaiting review
│   ├── approved/              # Approved for integration
│   └── rejected/              # Rejected tools
└── logs/
    └── daily.log              # Cron job logs
```

---

## Next Steps

1. **Run first detection** to see what tools are out there
2. **Review results** and adjust quality thresholds
3. **Schedule daily runs** via cron
4. **Build integrator** (Week 2) to add tools to BioMate database

---

## Support

- Documentation: `docs/ANALYSIS.md` and `docs/ARCHITECTURE.md`
- Issues: Check logs in `logs/` directory
- Configuration: Modify `config/*.yaml` files

---

**Ready to go!** Run your first detection:

```bash
python scripts/detect_github_tools.py --days 90 --min-stars 50
```
