# Auto-Update System Documentation

The BioMate Auto-Update System automatically discovers, validates, and integrates bioinformatics tools from GitHub into the platform, and generates blog posts for high-quality tools.

---

## Overview

### Architecture

The system is a **6-stage pipeline** that runs daily:

```
DETECT → FETCH → GENERATE → VALIDATE → TEST → INTEGRATE
(GitHub)  (Docs)  (Wrapper)   (XML)     (Run)  (Database)
                                               ↓
                                          BLOG GENERATION
```

**Primary Location**: `/home/yzhang/biomate/auto_update/`

### Key Capabilities

| Capability | Status | Success Rate |
|------------|--------|--------------|
| GitHub Tool Detection | Production | 100% |
| Documentation Fetching | Production | 95% |
| Galaxy XML Generation | Production | 100% |
| Wrapper Validation | Production | 100% |
| Container Testing | Needs Containers | Variable |
| Database Integration | Production | 100% |
| Blog Generation | Production | 100% |

---

## Daily Screening & Scheduling

### Cron Configuration

**File**: `auto_update/scripts/setup_cron.sh`

```bash
# Schedule: 2 AM daily (UTC)
0 2 * * * /home/yzhang/biomate/auto_update/scripts/daily_update.sh
```

### Main Entry Point

**File**: `auto_update/scripts/daily_update.sh` (305 lines)

**Process**:
1. Backup database before running
2. Gather pre-run statistics
3. Execute full pipeline
4. Collect post-run statistics
5. Generate daily summary report
6. Clean up old logs (>30 days) and reports (>90 days)

**Default Configuration**:
```bash
DAYS_BACK=1           # Look for tools updated in last 1 day
MIN_STARS=10          # Minimum GitHub stars
LIMIT=0               # No limit (process all found tools)
ENABLE_TEST=0         # Skip Docker testing (faster)
```

---

## Pipeline Stages

### Stage 1: GitHub Tool Detection

**File**: `auto_update/scripts/detect_github_tools.py` (547+ lines)

**Data Sources**: GitHub API with 55+ bioinformatics topics:
- Core: bioinformatics, genomics, proteomics, metabolomics
- Sequencing: single-cell, rna-seq, variant-calling, chip-seq, atac-seq
- Structural: protein-structure, molecular-dynamics, alphafold
- Specialized: crispr, drug-discovery, spatial-transcriptomics

**Quality Scoring Algorithm** (0.0-1.0):

| Factor | Weight | Details |
|--------|--------|---------|
| Popularity | 30% | Stars (tier1:500, tier2:200, tier3:50) |
| Code Quality | 35% | CI/CD, tests, linting |
| Documentation | 20% | README, docs, examples |
| Containerization | 10% | Dockerfile, Singularity |
| Recency | 10% | Days since last commit |
| Scientific | 35% | Has paper, citations (>10) |
| Releases | 5% | Has version tags |

**Auto-Discovery Classification**:
- **High Quality (>0.8)**: Auto-approved for processing
- **Medium Quality (0.5-0.8)**: Review queue
- **Low Quality (<0.5)**: Rejected

---

### Stage 2: Documentation Fetching

**File**: `auto_update/scripts/documentation_fetcher.py` (300+ lines)

**Data Extracted**:
- README.md content (cleaned markdown)
- Installation instructions
- Usage examples and API documentation
- Container information (Dockerfile, docker-compose.yml)
- Dependencies (requirements.txt, environment.yml)
- Help text and CLI details

**Success Rate**: 95%+

---

### Stage 3: Galaxy Wrapper Generation

**File**: `auto_update/scripts/galaxy_wrapper_generator.py` (600+ lines)

**Generates**:
```xml
<tool id="auto_foldseek" name="Foldseek" version="15.0">
    <description>Protein structure alignment</description>
    <command><![CDATA[foldseek commands]]></command>
    <inputs>
        <param name="input_db" type="data" format="fasta" />
    </inputs>
    <outputs>
        <data name="output_aln" format="txt" />
    </outputs>
</tool>
```

---

### Stage 4: Wrapper Validation

**File**: `auto_update/scripts/validate_wrapper.py` (400+ lines)

**Validation Checks**:
1. XML syntax validity
2. Required elements (id, name, version, description, command)
3. Command section structure
4. Container accessibility verification
5. Parameter usage validation
6. Tool ID format compliance

---

### Stage 5: Tool Testing (Optional)

**File**: `auto_update/scripts/test_tool_execution.py` (450+ lines)

Runs tools in Docker containers to verify execution. Requires container images to be available.

---

### Stage 6: Database Integration

**File**: `auto_update/scripts/integrate_tools.py` (500+ lines)

**Database**: `backend/database/galaxy_ai_tools.db`

**Auto-Update Columns**:
```sql
auto_discovered BOOLEAN DEFAULT 0
discovery_date TIMESTAMP
quality_score REAL
github_url TEXT
wrapper_path TEXT
topics TEXT
language TEXT
stars INTEGER
```

**Duplication Detection** (3-tier):
1. Exact tool_id match
2. Name similarity (fuzzy matching)
3. GitHub URL comparison

**Prevention Rate**: 100%

---

## Blog Generation System

### AI-Powered Evaluation

**File**: `auto_update/scripts/blog_worthiness_evaluator.py` (395 lines)

**Tool**: Claude Haiku 4.5 with Prompt Caching

**Blog-Worthy Criteria**:
- Specific bioinformatics tools (e.g., DeepVariant, AlphaFold)
- Novel computational models
- Tools solving specific research problems
- Methods with peer-reviewed publications

**Not Blog-Worthy**:
- General programming libraries (Biopython, NumPy)
- Generic containers/frameworks
- Low-level utilities without biological context

**Cost**: ~$0.002 per tool evaluation

---

### Blog Post Generation

**File**: `auto_update/scripts/blog_post_generator.py` (430 lines)

**Components**:
1. Tool introduction and significance
2. Biological relevance
3. Input/output descriptions
4. Workflow integration suggestions
5. "Try Now" button with authentication
6. GitHub badges and quality indicators

---

### Iterative Review Agent

**File**: `auto_update/scripts/blog_review_agent.py` (420 lines)

**Process**:
1. Reviews generated blog post
2. Identifies quality issues
3. Suggests improvements
4. Automatically improves post
5. Re-evaluates until quality >= 0.85 or max 5 iterations

---

## Configuration

### Environment Variables

**File**: `auto_update/.env`

```bash
GITHUB_TOKEN=ghp_...    # GitHub API token
ANTHROPIC_API_KEY=sk-...  # Claude API for evaluation
```

### Data Sources

**File**: `auto_update/config/sources.yaml`

```yaml
github:
  api_url: https://api.github.com
  min_stars: 50
  lookback_days: 90
  languages: [Python, R, Nextflow, Snakemake, WDL, Rust, Julia]

quality_thresholds:
  auto_approve: 0.8
  review_queue: 0.5
  minimum: 0.5
```

### Quality Filters

**File**: `auto_update/config/filters.yaml`

**Required Signals**:
- README.md
- License file
- Recent commit (last 90 days)

**Bonus Signals**:
- Documentation site: +0.1
- Tests: +0.15
- CI/CD: +0.15
- Container: +0.1
- Paper: +0.2

---

## Monitoring & Health Checks

### Monitoring Script

**File**: `auto_update/scripts/monitor_daily_runs.py` (13,587 lines)

**Metrics Tracked**:
- Total tools in database
- Auto-discovered count
- Tools added today/7 days
- Average per day (30d)
- Run status and duration

**Alert Levels**:

| Level | Condition |
|-------|-----------|
| Healthy | Ran in last 24h, DB accessible |
| Warning | Failed but completed, or no run in 30h |
| Critical | No run in 2 days, DB inaccessible |

### Daily Summary Reports

**Location**: `auto_update/reports/daily/summary_YYYY-MM-DD.json`

```json
{
  "date": "2025-11-07",
  "tools_added": 3,
  "citation_rate": 67.0,
  "avg_quality_score": 0.825,
  "categories": [{"category": "RNA-Seq", "count": 2}]
}
```

---

## Directory Structure

```
auto_update/
├── scripts/                          # Python & Bash scripts
│   ├── daily_update.sh              # Main entry point
│   ├── detect_github_tools.py       # GitHub screening
│   ├── documentation_fetcher.py     # Doc extraction
│   ├── galaxy_wrapper_generator.py  # XML generation
│   ├── validate_wrapper.py          # XML validation
│   ├── integrate_tools.py           # Database integration
│   ├── run_pipeline.py              # Orchestrator
│   ├── blog_worthiness_evaluator.py # AI evaluation
│   ├── blog_post_generator.py       # Blog creation
│   ├── blog_review_agent.py         # Quality improvement
│   └── monitor_daily_runs.py        # Health monitoring
├── config/
│   ├── sources.yaml                 # Data source config
│   └── filters.yaml                 # Quality filters
├── data/
│   ├── discoveries/                 # JSON discovery results
│   └── wrappers/                    # Generated XML wrappers
├── logs/daily/                      # Execution logs
├── reports/daily/                   # Summary reports
├── backups/                         # Database backups
└── .env                             # Environment variables
```

---

## Usage

### Manual Pipeline Run

```bash
cd /home/yzhang/biomate/auto_update
./scripts/daily_update.sh
```

### Detect Tools Only

```bash
python scripts/detect_github_tools.py --days 30 --min-stars 50
```

### Generate Blogs

```bash
python scripts/generate_blogs_with_review.py --all-new --output ./blogs
```

### Monitor Health

```bash
python scripts/monitor_daily_runs.py --health-check
```

---

## Integration Points

| System | Integration |
|--------|-------------|
| GitHub API | Tool detection and metadata |
| Galaxy Database | Tool storage (galaxy_ai_tools.db) |
| Claude AI | Blog evaluation and generation |
| Tool Search Index | Embeddings for semantic search |
| Frontend Blog System | Published blog posts |

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| Processing Speed | 2-4 tools/minute |
| Per-tool Latency | 12-18 seconds |
| Field Completeness | 87.5% |
| Citation Success Rate | 75% |
| Duplicate Prevention | 100% |
| Cost per Tool | $0.003-0.004 |
| Daily Capacity | 100-200 tools |

---

**Architecture Diagram**: See `docs/architecture/25_auto_update_pipeline.drawio.xml`

**Last Updated**: January 12, 2026
