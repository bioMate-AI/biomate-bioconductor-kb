# BioMate Project TODO List

**Last Updated:** 2026-01-10
**Branch:** `comprehensive_integration`

---

## High Priority

### 1. Enhanced Database Query Engine
- [ ] **Test LLM integration with Ollama** - The enhanced query engine (`Biomni/biomni/tool/database_enhanced.py`) works with direct endpoints but LLM-based query generation needs testing with responsive Ollama
- [ ] **Add more database configurations** - Currently have 8 databases (UniProt, KEGG, PDB, ChEMBL, PubChem, ClinVar, gnomAD, Ensembl). Add configs for remaining 25 schema files
- [ ] **Populate local database directory** - Download commonly used reference files (UniProt FASTA, PDB structures) to `./data/local_databases/` for local-first queries
- [ ] **Test retry with LLM feedback** - Verify that API errors are properly passed back to LLM for query refinement

### 2. Galaxy Integration
- [ ] **Test all 200+ Biomni tools via Galaxy** - Only tested `design_primer` and `find_restriction_sites` so far
- [ ] **Fix any remaining tool XML issues** - Some tools may have parameter handling issues similar to `find_restriction_sites` (list parameters passed as strings)
- [ ] **Verify Docker container coverage** - Ensure `biomate/biotools:arm64` has all required dependencies for all tools

### 3. Biomni Tool Wrappers
- [ ] **Update remaining database query functions** - Integrate `use_enhanced_query()` into other database functions (query_kegg, query_pdb, query_chembl, etc.)
- [ ] **Add error handling to Galaxy wrappers** - Improve error messages in `*_wrapper.py` files for better debugging

---

## Medium Priority

### 4. LLM Configuration
- [ ] **Configure hybrid LLM routing** - Set up routing between Ollama (local) and Anthropic API based on task complexity
- [ ] **Test with different Ollama models** - Verify compatibility with qwen3:32b, llama3, mistral, etc.
- [ ] **Add API key management** - Secure storage for Anthropic API keys in production

### 5. Caching and Performance
- [ ] **Implement cache warming** - Pre-populate cache with common queries
- [ ] **Add cache statistics dashboard** - Monitor cache hit rates and popular queries
- [ ] **Configure TTL per database** - Adjust cache expiration based on data update frequency

### 6. Testing
- [ ] **Create integration test suite** - Automated tests for enhanced query engine
- [ ] **Add Galaxy tool tests** - Test each tool category (biochemistry, genomics, etc.)
- [ ] **Performance benchmarks** - Measure query latency with/without cache

---

## Low Priority

### 7. Documentation
- [ ] **Document enhanced query engine API** - Usage examples for `EnhancedQueryEngine`
- [ ] **Update Biomni tool documentation** - Add Galaxy-specific usage notes
- [ ] **Create deployment guide** - Instructions for setting up on new machines

### 8. Future Enhancements
- [ ] **Add more local data file formats** - Support for GFF, BED, VCF local lookups
- [ ] **Implement query suggestions** - Suggest corrections for failed queries
- [ ] **Add query history and analytics** - Track user query patterns

---

## Completed Tasks ✓

- [x] Create enhanced database query engine with:
  - [x] Local database/cache lookup
  - [x] Query validation against API schemas
  - [x] Retry with LLM feedback
  - [x] Rate limiting with exponential backoff
  - [x] SQLite-based query caching
  - [x] User interaction hooks
- [x] Fix Galaxy API SQLAlchemy relationship errors
- [x] Fix tool XML escaping issues (283 files)
- [x] Configure Docker for Ollama access (host networking)
- [x] Install langchain-anthropic and langchain-ollama in Docker
- [x] Integrate enhanced engine with existing database.py
- [x] Push all content to `comprehensive_integration` branch

---

## Quick Start for New Machine

```bash
# Clone the repository
git clone https://github.com/bioMate-AI/biomate.git
cd biomate
git checkout comprehensive_integration

# Set up environment variables
export OLLAMA_HOST=http://localhost:11434
export LLM_SOURCE=Ollama
export ANTHROPIC_API_KEY=your_key_here  # Optional

# Start Ollama (if using local LLM)
ollama serve &
ollama pull qwen3:32b

# Test enhanced query engine
cd Biomni
python3 -c "
from biomni.tool.database_enhanced import EnhancedQueryEngine
engine = EnhancedQueryEngine(data_path='./data')
result = engine.query('uniprot', endpoint='https://rest.uniprot.org/uniprotkb/P01308')
print(f'Success: {result.success}, Source: {result.source}')
"

# Start Galaxy backend (from backend directory)
cd ../backend
./run.sh
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `Biomni/biomni/tool/database_enhanced.py` | Enhanced query engine with caching, validation, retry |
| `Biomni/biomni/tool/database.py` | Original database functions (now integrated with enhanced engine) |
| `Biomni/biomni/tool/schema_db/*.pkl` | API schemas for 33 databases |
| `backend/config/job_conf.yml` | Galaxy job configuration for Docker execution |
| `backend/biomni_workflows/galaxy/docker/Dockerfile.arm64` | ARM64 bioinformatics Docker image |
| `backend/lib/galaxy/managers/workflows.py` | Fixed SQLAlchemy user comparisons |
| `backend/lib/galaxy/webapps/galaxy/services/histories.py` | Fixed SQLAlchemy user comparisons |

---

## Notes

- The Biomni directory was converted from a git submodule to regular files for easier management
- Schema files (`.pkl`) contain API documentation used by LLM to generate correct queries
- Cache database is stored at `./data/query_cache/query_cache.db`
- Rate limits are configured per database in `DATABASE_CONFIGS` dict
