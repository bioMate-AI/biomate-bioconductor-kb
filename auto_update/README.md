# BioMate Auto-Update System

**Purpose:** Automated discovery and integration of cutting-edge bioinformatics tools, datasets, workflows, and AI models.

## Overview

This system automatically discovers, evaluates, and integrates new bioinformatics resources from multiple sources including GitHub, Hugging Face, PubMed, and scientific repositories.

## Directory Structure

```
auto_update/
├── README.md                 # This file
├── docs/
│   ├── ARCHITECTURE.md       # System architecture and design
│   ├── ANALYSIS.md          # Detailed analysis and recommendations
│   └── API_USAGE.md         # API documentation and rate limits
├── scripts/
│   ├── detect_github_tools.py       # GitHub tool discovery
│   ├── detect_huggingface_models.py # HuggingFace model discovery
│   ├── detect_workflows.py          # Workflow detection
│   ├── detect_datasets.py           # Dataset discovery
│   ├── quality_scorer.py            # Quality scoring algorithm
│   └── integrator.py                # Integration into BioMate
├── config/
│   ├── sources.yaml         # Data source configurations
│   ├── filters.yaml         # Quality filters and thresholds
│   └── credentials.yaml     # API tokens (gitignored)
└── data/
    ├── discoveries/         # Daily discovery reports
    ├── review_queue/        # Items awaiting review
    └── approved/            # Approved items ready for integration
```

## Quick Start

### 1. Setup

```bash
# Install dependencies
cd /home/yzhang/biomate/auto_update
pip install -r requirements.txt

# Configure GitHub token
cp config/credentials.yaml.example config/credentials.yaml
# Edit credentials.yaml and add your GitHub token
```

### 2. Run Detection

```bash
# Detect new GitHub tools
python scripts/detect_github_tools.py --days 90 --min-stars 50

# Output: data/discoveries/github_tools_YYYYMMDD.json
```

### 3. Review Results

```bash
# View high-quality discoveries
python scripts/review_discoveries.py --score-threshold 0.8

# Approve items
python scripts/approve_tool.py --id <tool_id>
```

### 4. Integrate Approved Tools

```bash
# Auto-generate Galaxy wrappers and add to database
python scripts/integrator.py --source data/approved/
```

## Features

### Automated Detection
- **GitHub**: New repos, trending tools, workflow files
- **Hugging Face**: Biology/genomics models, datasets
- **PubMed/bioRxiv**: Papers with associated code
- **Zenodo/FigShare**: Public datasets

### Quality Scoring
- Multi-factor algorithm (stars, docs, tests, CI/CD, papers)
- Configurable thresholds for auto-approval
- Manual review queue for medium-confidence items

### Integration
- Auto-generate Galaxy tool wrappers
- Create database entries with metadata
- Generate embeddings for semantic search
- Update tool index

### Monitoring
- Daily discovery reports
- Quality metrics tracking
- Integration success rates

## Configuration

### sources.yaml
```yaml
github:
  topics: [bioinformatics, genomics, proteomics, metabolomics]
  min_stars: 50
  lookback_days: 90

huggingface:
  tags: [biology, genomics, protein-folding, drug-discovery]
  min_downloads: 100

quality_thresholds:
  auto_approve: 0.8
  review_queue: 0.5
  reject: 0.5
```

### filters.yaml
```yaml
required_signals:
  - has_readme
  - has_license
  - recent_commit_30_days

bonus_signals:
  - has_documentation
  - has_tests
  - has_ci_cd
  - has_container
  - has_paper
```

## Usage Examples

### Find new tools from last 3 months
```bash
python scripts/detect_github_tools.py --days 90 --output data/discoveries/
```

### Search for protein-related models on Hugging Face
```bash
python scripts/detect_huggingface_models.py --tags protein,biology --limit 50
```

### Detect new Nextflow workflows
```bash
python scripts/detect_workflows.py --type nextflow --min-stars 20
```

### Review and approve discoveries
```bash
# List pending reviews
python scripts/review_discoveries.py --status pending

# Approve a tool
python scripts/approve_tool.py --id github/user/repo

# Auto-approve high-quality items
python scripts/auto_approve.py --threshold 0.85
```

## Scheduling

Add to crontab for automated daily runs:

```bash
# Daily detection at 6 AM
0 6 * * * cd /home/yzhang/biomate/auto_update && python scripts/detect_github_tools.py >> logs/github_daily.log 2>&1

# Weekly HuggingFace scan on Sunday at 7 AM
0 7 * * 0 cd /home/yzhang/biomate/auto_update && python scripts/detect_huggingface_models.py >> logs/huggingface_weekly.log 2>&1
```

## Development Status

- [x] Architecture design
- [x] Analysis and recommendations
- [x] Prototype GitHub detector
- [ ] Hugging Face detector
- [ ] Workflow detector
- [ ] Dataset detector
- [ ] Quality scorer
- [ ] Integration pipeline
- [ ] Web UI for review queue
- [ ] Email notifications

## References

- **Analysis Document**: `docs/ANALYSIS.md`
- **Architecture**: `docs/ARCHITECTURE.md`
- **API Documentation**: `docs/API_USAGE.md`

## Support

For questions or issues, refer to the documentation in `docs/` or review the implementation plan.
