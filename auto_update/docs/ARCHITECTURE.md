# Auto-Update System Architecture

**Version:** 1.0
**Date:** 2025-11-04
**Status:** Design Complete

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Auto-Update System                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │   GitHub     │   │ Hugging Face │   │   PubMed     │       │
│  │   Detector   │   │   Detector   │   │   Detector   │       │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘       │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                             │                                   │
│                   ┌─────────▼─────────┐                        │
│                   │ Quality Scorer    │                        │
│                   │ (0.0 - 1.0)       │                        │
│                   └─────────┬─────────┘                        │
│                             │                                   │
│              ┌──────────────┼──────────────┐                   │
│              │              │              │                   │
│     ┌────────▼────────┐     │     ┌───────▼────────┐          │
│     │ Auto-Add        │     │     │ Review Queue   │          │
│     │ (score > 0.8)   │     │     │ (0.5-0.8)      │          │
│     └────────┬────────┘     │     └───────┬────────┘          │
│              │              │              │                   │
│              │     ┌────────▼────────┐     │                   │
│              │     │ Reject          │     │                   │
│              │     │ (score < 0.5)   │     │                   │
│              │     └─────────────────┘     │                   │
│              │                              │                   │
│              └──────────────┬───────────────┘                   │
│                             │                                   │
│                   ┌─────────▼─────────┐                        │
│                   │   Integrator      │                        │
│                   │ - Generate wrapper│                        │
│                   │ - Add to database │                        │
│                   │ - Generate embed  │                        │
│                   └─────────┬─────────┘                        │
│                             │                                   │
│                   ┌─────────▼─────────┐                        │
│                   │ BioMate Database  │                        │
│                   │ galaxy_ai_tools.db│                        │
│                   └───────────────────┘                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Architecture

### 1. Detection Layer

**Responsibilities:**
- Scan external sources for new tools/models/datasets
- Extract metadata (name, description, URL, etc.)
- Filter by basic criteria (recent, maintained)

**Components:**

#### GitHubDetector
```python
class GitHubDetector:
    def __init__(self, token, topics, min_stars):
        self.client = GitHub(token)
        self.topics = topics
        self.min_stars = min_stars

    def detect(self, days_back=90):
        # Search for repos
        # Filter by quality signals
        # Return list of candidates
        pass
```

**Data Flow:**
```
GitHub API → Search repos by topic → Filter by criteria → Extract metadata → Return candidates
```

#### HuggingFaceDetector
```python
class HuggingFaceDetector:
    def __init__(self, tags, min_downloads):
        self.client = HfApi()
        self.tags = tags
        self.min_downloads = min_downloads

    def detect(self):
        # List models by tag
        # Filter by downloads
        # Extract metadata
        pass
```

#### WorkflowDetector
```python
class WorkflowDetector:
    def __init__(self, workflow_type='nextflow'):
        self.workflow_type = workflow_type

    def detect(self):
        # Search for workflow files
        # Parse workflow.nf / Snakefile
        # Extract steps
        pass
```

---

### 2. Quality Scoring Layer

**Responsibilities:**
- Evaluate each candidate on multiple dimensions
- Compute composite quality score (0.0 - 1.0)
- Classify as high/medium/low quality

**Algorithm:**

```python
class QualityScorer:
    # Weights (tunable)
    WEIGHTS = {
        'popularity': 0.3,      # Stars, downloads
        'code_quality': 0.35,   # Tests, CI/CD, linting
        'documentation': 0.2,   # README, docs, examples
        'containerization': 0.1,# Docker, Singularity
        'recency': 0.1,         # Last commit
        'scientific': 0.35,     # Paper, citations
        'releases': 0.05        # Tagged releases
    }

    def score(self, repo):
        scores = {}

        # Popularity
        if repo.stars > 500: scores['popularity'] = 1.0
        elif repo.stars > 200: scores['popularity'] = 0.67
        elif repo.stars > 50: scores['popularity'] = 0.33
        else: scores['popularity'] = 0.0

        # Code quality
        code_score = 0.0
        if repo.has_ci_cd: code_score += 0.5
        if repo.has_tests: code_score += 0.5
        scores['code_quality'] = code_score

        # Documentation
        doc_score = 0.0
        if repo.has_docs: doc_score += 0.5
        if repo.has_examples: doc_score += 0.25
        if repo.has_readme: doc_score += 0.25
        scores['documentation'] = doc_score

        # ... more signals

        # Weighted sum
        total = sum(scores[k] * self.WEIGHTS[k] for k in scores)
        return min(total, 1.0)
```

**Decision Thresholds:**
```python
THRESHOLDS = {
    'auto_add': 0.8,      # High confidence
    'review_queue': 0.5,  # Medium confidence
    'reject': 0.5         # Low confidence
}
```

---

### 3. Review Queue Layer

**Responsibilities:**
- Store medium-confidence items for manual review
- Provide UI/CLI for approval/rejection
- Track approval decisions

**Data Structure:**

```python
ReviewQueueItem = {
    'id': 'github/user/repo',
    'source': 'github',
    'name': 'Tool Name',
    'description': 'Brief description',
    'url': 'https://github.com/user/repo',
    'quality_score': 0.65,
    'signals': {
        'stars': 120,
        'has_tests': True,
        'has_ci_cd': False,
        'has_docs': True,
        'has_paper': False
    },
    'detected_at': '2025-11-04T10:30:00Z',
    'status': 'pending',  # pending, approved, rejected
    'reviewed_by': None,
    'reviewed_at': None
}
```

**Storage:**
```
data/review_queue/
├── pending/
│   ├── github_user_repo.json
│   └── hf_org_model.json
├── approved/
│   └── ...
└── rejected/
    └── ...
```

---

### 4. Integration Layer

**Responsibilities:**
- Generate Galaxy tool wrappers
- Add to database
- Generate embeddings
- Update RAG system

**Workflow:**

```python
class Integrator:
    def integrate(self, tool_metadata):
        # 1. Generate Galaxy wrapper
        wrapper_xml = self.generate_wrapper(tool_metadata)

        # 2. Validate wrapper
        if not self.validate_wrapper(wrapper_xml):
            raise ValidationError()

        # 3. Add to database
        self.add_to_database(tool_metadata, wrapper_xml)

        # 4. Generate embedding
        embedding = self.generate_embedding(tool_metadata)
        self.store_embedding(tool_metadata['id'], embedding)

        # 5. Notify RAG system
        self.notify_rag_update()
```

**Wrapper Generation:**

```python
def generate_wrapper(self, tool):
    template = """
    <tool id="{tool_id}" name="{name}" version="{version}">
        <description>{description}</description>
        <requirements>
            <container type="docker">{container_image}</container>
        </requirements>
        <command><![CDATA[
            {command}
        ]]></command>
        <inputs>
            {inputs}
        </inputs>
        <outputs>
            {outputs}
        </outputs>
        <help><![CDATA[
            {help_text}
        ]]></help>
        <citations>
            {citations}
        </citations>
    </tool>
    """

    return template.format(
        tool_id=tool['id'],
        name=tool['name'],
        version=tool['version'],
        description=tool['description'],
        container_image=tool.get('container', ''),
        command=self.extract_command(tool),
        inputs=self.generate_inputs(tool),
        outputs=self.generate_outputs(tool),
        help_text=tool.get('readme', ''),
        citations=self.format_citations(tool.get('papers', []))
    )
```

---

### 5. Storage Layer

**Databases:**

#### Tool Discovery Database (SQLite)
```sql
CREATE TABLE discoveries (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,  -- github, huggingface, pubmed
    name TEXT NOT NULL,
    description TEXT,
    url TEXT NOT NULL,
    quality_score REAL,
    metadata TEXT,  -- JSON blob
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status TEXT,  -- pending, approved, rejected, integrated
    reviewed_by TEXT,
    reviewed_at TIMESTAMP,
    integrated_at TIMESTAMP
);

CREATE INDEX idx_status ON discoveries(status);
CREATE INDEX idx_detected ON discoveries(detected_at);
CREATE INDEX idx_quality ON discoveries(quality_score);
```

#### Integration with BioMate Database
```sql
-- Add to existing galaxy_ai_tools.db
ALTER TABLE tools ADD COLUMN discovery_source TEXT;
ALTER TABLE tools ADD COLUMN discovery_date TIMESTAMP;
ALTER TABLE tools ADD COLUMN quality_score REAL;
```

---

## Data Flow

### End-to-End Flow

```
1. Detection (Daily at 6 AM)
   ↓
   GitHub API → Search repos (bioinformatics topics, created in last 90 days)
   ↓
   Filter → Stars > 50, Has README, Recent commits
   ↓
   Extract metadata → Name, description, URL, stars, CI/CD, tests, etc.
   ↓
   Store → data/discoveries/github_YYYYMMDD.json

2. Quality Scoring
   ↓
   Load discoveries → Read JSON file
   ↓
   For each tool → Calculate quality score (0.0 - 1.0)
   ↓
   Classify → High (>0.8), Medium (0.5-0.8), Low (<0.5)
   ↓
   Route → Auto-add / Review queue / Reject

3. Review (Manual, for medium-confidence)
   ↓
   Daily digest → Email with 10-20 tools
   ↓
   User reviews → Approve / Reject
   ↓
   Update status → Move to approved/ or rejected/

4. Integration (Approved tools only)
   ↓
   Generate wrapper → Galaxy XML from template
   ↓
   Validate → Check XML syntax, required fields
   ↓
   Add to database → Insert into galaxy_ai_tools.db
   ↓
   Generate embedding → sentence-transformers/all-MiniLM-L6-v2
   ↓
   Store embedding → tool_embeddings table
   ↓
   Notify RAG → Trigger index update
   ↓
   Tool is now searchable!
```

---

## Configuration

### sources.yaml

```yaml
github:
  api_url: https://api.github.com
  topics:
    - bioinformatics
    - genomics
    - proteomics
    - metabolomics
    - computational-biology
    - single-cell
    - rna-seq
    - variant-calling
  min_stars: 50
  lookback_days: 90
  languages:
    - Python
    - R
    - Nextflow
    - Snakemake
    - WDL

huggingface:
  api_url: https://huggingface.co/api
  tags:
    - biology
    - genomics
    - protein-folding
    - drug-discovery
    - chemistry
  min_downloads: 100
  min_likes: 10

pubmed:
  api_url: https://eutils.ncbi.nlm.nih.gov/entrez/eutils
  search_terms:
    - "bioinformatics software"
    - "genomics tool"
    - "computational pipeline"
  lookback_months: 6
  max_results: 100

quality_thresholds:
  auto_approve: 0.8
  review_queue: 0.5
  min_score: 0.5
```

### filters.yaml

```yaml
required_signals:
  - has_readme
  - has_license
  - recent_commit_90_days

bonus_signals:
  - has_documentation: 0.1
  - has_tests: 0.15
  - has_ci_cd: 0.15
  - has_container: 0.1
  - has_paper: 0.2
  - has_examples: 0.05

scoring_weights:
  popularity: 0.3
  code_quality: 0.35
  documentation: 0.2
  containerization: 0.1
  recency: 0.1
  scientific: 0.35
  releases: 0.05
```

---

## API Interfaces

### Detection API

```python
# GitHub Detector
detector = GitHubDetector(token=GITHUB_TOKEN)
tools = detector.detect(
    topics=['bioinformatics', 'genomics'],
    min_stars=50,
    days_back=90
)
# Returns: List[ToolMetadata]

# Quality Scorer
scorer = QualityScorer()
for tool in tools:
    tool.quality_score = scorer.score(tool)
    tool.classification = scorer.classify(tool.quality_score)

# Save discoveries
save_discoveries(tools, 'data/discoveries/github_20251104.json')
```

### Review API

```python
# Load review queue
queue = ReviewQueue('data/review_queue')
pending = queue.get_pending()

# Approve tool
queue.approve(tool_id='github/user/repo', reviewed_by='yzhang')

# Get approved tools ready for integration
approved = queue.get_approved()
```

### Integration API

```python
# Integrator
integrator = Integrator(database='backend/database/galaxy_ai_tools.db')

for tool in approved_tools:
    try:
        # Generate wrapper
        wrapper = integrator.generate_wrapper(tool)

        # Integrate
        integrator.integrate(tool, wrapper)

        print(f"✅ Integrated: {tool.name}")
    except Exception as e:
        print(f"❌ Failed: {tool.name} - {e}")
```

---

## Monitoring & Logging

### Metrics to Track

```python
METRICS = {
    'detection': {
        'tools_found': 0,
        'api_calls': 0,
        'api_errors': 0,
        'execution_time_seconds': 0
    },
    'quality_scoring': {
        'high_quality': 0,  # >0.8
        'medium_quality': 0,  # 0.5-0.8
        'low_quality': 0,  # <0.5
        'avg_score': 0.0
    },
    'review': {
        'pending_count': 0,
        'approved_count': 0,
        'rejected_count': 0,
        'approval_rate': 0.0
    },
    'integration': {
        'integration_attempts': 0,
        'integration_successes': 0,
        'integration_failures': 0,
        'success_rate': 0.0
    }
}
```

### Logging

```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/auto_update.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger('auto_update')
logger.info(f"Detected {len(tools)} new tools")
logger.warning(f"API rate limit at 80%")
logger.error(f"Integration failed for {tool.name}: {error}")
```

---

## Deployment

### Cron Jobs

```bash
# /etc/crontab or crontab -e

# Daily GitHub detection at 6 AM
0 6 * * * cd /home/yzhang/biomate/auto_update && python scripts/detect_github_tools.py >> logs/github_daily.log 2>&1

# Weekly Hugging Face scan on Sunday at 7 AM
0 7 * * 0 cd /home/yzhang/biomate/auto_update && python scripts/detect_huggingface_models.py >> logs/huggingface_weekly.log 2>&1

# Daily integration of approved tools at 8 AM
0 8 * * * cd /home/yzhang/biomate/auto_update && python scripts/integrator.py >> logs/integration.log 2>&1

# Weekly metrics report on Monday at 9 AM
0 9 * * 1 cd /home/yzhang/biomate/auto_update && python scripts/generate_report.py >> logs/report.log 2>&1
```

### Environment Variables

```bash
# .env file
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
HUGGINGFACE_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxx
DATABASE_PATH=/home/yzhang/biomate/backend/database/galaxy_ai_tools.db
LOG_LEVEL=INFO
```

---

## Security Considerations

1. **API Tokens**: Store in environment variables, never commit to git
2. **Rate Limiting**: Respect API limits, implement exponential backoff
3. **Input Validation**: Sanitize all external input (URLs, descriptions)
4. **Database Backups**: Backup before integration runs
5. **Sandboxing**: Test wrapper generation in isolated environment

---

## Performance Optimization

1. **Caching**: Cache GitHub API responses for 24 hours
2. **Parallelization**: Use asyncio for concurrent API calls
3. **Batch Processing**: Process tools in batches of 10
4. **Incremental Updates**: Only re-scan repos that changed
5. **Database Indexing**: Add indexes on frequently queried fields

---

## Future Enhancements

1. **Web UI**: Interactive review interface
2. **Email Notifications**: Daily digest of new tools
3. **Slack Integration**: Approve tools via Slack emoji reactions
4. **Analytics Dashboard**: Visualize metrics over time
5. **Machine Learning**: Train classifier on approval/rejection patterns
6. **Community Voting**: Let users upvote/downvote tools

---

**Document Version:** 1.0
**Last Updated:** 2025-11-04
**Next Review:** After Phase 1 completion
