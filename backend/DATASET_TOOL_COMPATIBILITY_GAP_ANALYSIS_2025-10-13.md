# Dataset-Tool Compatibility Gap Analysis (2025-10-13)

## Executive Summary

**Question:** Do we need to add compatibility mappings for Galaxy's native dataset tools?

**Answer:** **YES**, absolutely! Currently there's a significant gap:

### Current Status:

| Category | Tools | Has Compatibility Mappings? | Status |
|----------|-------|----------------------------|--------|
| **BioMate Local Datasets** | 91 | ✅ YES (embedded in metadata) | Complete |
| **BioMate API Tools** | 31 | ⚠️ PARTIAL (inferred from types) | Partial |
| **Galaxy Native Data Source** | 32 | ❌ NO | **MISSING** |
| **Galaxy ToolShed Data Tools** | 214 | ⚠️ PARTIAL (only ToolShed tools) | Partial |

### What Exists Now:

```sql
-- Current compatibility table has 9,656 mappings
-- But these are ONLY for:
-- 1. ToolShed analysis tools → data types
-- 2. Some BioMate datasets → compatible tools

-- MISSING: Galaxy native data source outputs → analysis tools
```

---

## Part 1: Current Compatibility System

### Database Schema:
```sql
CREATE TABLE tool_compatibility (
    tool_id TEXT,
    data_type TEXT,
    compatibility_type TEXT,  -- 'input' or 'output'
    confidence REAL,
    FOREIGN KEY (tool_id) REFERENCES tools (id)
);
```

### Current Coverage:

#### ✅ What's Covered:
1. **BioMate Local Datasets** → Analysis Tools
   ```json
   {
     "dataset_id": "biomate_dataset_biomni_data_lake_BindingDB_All_202409_tsv",
     "dataset_metadata": {
       "compatible_tools_count": 6,
       "compatible_tools": [
         "text_manipulation",
         "filter_data",
         "sort_data",
         "join_datasets",
         "ggplot2_visualization",
         "r_data_frame"
       ]
     }
   }
   ```

2. **ToolShed Tools** → Data Types
   ```sql
   SELECT * FROM tool_compatibility
   WHERE tool_id LIKE 'toolshed%' LIMIT 3;

   -- Results:
   -- tool_id: toolshed.g2.bx.psu.edu/repos/iuc/sra_tools/...
   -- data_type: input_data
   -- compatibility_type: input
   ```

#### ❌ What's MISSING:

1. **Galaxy Native Data Source Tools** → Analysis Tools
   - biomart (Ensembl) → What tools can use Ensembl data?
   - ucsc_tablebrowser → What tools work with UCSC data?
   - ebi_sra → What tools process SRA data?
   - ncbi_datasets → Compatible downstream tools?
   - flymine, wormbase, etc. → What analysis tools?

2. **Specific Output Types** from Native Tools
   - BioMart outputs: Gene lists, annotations, sequences
   - UCSC outputs: Genomic intervals, alignments, variants
   - SRA outputs: FASTQ files, BAM files

---

## Part 2: Why This Matters

### Scenario 1: User Workflow Discovery

**Without Compatibility Mappings:**
```python
# User: "Get mouse genes from Ensembl and run expression analysis"

# System can find data source:
data_tool = search_tools("ensembl mouse genes")
# Returns: biomart

# But can't recommend next steps!
next_tools = get_compatible_tools("biomart")
# Returns: [] (EMPTY - no mappings!)

# User must manually know which tools work with BioMart output
```

**With Compatibility Mappings:**
```python
# User: "Get mouse genes from Ensembl and run expression analysis"

# System finds data source:
data_tool = search_tools("ensembl mouse genes")
# Returns: biomart

# System recommends compatible tools:
next_tools = get_compatible_tools("biomart")
# Returns: [
#   {"tool_id": "nfcore_salmon", "confidence": 0.95},
#   {"tool_id": "nfcore_deseq2", "confidence": 0.92},
#   {"tool_id": "toolshed_goenrichment", "confidence": 0.88}
# ]

# System can auto-build workflow!
```

### Scenario 2: Data Source Selection

**Without Compatibility Mappings:**
```python
# User: "I want to run differential expression, what data should I start with?"

# System can't answer because it doesn't know:
# - What data sources produce expression data?
# - Which data sources are compatible with DESeq2?
```

**With Compatibility Mappings:**
```python
# User: "I want to run differential expression, what data should I start with?"

# System reverse-searches:
data_sources = recommend_data_source_for_tool("nfcore_deseq2")
# Returns: [
#   {"source": "ebi_sra", "reason": "RNA-seq FASTQ data", "confidence": 0.95},
#   {"source": "biomart", "reason": "Gene expression matrices", "confidence": 0.88},
#   {"source": "biomate_dm_proteinatlas", "reason": "Tissue expression", "confidence": 0.75}
# ]
```

### Scenario 3: Workflow Templates

**Without Mappings:**
- System can't suggest "RNA-seq from SRA" workflow
- User must know: SRA → FastQC → STAR → DESeq2

**With Mappings:**
- System recognizes: `ebi_sra` outputs FASTQ
- System knows: FASTQ-compatible tools (FastQC, Trimmomatic, etc.)
- System auto-generates complete workflow

---

## Part 3: What Needs to Be Added

### Priority 1: Galaxy Native Data Sources → Output Types (32 tools)

#### Genomics Data Sources:
```python
compatibility_mappings = {
    # BioMart / Ensembl
    "biomart": {
        "outputs": [
            {"type": "tabular", "format": "tsv", "content": "gene_annotations"},
            {"type": "fasta", "format": "fasta", "content": "sequences"},
            {"type": "gtf", "format": "gtf", "content": "gene_models"}
        ],
        "compatible_tools": [
            {"tool_id": "text_manipulation", "confidence": 0.98},
            {"tool_id": "filter_data", "confidence": 0.95},
            {"tool_id": "nfcore_deseq2", "confidence": 0.92, "use_case": "expression_analysis"},
            {"tool_id": "toolshed_goenrichment", "confidence": 0.90}
        ]
    },

    # UCSC Table Browser
    "ucsc_tablebrowser": {
        "outputs": [
            {"type": "bed", "format": "bed", "content": "genomic_intervals"},
            {"type": "wig", "format": "wig", "content": "signal_tracks"},
            {"type": "maf", "format": "maf", "content": "alignments"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_bedtools", "confidence": 0.98},
            {"tool_id": "nfcore_deeptools", "confidence": 0.95},
            {"tool_id": "toolshed_bedgraphtobigwig", "confidence": 0.92}
        ]
    },

    # EBI SRA / NCBI SRA
    "ebi_sra": {
        "outputs": [
            {"type": "fastqsanger", "format": "fastq.gz", "content": "reads"},
            {"type": "bam", "format": "bam", "content": "aligned_reads"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_fastqc", "confidence": 0.99},
            {"tool_id": "nfcore_trimgalore", "confidence": 0.98},
            {"tool_id": "nfcore_star", "confidence": 0.97},
            {"tool_id": "nfcore_salmon", "confidence": 0.96},
            {"tool_id": "nfcore_deseq2", "confidence": 0.90, "requires_preprocessing": true}
        ]
    },

    # NCBI GenBank
    "genbank": {
        "outputs": [
            {"type": "genbank", "format": "gb", "content": "sequences_annotations"},
            {"type": "fasta", "format": "fasta", "content": "sequences"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_blast", "confidence": 0.98},
            {"tool_id": "nfcore_mafft", "confidence": 0.95},
            {"tool_id": "nfcore_iqtree", "confidence": 0.93}
        ]
    },

    # NCBI Datasets
    "ncbi_datasets": {
        "outputs": [
            {"type": "json", "format": "json", "content": "genome_metadata"},
            {"type": "fasta", "format": "fasta.gz", "content": "genome_sequences"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_prokka", "confidence": 0.96, "use_case": "annotation"},
            {"tool_id": "nfcore_blast", "confidence": 0.95},
            {"tool_id": "nfcore_bakta", "confidence": 0.93}
        ]
    }
}
```

#### Model Organism Databases:
```python
model_organism_mappings = {
    # FlyMine (Drosophila)
    "flymine": {
        "outputs": [{"type": "tabular", "content": "gene_data"}],
        "compatible_tools": [
            {"tool_id": "text_manipulation", "confidence": 0.95},
            {"tool_id": "toolshed_goenrichment", "confidence": 0.90}
        ]
    },

    # WormBase (C. elegans)
    "wormbase": {
        "outputs": [{"type": "tabular", "content": "gene_data"}],
        "compatible_tools": [
            {"tool_id": "text_manipulation", "confidence": 0.95},
            {"tool_id": "nfcore_rnaseq", "confidence": 0.85, "requires_sequences": true}
        ]
    },

    # MouseMine
    "mousemine": {
        "outputs": [{"type": "tabular", "content": "gene_data"}],
        "compatible_tools": [
            {"tool_id": "nfcore_deseq2", "confidence": 0.88, "use_case": "expression"},
            {"tool_id": "toolshed_goenrichment", "confidence": 0.92}
        ]
    }

    # ... 8 more model organism DBs
}
```

### Priority 2: Galaxy ToolShed Data Tools → Enhanced Mappings (214 tools)

Current mappings are basic (just data_type). Need to add:
- Specific output formats
- Compatible tool recommendations
- Use case context

```python
# Current:
{"tool_id": "PubChem_Download", "data_type": "sdf", "compatibility_type": "output"}

# Enhanced:
{
    "tool_id": "PubChem_Download",
    "outputs": [
        {"type": "sdf", "format": "sdf", "content": "chemical_structures"}
    ],
    "compatible_tools": [
        {"tool_id": "nfcore_openbabel", "confidence": 0.98},
        {"tool_id": "nfcore_rdkit", "confidence": 0.95},
        {"tool_id": "toolshed_autodock", "confidence": 0.92, "use_case": "docking"}
    ]
}
```

### Priority 3: BioMate API Tools → Formal Mappings (31 tools)

Currently inferred from output types. Need explicit mappings:

```python
biomate_api_mappings = {
    "biomate_datasource_api_uniprot": {
        "outputs": [
            {"type": "fasta", "format": "fasta", "content": "protein_sequences"},
            {"type": "tsv", "format": "tsv", "content": "protein_annotations"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_blast", "confidence": 0.98},
            {"tool_id": "nfcore_colabfold", "confidence": 0.96, "use_case": "structure_prediction"},
            {"tool_id": "nfcore_mafft", "confidence": 0.95, "use_case": "alignment"}
        ]
    },

    "biomate_datasource_api_alphafold": {
        "outputs": [
            {"type": "pdb", "format": "pdb", "content": "protein_structure"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_pymol", "confidence": 0.95, "use_case": "visualization"},
            {"tool_id": "nfcore_autodock", "confidence": 0.93, "use_case": "docking"},
            {"tool_id": "toolshed_structure_analysis", "confidence": 0.90}
        ]
    },

    "biomate_datasource_api_chembl": {
        "outputs": [
            {"type": "sdf", "format": "sdf", "content": "drug_structures"},
            {"type": "tsv", "format": "tsv", "content": "bioactivity_data"}
        ],
        "compatible_tools": [
            {"tool_id": "nfcore_rdkit", "confidence": 0.97},
            {"tool_id": "nfcore_autodock", "confidence": 0.94, "use_case": "docking"},
            {"tool_id": "text_manipulation", "confidence": 0.92}
        ]
    }

    # ... 28 more API tools
}
```

---

## Part 4: Implementation Strategy

### Step 1: Create Compatibility Mapping Script

```python
#!/usr/bin/env python3
"""
Generate dataset-tool compatibility mappings for Galaxy native data sources.
"""

import sqlite3
from typing import Dict, List

class GalaxyDataSourceCompatibilityMapper:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)

    def add_galaxy_native_mappings(self):
        """Add compatibility mappings for 32 Galaxy native data source tools."""

        mappings = [
            # BioMart / Ensembl
            {
                "source_tool": "biomart",
                "output_types": ["tabular", "fasta", "gtf"],
                "compatible_tools": [
                    ("text_manipulation", 0.98),
                    ("filter_data", 0.95),
                    ("nfcore_deseq2", 0.92),
                    ("toolshed_goenrichment", 0.90),
                    ("nfcore_blast", 0.88),
                    ("ggplot2_visualization", 0.85)
                ]
            },

            # UCSC Table Browser
            {
                "source_tool": "ucsc_tablebrowser",
                "output_types": ["bed", "wig", "maf"],
                "compatible_tools": [
                    ("nfcore_bedtools", 0.98),
                    ("nfcore_deeptools", 0.95),
                    ("toolshed_bedgraphtobigwig", 0.92),
                    ("nfcore_chipseq", 0.90),
                    ("text_manipulation", 0.88)
                ]
            },

            # EBI SRA
            {
                "source_tool": "ebi_sra",
                "output_types": ["fastqsanger", "bam"],
                "compatible_tools": [
                    ("nfcore_fastqc", 0.99),
                    ("nfcore_trimgalore", 0.98),
                    ("nfcore_star", 0.97),
                    ("nfcore_salmon", 0.96),
                    ("nfcore_hisat2", 0.95),
                    ("nfcore_samtools", 0.94),
                    ("nfcore_deseq2", 0.90)
                ]
            },

            # NCBI SRA
            {
                "source_tool": "sra",
                "output_types": ["fastqsanger", "bam"],
                "compatible_tools": [
                    ("nfcore_fastqc", 0.99),
                    ("nfcore_trimgalore", 0.98),
                    ("nfcore_star", 0.97),
                    ("nfcore_salmon", 0.96)
                ]
            },

            # GenBank
            {
                "source_tool": "genbank",
                "output_types": ["genbank", "fasta"],
                "compatible_tools": [
                    ("nfcore_blast", 0.98),
                    ("nfcore_mafft", 0.95),
                    ("nfcore_iqtree", 0.93),
                    ("nfcore_clustalo", 0.92)
                ]
            },

            # Model Organisms (11 tools with similar patterns)
            *self._generate_model_organism_mappings(),

            # Plant Databases (2 tools)
            *self._generate_plant_db_mappings(),
        ]

        for mapping in mappings:
            self._insert_mappings(mapping)

        self.conn.commit()

    def _generate_model_organism_mappings(self) -> List[Dict]:
        """Generate mappings for FlyMine, WormBase, MouseMine, etc."""
        model_orgs = [
            "flymine", "wormbase", "mousemine", "ratmine",
            "modmine", "metabolicmine", "fly_modencode", "worm_modencode"
        ]

        mappings = []
        for org in model_orgs:
            mappings.append({
                "source_tool": org,
                "output_types": ["tabular"],
                "compatible_tools": [
                    ("text_manipulation", 0.95),
                    ("filter_data", 0.93),
                    ("toolshed_goenrichment", 0.90),
                    ("ggplot2_visualization", 0.85)
                ]
            })

        return mappings

    def _insert_mappings(self, mapping: Dict):
        """Insert compatibility mappings into database."""
        source_tool = mapping["source_tool"]

        for tool_id, confidence in mapping["compatible_tools"]:
            # Insert for each output type
            for output_type in mapping["output_types"]:
                self.conn.execute("""
                    INSERT INTO tool_compatibility
                    (tool_id, data_type, compatibility_type, confidence)
                    VALUES (?, ?, 'output', ?)
                """, (source_tool, output_type, confidence))

                # Also create reverse mapping (tool can accept this data type)
                self.conn.execute("""
                    INSERT INTO tool_compatibility
                    (tool_id, data_type, compatibility_type, confidence)
                    VALUES (?, ?, 'input', ?)
                """, (tool_id, output_type, confidence))

if __name__ == "__main__":
    mapper = GalaxyDataSourceCompatibilityMapper(
        "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
    )

    print("Adding Galaxy native data source compatibility mappings...")
    mapper.add_galaxy_native_mappings()
    print("✓ Added mappings for 32 Galaxy native data sources")

    # Verify
    cursor = mapper.conn.execute("""
        SELECT COUNT(*) FROM tool_compatibility
        WHERE tool_id IN ('biomart', 'ucsc_tablebrowser', 'ebi_sra', 'sra', 'genbank')
    """)
    count = cursor.fetchone()[0]
    print(f"✓ Verified: {count} new compatibility mappings")
```

### Step 2: Enhance RAG Integration

Modify `enhanced_galaxy_tool_rag.py`:

```python
def get_compatible_tools(self, dataset_id: str, min_confidence: float = 0.5) -> List[Dict]:
    """Get tools compatible with a specific dataset or data source."""

    # Check if this is a Galaxy native data source
    if dataset_id in self.native_data_sources:
        return self._get_native_source_compatible_tools(dataset_id, min_confidence)

    # Existing logic for BioMate datasets
    ...

def _get_native_source_compatible_tools(self, source_id: str, min_confidence: float) -> List[Dict]:
    """Get tools compatible with Galaxy native data sources."""

    with sqlite3.connect(self.db_path) as conn:
        cursor = conn.execute("""
            SELECT tc.tool_id, tc.confidence, t.name, t.category, t.description
            FROM tool_compatibility tc
            JOIN tools t ON tc.tool_id = t.tool_id
            WHERE tc.tool_id = ?
              AND tc.compatibility_type = 'output'
              AND tc.confidence >= ?
            ORDER BY tc.confidence DESC
        """, (source_id, min_confidence))

        results = []
        for row in cursor.fetchall():
            results.append({
                "tool_id": row[0],
                "confidence": row[1],
                "name": row[2],
                "category": row[3],
                "description": row[4]
            })

        return results
```

### Step 3: Update Documentation

Create comprehensive workflow examples showing:
- BioMart → DESeq2 workflow
- UCSC → BEDTools workflow
- SRA → RNA-seq pipeline workflow

---

## Part 5: Expected Impact

### Before Adding Mappings:

```python
# Query: "Get fly genes and analyze expression"
workflow = generate_workflow("Get fly genes and analyze expression")

# Result: Incomplete workflow
{
    "steps": [
        {"tool_id": "flymine", "annotation": "Get fly genes"},
        # STOPS HERE - system doesn't know what comes next
    ]
}
```

### After Adding Mappings:

```python
# Query: "Get fly genes and analyze expression"
workflow = generate_workflow("Get fly genes and analyze expression")

# Result: Complete workflow
{
    "steps": [
        {"tool_id": "flymine", "annotation": "Get fly gene data"},
        {"tool_id": "text_manipulation", "annotation": "Filter gene list"},
        {"tool_id": "nfcore_deseq2", "annotation": "Differential expression analysis"},
        {"tool_id": "toolshed_goenrichment", "annotation": "GO term enrichment"},
        {"tool_id": "ggplot2_visualization", "annotation": "Visualize results"}
    ],
    "total_time_estimate": "45 minutes",
    "container_downloads": ["deseq2", "ggplot2"]
}
```

---

## Part 6: Recommendations

### Immediate Action (High Priority):
1. ✅ **Create compatibility mapping script** (1-2 days)
2. ✅ **Add mappings for 32 Galaxy native tools** (2-3 days)
3. ✅ **Test workflow generation** with native data sources (1 day)

### Short-term (Medium Priority):
4. ⚠️ **Enhance ToolShed tool mappings** (214 tools, 3-5 days)
5. ⚠️ **Add explicit BioMate API mappings** (31 tools, 2 days)

### Long-term (Low Priority):
6. 📊 **Machine learning for compatibility prediction**
7. 📈 **User feedback loop** (learn from actual workflow usage)
8. 🔄 **Auto-update** as new tools are added

---

## Conclusion

**YES, we absolutely need to add dataset-tool compatibility mappings for Galaxy native data source tools!**

### Current Gap:
- 32 Galaxy native data sources have **NO compatibility mappings**
- Users can't discover what to do with BioMart/UCSC/SRA data
- Workflow auto-generation is incomplete

### Solution:
- Add ~200-300 compatibility mappings for native sources
- Enhance existing 9,656 mappings with richer metadata
- Enable complete workflow discovery and generation

### Benefits:
- ✅ Complete workflow recommendations
- ✅ Better data source discovery
- ✅ Improved user experience
- ✅ Automatic pipeline generation
- ✅ Integration with existing 368 data tools

**Estimated Effort:** 5-7 days
**Expected Value:** High (enables key workflow features)

---

**Document Version:** 1.0
**Created:** 2025-10-13
**Author:** BioMate Analysis System
**Related:** GALAXY_VS_BIOMATE_DATASET_TOOLS_2025-10-13.md

