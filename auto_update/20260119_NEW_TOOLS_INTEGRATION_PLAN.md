# New Tools Integration Plan (Revised v3)
**Date:** 2026-01-19
**Status:** Planning
**Revision:** 3 - Simplified approach using existing infrastructure

---

## Executive Summary

Integration of 14 cutting-edge bioinformatics tools:
1. **Use existing MCP servers** where available (Chai-1, AlphaFold 3, Boltz)
2. **Standard auto_update pipeline** for the rest (detect → fetch → wrap → validate → integrate)
3. **Deep knowledge collection** for all tools (publications, docs, examples, troubleshooting)

---

## Tools Classification

### Group A: Existing MCP Servers (Integrate)

| Tool | MCP Server | Source |
|------|-----------|--------|
| **Chai-1** | chai-lab MCP | GitHub: chaidiscovery/chai-lab |
| **AlphaFold 3** | AlphaFold-MCP-Server | GitHub: Augmented-Nature/AlphaFold-MCP-Server |
| **Boltz-2** | boltz_mcp_server.py | Local: ToolUniverse_biomate |

### Group B: Standard Pipeline (API + Galaxy Wrapper)

| Tool | GitHub | Install | Notes |
|------|--------|---------|-------|
| **Evo 2** | ArcInstitute/evo2 | pip + NVIDIA NIM API | Use API for inference |
| **State** | ArcInstitute/state | uv | Virtual cell model |
| **ProTrek** | westlake-repl/ProTrek | conda | Has web API too |
| **DrugCLIP** | bowen-gao/DrugCLIP | clone | Virtual screening |
| **ProFam-1** | alex-hh/profam | clone | Protein family LM |
| **SynCraft** | catalystforyou/SynCraft-Core | clone | Uses Gemini API |
| **scFv_Pmpnn_AF2** | jbderoo/scFv_Pmpnn_AF2 | clone | Intrabody design |

### Group C: Commercial/Skip

| Tool | Reason |
|------|--------|
| **Noetik OCTO** | Commercial, no public access |
| **Benchling** | Commercial SaaS (API available with enterprise credentials) |
| **Latent-X2** | Commercial, partnership required |
| **BoltzGen** | Use Boltz-2 instead |

---

## Knowledge Collection Requirements

### For Each Tool, Collect:

#### 1. Publications
```json
{
  "primary_citation": {"doi": "...", "pmid": "...", "title": "...", "authors": [...], "journal": "...", "year": ...},
  "benchmark_papers": [...],
  "review_papers": [...]
}
```

#### 2. Documentation
| Field | Source |
|-------|--------|
| `help_text` | GitHub README, CLI --help |
| `usage_guide` | Official docs, tutorials |
| `examples` | Example scripts, notebooks |
| `scientific_context` | When/why to use |

#### 3. Best Practices
| Field | Content |
|-------|---------|
| `recommended_parameters` | Defaults, ranges |
| `use_cases` | Common scenarios |
| `limitations` | Known issues |
| `alternatives` | When to use other tools |

#### 4. Troubleshooting
- Common errors & solutions
- Hardware requirements
- Dependency issues

---

## Tool Knowledge Summary

### 1. State (Arc Institute)
- **Publication**: bioRxiv 2025.06.26.661135
- **GitHub**: https://github.com/ArcInstitute/state
- **What**: Virtual cell model predicting perturbation responses
- **Key**: SE (embedding) + ST (transition) modules, 270M cells training
- **Install**: `uv tool install arc-state`

### 2. Chai-1
- **Publication**: Chai Discovery technical report
- **GitHub**: https://github.com/chaidiscovery/chai-lab
- **MCP**: chai-lab MCP (use existing)
- **What**: Multi-modal structure prediction (protein, DNA, RNA, ligands)
- **API**: BioLM available

### 3. Boltz-2
- **Publication**: MIT/Recursion paper
- **GitHub**: https://github.com/jwohlwend/boltz
- **MCP**: Already in ToolUniverse (use existing)
- **What**: Structure + binding affinity prediction
- **License**: MIT (fully open)

### 4. Evo 2
- **Publication**: Arc Institute Evo 2 paper
- **GitHub**: https://github.com/ArcInstitute/evo2
- **What**: 40B param DNA foundation model
- **API**: NVIDIA NIM (40 req/min)
- **Install**: `pip install evo2`

### 5. DrugCLIP
- **Publication**: Science 2026 (DOI: 10.1126/science.ads9530)
- **GitHub**: https://github.com/bowen-gao/DrugCLIP
- **What**: Virtual screening, 10M× faster
- **Install**: Clone + RDKit

### 6. scFv_Pmpnn_AF2
- **Publication**: Science Advances 2026 (DOI: 10.1126/sciadv.adx8352)
- **GitHub**: https://github.com/jbderoo/scFv_Pmpnn_AF2
- **What**: AI-assisted intrabody design
- **Dependencies**: ProteinMPNN, ColabFold, ANARCI

### 7. ProTrek
- **Publication**: Nature Biotech 2025 (DOI: 10.1038/s41587-025-02836-0)
- **GitHub**: https://github.com/westlake-repl/ProTrek
- **What**: Trimodal protein model (seq-struct-func)
- **API**: search-protrek.com (5B+ proteins)

### 8. ProFam-1
- **Publication**: bioRxiv 2025.12.19.695431
- **GitHub**: https://github.com/alex-hh/profam
- **What**: Protein family language model
- **Key**: 251M params, fitness prediction

### 9. SynCraft
- **Publication**: arXiv 2512.20333
- **GitHub**: https://github.com/catalystforyou/SynCraft-Core
- **What**: LLM-guided synthesizability optimization
- **Dependencies**: Gemini-2.5-Pro API

### 10. AlphaFold 3
- **Publication**: Nature 2024
- **GitHub**: https://github.com/google-deepmind/alphafold3
- **MCP**: AlphaFold-MCP-Server (use existing)
- **License**: CC-BY-NC-SA (non-commercial)
- **Alternative**: Boltz-2 (MIT license)

---

## Implementation Plan

### Phase 1: MCP Integration (Immediate)

**Task 1.1: Integrate existing MCP servers into Biomni**

Add to `Biomni/tutorials/examples/add_mcp_server/mcp_config.yaml`:
```yaml
mcp_servers:
  chai1:
    command: "npx"
    args: ["-y", "@anthropic/mcp-chai1"]
    # or clone from chaidiscovery/chai-lab

  alphafold:
    command: "python"
    args: ["-m", "alphafold_mcp_server"]
    # from Augmented-Nature/AlphaFold-MCP-Server

  boltz:
    # Already in ToolUniverse - just register
```

**Task 1.2: Verify Boltz MCP server in ToolUniverse**
- Location: `research_repos/ToolUniverse_biomate/src/tooluniverse/remote/boltz/`
- Update if needed for Boltz-2 features

### Phase 2: Knowledge Collection

**Task 2.1: Create knowledge collector**
```python
# auto_update/scripts/collect_new_tool_knowledge.py
# For each tool:
# 1. Fetch publication metadata from DOI/PubMed
# 2. Download README from GitHub
# 3. Extract examples, parameters, requirements
# 4. Store in tool_knowledge table
```

**Task 2.2: Collect for all 10 tools**
- Publications (DOI, PMID)
- GitHub documentation
- Examples and tutorials
- Hardware requirements

### Phase 3: Standard Pipeline Integration

**Task 3.1: Add tools to sources.yaml**
```yaml
manual_repos:
  - ArcInstitute/state
  - ArcInstitute/evo2
  - westlake-repl/ProTrek
  - bowen-gao/DrugCLIP
  - jbderoo/scFv_Pmpnn_AF2
  - alex-hh/profam
  - catalystforyou/SynCraft-Core
```

**Task 3.2: Run auto_update pipeline**
```bash
python scripts/run_pipeline.py --repos manual_repos
```

**Task 3.3: Generate Galaxy wrappers** (where applicable)

### Phase 4: Database Population

**Task 4.1: Populate tools table** (49 fields)
- Basic metadata
- Documentation fields
- Best practice fields

**Task 4.2: Populate tool_knowledge table**
- Primary citations
- Benchmark papers
- Use cases, limitations

### Phase 5: Skills & Testing

**Task 5.1: Create skill files** (optional)
- For tools requiring detailed guidance

**Task 5.2: End-to-end testing**
- Test MCP integrations
- Validate Galaxy wrappers
- Test knowledge retrieval

---

## API Keys Required

| Service | Purpose | How to Get |
|---------|---------|------------|
| NVIDIA NGC | Evo 2 API | developer.nvidia.com |
| BioLM | Chai-1 API (optional) | biolm.ai |
| Google | SynCraft (Gemini) | console.cloud.google.com |

---

## Summary

| Phase | Tasks | Tools |
|-------|-------|-------|
| 1. MCP Integration | Integrate 3 existing MCPs | Chai-1, AlphaFold 3, Boltz-2 |
| 2. Knowledge Collection | Docs, publications, examples | All 10 tools |
| 3. Pipeline Integration | Add to auto_update | 7 tools (Group B) |
| 4. Database Population | tool_knowledge table | All 10 tools |
| 5. Testing | E2E validation | All tools |

---

## References

### Publications
| Tool | DOI/Source |
|------|------------|
| DrugCLIP | 10.1126/science.ads9530 |
| ProTrek | 10.1038/s41587-025-02836-0 |
| scFv_Pmpnn_AF2 | 10.1126/sciadv.adx8352 |
| ProFam-1 | bioRxiv 2025.12.19.695431 |
| SynCraft | arXiv 2512.20333 |
| State | bioRxiv 2025.06.26.661135 |

### MCP Servers
- Chai-1: https://github.com/chaidiscovery/chai-lab
- AlphaFold: https://github.com/Augmented-Nature/AlphaFold-MCP-Server
- Boltz: ToolUniverse_biomate (local)
