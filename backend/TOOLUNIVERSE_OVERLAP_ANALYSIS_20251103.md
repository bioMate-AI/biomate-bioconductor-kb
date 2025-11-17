# ToolUniverse vs Galaxy Tools - Overlap Analysis & Integration Strategy
**Date:** November 3, 2025
**Status:** Analysis Complete

## Executive Summary

**Key Finding:** ToolUniverse and Galaxy tools are **complementary rather than overlapping**. They serve different purposes in the bioinformatics workflow.

- **ToolUniverse:** 745 total tools (68 main modules, 670 individual functions, 7 remote tools)
- **Galaxy:** 9,212 tools across 57 categories
- **True Overlaps:** Minimal (< 5%)
- **Recommendation:** Integrate both systems to create a comprehensive platform

## 1. Tool Inventory

### ToolUniverse Tool Breakdown

#### Main Tool Modules (68)
**Literature & Publications (14 tools):**
- pubmed, pmc, arxiv, biorxiv, medrxiv
- crossref, semantic_scholar, europe_pmc
- openalex, doaj, dblp, hal, osf_preprints, unpaywall

**Clinical & Drug Data (6 tools):**
- openfda, dailymed, ctg (ClinicalTrials.gov)
- clinvar, medlineplus, odphp

**Protein & Sequence (7 tools):**
- uniprot, alphafold, boltz
- rcsb_pdb, ensembl, string, protein_structure_3d

**Chemical & Molecular (5 tools):**
- pubchem, chem, admetai
- molecule_2d, molecule_3d

**Genomics & Variation (6 tools):**
- dbsnp, gnomad, gwas
- geo, ucsc, genomics_gene_search

**Cell & Biology (4 tools):**
- cellosaurus, hpa, biogrid, humanbase

**Pathways & Ontology (4 tools):**
- enrichr, gene_ontology, reactome, efo

**Databases & Knowledge (3 tools):**
- pubtator, wikidata_sparql, openaire

**Utility & Infrastructure (12 tools):**
- agentic, compose, custom, dataset
- graphql, restful, url, xml
- markitdown, mcp_client, visualization, remote

**Other (7 tools):**
- base, core, fatcat, openfda_adv
- package, uspto, zenodo

#### Individual Tool Functions (670+)
Examples of specialized functions:

**PubChem API Functions:**
- `PubChem_get_CID_by_compound_name`
- `PubChem_get_compound_properties_by_CID`
- `PubChem_search_compounds_by_similarity`
- `PubChem_search_compounds_by_substructure`

**UniProt API Functions:**
- `UniProt_get_function_by_accession`
- `UniProt_get_sequence_by_accession`
- `UniProt_get_disease_variants_by_accession`
- `UniProt_get_subcellular_location_by_accession`

**FDA/FAERS Functions (100+ functions):**
- `FDA_get_adverse_reactions_by_drug_name`
- `FDA_get_clinical_pharmacology_by_drug_name`
- `FAERS_count_death_related_by_drug`
- `FAERS_count_patient_age_distribution`

**ADMET Prediction Functions:**
- `ADMETAI_predict_BBB_penetrance`
- `ADMETAI_predict_toxicity`
- `ADMETAI_predict_bioavailability`

#### Remote Tools (7)
Specialized ML models and databases:
- **boltz** - Protein structure prediction
- **depmap_24q2** - Cancer dependency map
- **immune_compass** - Immune cell analysis
- **pinnacle** - Genomic variant effects
- **transcriptformer** - Gene expression modeling
- **expert_feedback** - Human-in-the-loop validation
- **uspto_downloader** - Patent data

### Galaxy Tool Breakdown (9,212 tools)

**Top Categories:**
- Metagenomics: 948 tools
- Sequence Analysis: 1,670 tools
- Variant Analysis: 508 tools
- Statistics: 488 tools
- Proteomics: 397 tools
- RNA: 389 tools
- Transcriptomics: 307 tools
- Assembly: 298 tools
- Convert Formats: 287 tools
- Computational chemistry: 282 tools

**Nature of Galaxy Tools:**
- Command-line bioinformatics software (BLAST, BWA, HISAT, etc.)
- Data processing pipelines (assembly, alignment, variant calling)
- Statistical analysis tools
- Format converters
- Workflow execution tools

## 2. Overlap Analysis

### Minimal True Overlap

The analysis found only **38 keyword-based potential overlaps**, but upon closer inspection, these are **false positives**:

**Examples of False Positives:**
- `alphafold` tool in ToolUniverse vs "ALPHAFOLD" in Galaxy
  - ToolUniverse: API wrapper to query AlphaFold database
  - Galaxy: Tool to run AlphaFold locally (different purposes)

- `gene_ontology` (1,618 "matches")
  - These are tools that USE Gene Ontology, not tools that QUERY Gene Ontology API

- `base`, `core`, `dataset` (3,000+ "matches")
  - Generic keywords that appear in many tool names

### Why They Don't Overlap

**ToolUniverse Tools:**
- API wrappers for external databases
- Real-time data retrieval
- Knowledge graph queries
- Literature search
- ML model inference endpoints

**Galaxy Tools:**
- Local computational tools
- Data processing executables
- Workflow components
- File format converters

**Example Comparison:**

| Feature | ToolUniverse `uniprot_tool` | Galaxy UniProt Tools |
|---------|----------------------------|---------------------|
| Purpose | Query UniProt REST API | Download/process UniProt data |
| Operation | Fetch protein info by accession | Parse UniProt XML/FASTA files |
| Data Source | Live UniProt database | Local UniProt files |
| Use Case | Look up single protein details | Batch process protein datasets |

## 3. Integration Strategy

### Recommended Approach: HYBRID INTEGRATION

Instead of choosing one over the other, integrate both to create a comprehensive platform.

#### Phase 1: Database API Integration (High Priority - 33 tools)

**Literature APIs (10 tools):**
```
Priority 1 (Core):
- pubmed, pmc - Essential for literature lookup
- crossref - DOI resolution and metadata

Priority 2 (Extended):
- biorxiv, medrxiv - Preprints
- semantic_scholar, openalex - Alternative literature search
- arxiv - Physics/CS papers
- europe_pmc, unpaywall - Open access search
```

**Clinical/Drug APIs (5 tools):**
```
Priority 1:
- openfda - FDA adverse events, drug labels
- ctg - ClinicalTrials.gov data
- dailymed - Drug information

Priority 2:
- medlineplus, odphp - Health information
```

**Protein/Structure APIs (5 tools):**
```
Priority 1:
- uniprot - Protein sequence and function
- alphafold - Structure predictions
- rcsb_pdb - Protein structures

Priority 2:
- string - Protein interactions
- boltz - Advanced structure prediction
```

**Chemical APIs (3 tools):**
```
Priority 1:
- pubchem - Chemical properties and bioactivity
- admetai - Drug property prediction

Priority 2:
- chem - ChEMBL queries
```

**Knowledge/Ontology APIs (4 tools):**
```
Priority 1:
- gene_ontology - GO terms and annotations
- enrichr - Pathway enrichment

Priority 2:
- reactome - Pathway data
- pubtator - Biomedical entity extraction
```

**Genomics APIs (4 tools):**
```
Priority 1:
- dbsnp - Variant information
- gnomad - Population genetics

Priority 2:
- gwas - GWAS catalog
- ensembl - Genome annotations
```

**Cell/Tissue APIs (2 tools):**
```
Priority 1:
- cellosaurus - Cell line information
- hpa - Human Protein Atlas
```

#### Phase 2: Integration Architecture

**1. Unified Tool Registry**

Create a unified tool catalog that includes both Galaxy tools and ToolUniverse APIs:

```python
# backend/services/unified_tool_registry.py

class UnifiedToolRegistry:
    """
    Combines Galaxy tools and ToolUniverse APIs in a single searchable registry.
    """

    def __init__(self):
        self.galaxy_tools = self.load_galaxy_tools()  # From galaxy_ai_tools.db
        self.tooluniverse_apis = self.load_tooluniverse_apis()  # From ToolUniverse

    def search_tools(self, query: str, categories: List[str] = None) -> List[Tool]:
        """
        Search across both Galaxy tools and ToolUniverse APIs.
        Returns unified tool objects with standardized interface.
        """
        galaxy_results = self.search_galaxy(query, categories)
        api_results = self.search_apis(query, categories)
        return self.merge_and_rank(galaxy_results, api_results)

    def get_tool(self, tool_id: str) -> Tool:
        """
        Get a tool by ID, automatically determining if it's Galaxy or API-based.
        """
        if tool_id.startswith("galaxy:"):
            return self.get_galaxy_tool(tool_id)
        elif tool_id.startswith("api:"):
            return self.get_api_tool(tool_id)
```

**2. Workflow Integration**

Enable workflows to use both Galaxy tools and API calls:

```yaml
# Example workflow combining both types

workflow:
  name: "Protein Analysis Pipeline"
  steps:
    # Step 1: Use ToolUniverse API to fetch protein info
    - id: "fetch_protein"
      tool: "api:uniprot:get_sequence_by_accession"
      inputs:
        accession: "${protein_id}"

    # Step 2: Use Galaxy tool for sequence analysis
    - id: "predict_structure"
      tool: "galaxy:alphafold2"
      inputs:
        sequence: "${fetch_protein.sequence}"

    # Step 3: Use ToolUniverse API to enrich with literature
    - id: "find_papers"
      tool: "api:pubmed:search_articles"
      inputs:
        query: "${protein_id}"

    # Step 4: Use Galaxy tool for visualization
    - id: "visualize"
      tool: "galaxy:pymol_visualization"
      inputs:
        structure: "${predict_structure.pdb}"
```

**3. API Tool Wrapper**

Create Galaxy-compatible wrappers for ToolUniverse APIs:

```xml
<!-- tools/api_wrappers/uniprot_fetch.xml -->
<tool id="api_uniprot_fetch" name="UniProt Fetch" version="1.0.0">
    <description>Fetch protein information from UniProt API</description>

    <command detect_errors="exit_code"><![CDATA[
        python '$__tool_directory__/uniprot_fetch.py'
            --accession '$accession'
            --output '$output'
            --format '$format'
    ]]></command>

    <inputs>
        <param name="accession" type="text" label="UniProt Accession" />
        <param name="format" type="select" label="Output Format">
            <option value="fasta">FASTA</option>
            <option value="json">JSON</option>
            <option value="xml">XML</option>
        </param>
    </inputs>

    <outputs>
        <data name="output" format="auto" />
    </outputs>

    <help><![CDATA[
        Fetches protein information from UniProt REST API.
        Uses ToolUniverse uniprot_tool module.
    ]]></help>
</tool>
```

```python
# tools/api_wrappers/uniprot_fetch.py
"""
Galaxy tool wrapper for ToolUniverse UniProt API.
"""
import sys
import argparse
from tooluniverse.uniprot_tool import UniprotTool

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--accession', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--format', default='fasta')
    args = parser.parse_args()

    # Use ToolUniverse API
    tool = UniprotTool()
    data = tool.get_entry_by_accession(args.accession)

    # Write to Galaxy output
    with open(args.output, 'w') as f:
        if args.format == 'fasta':
            f.write(data['sequence']['fasta'])
        elif args.format == 'json':
            import json
            json.dump(data, f, indent=2)
        elif args.format == 'xml':
            f.write(data['xml'])

if __name__ == '__main__':
    main()
```

#### Phase 3: Enhanced Chat Interface

Integrate ToolUniverse APIs into BioMate chat for intelligent data retrieval:

```python
# backend/services/llm_workflow_generator.py

class EnhancedWorkflowGenerator:
    """
    Enhanced workflow generator that can use both Galaxy tools and APIs.
    """

    def __init__(self):
        self.galaxy_tools = load_galaxy_tools()
        self.api_tools = load_tooluniverse_apis()

    async def generate_workflow(self, user_query: str):
        """
        Generate workflow using both computational tools and API calls.

        Example:
        User: "Analyze the function of protein P12345"

        Generated workflow:
        1. API: uniprot.get_function_by_accession("P12345")
        2. API: pubmed.search_articles(query=protein_name)
        3. API: alphafold.get_prediction("P12345")
        4. Galaxy: pymol_visualization(structure)
        """
        # Analyze query to determine if API calls are needed
        needs_literature = "papers" in user_query or "publications" in user_query
        needs_protein_info = re.search(r'\b[A-Z]\d{5}\b', user_query)  # UniProt accession
        needs_chemical = "compound" in user_query or "molecule" in user_query

        steps = []

        if needs_protein_info:
            steps.append({
                "type": "api",
                "tool": "uniprot:get_entry",
                "purpose": "Fetch protein information"
            })

        if needs_literature:
            steps.append({
                "type": "api",
                "tool": "pubmed:search",
                "purpose": "Find relevant publications"
            })

        if needs_chemical:
            steps.append({
                "type": "api",
                "tool": "pubchem:search",
                "purpose": "Retrieve chemical properties"
            })

        # Add computational analysis steps using Galaxy tools
        analysis_steps = await self.select_galaxy_tools(user_query)
        steps.extend(analysis_steps)

        return WorkflowDefinition(steps=steps)
```

#### Phase 4: Knowledge Graph Integration

Use ToolUniverse APIs to build a comprehensive knowledge graph:

```python
# backend/services/knowledge_graph.py

class BioMateKnowledgeGraph:
    """
    Build knowledge graph using ToolUniverse APIs.
    """

    def __init__(self):
        self.uniprot = UniProtTool()
        self.pubmed = PubMedTool()
        self.gene_ontology = GeneOntologyTool()
        self.string = StringTool()
        self.reactome = ReactomeTool()

    async def build_protein_subgraph(self, protein_id: str):
        """
        Build comprehensive protein knowledge subgraph.

        Integrates data from:
        - UniProt: Sequence, function, PTMs
        - PubMed: Publications
        - Gene Ontology: Functional annotations
        - STRING: Protein interactions
        - Reactome: Pathway involvement
        - AlphaFold: Structure predictions
        """
        # Fetch from multiple sources in parallel
        results = await asyncio.gather(
            self.uniprot.get_entry(protein_id),
            self.pubmed.search(f"{protein_id}[ACCN]"),
            self.gene_ontology.get_annotations(protein_id),
            self.string.get_interactions(protein_id),
            self.reactome.get_pathways(protein_id),
        )

        # Build unified knowledge graph
        graph = {
            "protein": results[0],
            "publications": results[1],
            "go_terms": results[2],
            "interactions": results[3],
            "pathways": results[4],
        }

        return graph
```

## 4. Implementation Roadmap

### Week 1-2: Infrastructure Setup
- [ ] Install ToolUniverse package in backend environment
- [ ] Create API tool wrapper framework
- [ ] Set up unified tool registry
- [ ] Test basic API connectivity

### Week 3-4: Priority 1 API Integration
- [ ] Integrate PubMed, PMC, Crossref (literature)
- [ ] Integrate UniProt (proteins)
- [ ] Integrate PubChem (chemicals)
- [ ] Integrate OpenFDA (drugs/adverse events)
- [ ] Create Galaxy tool wrappers for each API

### Week 5-6: Workflow Integration
- [ ] Update workflow execution engine to support API calls
- [ ] Implement API result caching
- [ ] Add API steps to workflow builder UI
- [ ] Test hybrid workflows (Galaxy + API)

### Week 7-8: Chat Enhancement
- [ ] Integrate API tools into LLM tool selection
- [ ] Add knowledge graph queries to chat
- [ ] Implement literature search in chat responses
- [ ] Add protein/chemical lookups to chat

### Week 9-10: Testing & Documentation
- [ ] End-to-end testing of hybrid workflows
- [ ] Performance optimization
- [ ] User documentation
- [ ] API rate limiting and error handling

## 5. Technical Considerations

### API Rate Limiting
```python
# backend/services/api_rate_limiter.py

from aiolimiter import AsyncLimiter

class APIRateLimiter:
    """
    Manage rate limits for external APIs.
    """

    limiters = {
        "pubmed": AsyncLimiter(3, 1),  # 3 requests per second (NCBI limit)
        "uniprot": AsyncLimiter(10, 1),  # 10 requests per second
        "pubchem": AsyncLimiter(5, 1),  # 5 requests per second
        "openfda": AsyncLimiter(240, 60),  # 240 requests per minute
    }

    @classmethod
    async def acquire(cls, api_name: str):
        """Acquire rate limit token before API call."""
        if api_name in cls.limiters:
            async with cls.limiters[api_name]:
                yield
        else:
            yield
```

### Caching Strategy
```python
# backend/services/api_cache.py

class APICache:
    """
    Cache API responses to reduce external calls.
    """

    def __init__(self, redis_client):
        self.redis = redis_client

    async def get_or_fetch(self, key: str, fetch_fn, ttl: int = 3600):
        """
        Get from cache or fetch and cache.

        Args:
            key: Cache key
            fetch_fn: Async function to fetch data
            ttl: Time to live in seconds
        """
        cached = await self.redis.get(key)
        if cached:
            return json.loads(cached)

        data = await fetch_fn()
        await self.redis.setex(key, ttl, json.dumps(data))
        return data
```

### Error Handling
```python
# backend/services/api_error_handler.py

class APIErrorHandler:
    """
    Graceful degradation when APIs are unavailable.
    """

    @staticmethod
    async def call_with_fallback(api_fn, fallback_fn=None):
        """
        Call API with fallback strategy.
        """
        try:
            return await api_fn()
        except APIRateLimitError:
            logger.warning("API rate limit exceeded, queuing for later")
            return {"status": "queued", "message": "Rate limit exceeded"}
        except APITimeoutError:
            logger.error("API timeout")
            if fallback_fn:
                return await fallback_fn()
            return {"status": "error", "message": "API unavailable"}
        except Exception as e:
            logger.error(f"API error: {e}")
            return {"status": "error", "message": str(e)}
```

## 6. Benefits of Integration

### For Users
1. **Comprehensive Data Access:** Query live databases without manual downloads
2. **Literature Integration:** Automatic citation and reference lookup
3. **Intelligent Workflows:** Combine data retrieval with analysis
4. **Knowledge Discovery:** Cross-reference proteins, chemicals, diseases
5. **Time Savings:** No need to manually search multiple databases

### For BioMate
1. **Competitive Advantage:** Unique combination of Galaxy + API access
2. **Richer Context:** LLM can use real-time database information
3. **Better Recommendations:** Tool selection based on live data
4. **Workflow Intelligence:** Auto-populate inputs from database queries
5. **Knowledge Graph:** Build comprehensive biological knowledge base

### Example Use Cases

**Use Case 1: Drug Discovery Workflow**
```
User query: "Find drugs that target BRAF V600E mutation and their adverse events"

Workflow:
1. API: uniprot.get_entry("BRAF") → Get protein info
2. API: dbsnp.get_variant("V600E") → Get mutation details
3. API: pubchem.search_by_target("BRAF") → Find targeting compounds
4. API: openfda.get_adverse_events(drug_names) → Get safety data
5. Galaxy: compound_analysis → Analyze chemical properties
6. API: pubmed.search(drugs + "BRAF V600E") → Find clinical studies
7. Generate: Comprehensive report with structures, safety, and literature
```

**Use Case 2: Protein Function Analysis**
```
User query: "Analyze the function and interactions of protein P12345"

Workflow:
1. API: uniprot.get_function("P12345") → Get functional annotation
2. API: string.get_interactions("P12345") → Get protein network
3. API: alphafold.get_structure("P12345") → Get predicted structure
4. API: gene_ontology.get_terms("P12345") → Get GO annotations
5. API: reactome.get_pathways("P12345") → Get pathway involvement
6. Galaxy: pymol_visualization → Create structure images
7. API: pubmed.search("P12345") → Find relevant papers
8. Generate: Comprehensive protein report with visualizations
```

**Use Case 3: Variant Interpretation**
```
User query: "Is rs1234567 pathogenic and what diseases is it associated with?"

Workflow:
1. API: dbsnp.get_variant("rs1234567") → Get variant details
2. API: clinvar.get_interpretation("rs1234567") → Get clinical significance
3. API: gnomad.get_frequency("rs1234567") → Get population frequency
4. API: pubmed.search("rs1234567") → Find related studies
5. API: gwas.get_associations("rs1234567") → Get disease associations
6. Generate: Variant interpretation report with evidence
```

## 7. Conclusion

ToolUniverse and Galaxy are **complementary systems** that should be **integrated**, not replaced:

- **Galaxy:** Provides computational analysis tools (9,212 tools)
- **ToolUniverse:** Provides database query APIs (745 tools)
- **Together:** Create a comprehensive bioinformatics platform

The integration strategy focuses on:
1. Adding ToolUniverse API wrappers to Galaxy tool catalog
2. Enabling hybrid workflows that combine computation and data retrieval
3. Enhancing chat interface with real-time database queries
4. Building knowledge graphs from multiple data sources

**Next Steps:**
1. Review and approve this integration strategy
2. Begin Phase 1 implementation (Priority 1 APIs)
3. Test hybrid workflows with selected use cases
4. Gather user feedback and iterate

## 8. Files and References

**Analysis Files:**
- Analysis script: `/tmp/analyze_tool_overlap.py`
- JSON report: `/tmp/tool_overlap_analysis.json`
- This document: `/home/yzhang/biomate/backend/TOOLUNIVERSE_OVERLAP_ANALYSIS_20251103.md`

**ToolUniverse Repository:**
- Location: `/home/yzhang/biomate/research_repos/ToolUniverse_biomate/`
- Documentation: `/home/yzhang/biomate/reference/TOOLUNIVERSE_INTEGRATION_ARCHITECTURE_20251028.md`

**Galaxy Database:**
- Location: `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db`
- Tools: 9,212 with scientific context
- nf-core: 1,841 tools with nf-core metadata
