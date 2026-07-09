# Reddit Bioinformatics Data Collection — Design & Findings

**Date:** 2026-07-03  
**Script:** `backend/scripts/reddit_bioinformatics_collector.py`  
**Output dir:** `backend/data/reddit/`

---

## Purpose

Collect questions, pain points, tool discussions, and community-validated answers from Reddit's bioinformatics communities to inform:

- **Product design** — which workflows, tools, and pain points are most common
- **Marketing** — vocabulary users actually use, topics that generate engagement
- **Evaluation** — real-world questions to benchmark BioMate's AI assistant against
- **LLM training data** — high-quality Q&A pairs with community upvote signal

---

## Approach

Uses Reddit's official API via **PRAW** (Python Reddit API Wrapper). Read-only access, rate-limit-aware (60 req/min with OAuth). No scraping — all data retrieved through Reddit's public API.

### Two-tier collection strategy

**Tier 1 — Native bioinformatics subreddits** (scrape top/hot posts directly):

| Subreddit | Focus |
|---|---|
| r/bioinformatics | Core community — tools, pipelines, career |
| r/learnbioinformatics | Beginner questions — high pain-signal density |
| r/computational_biology | Methods, algorithms, academic |
| r/genomics | Sequencing, variant calling, WGS |
| r/scrnaseq | Single-cell RNA-seq — Seurat, Scanpy, Monocle |
| r/epigenetics | ATAC-seq, ChIP-seq, methylation |
| r/proteomics | Mass spec, protein ID |
| r/genetics | Population genetics, GWAS |
| r/drugdiscovery | ADMET, docking, MedChem |

**Tier 2 — General subreddits, filtered by biology search terms:**

r/MachineLearning, r/datascience, r/labrats, r/biotech, r/biology, r/clinicalresearch

Search terms include: RNA-seq, single cell, GWAS, variant calling, DESeq2, Seurat, AlphaFold, ADMET, Nextflow, Snakemake, etc.

### Per-post data collected

- Title, body text, score, upvote ratio, comment count
- Date, subreddit, flair, author, permalink
- Top 10 comments (sorted by score) with body + score

---

## Text Mining Signals

Applied to every post at collection time:

### `is_question` (boolean)
Regex patterns detecting help-seeking: `?`, `how to`, `what is`, `which tool`, `best way`, `recommend`, `help`, etc.

### `has_pain_signal` (boolean)
Frustration/failure vocabulary: `struggling`, `confused`, `frustrated`, `doesn't work`, `not working`, `stuck`, `nightmare`, `can't figure out`, etc.

### `tool_mentions` (list)
Detects mentions of 30+ tools and platforms:
- **BioMate competitors:** Galaxy, Terra, DNAnexus, Basespace, Seven Bridges, Illumina DRAGEN
- **R/Bioconductor tools:** DESeq2, edgeR, limma, Seurat, Scanpy, Monocle
- **Pipeline tools:** Nextflow, Snakemake, CWL
- **Alignment/variant:** GATK, BWA, STAR, HISAT2, Salmon, kallisto
- **Structure:** AlphaFold, Rosetta, PyMOL
- **LLMs in bio:** ChatGPT, GPT-4, Claude, Gemini

---

## Output Files

All saved to `backend/data/reddit/` with timestamp suffix.

### `reddit_posts_TIMESTAMP.json`
Full raw data. Each record:
```json
{
  "id": "abc123",
  "subreddit": "bioinformatics",
  "title": "Best tool for differential expression with low replicates?",
  "selftext": "...",
  "score": 342,
  "upvote_ratio": 0.97,
  "num_comments": 47,
  "created_date": "2025-11-14",
  "url": "https://reddit.com/r/bioinformatics/comments/...",
  "flair": "Tools",
  "is_question": true,
  "has_pain_signal": false,
  "tool_mentions": ["DESeq2", "edgeR"],
  "top_comments": [
    { "body": "DESeq2 handles low replicates well...", "score": 89 },
    ...
  ]
}
```

### `reddit_posts_TIMESTAMP.csv`
Flat CSV version. Top answer inlined as `top_answer` / `top_answer_score` columns. Best for Excel / Google Sheets review.

### `reddit_qa_TIMESTAMP.csv`
**Most useful for product and evaluation work.** Contains:
- Well-answered questions (top answer score > 10), sorted by post engagement
- Top-voted unanswered questions (for gap analysis)
- Columns: subreddit, date, score, question, question_body, best_answer, answer_score, url, tool_mentions, has_pain_signal

Directly usable as:
- LLM evaluation benchmark (does BioMate's AI answer match the community answer?)
- Fine-tuning data pairs
- Marketing copy inspiration (real user vocabulary)

### `reddit_analysis_TIMESTAMP.json`
Structured summary:
- `top_questions` — top 20 questions by post score
- `top_pain_posts` — top 20 frustration posts by score
- `subreddit_breakdown` — post count per subreddit
- `tool_mention_frequency` — ranked tool mentions across all posts
- `flair_breakdown` — topic distribution via post flairs
- `well_answered_questions` — top 50 Q&A pairs with high-quality answers

---

## Usage

### One-time setup

```bash
pip install praw pandas

# Create app at: https://www.reddit.com/prefs/apps
# App type: script | redirect URI: http://localhost:8080

export REDDIT_CLIENT_ID=your_client_id
export REDDIT_CLIENT_SECRET=your_client_secret
export REDDIT_USER_AGENT="BioMate Research Bot 1.0 by u/your_username"
```

### Run options

```bash
cd backend/scripts

# Full collection + analysis, top posts from past year (recommended)
python reddit_bioinformatics_collector.py --mode full --sort top --time-filter year --limit 100

# Quick test run (faster, smaller)
python reddit_bioinformatics_collector.py --mode full --limit 25 --time-filter month

# Re-analyze existing data without re-crawling
python reddit_bioinformatics_collector.py --mode analyze --input ../data/reddit/reddit_posts_20260703_1200.json

# Collect recent posts (monitor community in real-time)
python reddit_bioinformatics_collector.py --mode full --sort new --time-filter week --limit 50
```

### Expected runtime and volume

| Config | Posts collected | Runtime |
|---|---|---|
| `--limit 25 --time-filter month` | ~500–800 | ~5 min |
| `--limit 100 --time-filter year` | ~2,000–4,000 | ~20 min |
| `--limit 500 --time-filter all` | ~10,000+ | ~90 min |

Rate limiter is built-in (0.5s between requests). Reddit allows 60 requests/min with OAuth.

---

## How to Use the Data

### Product design
Read `reddit_qa_*.csv`, filter `has_pain_signal = true`, sort by `score` descending.
Each row is a real user problem that BioMate can position against.

### Marketing / vocabulary
Scan high-score question titles for phrasing patterns. Users write:
- "best tool for…" not "optimal software for…"
- "pipeline for…" not "workflow solution for…"
- "running DESeq2 on low replicates" not "differential expression with insufficient biological replication"
Use this vocabulary in landing pages, docs, and outreach.

### Evaluation benchmark
Run BioMate's AI assistant against the `question` field of top Q&A pairs.
Compare BioMate's answer to `best_answer` (community-validated ground truth).
Use `answer_score` as a proxy for answer quality ceiling.

### Competitive intelligence
Read `tool_mention_frequency` from the analysis JSON.
High-mention tools with pain signals attached = BioMate positioning opportunities.
Example: if Galaxy appears frequently alongside `has_pain_signal = true` posts, that's a direct positioning signal.

### LLM training data
`reddit_qa_*.csv` is structured as question → answer pairs with quality signal (answer_score).
Filter `answer_score > 20` for high-quality pairs.
Can be fed directly into supervised fine-tuning or RLHF preference datasets.

---

## Terms of Service Compliance

- All data retrieved via Reddit's **official API** (not HTML scraping)
- Rate limits respected (built-in delays)
- **User contact via scraped usernames is prohibited** by Reddit ToS and violates GDPR/CAN-SPAM
- For community outreach: post in r/bioinformatics directly, or use Reddit's ad platform
- Author usernames in the data are for research context only — do not build outreach lists from them

---

## Known Limitations

1. **r/scrnaseq is small** — focused but lower volume than r/bioinformatics
2. **General subs (r/datascience, r/MachineLearning)** — lots of noise; biology search filter reduces but doesn't eliminate irrelevant posts
3. **Deleted posts/comments** — `[deleted]` and `[removed]` appear for older moderated content
4. **pushshift.io not used** — the historical Reddit archive (pushshift) became restricted in 2023; this script only reaches what Reddit's current API exposes (typically posts from the last 1–2 years via `top`)
5. **Comment depth** — only top-level and second-level comments fetched; deep threads truncated at 10 comments per post

---

## Suggested Recurring Schedule

Run monthly with `--sort new --time-filter month` to track emerging pain points and tool discussions in near-real-time. Consider a cron job via `scripts/schedule` once the credential env vars are stable on the dev EC2.

---

## Next Steps

- [ ] Run a full collection pass (`--limit 100 --time-filter year`) and review `reddit_qa_*.csv`
- [ ] Build a BioMate evaluation harness: send `question` to BioMate AI → score against `best_answer`
- [ ] Extract recurring topic clusters (k-means or LDA on `title + selftext`) to map community needs
- [ ] Add r/labrats and r/biotech to Tier 1 (currently Tier 2 search-filtered) if volume warrants
- [ ] Cross-reference `tool_mention_frequency` against BioMate's indexed workflow coverage gaps
