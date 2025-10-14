# BioMate E2E Test Plan with LLM Parameter Validation

**Created**: 2025-10-14
**Status**: READY FOR IMPLEMENTATION
**Purpose**: Comprehensive end-to-end testing with visual validation and parameter generation testing
**Execution Mode**: Visual browser automation with Playwright

---

## 📋 Table of Contents

1. [Testing Objectives](#testing-objectives)
2. [Test Infrastructure](#test-infrastructure)
3. [Test Case Specifications](#test-case-specifications)
4. [Parameter Validation Criteria](#parameter-validation-criteria)
5. [Execution Validation](#execution-validation)
6. [Visual Evidence Requirements](#visual-evidence-requirements)
7. [Success Metrics](#success-metrics)

---

## Testing Objectives

### Primary Goals
1. **End-to-End Validation**: Verify complete user journey from query to workflow execution results
2. **Parameter Generation Testing**: Validate LLM parameter inference accuracy and confidence scores
3. **Visual Observability**: Capture visual evidence of entire process via browser automation
4. **Workflow Execution**: Confirm workflows execute successfully with generated parameters
5. **Reproducibility**: Ensure tests can be re-run with consistent results

### What We're Testing
- ✅ Natural language query processing
- ✅ Workflow generation (template search → adapt/reuse → generate from scratch)
- ✅ **LLM parameter generation for data source tools**
- ✅ **Parameter confidence scoring**
- ✅ **Parameter accuracy against expected values**
- ✅ Workflow visualization in workflow builder
- ✅ Workflow execution with auto-generated parameters
- ✅ Tool installation (on-demand containers)
- ✅ Data flow between steps
- ✅ Output file generation and validation

---

## Test Infrastructure

### Technology Stack

**Browser Automation**:
```python
# pytest with pytest-playwright
import pytest
from playwright.sync_api import Page, expect

@pytest.fixture(scope="session")
def browser_context(playwright):
    browser = playwright.chromium.launch(
        headless=False,  # Visible browser
        slow_mo=500      # 500ms delay between actions for visibility
    )
    context = browser.new_context(
        viewport={"width": 1920, "height": 1080},
        record_video_dir="./test_videos"
    )
    yield context
    context.close()
    browser.close()
```

**Screenshot Management**:
```python
class ScreenshotManager:
    def __init__(self, test_name: str):
        self.test_name = test_name
        self.screenshot_dir = f"./test_screenshots/{test_name}"
        os.makedirs(self.screenshot_dir, exist_ok=True)
        self.step_counter = 0

    def capture(self, page: Page, description: str):
        self.step_counter += 1
        filename = f"{self.step_counter:02d}_{description}.png"
        page.screenshot(path=f"{self.screenshot_dir}/{filename}")
        return filename
```

**Parameter Validator**:
```python
class ParameterValidator:
    def validate_generated_parameters(
        self,
        actual: List[Dict],
        expected: Dict[str, Dict],
        min_confidence: float = 0.7
    ) -> Dict[str, Any]:
        """
        Validate LLM-generated parameters against expected values.

        Args:
            actual: List of generated_parameters from API
            expected: Dict mapping tool_id to expected params
            min_confidence: Minimum acceptable confidence score

        Returns:
            Validation results with pass/fail and details
        """
        results = {
            "total_params": len(actual),
            "passed": 0,
            "failed": 0,
            "low_confidence": 0,
            "details": []
        }

        for param in actual:
            tool_id = param["tool_id"]
            expected_params = expected.get(tool_id, {})

            # Check confidence
            if param["confidence"] < min_confidence:
                results["low_confidence"] += 1

            # Check parameter accuracy
            param_match = self._compare_parameters(
                param["parameters"],
                expected_params
            )

            if param_match["all_match"]:
                results["passed"] += 1
            else:
                results["failed"] += 1

            results["details"].append({
                "tool_id": tool_id,
                "confidence": param["confidence"],
                "expected": expected_params,
                "actual": param["parameters"],
                "match": param_match
            })

        return results
```

### Directory Structure

```
backend/tests/e2e_ui/
├── conftest.py                       # Pytest configuration and fixtures
├── page_objects/
│   ├── chat_page.py                 # Chat interface page object
│   ├── workflow_page.py             # Workflow builder page object
│   └── execution_page.py            # Workflow execution page object
├── test_cases/
│   ├── test_01_dia_lcms.py         # DIA LC-MS proteomics
│   ├── test_02_peptide_qc.py       # Peptide drug QC
│   ├── test_03_scrna_seq.py        # Single cell RNA-seq
│   ├── test_04_crispr_screen.py    # CRISPR screen analysis
│   ├── test_05_cryoem.py           # Cryo-EM structure
│   ├── test_06_wgs_variant.py      # WGS variant calling
│   ├── test_07_digital_path.py     # Digital pathology
│   ├── test_08_multiomics.py       # Multi-omics integration
│   ├── test_09_metagenomics.py     # Metagenomics analysis
│   └── test_10_spatial_tx.py       # Spatial transcriptomics
├── utilities/
│   ├── screenshot_manager.py       # Screenshot organization
│   ├── parameter_validator.py      # Parameter validation logic
│   └── workflow_validator.py       # Workflow structure validation
├── test_data/
│   ├── expected_parameters.json    # Expected parameter values per test
│   └── mock_inputs/                # Mock input data files
└── reports/
    └── html_report_template.html   # HTML report with screenshots
```

---

## Test Case Specifications

### Test Case 1: DIA LC-MS Proteomics Analysis

**User Query**: "Analyze DIA LC-MS data for protein identification and quantification"

**Expected Workflow Steps**:
1. **OpenSwath** - DIA data extraction
2. **PyProphet** - Statistical validation
3. **TRIC** - Multi-run alignment
4. **MSstats** - Differential abundance

**Expected Parameter Generation**:
```json
{
  "step_0_openswath": {
    "tool_id": "biomate_dm_swath_library",
    "expected_params": {
      "library_type": "spectral",
      "organism": "human",
      "tissue": "plasma"
    },
    "min_confidence": 0.75,
    "critical_params": ["library_type", "organism"]
  }
}
```

**Test Steps**:
1. Navigate to BioMate chat interface
2. Enter user query
3. **Screenshot**: Chat input
4. Wait for workflow generation
5. **Screenshot**: Chat response with workflow suggestion
6. **Validate**: API response contains `generated_parameters`
7. **Validate**: Parameter confidence scores >= 0.75
8. **Validate**: Parameter values match expected (organism, library_type)
9. Click "View Workflow" button
10. **Screenshot**: Workflow builder with all steps
11. **Validate**: Workflow has 4 steps (OpenSwath → PyProphet → TRIC → MSstats)
12. **Validate**: Step 0 has auto-filled parameters (⚡ indicator)
13. Click "Execute Workflow"
14. **Screenshot**: Workflow execution start
15. Monitor execution progress
16. **Screenshot**: Each step completion
17. Wait for workflow completion
18. **Screenshot**: Final workflow status
19. **Validate**: All steps show "completed" status
20. **Validate**: Output files generated (pepXML, mzML, quantification.tsv)

**Expected Execution Time**: 15-25 minutes

**Success Criteria**:
- ✅ Workflow generated within 10 seconds
- ✅ Parameter confidence >= 0.75 for all critical params
- ✅ Parameter accuracy >= 80% (organism, library_type correct)
- ✅ Workflow executes without errors
- ✅ All 4 steps complete successfully
- ✅ Output files generated and validated

---

### Test Case 2: Peptide Drug Quality Control

**User Query**: "Quality control analysis for therapeutic peptide purity and identity"

**Expected Workflow Steps**:
1. **LC-MS Data Import** - Load raw data
2. **Peak Detection** - Identify peptide peaks
3. **Purity Calculation** - Calculate % purity
4. **Sequence Confirmation** - Verify peptide sequence

**Expected Parameter Generation**:
```json
{
  "step_0_lcms_import": {
    "tool_id": "biomate_dm_mass_spec_data",
    "expected_params": {
      "data_type": "lcms",
      "format": "mzML",
      "ionization": "ESI",
      "polarity": "positive"
    },
    "min_confidence": 0.80,
    "critical_params": ["data_type", "ionization"]
  },
  "step_1_peak_detection": {
    "tool_id": "biomate_tool_xcms_findpeaks",
    "expected_params": {
      "method": "centWave",
      "ppm": 15,
      "peakwidth_min": 10,
      "peakwidth_max": 60
    },
    "min_confidence": 0.65,
    "critical_params": ["method"]
  }
}
```

**Test Steps**:
1. Navigate to chat interface
2. Enter query: "Quality control analysis for therapeutic peptide purity and identity"
3. **Screenshot**: Chat input
4. Wait for workflow generation (max 10s)
5. **Screenshot**: Generated workflow response
6. **Extract & Validate Parameters**:
   ```python
   response = api_response['generated_parameters']
   validator = ParameterValidator()
   results = validator.validate_generated_parameters(
       actual=response,
       expected=EXPECTED_PARAMS_TEST_02,
       min_confidence=0.65
   )
   assert results['passed'] >= 1  # At least 1 tool with correct params
   assert results['low_confidence'] == 0  # No params below 0.65
   ```
7. Click "View Workflow"
8. **Screenshot**: Workflow builder
9. **Validate Workflow Structure**:
   - 4 steps present
   - Step connections: 0→1→2→3
   - Step 0 and 1 have ⚡ auto-filled indicator
10. Inspect Step 0 parameters in workflow builder
11. **Screenshot**: Step 0 parameter panel
12. **Validate**: Parameters match expected values
13. Click "Execute Workflow"
14. **Screenshot**: Execution confirmation dialog (if parameters need review)
15. If parameter preview dialog appears:
    - **Screenshot**: Parameter preview dialog
    - **Validate**: Low-confidence params highlighted
    - **Validate**: Reasoning text present
    - Click "Confirm & Execute"
16. **Screenshot**: Execution started
17. Monitor progress (poll every 5s)
18. **Screenshot**: Step 1 completion
19. **Screenshot**: Step 2 completion
20. **Screenshot**: Step 3 completion
21. **Screenshot**: Workflow completed
22. **Validate Outputs**:
    ```python
    outputs = get_workflow_outputs(workflow_id)
    assert len(outputs) >= 2
    assert any('purity_report' in o['name'] for o in outputs)
    assert any('sequence_confirmation' in o['name'] for o in outputs)
    ```

**Expected Execution Time**: 10-15 minutes

**Success Criteria**:
- ✅ Workflow generation < 10 seconds
- ✅ At least 2 tools with parameter generation
- ✅ All critical parameters correct (data_type, ionization, method)
- ✅ Confidence scores >= 0.65 for all params
- ✅ Workflow executes end-to-end
- ✅ Purity report generated
- ✅ Sequence confirmation output present

---

### Test Case 3: Single Cell RNA-Seq with Permutation Testing

**User Query**: "Single cell RNA-seq analysis with permutation testing for differential expression"

**Expected Workflow Steps**:
1. **CellRanger** - Read alignment and UMI counting
2. **Seurat QC** - Quality control and filtering
3. **Normalization & Clustering** - Cell type identification
4. **Permutation DE Analysis** - Statistical testing with permutations

**Expected Parameter Generation**:
```json
{
  "step_0_cellranger": {
    "tool_id": "biomate_dm_10x_genomics",
    "expected_params": {
      "chemistry": "auto",
      "genome": "GRCh38",
      "expected_cells": 3000
    },
    "min_confidence": 0.70,
    "critical_params": ["genome"]
  },
  "step_2_clustering": {
    "tool_id": "biomate_tool_seurat_cluster",
    "expected_params": {
      "resolution": 0.8,
      "dims": 30,
      "algorithm": "louvain"
    },
    "min_confidence": 0.60,
    "critical_params": []
  },
  "step_3_permutation_de": {
    "tool_id": "biomate_tool_permutation_test",
    "expected_params": {
      "n_permutations": 1000,
      "test_type": "wilcoxon",
      "fdr_method": "BH"
    },
    "min_confidence": 0.65,
    "critical_params": ["test_type"]
  }
}
```

**Test Steps**:
1. Chat input: "Single cell RNA-seq analysis with permutation testing for differential expression"
2. **Screenshot**: Chat interface
3. Wait for workflow generation
4. **Screenshot**: Workflow generated message
5. **Validate Generated Parameters**:
   - Extract `generated_parameters` from API response
   - Validate 3 tools have parameters (CellRanger, Clustering, Permutation)
   - Check genome parameter = "GRCh38" or "hg38" (either acceptable)
   - Check test_type = "wilcoxon"
   - Verify all confidence scores >= 0.60
6. Open workflow in builder
7. **Screenshot**: Full workflow (4 steps)
8. **Validate Workflow**:
   - Step 0: CellRanger (data source with params)
   - Step 1: Seurat QC (default params)
   - Step 2: Clustering (LLM params)
   - Step 3: Permutation DE (LLM params)
9. **Screenshot**: Step 0 parameter panel showing genome
10. **Screenshot**: Step 3 parameter panel showing permutations
11. Click "Execute Workflow"
12. **Screenshot**: Execution start
13. Wait for Step 0 completion (CellRanger - long running)
14. **Screenshot**: Step 0 complete (may take 10-15 min)
15. **Screenshot**: Step 1 complete
16. **Screenshot**: Step 2 complete
17. **Screenshot**: Step 3 complete
18. **Screenshot**: Final results
19. **Validate Outputs**:
    - Cell clustering visualization
    - DE genes table with p-values and FDR
    - Permutation distribution plot

**Expected Execution Time**: 25-35 minutes (CellRanger is slow)

**Success Criteria**:
- ✅ 3 tools with parameter generation
- ✅ Genome parameter correctly inferred
- ✅ Permutation test parameters present
- ✅ All confidence >= 0.60
- ✅ Workflow completes without errors
- ✅ DE results with FDR-adjusted p-values generated

---

### Test Case 4: CRISPR Screen Gene Essentiality Analysis

**User Query**: "CRISPR knockout screen analysis to identify essential genes using MAGeCK"

**Expected Workflow Steps**:
1. **Read Count Data Import** - Load sgRNA counts
2. **MAGeCK Count** - Generate count summary
3. **MAGeCK Test** - Statistical analysis for gene essentiality
4. **Visualization** - Plot gene rankings and QC

**Expected Parameter Generation**:
```json
{
  "step_0_import_counts": {
    "tool_id": "biomate_dm_crispr_counts",
    "expected_params": {
      "screen_type": "knockout",
      "library": "brunello",
      "control_group": "control",
      "treatment_group": "treatment"
    },
    "min_confidence": 0.75,
    "critical_params": ["screen_type", "library"]
  },
  "step_2_mageck_test": {
    "tool_id": "biomate_tool_mageck_test",
    "expected_params": {
      "norm_method": "median",
      "test_method": "RRA",
      "fdr_threshold": 0.25
    },
    "min_confidence": 0.70,
    "critical_params": ["test_method"]
  }
}
```

**Test Steps**:
1. Enter query: "CRISPR knockout screen analysis to identify essential genes using MAGeCK"
2. **Screenshot**: Chat input
3. Wait for workflow generation
4. **Screenshot**: Workflow response
5. **Validate Parameters**:
   - `screen_type` = "knockout"
   - `library` = "brunello" or "gecko" or "toronto" (any valid library)
   - `test_method` = "RRA" (Robust Rank Aggregation)
   - Confidence >= 0.70 for both tools
6. Open workflow
7. **Screenshot**: Workflow builder (4 steps)
8. **Validate Structure**:
   - Import → MAGeCK Count → MAGeCK Test → Visualization
   - Steps 0 and 2 have auto-filled params
9. Inspect parameters in workflow builder
10. **Screenshot**: Step 0 params (screen_type, library)
11. **Screenshot**: Step 2 params (norm_method, test_method)
12. Execute workflow
13. **Screenshot**: Execution start
14. Monitor each step
15. **Screenshots**: Steps 1, 2, 3, 4 completion
16. **Validate Outputs**:
    - Essential genes list (FDR < 0.25)
    - Non-essential genes list
    - Gene ranking plot
    - QC metrics (Gini coefficient, read distribution)

**Expected Execution Time**: 8-12 minutes

**Success Criteria**:
- ✅ Screen type correctly identified as "knockout"
- ✅ Library parameter inferred (Brunello preferred)
- ✅ MAGeCK test method = "RRA"
- ✅ All confidence >= 0.70
- ✅ Workflow executes successfully
- ✅ Essential genes identified with FDR values

---

### Test Case 5: Cryo-EM 3D Reconstruction

**User Query**: "Cryo-EM data processing for 3D protein structure reconstruction"

**Expected Workflow Steps**:
1. **MotionCor2** - Motion correction
2. **CTFFIND4** - CTF estimation
3. **RELION Particle Picking** - Automated picking
4. **RELION 2D Classification** - Class averaging
5. **RELION 3D Reconstruction** - Initial model and refinement

**Expected Parameter Generation**:
```json
{
  "step_0_motioncor": {
    "tool_id": "biomate_dm_cryoem_movies",
    "expected_params": {
      "pixel_size": 1.0,
      "voltage": 300,
      "dose_per_frame": 1.0
    },
    "min_confidence": 0.60,
    "critical_params": ["voltage"]
  },
  "step_1_ctffind": {
    "tool_id": "biomate_tool_ctffind4",
    "expected_params": {
      "box_size": 512,
      "min_resolution": 30,
      "max_resolution": 5
    },
    "min_confidence": 0.50,
    "critical_params": []
  }
}
```

**Test Steps**:
1. Query: "Cryo-EM data processing for 3D protein structure reconstruction"
2. **Screenshot**: Chat
3. Wait for workflow (may take slightly longer due to complexity)
4. **Screenshot**: Generated workflow
5. **Validate Parameters**:
   - Voltage parameter present (300 kV is common)
   - Pixel size if inferred
   - No strict validation on exact values (cryo-EM params are experiment-specific)
   - Confidence >= 0.50 acceptable (cryo-EM has many optional params)
6. Open workflow
7. **Screenshot**: 5-step workflow
8. **Validate**: MotionCor2 → CTFFIND4 → Picking → 2D Class → 3D Recon
9. **Screenshot**: Step 0 parameters
10. **Screenshot**: Step 1 parameters
11. Execute workflow
12. **Note**: This test may use mock data (cryo-EM is very slow)
13. **Screenshots**: Each step completion
14. **Validate Outputs**:
    - Motion-corrected micrographs
    - CTF estimation results
    - Particle coordinates
    - 2D class averages
    - 3D reconstruction (if completed)

**Expected Execution Time**: 30-60 minutes (or use mock mode)

**Success Criteria**:
- ✅ Workflow generated with 5 steps
- ✅ Voltage parameter inferred
- ✅ Confidence >= 0.50 for generated params
- ✅ Workflow structure valid
- ✅ At least first 3 steps complete (or all steps with mock data)

---

### Test Case 6: Whole Genome Sequencing Variant Calling

**User Query**: "Whole genome sequencing analysis with GATK best practices for variant calling"

**Expected Workflow Steps**:
1. **BWA-MEM Alignment** - Align reads to reference
2. **MarkDuplicates** - Remove PCR duplicates
3. **Base Recalibration** - GATK BQSR
4. **HaplotypeCaller** - Variant calling
5. **VQSR** - Variant quality score recalibration

**Expected Parameter Generation**:
```json
{
  "step_0_bwa_align": {
    "tool_id": "biomate_dm_genome_reference",
    "expected_params": {
      "genome": "GRCh38",
      "aligner": "bwa-mem"
    },
    "min_confidence": 0.80,
    "critical_params": ["genome"]
  },
  "step_3_haplotypecaller": {
    "tool_id": "biomate_tool_gatk_haplotypecaller",
    "expected_params": {
      "ploidy": 2,
      "emit_ref_confidence": "GVCF"
    },
    "min_confidence": 0.65,
    "critical_params": ["ploidy"]
  }
}
```

**Test Steps**:
1. Query: "Whole genome sequencing analysis with GATK best practices for variant calling"
2. **Screenshot**: Chat
3. Workflow generation
4. **Screenshot**: Workflow
5. **Validate Parameters**:
   - Genome = "GRCh38" or "hg38"
   - Aligner = "bwa-mem"
   - Ploidy = 2 (diploid)
   - Emit mode = "GVCF" or "BOTH"
6. Open workflow
7. **Screenshot**: 5-step GATK pipeline
8. **Validate Structure**: BWA → MarkDup → BQSR → HaplotypeCaller → VQSR
9. **Screenshot**: Step 0 (genome reference)
10. **Screenshot**: Step 3 (HaplotypeCaller params)
11. Execute workflow
12. **Screenshots**: Each step
13. **Validate Outputs**:
    - Aligned BAM
    - Deduplicated BAM
    - Recalibration report
    - VCF with variants
    - VQSR-filtered VCF

**Expected Execution Time**: 40-60 minutes (WGS is slow)

**Success Criteria**:
- ✅ Genome reference correctly identified
- ✅ Ploidy = 2
- ✅ GVCF mode for HaplotypeCaller
- ✅ Confidence >= 0.65
- ✅ Workflow executes (may use subsampled data)
- ✅ VCF file generated with variants

---

### Test Case 7: Digital Pathology TIL Analysis

**User Query**: "Digital pathology image analysis for tumor-infiltrating lymphocyte quantification and survival prediction"

**Expected Workflow Steps**:
1. **Image Preprocessing** - Tissue detection and normalization
2. **Cell Segmentation** - QuPath or CellProfiler
3. **TIL Quantification** - Count immune cells in tumor regions
4. **Survival Analysis** - Cox regression with TIL scores

**Expected Parameter Generation**:
```json
{
  "step_0_image_import": {
    "tool_id": "biomate_dm_wsi_images",
    "expected_params": {
      "image_format": "svs",
      "magnification": 40,
      "tissue_type": "tumor"
    },
    "min_confidence": 0.70,
    "critical_params": ["tissue_type"]
  },
  "step_2_til_quantification": {
    "tool_id": "biomate_tool_til_scorer",
    "expected_params": {
      "cell_types": ["lymphocyte", "tumor"],
      "proximity_threshold": 50,
      "til_score_method": "spatial_density"
    },
    "min_confidence": 0.60,
    "critical_params": ["cell_types"]
  }
}
```

**Test Steps**:
1. Query: "Digital pathology image analysis for tumor-infiltrating lymphocyte quantification and survival prediction"
2. **Screenshot**: Chat
3. Workflow generation
4. **Screenshot**: Workflow
5. **Validate Parameters**:
   - Tissue type = "tumor"
   - Cell types include "lymphocyte"
   - TIL score method specified
6. Open workflow
7. **Screenshot**: 4-step workflow
8. **Screenshot**: Step 0 (image import params)
9. **Screenshot**: Step 2 (TIL quantification params)
10. Execute workflow
11. **Screenshots**: Each step
12. **Validate Outputs**:
    - Segmented cell masks
    - TIL counts per region
    - TIL spatial distribution heatmap
    - Survival curves (if clinical data provided)

**Expected Execution Time**: 15-25 minutes

**Success Criteria**:
- ✅ Tissue type = "tumor"
- ✅ Cell types include lymphocyte
- ✅ Confidence >= 0.60
- ✅ Workflow executes
- ✅ TIL quantification output generated

---

### Test Case 8: Multi-Omics Integration (Complex Multi-Branch)

**User Query**: "Integrated multi-omics analysis combining RNA-seq, proteomics, and metabolomics data"

**Expected Workflow Steps**:
```
Branch 1 (RNA-seq):
  1a. DESeq2 differential expression

Branch 2 (Proteomics):
  1b. MaxQuant protein quantification

Branch 3 (Metabolomics):
  1c. XCMS metabolite detection

Merge:
  2. MOFA+ multi-omics factor analysis
  3. Pathway enrichment across all omics
```

**Expected Parameter Generation**:
```json
{
  "step_1a_deseq2": {
    "tool_id": "biomate_dm_rnaseq_counts",
    "expected_params": {
      "organism": "human",
      "read_type": "paired"
    },
    "min_confidence": 0.75,
    "critical_params": ["organism"]
  },
  "step_1b_maxquant": {
    "tool_id": "biomate_dm_proteomics_raw",
    "expected_params": {
      "instrument_type": "orbitrap",
      "enzyme": "trypsin"
    },
    "min_confidence": 0.70,
    "critical_params": ["enzyme"]
  },
  "step_1c_xcms": {
    "tool_id": "biomate_dm_metabolomics_raw",
    "expected_params": {
      "ionization": "ESI",
      "polarity": "negative"
    },
    "min_confidence": 0.60,
    "critical_params": []
  }
}
```

**Test Steps**:
1. Query: "Integrated multi-omics analysis combining RNA-seq, proteomics, and metabolomics data"
2. **Screenshot**: Chat
3. Workflow generation (may take slightly longer)
4. **Screenshot**: Workflow generated
5. **Validate Parameters**:
   - 3 data source tools (one per omics type)
   - Organism = "human"
   - Enzyme = "trypsin"
   - Ionization mode specified
6. Open workflow
7. **Screenshot**: Multi-branch workflow
8. **Validate Structure**:
   - 3 parallel branches
   - Merge at MOFA+ step
   - Final pathway enrichment
9. **Screenshots**: Parameters for each branch (1a, 1b, 1c)
10. Execute workflow
11. **Screenshots**: Parallel execution progress
12. **Screenshots**: Merge step execution
13. **Validate Outputs**:
    - DE genes list
    - Differential proteins
    - Differential metabolites
    - MOFA+ factors
    - Integrated pathway enrichment

**Expected Execution Time**: 30-45 minutes

**Success Criteria**:
- ✅ Multi-branch workflow generated
- ✅ 3 data source tools with parameters
- ✅ Organism correctly identified
- ✅ All confidence >= 0.60
- ✅ Workflow executes with parallel branches
- ✅ Integration step completes
- ✅ Combined results generated

---

### Test Case 9: Metagenomics Functional Annotation

**User Query**: "Metagenomic shotgun sequencing analysis for taxonomic profiling and functional annotation"

**Expected Workflow Steps**:
1. **Quality Control** - Trimmomatic
2. **Host Removal** - Bowtie2 against human genome
3. **Taxonomic Classification** - Kraken2
4. **Functional Annotation** - HUMAnN3
5. **Pathway Abundance** - Stratified by taxa

**Expected Parameter Generation**:
```json
{
  "step_2_host_removal": {
    "tool_id": "biomate_dm_genome_reference",
    "expected_params": {
      "genome": "GRCh38",
      "purpose": "host_removal"
    },
    "min_confidence": 0.75,
    "critical_params": ["genome"]
  },
  "step_3_kraken2": {
    "tool_id": "biomate_tool_kraken2",
    "expected_params": {
      "database": "standard",
      "confidence": 0.1
    },
    "min_confidence": 0.65,
    "critical_params": ["database"]
  },
  "step_4_humann3": {
    "tool_id": "biomate_tool_humann3",
    "expected_params": {
      "protein_database": "uniref90",
      "nucleotide_database": "chocophlan"
    },
    "min_confidence": 0.60,
    "critical_params": []
  }
}
```

**Test Steps**:
1. Query: "Metagenomic shotgun sequencing analysis for taxonomic profiling and functional annotation"
2. **Screenshot**: Chat
3. Workflow generation
4. **Screenshot**: Workflow
5. **Validate Parameters**:
   - Host genome = "GRCh38"
   - Kraken database = "standard"
   - HUMAnN protein DB specified
6. Open workflow
7. **Screenshot**: 5-step metagenomics pipeline
8. **Screenshots**: Parameters for steps 2, 3, 4
9. Execute workflow
10. **Screenshots**: Each step completion
11. **Validate Outputs**:
    - Taxonomic composition
    - Species abundance table
    - Gene family abundances
    - Pathway abundances
    - Stratified pathway-taxa table

**Expected Execution Time**: 25-40 minutes

**Success Criteria**:
- ✅ Host genome correctly identified
- ✅ Kraken database parameter present
- ✅ HUMAnN databases specified
- ✅ Confidence >= 0.60
- ✅ Workflow executes
- ✅ Taxonomic and functional outputs generated

---

### Test Case 10: Spatial Transcriptomics Analysis

**User Query**: "Spatial transcriptomics data analysis for spatial domain identification and cell-cell interaction"

**Expected Workflow Steps**:
1. **Visium Data Import** - Load 10x Visium data
2. **Quality Control** - Filter spots and genes
3. **Spatial Clustering** - Identify spatial domains (BayesSpace or Giotto)
4. **Cell-Cell Interaction** - CellChat or similar
5. **Visualization** - Spatial plots with domains

**Expected Parameter Generation**:
```json
{
  "step_0_visium_import": {
    "tool_id": "biomate_dm_spatial_transcriptomics",
    "expected_params": {
      "platform": "visium",
      "tissue_type": "brain",
      "resolution": "standard"
    },
    "min_confidence": 0.70,
    "critical_params": ["platform"]
  },
  "step_2_spatial_clustering": {
    "tool_id": "biomate_tool_bayesspace",
    "expected_params": {
      "n_clusters": 7,
      "spatial_weight": 0.5
    },
    "min_confidence": 0.55,
    "critical_params": []
  }
}
```

**Test Steps**:
1. Query: "Spatial transcriptomics data analysis for spatial domain identification and cell-cell interaction"
2. **Screenshot**: Chat
3. Workflow generation
4. **Screenshot**: Workflow
5. **Validate Parameters**:
   - Platform = "visium" or "10x_visium"
   - Tissue type if inferred
   - Number of clusters if specified
6. Open workflow
7. **Screenshot**: 5-step spatial workflow
8. **Screenshots**: Step 0 and step 2 parameters
9. Execute workflow
10. **Screenshots**: Each step
11. **Validate Outputs**:
    - Filtered Visium object
    - Spatial domain assignments
    - Cell-cell interaction scores
    - Spatial plots with domains

**Expected Execution Time**: 18-28 minutes

**Success Criteria**:
- ✅ Platform = "visium"
- ✅ Clustering parameters present
- ✅ Confidence >= 0.55
- ✅ Workflow executes
- ✅ Spatial domains identified
- ✅ Visualization generated

---

## Parameter Validation Criteria

### Confidence Score Thresholds

**High Confidence (0.8 - 1.0)**:
- Parameter value can be used directly without user review
- Expected for explicit mentions in user query
- Example: "mouse genes" → organism="mouse" (confidence: 0.95)

**Medium Confidence (0.6 - 0.8)**:
- Parameter value reasonable but may need review
- Inferred from context or domain knowledge
- Example: "LC-MS proteomics" → ionization="ESI" (confidence: 0.72)

**Low Confidence (< 0.6)**:
- Parameter value uncertain, user review recommended
- Show in parameter preview dialog with warning
- Example: Guessing optimal cluster count (confidence: 0.45)

### Parameter Accuracy Metrics

**Critical Parameters**: Must match exactly
- Organism (human, mouse, etc.)
- Genome version (GRCh38, mm10, etc.)
- Data type (RNA-seq, proteomics, etc.)
- Screen type (knockout, activation, etc.)

**Flexible Parameters**: Within acceptable range
- Numeric thresholds (±20% acceptable)
- Method choices (similar methods acceptable)
- QC cutoffs (reasonable values acceptable)

### Validation Formula

```python
def calculate_parameter_accuracy(test_results: List[Dict]) -> float:
    """
    Calculate overall parameter accuracy across all tests.

    Returns:
        Accuracy score (0-1) representing % of correct parameters
    """
    total_params = 0
    correct_params = 0

    for test in test_results:
        for detail in test['validation']['details']:
            total_params += len(detail['expected'])
            correct_params += detail['match']['correct_count']

    return correct_params / total_params if total_params > 0 else 0.0
```

**Success Threshold**: >= 80% accuracy across all critical parameters

---

## Execution Validation

### Step-Level Validation

For each workflow step:
1. **Status Check**: Verify step status = "completed"
2. **Output Existence**: Check output files generated
3. **Output Format**: Validate file format (e.g., VCF, BAM, TSV)
4. **Output Content**: Basic content validation (non-empty, valid header)

### Workflow-Level Validation

For complete workflow:
1. **All Steps Complete**: Every step shows "completed" status
2. **No Errors**: No steps with "error" or "failed" status
3. **Execution Time**: Within expected range (no infinite loops)
4. **Final Outputs**: All expected output files present

### Tool Installation Validation

For containerized tools:
1. **On-Demand Install**: Tools install automatically when needed
2. **Install Success**: Installation completes without errors
3. **Container Running**: Container starts successfully
4. **Tool Execution**: Tool runs within container

---

## Visual Evidence Requirements

### Required Screenshots per Test

**Minimum 15 screenshots per test case**:

1. **Chat Input** - User query entered
2. **Chat Response** - Workflow suggestion message
3. **Workflow Builder** - Complete workflow visualization
4. **Step 0 Parameters** - First step with auto-filled params
5. **Parameter Dialog** (if shown) - Parameter preview before execution
6. **Execution Start** - Workflow execution initiated
7. **Step 1 Complete** - First step completion
8. **Step 2 Complete** - Second step completion
9. **Step N Complete** - Each additional step
10. **Workflow Complete** - Final completion status
11. **Output List** - Generated output files
12. **Output Preview** (optional) - Preview of key result file
13-15. **Additional Context** - Any error screens, parameter edits, etc.

### Video Recording

- **Full Test Video**: Record entire test execution from start to finish
- **Video Settings**:
  ```python
  record_video_dir="./test_videos",
  record_video_size={"width": 1920, "height": 1080}
  ```
- **Video Per Test**: Each test case generates separate video file
- **Video Archival**: Videos saved with test name and timestamp

### HTML Report

**Report Structure**:
```html
<!DOCTYPE html>
<html>
<head>
    <title>BioMate E2E Test Report - [Date]</title>
</head>
<body>
    <h1>BioMate E2E Test Report</h1>
    <div class="summary">
        <h2>Test Summary</h2>
        <p>Total Tests: 10</p>
        <p>Passed: 9</p>
        <p>Failed: 1</p>
        <p>Parameter Accuracy: 87.3%</p>
        <p>Average Execution Time: 23.4 minutes</p>
    </div>

    <div class="test-case" id="test-01">
        <h2>Test Case 1: DIA LC-MS Proteomics</h2>
        <div class="status">✅ PASSED</div>

        <h3>Parameter Validation</h3>
        <table>
            <tr>
                <th>Tool</th>
                <th>Parameter</th>
                <th>Expected</th>
                <th>Actual</th>
                <th>Confidence</th>
                <th>Match</th>
            </tr>
            <tr>
                <td>OpenSwath</td>
                <td>organism</td>
                <td>human</td>
                <td>human</td>
                <td>0.89</td>
                <td>✅</td>
            </tr>
        </table>

        <h3>Execution Results</h3>
        <p>Execution Time: 18m 32s</p>
        <p>All 4 steps completed successfully</p>

        <h3>Screenshots</h3>
        <div class="screenshots">
            <img src="test_01/01_chat_input.png" alt="Chat Input">
            <img src="test_01/02_workflow_generated.png" alt="Workflow">
            ...
        </div>

        <h3>Video</h3>
        <video controls src="videos/test_01_dia_lcms.mp4"></video>
    </div>

    <!-- Repeat for all 10 tests -->
</body>
</html>
```

---

## Success Metrics

### Overall Test Suite Metrics

**Target Metrics**:
- ✅ **Pass Rate**: >= 90% (9/10 tests passing)
- ✅ **Parameter Accuracy**: >= 80% across all critical parameters
- ✅ **Workflow Execution**: 100% of generated workflows execute without errors
- ✅ **Average Confidence**: >= 0.70 for all generated parameters
- ✅ **Execution Time**: Within 2x expected time (no hangs)

### Per-Test Metrics

**Each test must achieve**:
- ✅ Workflow generated within 15 seconds
- ✅ At least 1 tool with parameter generation
- ✅ All critical parameters correct OR confidence >= 0.70
- ✅ Workflow executes end-to-end
- ✅ Expected outputs generated
- ✅ Visual evidence captured (screenshots + video)

### Parameter Generation Metrics

**Across all 10 tests**:
- ✅ **Total Parameters Generated**: Expect 20-30 parameter sets
- ✅ **High Confidence**: >= 50% with confidence >= 0.8
- ✅ **Medium Confidence**: >= 30% with confidence 0.6-0.8
- ✅ **Low Confidence**: <= 20% with confidence < 0.6
- ✅ **Critical Param Accuracy**: >= 85% for organism, genome, data type

---

## Test Execution Command

```bash
# Run all E2E tests with visual browser
cd backend/tests/e2e_ui
pytest test_cases/ \
    --headed \
    --slowmo=500 \
    --video=on \
    --screenshot=on \
    --html=reports/test_report.html \
    --self-contained-html \
    -v

# Run single test case
pytest test_cases/test_01_dia_lcms.py::test_dia_lcms_workflow \
    --headed --slowmo=500 --video=on

# Run in parallel (careful - may interfere with visual observation)
pytest test_cases/ -n 3 --dist loadgroup
```

---

## Test Data Requirements

### Mock Data Files

For faster testing, provide mock data:
- **Small FASTQ files** (10K reads) for sequencing workflows
- **Subsampled mass spec data** for proteomics/metabolomics
- **Toy images** for digital pathology
- **Pre-computed matrices** for single cell analysis

### Data Location

```
backend/tests/e2e_ui/test_data/mock_inputs/
├── rnaseq_R1_10k.fastq.gz
├── rnaseq_R2_10k.fastq.gz
├── lcms_sample.mzML
├── crispr_counts.txt
├── wsi_image_small.svs
└── visium_sample/
    ├── filtered_feature_bc_matrix/
    └── spatial/
```

---

## Next Steps After Test Plan

1. **Implement Test Framework** (Phase 3):
   - Set up Playwright with pytest
   - Create page objects (ChatPage, WorkflowPage, ExecutionPage)
   - Build ParameterValidator and ScreenshotManager utilities

2. **Implement Test Cases** (Phase 4):
   - Write all 10 test case files
   - Add expected parameter specifications
   - Create mock data files

3. **Execute Tests** (Phase 5):
   - Run tests with visible browser
   - Collect screenshots and videos
   - Generate HTML report

4. **Analyze Results**:
   - Calculate parameter accuracy
   - Identify failure patterns
   - Document issues and improvements

---

**Document Version**: 1.0
**Total Test Cases**: 10
**Expected Total Execution Time**: 4-6 hours (sequential), 2-3 hours (parallel)
**Visual Evidence**: 150+ screenshots, 10 videos, 1 comprehensive HTML report
