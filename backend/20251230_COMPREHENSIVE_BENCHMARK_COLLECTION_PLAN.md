# Comprehensive Benchmark Collection Plan

## Executive Summary

**Current State Analysis:**
- Galaxy AI Tools DB: 8,095 tools total
- tool_knowledge table: 1,627 entries with citations
- BioMate tools: 286 XML tools across 21 domains
- nf-core modules: 335 modules, 213 with DOIs
- Auto-update tools: 4 (foldseek, htslib, MMseqs2, samtools)

**Critical Issues Identified:**
1. **Wrong Citations**: MetaPhlAn points to underwater laser scanner paper
2. **Wrong Citations**: DIA-NN points to 2006 DiANNA (disulfide bonds), not modern proteomics tool
3. **Missing Modern Tools**: AlphaFold3, DIA-NN (correct), Cellpose, modern LLM-based tools
4. **Empty Citations**: Major tools like AlphaFold, Salmon (in tools table), HISAT2 have empty citations

---

## Phase 1: Citation Validation & Correction

### 1.1 Identify Wrongly Cited Tools

**Automated Detection Strategy:**
```python
# Heuristics for detecting wrong citations:
1. Year mismatch: Tool first released 2020+, citation from 2006
2. Title keyword mismatch: "DIA" in tool name, but citation about "disulfide"
3. Journal domain mismatch: Proteomics tool citing optics journal
```

**Priority Tools to Audit:**
| Tool | Current Issue | Correct Citation |
|------|---------------|------------------|
| DIA-NN | Cites DiANNA 2006 (disulfide bonds) | Demichev et al. 2020, Nature Methods |
| MetaPhlAn | Cites underwater laser scanner 2023 | Beghini et al. 2021, eLife |
| AlphaFold | Empty/missing | Jumper et al. 2021, Nature |
| AlphaFold3 | Not in database | Abramson et al. 2024, Nature |
| Cellpose | Missing | Stringer et al. 2021, Nature Methods |

### 1.2 Citation Verification Process

1. Cross-reference tool name with PubMed
2. Verify DOI resolves to correct paper
3. Check author list matches tool developers
4. Validate journal is domain-appropriate

---

## Phase 2: Collect BioMate Tool Citations

### 2.1 BioMate Tool Categories (286 tools)

| Domain | Tool Count | Priority |
|--------|------------|----------|
| genomics | ~40 | HIGH |
| database | ~35 | HIGH |
| molecular_biology | ~30 | HIGH |
| pharmacology | ~25 | HIGH |
| bioimaging | ~20 | MEDIUM |
| immunology | ~15 | MEDIUM |
| cancer_biology | ~10 | MEDIUM |
| biochemistry | ~10 | MEDIUM |
| microbiology | ~15 | MEDIUM |
| synthetic_biology | ~10 | LOW |
| systems_biology | ~10 | LOW |
| Others | ~65 | LOW |

### 2.2 Citation Collection Strategy for BioMate

For each BioMate tool:
1. Extract tool name from XML `<tool id="...">`
2. Search PubMed for tool paper
3. Check bio.tools registry for DOI
4. Query CrossRef for citation metadata
5. Store in tool_knowledge table

**Sample BioMate Tools Requiring Citations:**
- `analyze_chromatin_interactions` → Hi-C/4C analysis benchmarks
- `gene_set_enrichment_analysis` → GSEA paper + comparisons
- `generate_gene_embeddings_with_ESM_models` → ESM paper (Meta AI)
- `annotate_celltype_scRNA` → CellTypist, scType papers
- `docking_autodock_vina` → AutoDock Vina paper

---

## Phase 3: nf-core DOI Integration

### 3.1 Current nf-core Coverage

- Total modules: 335
- Modules with DOIs: 213 (64%)
- Modules without DOIs: 122 (36%)

### 3.2 Priority nf-core Tools Missing DOIs

```
salmon, star, hisat2, bwa-mem2, minimap2, cellranger
kallisto, bowtie2, samtools, bcftools, gatk4
featurecounts, multiqc, fastp, trim_galore
```

### 3.3 Integration Process

1. Parse `nfcore_index.json` for existing DOIs
2. Cross-reference with bio.tools API
3. Map nf-core tool names to Galaxy tool IDs
4. Update tool_knowledge table

---

## Phase 4: Auto-Update Tool Citations

### 4.1 Current Auto-Update Tools

| Tool | Citation Status | Primary Paper |
|------|-----------------|---------------|
| foldseek | Missing | van Kempen et al. 2023, Nat Biotechnol |
| htslib | Missing | Danecek et al. 2021, GigaScience |
| MMseqs2 | Missing | Steinegger & Söding 2017, Nat Biotechnol |
| samtools | Missing | Li et al. 2009, Bioinformatics |

### 4.2 Collection Process

1. Check tool GitHub README for citation
2. Extract DOI from CITATION.cff if present
3. Query bio.tools API
4. Fallback to PubMed search

---

## Phase 5: Modern Tool Gap Analysis

### 5.1 Critical Missing Tools (2023-2024)

| Tool | Domain | Publication |
|------|--------|-------------|
| AlphaFold3 | Protein Structure | Abramson et al. 2024, Nature |
| DIA-NN v1.8+ | Proteomics | Demichev et al. 2020 + updates |
| Cellpose 2.0 | Cell Segmentation | Pachitariu & Stringer 2022 |
| scVI-tools | scRNA-seq | Gayoso et al. 2022, Nat Biotechnol |
| CellTypist | Cell Annotation | Dominguez Conde et al. 2022, Science |
| Enformer | Genomics | Avsec et al. 2021, Nat Methods |
| ESM-2/ESMFold | Protein ML | Lin et al. 2023, Science |
| GPT-4 for Bio | AI | Various 2023-2024 |

### 5.2 Benchmark Papers to Collect

**RNA-seq Benchmarks:**
- Soneson & Robinson 2018 (comparison of DE methods)
- Baruzzo et al. 2017 (aligner comparison)

**Proteomics Benchmarks:**
- Sinitcyn et al. 2021 (DIA software comparison)
- Navarro et al. 2016 (proteomics pipelines)

**Single-cell Benchmarks:**
- Luecken et al. 2022 (scRNA integration)
- Abdelaal et al. 2019 (cell type annotation)

**Protein Structure Benchmarks:**
- CASP15 results 2022
- Jumper et al. 2021 (AlphaFold)

---

## Phase 6: Implementation Plan

### 6.1 Database Schema Updates

```sql
-- Add citation verification fields
ALTER TABLE tool_knowledge ADD COLUMN citation_verified BOOLEAN DEFAULT 0;
ALTER TABLE tool_knowledge ADD COLUMN verification_date TEXT;
ALTER TABLE tool_knowledge ADD COLUMN verification_method TEXT;
ALTER TABLE tool_knowledge ADD COLUMN citation_confidence REAL;
```

### 6.2 Collection Pipeline

```python
# Automated citation collector
class BenchmarkCitationCollector:
    def __init__(self):
        self.pubmed_client = PubMedClient()
        self.biotools_client = BioToolsClient()
        self.crossref_client = CrossRefClient()

    def collect_for_tool(self, tool_name: str) -> dict:
        # 1. Check bio.tools first
        biotools_result = self.biotools_client.search(tool_name)
        if biotools_result and biotools_result.get('doi'):
            return self._enrich_citation(biotools_result)

        # 2. PubMed search
        pubmed_result = self.pubmed_client.search(f"{tool_name} software")
        if pubmed_result:
            return self._verify_and_enrich(pubmed_result, tool_name)

        # 3. CrossRef fallback
        return self.crossref_client.search(tool_name)

    def verify_citation(self, tool_name: str, citation: dict) -> float:
        # Returns confidence score 0-1
        score = 0.0

        # Check title contains tool name
        if tool_name.lower() in citation.get('title', '').lower():
            score += 0.4

        # Check year is reasonable
        if citation.get('year', 0) >= 2000:
            score += 0.2

        # Check journal is in bioinformatics list
        bio_journals = ['Nature Methods', 'Bioinformatics', 'Genome Biol', ...]
        if citation.get('journal') in bio_journals:
            score += 0.4

        return score
```

### 6.3 Priority Execution Order

1. **Week 1**: Fix critical wrong citations (DIA-NN, MetaPhlAn, etc.)
2. **Week 2**: Add missing modern tools (AlphaFold3, Cellpose, etc.)
3. **Week 3**: Collect BioMate tool citations (286 tools)
4. **Week 4**: Integrate nf-core DOIs (213 existing, 122 to find)
5. **Week 5**: Auto-update tool citations (4 tools)
6. **Week 6**: Benchmark paper collection (comparisons, reviews)

---

## Phase 7: Quality Metrics

### 7.1 Target Coverage

| Metric | Current | Target |
|--------|---------|--------|
| Tools with verified citations | ~1,500 | 3,000+ |
| Citation accuracy | ~90% | 99%+ |
| BioMate tool coverage | 0% | 100% |
| Modern tools (2023-2024) | ~10 | 50+ |
| Benchmark papers | ~50 | 200+ |

### 7.2 Validation Checks

1. DOI resolution test (all DOIs must resolve)
2. Author-tool correlation (tool developers should match authors)
3. Journal domain check (bioinformatics journals for bio tools)
4. Year sanity check (tool release year <= citation year)
5. Title keyword overlap (tool name should appear in title)

---

## Appendix A: BioMate Tool Domains

```
biochemistry/         - 9 tools
bioengineering/       - 13 tools
bioimaging/           - 19 tools
biophysics/           - 3 tools
cancer_biology/       - 7 tools
cell_biology/         - 5 tools
database/             - 36 tools (query APIs)
genetics/             - 11 tools
genomics/             - 26 tools
glycoengineering/     - 3 tools
immunology/           - 14 tools
lab_automation/       - 5 tools
literature/           - 8 tools
microbiology/         - 17 tools
molecular_biology/    - 27 tools
pathology/            - 8 tools
pharmacology/         - 26 tools
physiology/           - 13 tools
protocols/            - 2 tools
synthetic_biology/    - 11 tools
systems_biology/      - 12 tools
```

## Appendix B: API Resources

| Resource | URL | Purpose |
|----------|-----|---------|
| PubMed E-utilities | https://eutils.ncbi.nlm.nih.gov/entrez/eutils/ | Paper search |
| bio.tools | https://bio.tools/api/ | Tool registry with DOIs |
| CrossRef | https://api.crossref.org/ | DOI metadata |
| Europe PMC | https://www.ebi.ac.uk/europepmc/webservices/rest/ | Paper metadata |
| Semantic Scholar | https://api.semanticscholar.org/ | Citation counts |

## Appendix C: Complete List of Wrong Citations Found

### Confirmed Wrong Citations (tool_knowledge table)

| Tool | Wrong Citation | Wrong Journal | Correct Paper |
|------|----------------|---------------|---------------|
| MetaPhlAn | High-accuracy calibration method for an underwater one-mirror galvanometric laser scanner | Opt Express | Beghini et al. 2021, eLife (bioBakery 3) |
| Bracken | [High-isolation preparedness for very contagious and potential severely ill patients] | Ugeskr Laeger | Lu et al. 2017, PeerJ Comput Sci |
| DIA-NN (in tools table) | DiANNA 1.1: An extension of the DiANNA web server for ternary cysteine classification | NAR 2006 | Demichev et al. 2020, Nat Methods |

### Suspicious Citations (Generic Tool Names)

These tools have generic names and may have incorrect citations:
- **Join** → J Am Chem Soc (chemistry, may be wrong)
- **Map** → J Chem Inf Model (cheminformatics - verify)
- **Pick** → Journal of Computational Chemistry (verify)
- **Cluster** → J Chem Inf Model (verify)
- **Normalize** → Curr Med Chem (verify)

### Citation Verification SQL Query

```sql
-- Find tools with suspicious citations (title doesn't contain tool name)
SELECT tool_name,
       json_extract(primary_citation, '$.title') as title,
       json_extract(primary_citation, '$.year') as year,
       json_extract(primary_citation, '$.journal') as journal
FROM tool_knowledge
WHERE json_extract(primary_citation, '$.title') NOT LIKE '%' || tool_name || '%'
  AND json_extract(primary_citation, '$.title') IS NOT NULL
  AND length(json_extract(primary_citation, '$.title')) > 10;

-- Find bio tools citing non-bio journals
SELECT tool_name, json_extract(primary_citation, '$.journal') as journal
FROM tool_knowledge
WHERE json_extract(primary_citation, '$.journal') LIKE '%Opt%'
   OR json_extract(primary_citation, '$.journal') LIKE '%Phys%';
```

## Appendix D: Correct Citations for Wrong Entries

```python
CITATION_CORRECTIONS = {
    "MetaPhlAn": {
        "doi": "10.7554/eLife.65088",
        "pmid": "33944776",
        "title": "Integrating taxonomic, functional, and strain-level profiling of diverse microbial communities with bioBakery 3",
        "authors": ["Beghini F", "McIver LJ", "Blanco-Míguez A", "et al."],
        "journal": "eLife",
        "year": 2021
    },
    "Bracken": {
        "doi": "10.7717/peerj-cs.104",
        "pmid": "29043154",
        "title": "Bracken: estimating species abundance in metagenomics data",
        "authors": ["Lu J", "Breitwieser FP", "Thielen P", "Salzberg SL"],
        "journal": "PeerJ Comput Sci",
        "year": 2017
    },
    "DIA-NN": {
        "doi": "10.1038/s41592-019-0638-x",
        "pmid": "31768060",
        "title": "DIA-NN: neural networks and interference correction enable deep proteome coverage in high throughput",
        "authors": ["Demichev V", "Messner CB", "Vernardis SI", "Lilley KS", "Ralser M"],
        "journal": "Nat Methods",
        "year": 2020
    },
    "AlphaFold": {
        "doi": "10.1038/s41586-021-03819-2",
        "pmid": "34265844",
        "title": "Highly accurate protein structure prediction with AlphaFold",
        "authors": ["Jumper J", "Evans R", "Pritzel A", "et al."],
        "journal": "Nature",
        "year": 2021
    },
    "AlphaFold3": {
        "doi": "10.1038/s41586-024-07487-w",
        "pmid": "38718835",
        "title": "Accurate structure prediction of biomolecular interactions with AlphaFold 3",
        "authors": ["Abramson J", "Adler J", "Dunger J", "et al."],
        "journal": "Nature",
        "year": 2024
    }
}
```

---

*Generated: 2024-12-30*
*Status: Ready for Implementation*
