# BioMate Comprehensive Integration - Development Roadmap

**Created:** 2026-01-10
**Branch:** `comprehensive_integration`
**Author:** Claude Opus 4.5 + Human collaboration

---

## Executive Summary

This document captures the current state of the BioMate project after implementing an enhanced database query system and integrating the Biomni bioinformatics tool framework. The work focused on making LLM-based database queries more reliable through local caching, validation, retry mechanisms, and rate limiting.

---

## Background and Motivation

### Why This Work Was Needed

The original Biomni database query system had several limitations:

1. **No validation of LLM-generated queries**: When the LLM generated an API URL from natural language, there was no check against the API schema before making the request. This led to failed queries that could have been prevented.

2. **No caching**: Every identical query made a fresh API call, wasting time and risking rate limits. For stable data like protein sequences, caching could save significant latency.

3. **No retry with feedback**: When an API call failed, the system returned an error without attempting to fix the query. The LLM could potentially correct its query if given the error message.

4. **No local data lookup**: Many bioinformatics labs have local copies of UniProt, PDB, or genome files. The system should check local files before making network requests.

5. **No rate limiting**: Different APIs have different rate limits (KEGG: 10/min, PubChem: 5/min). Without proper rate limiting, queries could be blocked.

### What Was Implemented

Created `Biomni/biomni/tool/database_enhanced.py` with:

- **LocalDatabaseManager**: Scans for local FASTA/PDB files, manages SQLite cache
- **QueryValidator**: Validates URLs against API schemas before execution
- **RateLimiter**: Per-database rate limiting with exponential backoff
- **EnhancedQueryEngine**: Orchestrates the full query flow with retry logic

---

## Current Work Session Summary

### Session Date: 2026-01-09 to 2026-01-10

#### What Was Accomplished

1. **Created Enhanced Database Query Engine** (`database_enhanced.py`)
   - 600+ lines of Python implementing the full enhancement stack
   - Supports 8 databases with full configuration
   - SQLite-based persistent caching with TTL
   - Tested successfully with direct API endpoints

2. **Integrated with Existing Codebase**
   - Modified `database.py` to import and use enhanced engine
   - Added `use_enhanced=True` parameter to `query_uniprot()` for backward compatibility
   - Enhanced engine is optional - falls back to original behavior if unavailable

3. **Fixed Galaxy Integration Issues**
   - Fixed SQLAlchemy relationship comparison errors in `workflows.py` and `histories.py`
   - Fixed XML escaping issues in 283 tool definition files
   - Configured Docker host networking for Ollama LLM access

4. **Repository Cleanup**
   - Converted all git submodules (Biomni, research repos) to regular directories
   - Force-added previously ignored schema files (33 `.pkl` files)
   - Pushed 37,787 files to `comprehensive_integration` branch

#### What Was Tested

| Component | Status | Notes |
|-----------|--------|-------|
| Query parameter extraction | ✅ Passed | Correctly extracts accession, gene, organism from prompts |
| URL validation | ✅ Passed | Validates against schema, reports warnings |
| SQLite caching | ✅ Passed | Stores and retrieves cached results |
| Direct API queries | ✅ Passed | UniProt P01308 query returned insulin data |
| Cache hit on repeat query | ✅ Passed | Second query returned `source: cache` |
| LLM query generation | ⚠️ Timeout | Ollama was slow to respond, needs retry |

---

## TODO Items

### High Priority

#### 1. Complete LLM Integration Testing
**Background:** The enhanced query engine's LLM integration was not fully tested because Ollama was slow to respond during the session. The `_generate_query()` method needs validation with a responsive LLM.

**Motivation:** Without LLM-based query generation, users must provide direct API endpoints. The natural language interface is the key user-facing feature.

**Tasks:**
- [ ] Test with Ollama qwen3:32b when server is responsive
- [ ] Test with Anthropic API as fallback
- [ ] Verify retry-with-feedback loop works (API error → LLM correction → retry)
- [ ] Measure query generation latency

#### 2. Expand Database Configurations
**Background:** The `DATABASE_CONFIGS` dictionary currently has 8 databases, but there are 33 schema files available. Each database needs proper rate limit configuration.

**Motivation:** Users querying KEGG, Reactome, or other databases won't benefit from rate limiting or validation without proper configuration.

**Tasks:**
- [ ] Add configs for: Reactome, StringDB, InterPro, JASPAR, GWAS Catalog, PRIDE, QuickGO, etc.
- [ ] Research rate limits for each API (check documentation)
- [ ] Set appropriate cache TTLs (clinical data: 24h, structure data: 1 month)

#### 3. Populate Local Reference Data
**Background:** The `LocalDatabaseManager` can check local files before API calls, but the `./data/local_databases/` directory is empty.

**Motivation:** For frequently accessed data (human proteome, common gene sequences), local lookup is 100x faster than API calls.

**Tasks:**
- [ ] Download Swiss-Prot human proteome FASTA (~20MB)
- [ ] Download PDB structures for common proteins (BRCA1, TP53, insulin)
- [ ] Add KEGG pathway XML files for common pathways
- [ ] Update `_lookup_local_*` methods if new formats are added

#### 4. Test Remaining Biomni Galaxy Tools
**Background:** Only 2 of 200+ tools were tested during this session (`design_primer`, `find_restriction_sites`). The wrapper scripts may have similar issues.

**Motivation:** Users expect all advertised tools to work. Untested tools may fail in production.

**Tasks:**
- [ ] Create test script that runs each tool with sample inputs
- [ ] Document which tools require specific Docker images
- [ ] Fix any parameter handling issues (list vs string)
- [ ] Verify all database query tools work with enhanced engine

---

### Medium Priority

#### 5. Implement Hybrid LLM Routing
**Background:** Currently, the system uses either Ollama or Anthropic, configured via environment variables. A hybrid approach could use fast local models for simple queries and powerful cloud models for complex ones.

**Motivation:** Reduce latency for simple queries while maintaining quality for complex ones. Also provides fallback if one service is unavailable.

**Tasks:**
- [ ] Design query complexity classifier
- [ ] Implement routing logic in `_generate_query()`
- [ ] Add health checks for both LLM services
- [ ] Configure automatic fallback on timeout

#### 6. Add Cache Analytics Dashboard
**Background:** The cache stores queries in SQLite with access counts and timestamps, but there's no way to visualize this data.

**Motivation:** Understanding cache hit rates helps optimize TTLs and identify popular queries for pre-warming.

**Tasks:**
- [ ] Create `get_cache_analytics()` method
- [ ] Add metrics: hit rate, popular queries, cache size
- [ ] Optional: Simple web dashboard for monitoring

#### 7. Create Integration Test Suite
**Background:** Currently, testing is manual. Automated tests would catch regressions and validate the full query flow.

**Motivation:** As the codebase grows, manual testing becomes impractical. CI/CD requires automated tests.

**Tasks:**
- [ ] Create `test_database_enhanced.py` with pytest
- [ ] Mock API responses for deterministic testing
- [ ] Test cache behavior, validation, rate limiting
- [ ] Add to CI pipeline

---

### Low Priority

#### 8. Documentation Updates
**Background:** The enhanced query engine has inline docstrings but no standalone documentation.

**Motivation:** Other developers need to understand how to use and extend the system.

**Tasks:**
- [ ] Create `docs/enhanced_query_engine.md` with examples
- [ ] Add architecture diagram showing query flow
- [ ] Document configuration options

#### 9. Add More Local File Formats
**Background:** Currently supports FASTA and PDB files. Bioinformatics uses many formats: GFF, BED, VCF, BAM, etc.

**Motivation:** Users with local variant calls (VCF) or annotations (GFF) should benefit from local lookup.

**Tasks:**
- [ ] Add VCF parsing for variant lookups
- [ ] Add GFF/GTF parsing for gene annotations
- [ ] Add BAM index lookup for alignment data

#### 10. Query Suggestion System
**Background:** When a query fails, the system returns an error but doesn't suggest corrections.

**Motivation:** Users may not know the correct query syntax. Suggestions improve UX.

**Tasks:**
- [ ] Analyze common query errors
- [ ] Build suggestion generator based on schema
- [ ] Integrate with user interaction callback

---

## Key Files Reference

| File Path | Purpose | Last Modified |
|-----------|---------|---------------|
| `Biomni/biomni/tool/database_enhanced.py` | Enhanced query engine (NEW) | 2026-01-10 |
| `Biomni/biomni/tool/database.py` | Original database functions (MODIFIED) | 2026-01-10 |
| `Biomni/biomni/tool/schema_db/*.pkl` | API schemas for 33 databases | - |
| `backend/config/job_conf.yml` | Galaxy Docker job configuration | 2026-01-09 |
| `backend/lib/galaxy/managers/workflows.py` | Fixed SQLAlchemy errors | 2026-01-09 |
| `backend/lib/galaxy/webapps/galaxy/services/histories.py` | Fixed SQLAlchemy errors | 2026-01-09 |

---

## Environment Setup for New Machine

```bash
# Clone repository
git clone https://github.com/bioMate-AI/biomate.git
cd biomate
git checkout comprehensive_integration

# Environment variables
export OLLAMA_HOST=http://localhost:11434
export LLM_SOURCE=Ollama
export BIOMNI_LLM=qwen3:32b
export ANTHROPIC_API_KEY=sk-...  # Optional fallback

# Start Ollama
ollama serve &
ollama pull qwen3:32b

# Verify installation
python3 -c "
import sys
sys.path.insert(0, 'Biomni')
from biomni.tool.database_enhanced import EnhancedQueryEngine
engine = EnhancedQueryEngine(data_path='./data')
result = engine.query('uniprot', endpoint='https://rest.uniprot.org/uniprotkb/P01308')
print(f'Test: {\"PASSED\" if result.success else \"FAILED\"} - Source: {result.source}')
print(f'Cache stats: {engine.get_cache_stats()}')
"
```

---

## Architecture Overview

```
User Query (Natural Language)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│                  EnhancedQueryEngine                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ LocalDBManager  │  │ QueryValidator  │  │ RateLimiter │ │
│  │ - Check local   │  │ - Load schema   │  │ - Per-DB    │ │
│  │ - Check cache   │  │ - Validate URL  │  │ - Backoff   │ │
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘ │
│           │                    │                   │        │
│           ▼                    ▼                   ▼        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Query Flow                           ││
│  │  1. Check local files → 2. Check cache → 3. Generate    ││
│  │  query with LLM → 4. Validate → 5. Rate limit →         ││
│  │  6. Execute API → 7. Cache result → 8. Return           ││
│  └─────────────────────────────────────────────────────────┘│
│           │                                                 │
│           ▼ (on failure)                                    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Retry Loop: Pass error to LLM → Regenerate → Retry     ││
│  │  Max 3 attempts with exponential backoff                ││
│  └─────────────────────────────────────────────────────────┘│
│           │                                                 │
│           ▼ (if all retries fail)                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  User Interaction Callback (optional)                   ││
│  │  Ask user to clarify or provide direct endpoint         ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
         │
         ▼
    QueryResult
    - success: bool
    - data: dict
    - source: "local" | "cache" | "api"
    - attempts: int
```

---

## Completed Work ✓

- [x] Design and implement `database_enhanced.py` (600+ lines)
- [x] Implement `LocalDatabaseManager` with SQLite cache
- [x] Implement `QueryValidator` with schema loading
- [x] Implement `RateLimiter` with exponential backoff
- [x] Implement `EnhancedQueryEngine` orchestration
- [x] Configure 8 databases with rate limits and TTLs
- [x] Integrate with existing `database.py` (backward compatible)
- [x] Fix Galaxy SQLAlchemy relationship errors
- [x] Fix 283 tool XML escaping issues
- [x] Configure Docker host networking for Ollama
- [x] Install langchain-anthropic and langchain-ollama
- [x] Test direct endpoint queries (UniProt insulin: P01308)
- [x] Verify caching works (second query hit cache)
- [x] Convert submodules to regular directories
- [x] Push all 37,787 files to repository
