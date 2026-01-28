# E2E Workflow Debug Progress

**Date:** 2026-01-27 16:01
**Session:** Continued from "BioMate E2E Testing: Bug Fixes & Workflow Import"

---

## Issue Resolved: Galaxy Workflow Import Failing

### Root Cause
The frontend was using the `bootstrap_admin_api_key` instead of a real user's API key:
```
# Old (broken):
GALAXY_API_KEY=e5b2a0e7e843b203ec49ec9a5b1a2dbfab20f92e72651410f29bd7b2101467b3  # bootstrap key

# New (working):
GALAXY_API_KEY=7341822cd19cddaa49139f6cccae8c76  # admin@galaxy.org user key
```

The `BootstrapAdminUser` is a Pydantic model (not SQLAlchemy), which cannot be assigned to database relationships like `StoredWorkflow.user`. This caused:
```
AttributeError: 'BootstrapAdminUser' object has no attribute '_sa_instance_state'
```

### Fix Applied
1. **Generated proper API key** for admin user via Galaxy API:
   ```bash
   curl -X POST "http://localhost:8081/api/users/f2db41e1fa331b3e/api_key" \
     -H "x-api-key: e5b2a0e7e843b203ec49ec9a5b1a2dbfab20f92e72651410f29bd7b2101467b3"
   # Returns: "7341822cd19cddaa49139f6cccae8c76"
   ```

2. **Updated `/home/yzhang/biomate/frontend/.env`**:
   ```
   GALAXY_API_KEY=7341822cd19cddaa49139f6cccae8c76
   VITE_GALAXY_API_KEY=7341822cd19cddaa49139f6cccae8c76
   ```

3. **Restarted frontend** to pick up new configuration

### Verification
- Galaxy API calls now authenticate as real `admin@galaxy.org` user
- Workflow import to Galaxy: **WORKING**
- History creation: **WORKING**
- Workflow invocation: **WORKING** (fails only when tools aren't installed - expected)

---

## Files Modified

| File | Change |
|------|--------|
| `/home/yzhang/biomate/frontend/.env` | Updated GALAXY_API_KEY and VITE_GALAXY_API_KEY |

---

## Current State

- **Galaxy:** Running on port 8081
- **Frontend:** Running on port 5000, connected to Galaxy
- **API Key:** Using admin@galaxy.org user's key (id: f2db41e1fa331b3e)

---

## Next Steps

1. Test E2E with existing BioMate workflows
2. Test query tools that can be preloaded
3. Validate complete workflow execution pipeline

---

## Test Commands

### Test Galaxy Connection
```bash
curl -s http://localhost:8081/api/version
curl -s http://localhost:5000/api/health
```

### Test Workflow Import
```bash
curl -s -X POST "http://localhost:8081/api/workflows" \
  -H "Content-Type: application/json" \
  -H "x-api-key: 7341822cd19cddaa49139f6cccae8c76" \
  -d '{"workflow": {...}}'
```

### Test E2E Execution
```bash
curl -s -X POST "http://localhost:5000/api/workflows/execute" \
  -H "Content-Type: application/json" \
  -d '{"workflowDefinition": {...}, "executionConfig": {"mode": "sandbox"}}'
```

---

## E2E Testing Progress (16:20)

### Biomni Tools Discovered

**Total Tools Loaded in Galaxy:** 356 tools (216 biomni tools)

**Query/Database Tools (ideal for testing - no file inputs):**
| Tool ID | Name |
|---------|------|
| `biomni_database_get_hpo_names` | Get HPO Names |
| `biomni_database_blast_sequence` | BLAST Sequence |
| `biomni_database_region_to_ccre_screen` | Region to CCRE Screen |
| `biomni_database_get_genes_near_ccre` | Get Genes Near CCRE |
| `biomni_database_reduce_tokens` | Reduce Tokens |
| `biomni_genomics_gene_set_enrichment_analysis` | Gene Set Enrichment Analysis |
| `biomni_systems_biology_query_chatnt` | Query ChatNT |

### Tool Test Results

**Gene Set Enrichment Analysis Test:**
- Tool: `biomni_genomics_gene_set_enrichment_analysis`
- Test Input: `CCNA2, CCNB1, CDK1, CDK2, TP53, RB1, E2F1, PCNA`
- Database: `ontology`
- Status: **Job Failed** - Exit code 1
- Error: Matplotlib cache directory permission issue (warning treated as error)
- Note: This is a Docker container execution issue, not an API issue

### Workflow Templates Available

**3 workflow templates in `/home/yzhang/biomate/frontend/data/workflow-templates/`:**
1. `5e61355f-...` - RNA-seq Differential Expression Analysis (requires FASTQ inputs)
2. `e0a62b3b-...` - TBD
3. `fd0e36c4-...` - TBD

### Frontend API Endpoints Tested

| Endpoint | Status |
|----------|--------|
| `GET /api/health` | Working |
| `POST /api/workflows/execute` | Working (API key fix applied) |
| `GET /api/workflow-templates/search` | Working |
| `GET /api/workflow-templates` | Working (returns 3 templates) |
| `POST /api/ai_assistant/chat` | Timeout/hangs (needs investigation) |

### Key Findings

1. **Workflow Import Pipeline:** Fixed and working
2. **Galaxy Tool Execution:** Has permission issues with Docker containers
3. **Biomni Tools:** 216 tools loaded, 7 database/query tools available
4. **Next:** Need to fix Docker execution environment for biomni tools
