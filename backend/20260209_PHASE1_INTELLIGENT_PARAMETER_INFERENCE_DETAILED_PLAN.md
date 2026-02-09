# Phase 1: Intelligent Parameter Inference - Detailed Implementation Plan
## Systematic Context Gathering + Pilot Analysis + Test Harness Integration

**Date:** February 9, 2026
**Problem:** Simple "ask and suggest" is insufficient - parameter inference requires systematic context gathering, pilot data analysis, and optimization through evaluation.

**Inspiration:** Cryo-EM smart platform's context-aware intelligence (sample type, GPU detection, molecular weight → particle size estimation)

---

## Executive Summary

**The Challenge:** To recommend optimal parameters, we need:
1. **User context** (experimental design, organism, goals) - *some users can provide*
2. **Data characteristics** (GC content, read quality, particle size) - *require pilot analysis*
3. **Computational constraints** (GPU memory, CPU cores, runtime limits) - *system detectable*
4. **Empirical optima** (what actually works best) - *require test harness evaluation*

**The Solution:** 4-tier intelligent system:
- **Tier 1:** Progressive context gathering via LLM dialogue
- **Tier 2:** Automated pilot data analysis
- **Tier 3:** System environment detection
- **Tier 4:** Test harness parameter optimization

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     USER QUERY                                  │
│   "Analyze ChIP-seq data for H3K27me3 in mouse brain"          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  TIER 1: CONTEXT REQUIREMENTS DATABASE                          │
│  - Query tool's parameter context requirements                  │
│  - Identify what we need to know:                               │
│    ✓ User-providable: organism, antibody target, tissue        │
│    ✗ Data-dependent: sequencing depth, read length, quality    │
│    ✗ Empirical: optimal q-value, peak-calling strategy         │
└────────────────────┬────────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌──────────────────┐    ┌──────────────────┐
│ TIER 2: LLM      │    │ TIER 3: PILOT    │
│ DIALOGUE         │    │ ANALYSIS         │
│                  │    │                  │
│ Progressive Q&A  │    │ Quick data scan  │
│ - Mark type?     │    │ - FastQC stats   │
│ - Organism?      │    │ - BAM peek       │
│ - Goal?          │    │ - File headers   │
└────────┬─────────┘    └────────┬─────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
         ┌───────────────────────┐
         │ TIER 4: ENVIRONMENT   │
         │ DETECTION             │
         │ - GPU memory          │
         │ - CPU cores           │
         │ - Disk space          │
         └───────────┬───────────┘
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  PARAMETER INFERENCE ENGINE                                     │
│  1. Match context → situations (from expert knowledge)          │
│  2. Apply pilot analysis results                                │
│  3. Adjust for system constraints                               │
│  4. Query test harness for empirical optima (if available)      │
└────────────────────┬────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  PARAMETER RECOMMENDATIONS                                      │
│  - peak_type: "broad" (from expert knowledge: H3K27me3)         │
│  - qvalue: 0.05 (from expert knowledge: broad marks)            │
│  - extsize: 200 (from pilot: median fragment length = 180bp)   │
│  - low_mem_mode: True (from environment: GPU = 8GB < 16GB)     │
│  - num_replicates: 2 (from pilot: detected 2 BAM files)        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component 1: Parameter Context Requirements Database

### 1.1 Schema Design

**New file:** `backend/lib/galaxy/ai/knowledge/parameter_context_requirements.json`

```json
{
  "biomni/genomics/perform_chipseq_peak_calling_with_macs2": {
    "parameters": {
      "peak_type": {
        "context_type": "user_providable",
        "required_context": ["antibody_target", "histone_mark_type"],
        "question_template": "What histone mark or transcription factor are you targeting?",
        "parse_function": "classify_mark_type",
        "examples": {
          "H3K27me3": "broad",
          "H3K4me3": "narrow",
          "CTCF": "narrow"
        }
      },
      "qvalue": {
        "context_type": "expert_knowledge",
        "depends_on": ["peak_type"],
        "mapping": {
          "broad": 0.05,
          "narrow": 0.01
        }
      },
      "extsize": {
        "context_type": "data_dependent",
        "pilot_analysis": "estimate_fragment_size",
        "pilot_params": {
          "input_file": "bam_file",
          "method": "cross_correlation",
          "fallback": 200
        }
      },
      "gsize": {
        "context_type": "user_providable",
        "required_context": ["organism"],
        "question_template": "What organism is this data from?",
        "mapping": {
          "human": "hs",
          "mouse": "mm",
          "drosophila": "dm"
        }
      },
      "shift": {
        "context_type": "data_dependent",
        "pilot_analysis": "estimate_fragment_shift",
        "depends_on": ["sequencing_protocol"],
        "conditions": {
          "single_end": "use_extsize/2",
          "paired_end": "auto"
        }
      }
    }
  },

  "biomni/molecular_biology/design_primer": {
    "parameters": {
      "primer_length": {
        "context_type": "data_dependent",
        "pilot_analysis": "analyze_template_gc_content",
        "pilot_params": {
          "input_file": "template_sequence",
          "window_size": 100,
          "analysis_type": "gc_percentage"
        },
        "decision_tree": {
          "gc_content < 35": "22-25bp",  // AT-rich
          "gc_content 35-65": "20-22bp",  // balanced
          "gc_content > 65": "22-25bp"    // GC-rich
        }
      },
      "melting_temperature": {
        "context_type": "user_providable",
        "required_context": ["application_type"],
        "question_template": "What is the PCR application? (standard/qPCR/mutagenesis/colony)",
        "mapping": {
          "standard": "58-62C",
          "qpcr": "60-63C",
          "mutagenesis": "78-82C",
          "colony": "55-58C"
        }
      },
      "gc_content_target": {
        "context_type": "data_dependent",
        "pilot_analysis": "analyze_template_gc_content",
        "adjustment": "match_template_gc_within_10_percent"
      }
    }
  },

  "biomni/genomics/create_scvi_embeddings_scRNA": {
    "parameters": {
      "n_latent": {
        "context_type": "data_dependent",
        "pilot_analysis": "estimate_scrnaseq_complexity",
        "pilot_params": {
          "input_file": "counts_matrix",
          "metrics": ["num_genes", "num_cell_types", "batch_effects"]
        },
        "decision_tree": {
          "num_cell_types <= 5 AND batch_effects == 'minimal'": 10,
          "num_cell_types 6-15 OR batch_effects == 'moderate'": 20,
          "num_cell_types > 15 OR batch_effects == 'strong'": 30
        }
      },
      "n_layers": {
        "context_type": "data_dependent",
        "depends_on": ["dataset_size"],
        "pilot_analysis": "count_cells_and_genes",
        "decision_tree": {
          "num_cells < 5000": 1,
          "num_cells 5000-50000": 2,
          "num_cells > 50000": 3
        }
      }
    }
  },

  "biomni/bioimaging/segment_with_nn_unet": {
    "parameters": {
      "configuration": {
        "context_type": "data_dependent",
        "pilot_analysis": "analyze_image_dimensions_and_anisotropy",
        "pilot_params": {
          "input_file": "image_stack",
          "metrics": ["voxel_spacing", "image_size", "anisotropy_ratio"]
        },
        "decision_tree": {
          "anisotropy_ratio < 3 AND image_size[2] >= 64": "3d_fullres",
          "anisotropy_ratio >= 3 OR image_size[2] < 64": "2d",
          "image_size[0] > 512 OR image_size[1] > 512": "3d_lowres_then_cascade"
        }
      },
      "patch_size": {
        "context_type": "environment_dependent",
        "pilot_analysis": "detect_gpu_memory",
        "adjustment": "scale_patch_size_to_gpu_memory",
        "constraints": {
          "gpu_memory < 8GB": "reduce_by_50_percent",
          "gpu_memory 8-16GB": "use_default",
          "gpu_memory > 16GB": "increase_by_25_percent"
        }
      }
    }
  }
}
```

### 1.2 Context Type Classification

| Context Type | How to Obtain | Example Parameters |
|--------------|---------------|-------------------|
| **user_providable** | LLM dialogue | organism, antibody target, experimental goal, sample type |
| **data_dependent** | Pilot analysis | GC content, sequencing depth, particle size, image anisotropy |
| **environment_dependent** | System detection | GPU memory, CPU cores, disk space, network bandwidth |
| **expert_knowledge** | Load from expert_parameters | Derived from other context via rules |
| **empirical_optimal** | Test harness query | Best-performing value from historical runs |

---

## Component 2: Progressive Context Gathering (LLM Dialogue)

### 2.1 Context Gathering Agent

**New file:** `backend/lib/galaxy/ai/agents/context_gatherer.py`

```python
class ContextGatherer:
    """
    Systematically gathers required context from user through progressive dialogue.
    """

    def __init__(self, tool_id: str):
        self.tool_id = tool_id
        self.requirements = load_context_requirements(tool_id)
        self.gathered_context = {}
        self.questions_asked = []

    def gather_context(self, initial_query: str) -> dict:
        """
        Main entry point: extract what we can from initial query, then ask for missing info.
        """
        # Step 1: Parse initial query for any context clues
        self.gathered_context = self.extract_from_query(initial_query)

        # Step 2: Identify what's still needed
        missing_user_providable = self.identify_missing_user_context()

        # Step 3: Generate progressive questions
        if missing_user_providable:
            questions = self.generate_context_questions(missing_user_providable)
            return {
                'status': 'need_more_context',
                'questions': questions,
                'gathered_so_far': self.gathered_context
            }
        else:
            return {
                'status': 'context_complete',
                'context': self.gathered_context
            }

    def extract_from_query(self, query: str) -> dict:
        """
        Use LLM to extract context from user's natural language query.
        """
        prompt = f"""
        Extract experimental context from this user query for tool {self.tool_id}:

        User query: "{query}"

        Required context fields (from parameter context requirements):
        {json.dumps(self.get_user_providable_fields(), indent=2)}

        Return a JSON object with extracted values. Use null for fields not mentioned.
        Be generous in inference (e.g., "H3K27me3" → antibody_target="H3K27me3",
        histone_mark_type="broad").
        """

        response = claude_api.structured_completion(
            prompt,
            schema=ContextExtraction,
            model="sonnet-4"
        )

        return response.context

    def identify_missing_user_context(self) -> list:
        """
        Find which user-providable context fields are still None.
        """
        missing = []
        for param_name, param_req in self.requirements['parameters'].items():
            if param_req['context_type'] != 'user_providable':
                continue

            for field in param_req['required_context']:
                if field not in self.gathered_context or self.gathered_context[field] is None:
                    missing.append({
                        'field': field,
                        'parameter': param_name,
                        'question_template': param_req['question_template'],
                        'examples': param_req.get('examples', {})
                    })

        return missing

    def generate_context_questions(self, missing_fields: list) -> list:
        """
        Generate user-friendly questions to fill missing context.

        Use progressive disclosure: don't ask everything at once.
        Group related questions.
        """
        # Prioritize: organism > experiment type > technical details
        priority_order = ['organism', 'antibody_target', 'sample_type', 'experimental_goal']

        sorted_fields = sorted(
            missing_fields,
            key=lambda x: priority_order.index(x['field']) if x['field'] in priority_order else 999
        )

        # Ask max 3 questions at a time (progressive disclosure)
        questions_to_ask = sorted_fields[:3]

        formatted_questions = []
        for field_info in questions_to_ask:
            formatted_questions.append({
                'field': field_info['field'],
                'question': field_info['question_template'],
                'type': 'select' if field_info.get('examples') else 'text',
                'options': list(field_info['examples'].keys()) if field_info.get('examples') else None,
                'help_text': f"This helps us determine the optimal {field_info['parameter']}"
            })

        return formatted_questions

    def update_context(self, user_answers: dict):
        """
        User provided answers to questions - update gathered context.
        """
        self.gathered_context.update(user_answers)
        self.questions_asked.extend(user_answers.keys())
```

### 2.2 UI Integration: Progressive Question Flow

**Frontend component:**

```typescript
// frontend/src/components/ContextGatheringWizard.tsx

function ContextGatheringWizard({ toolId, initialQuery, onContextComplete }) {
  const [step, setStep] = useState(1);
  const [context, setContext] = useState({});
  const [questions, setQuestions] = useState([]);

  useEffect(() => {
    // Initial context extraction
    fetch('/api/ai/context/gather', {
      method: 'POST',
      body: JSON.stringify({ tool_id: toolId, query: initialQuery })
    })
    .then(r => r.json())
    .then(data => {
      if (data.status === 'need_more_context') {
        setQuestions(data.questions);
        setContext(data.gathered_so_far);
      } else {
        onContextComplete(data.context);
      }
    });
  }, [toolId, initialQuery]);

  const handleAnswers = (answers) => {
    fetch('/api/ai/context/update', {
      method: 'POST',
      body: JSON.stringify({ tool_id: toolId, answers })
    })
    .then(r => r.json())
    .then(data => {
      setContext(data.context);
      if (data.status === 'context_complete') {
        onContextComplete(data.context);
      } else {
        setQuestions(data.questions);
        setStep(step + 1);
      }
    });
  };

  return (
    <div className="context-wizard">
      <ProgressBar currentStep={step} totalSteps={estimateSteps(questions)} />

      <h3>Help us optimize parameters for your experiment</h3>
      <p className="subtitle">We've extracted some information from your request:</p>

      <ContextSummary context={context} />

      {questions.length > 0 && (
        <QuestionGroup
          questions={questions}
          onSubmit={handleAnswers}
          onSkip={() => onContextComplete(context)}  // Allow skipping
        />
      )}
    </div>
  );
}
```

---

## Component 3: Automated Pilot Data Analysis

### 3.1 Pilot Analysis Registry

**New file:** `backend/lib/galaxy/ai/pilot_analysis/registry.py`

```python
PILOT_ANALYZERS = {
    # === Genomics ===
    "estimate_fragment_size": {
        "input_type": "bam",
        "tool": "samtools_stats",
        "extract": "insert_size_average",
        "runtime": "~30s per 10M reads",
        "fallback": 200
    },

    "estimate_fragment_shift": {
        "input_type": "bam",
        "tool": "cross_correlation_analysis",
        "extract": "peak_shift",
        "runtime": "~2min per 100M reads"
    },

    "detect_sequencing_protocol": {
        "input_type": "bam/fastq",
        "tool": "samtools_view + header_parse",
        "extract": "single_end_vs_paired_end",
        "runtime": "<5s"
    },

    "estimate_read_quality": {
        "input_type": "fastq",
        "tool": "fastqc_lite",  // Quick version, skip plots
        "extract": ["mean_quality_score", "sequence_duplication_level", "gc_content"],
        "runtime": "~1min per 50M reads"
    },

    "count_reads_and_depth": {
        "input_type": "bam/fastq",
        "tool": "wc + samtools_flagstat",
        "extract": ["total_reads", "mapped_reads", "estimated_depth"],
        "runtime": "<30s"
    },

    "analyze_template_gc_content": {
        "input_type": "fasta",
        "tool": "seqkit_fx2tab",
        "extract": ["gc_percentage", "at_rich_regions", "cpg_islands"],
        "runtime": "<10s for <10kb sequences"
    },

    # === scRNA-seq ===
    "estimate_scrnaseq_complexity": {
        "input_type": "h5ad/mtx",
        "tool": "scanpy_qc",
        "extract": ["num_cells", "num_genes", "num_batches", "estimated_cell_types"],
        "runtime": "~30s per 10k cells"
    },

    "count_cells_and_genes": {
        "input_type": "h5ad/mtx",
        "tool": "anndata_shape",
        "extract": ["n_obs", "n_vars"],
        "runtime": "<5s"
    },

    "detect_batch_effects": {
        "input_type": "h5ad",
        "tool": "scanpy_batch_entropy",
        "extract": ["batch_entropy_score", "num_batches"],
        "runtime": "~1min per 10k cells"
    },

    # === Bioimaging ===
    "analyze_image_dimensions_and_anisotropy": {
        "input_type": "nifti/tiff_stack",
        "tool": "nibabel_header_read",
        "extract": ["voxel_spacing", "image_dimensions", "anisotropy_ratio"],
        "runtime": "<5s"
    },

    "detect_image_modality": {
        "input_type": "nifti/dicom",
        "tool": "metadata_parser",
        "extract": ["modality", "contrast_agent", "sequence_type"],
        "runtime": "<5s"
    },

    # === Cryo-EM ===
    "estimate_particle_size_from_micrographs": {
        "input_type": "mrc/tiff",
        "tool": "cryolo_general_model_quick",
        "extract": ["median_particle_diameter", "particle_count", "ice_thickness_estimate"],
        "runtime": "~2min for 10 micrographs"
    },

    "analyze_ctf_quality": {
        "input_type": "mrc",
        "tool": "ctffind4_quick",
        "extract": ["defocus_range", "resolution_estimate", "astigmatism"],
        "runtime": "~30s per micrograph"
    },

    "estimate_molecular_weight_from_sequence": {
        "input_type": "fasta",
        "tool": "bio_python_mass",
        "extract": ["molecular_weight_kda", "estimated_particle_diameter_angstrom"],
        "runtime": "<1s"
    },

    # === Molecular Biology ===
    "detect_repeat_regions": {
        "input_type": "fasta",
        "tool": "dust_masker",
        "extract": ["low_complexity_fraction", "repeat_fraction"],
        "runtime": "<5s for <10kb"
    },

    "find_restriction_sites": {
        "input_type": "fasta",
        "tool": "biopython_restriction_batch",
        "extract": ["common_enzyme_sites", "unique_cutters"],
        "runtime": "<5s"
    },

    # === Pharmacology ===
    "calculate_ligand_properties": {
        "input_type": "smiles",
        "tool": "rdkit_descriptors",
        "extract": ["molecular_weight", "logp", "num_rotatable_bonds", "tpsa"],
        "runtime": "<1s per molecule"
    },

    "detect_protein_binding_site": {
        "input_type": "pdb",
        "tool": "fpocket_lite",
        "extract": ["pocket_centers", "pocket_volumes", "druggability_scores"],
        "runtime": "~10s per structure"
    }
}
```

### 3.2 Pilot Analysis Executor

**New file:** `backend/lib/galaxy/ai/pilot_analysis/executor.py`

```python
class PilotAnalysisExecutor:
    """
    Executes quick pilot analyses to extract data-dependent context.
    """

    def __init__(self, max_runtime_seconds=300):
        self.max_runtime = max_runtime_seconds
        self.cache = {}  # Cache results to avoid re-analysis

    def analyze(self, analysis_name: str, input_file: str, params: dict = {}) -> dict:
        """
        Run a pilot analysis and return extracted context.

        Args:
            analysis_name: Key from PILOT_ANALYZERS registry
            input_file: Path to input data
            params: Additional parameters for the analysis

        Returns:
            dict with extracted context fields
        """
        # Check cache first
        cache_key = f"{analysis_name}:{input_file}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        analyzer = PILOT_ANALYZERS.get(analysis_name)
        if not analyzer:
            raise ValueError(f"Unknown analysis: {analysis_name}")

        # Validate input type
        if not self.validate_input_type(input_file, analyzer['input_type']):
            raise TypeError(f"Input {input_file} does not match required type {analyzer['input_type']}")

        # Execute analysis with timeout
        try:
            result = self.run_analyzer(analyzer, input_file, params)
            self.cache[cache_key] = result
            return result
        except TimeoutError:
            # Use fallback if analysis takes too long
            if 'fallback' in analyzer:
                return {'value': analyzer['fallback'], 'source': 'fallback_timeout'}
            else:
                raise

    def run_analyzer(self, analyzer: dict, input_file: str, params: dict) -> dict:
        """
        Dispatch to the appropriate analysis tool.
        """
        tool = analyzer['tool']
        extract_fields = analyzer['extract']

        if tool == "samtools_stats":
            output = subprocess.check_output(
                ['samtools', 'stats', input_file],
                timeout=self.max_runtime
            )
            stats = parse_samtools_stats(output)
            return {field: stats.get(field) for field in extract_fields}

        elif tool == "fastqc_lite":
            # Run FastQC without generating HTML (faster)
            output = subprocess.check_output(
                ['fastqc', '--extract', '--nogroup', '-o', '/tmp/', input_file],
                timeout=self.max_runtime
            )
            fastqc_data = parse_fastqc_data(f'/tmp/{os.path.basename(input_file)}_fastqc/fastqc_data.txt')
            return {field: fastqc_data.get(field) for field in extract_fields}

        elif tool == "seqkit_fx2tab":
            output = subprocess.check_output(
                ['seqkit', 'fx2tab', '--only-id', '--name', '--seq', '--gc', input_file],
                timeout=self.max_runtime
            )
            gc_content = parse_seqkit_gc(output)
            return {'gc_percentage': gc_content}

        elif tool == "nibabel_header_read":
            import nibabel as nib
            img = nib.load(input_file)
            header = img.header
            voxel_dims = header.get_zooms()
            return {
                'voxel_spacing': voxel_dims,
                'image_dimensions': img.shape,
                'anisotropy_ratio': max(voxel_dims) / min(voxel_dims)
            }

        elif tool == "anndata_shape":
            import anndata
            adata = anndata.read_h5ad(input_file)
            return {
                'n_obs': adata.n_obs,  # num cells
                'n_vars': adata.n_vars  # num genes
            }

        elif tool == "rdkit_descriptors":
            from rdkit import Chem
            from rdkit.Chem import Descriptors
            mol = Chem.MolFromSmiles(input_file)  # input_file is actually SMILES string
            return {
                'molecular_weight': Descriptors.MolWt(mol),
                'logp': Descriptors.MolLogP(mol),
                'num_rotatable_bonds': Descriptors.NumRotatableBonds(mol),
                'tpsa': Descriptors.TPSA(mol)
            }

        # ... implement other analyzers

        else:
            raise NotImplementedError(f"Analyzer tool '{tool}' not yet implemented")

    def validate_input_type(self, file_path: str, required_type: str) -> bool:
        """
        Check if file matches required input type.
        """
        ext = os.path.splitext(file_path)[1].lower()
        type_extensions = {
            'bam': ['.bam'],
            'fastq': ['.fastq', '.fq', '.fastq.gz', '.fq.gz'],
            'fasta': ['.fasta', '.fa', '.fna'],
            'h5ad': ['.h5ad'],
            'mtx': ['.mtx', '.mtx.gz'],
            'nifti': ['.nii', '.nii.gz'],
            'mrc': ['.mrc', '.mrcs'],
            'pdb': ['.pdb'],
            'smiles': ['*']  # Special case: SMILES is a string, not a file
        }

        allowed_extensions = []
        for t in required_type.split('/'):
            allowed_extensions.extend(type_extensions.get(t, []))

        return ext in allowed_extensions or '*' in allowed_extensions
```

### 3.3 Integration: Pilot Analysis Trigger

```python
class IntelligentParameterInferencer:
    """
    Enhanced parameter inferencer with pilot analysis integration.
    """

    def infer_parameters(self, tool_id: str, user_context: dict, input_files: dict) -> dict:
        """
        Args:
            tool_id: Tool to configure
            user_context: Context gathered from user dialogue
            input_files: {dataset_name: file_path} from workflow inputs

        Returns:
            Complete parameter recommendations
        """
        requirements = load_context_requirements(tool_id)

        # Collect all contexts
        all_context = user_context.copy()

        # Add environment context
        all_context['system'] = self.detect_environment()

        # Run pilot analyses for data-dependent parameters
        pilot_executor = PilotAnalysisExecutor()

        for param_name, param_req in requirements['parameters'].items():
            if param_req['context_type'] == 'data_dependent':
                analysis_name = param_req['pilot_analysis']
                input_file_key = param_req['pilot_params'].get('input_file')

                if input_file_key in input_files:
                    input_path = input_files[input_file_key]

                    try:
                        pilot_result = pilot_executor.analyze(
                            analysis_name,
                            input_path,
                            param_req.get('pilot_params', {})
                        )
                        all_context[param_name + '_pilot'] = pilot_result

                    except Exception as e:
                        logger.warning(f"Pilot analysis {analysis_name} failed: {e}")
                        # Use fallback or skip this parameter
                        if 'fallback' in PILOT_ANALYZERS[analysis_name]:
                            all_context[param_name + '_pilot'] = {
                                'value': PILOT_ANALYZERS[analysis_name]['fallback'],
                                'source': 'fallback_error'
                            }

        # Now infer parameters using complete context
        recommendations = {}

        for param_name, param_req in requirements['parameters'].items():
            recommendation = self.infer_single_parameter(
                param_name,
                param_req,
                all_context
            )
            if recommendation:
                recommendations[param_name] = recommendation

        return recommendations

    def detect_environment(self) -> dict:
        """
        Detect system environment: GPU memory, CPU cores, disk space.
        """
        import psutil
        import torch

        env = {
            'cpu_count': psutil.cpu_count(),
            'memory_gb': psutil.virtual_memory().total / (1024**3),
            'disk_free_gb': psutil.disk_usage('/').free / (1024**3)
        }

        # GPU detection
        if torch.cuda.is_available():
            env['gpu_count'] = torch.cuda.device_count()
            env['gpu_memory_gb'] = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            env['gpu_name'] = torch.cuda.get_device_name(0)
        else:
            env['gpu_count'] = 0
            env['gpu_memory_gb'] = 0

        return env
```

---

## Component 4: Test Harness Integration for Parameter Optimization

### 4.1 Test Harness as Parameter Oracle

**Concept:** The test harness runs benchmarks with different parameter combinations. Use results to find empirical optima.

**New file:** `backend/lib/galaxy/ai/test_harness/parameter_optimizer.py`

```python
class ParameterOptimizer:
    """
    Query test harness results to find empirically optimal parameters.
    """

    def __init__(self, test_harness_db: str = "backend/test_results.db"):
        self.db_path = test_harness_db

    def get_optimal_parameters(self, tool_id: str, context: dict) -> dict:
        """
        Query test harness DB for best-performing parameters given context.

        Args:
            tool_id: Tool identifier
            context: Experimental context (e.g., {'organism': 'human', 'mark_type': 'broad'})

        Returns:
            dict of {param_name: optimal_value} with metadata
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Find test runs matching this context
        cursor.execute("""
            SELECT test_id, parameters, metrics, context
            FROM test_runs
            WHERE tool_id = ?
            AND status = 'passed'
            ORDER BY run_date DESC
            LIMIT 1000
        """, (tool_id,))

        runs = cursor.fetchall()

        if not runs:
            return {}  # No test data available

        # Filter runs by context similarity
        matching_runs = []
        for test_id, params_json, metrics_json, context_json in runs:
            test_context = json.loads(context_json)
            similarity = self.calculate_context_similarity(context, test_context)
            if similarity > 0.7:  # 70% match threshold
                matching_runs.append({
                    'test_id': test_id,
                    'parameters': json.loads(params_json),
                    'metrics': json.loads(metrics_json),
                    'similarity': similarity
                })

        if not matching_runs:
            return {}

        # Find parameter values that consistently yield best metrics
        optimal_params = {}

        for param_name in self.get_tunable_parameters(tool_id):
            param_performance = defaultdict(list)

            for run in matching_runs:
                param_value = run['parameters'].get(param_name)
                if param_value is not None:
                    # Track performance for this parameter value
                    param_performance[param_value].append(run['metrics']['overall_score'])

            # Find value with best average performance
            best_value = max(
                param_performance.items(),
                key=lambda x: np.mean(x[1])
            )[0]

            optimal_params[param_name] = {
                'value': best_value,
                'confidence': len(param_performance[best_value]) / len(matching_runs),
                'source': 'test_harness_empirical',
                'num_trials': len(param_performance[best_value]),
                'avg_score': np.mean(param_performance[best_value])
            }

        conn.close()
        return optimal_params

    def calculate_context_similarity(self, context1: dict, context2: dict) -> float:
        """
        Calculate similarity between two experimental contexts.
        """
        matching_fields = 0
        total_fields = len(set(context1.keys()) | set(context2.keys()))

        for key in context1:
            if key in context2 and context1[key] == context2[key]:
                matching_fields += 1

        return matching_fields / total_fields if total_fields > 0 else 0

    def suggest_parameter_experiments(self, tool_id: str, context: dict) -> list:
        """
        Suggest parameter combinations to test to improve coverage.

        Returns list of {parameters: dict, rationale: str} to add to test harness.
        """
        current_coverage = self.assess_coverage(tool_id, context)

        suggestions = []

        # Example: If we've never tested low q-value for broad peaks, suggest it
        if context.get('mark_type') == 'broad' and not current_coverage.get('qvalue_0.01'):
            suggestions.append({
                'parameters': {'qvalue': 0.01},
                'rationale': 'Test lower q-value for broad peaks - no empirical data',
                'priority': 'high'
            })

        return suggestions
```

### 4.2 Feedback Loop: Test Harness ← → Parameter Recommendations

```
┌─────────────────────────────────────────────┐
│   PARAMETER INFERENCE ENGINE                │
│   (recommends based on expert knowledge)    │
└──────────────────┬──────────────────────────┘
                   │
                   ├─────► User runs workflow
                   │
                   ▼
┌─────────────────────────────────────────────┐
│   WORKFLOW EXECUTION                        │
│   (Galaxy/Nextflow with actual data)        │
└──────────────────┬──────────────────────────┘
                   │
                   ├─────► Job succeeds/fails
                   │
                   ▼
┌─────────────────────────────────────────────┐
│   TEST HARNESS                              │
│   - Records: parameters + results + context │
│   - Computes: success rate, quality metrics │
└──────────────────┬──────────────────────────┘
                   │
                   ├─────► Accumulates data
                   │
                   ▼
┌─────────────────────────────────────────────┐
│   PARAMETER OPTIMIZER                       │
│   - Analyzes: what parameters work best     │
│   - Updates: empirical parameter knowledge  │
└──────────────────┬──────────────────────────┘
                   │
                   └─────► Feeds back to inference engine
```

**Implementation:**

1. **Execution tracking:** Every workflow run logs to test harness DB
2. **Parameter extraction:** Capture all parameter values used
3. **Outcome metrics:** Success/failure, output quality scores, runtime
4. **Context capture:** Log experimental context (organism, data type, etc.)
5. **Analysis:** Weekly batch job to find empirically optimal parameters
6. **Update:** Merge empirical optima into expert knowledge base

---

## Component 5: Domain-Specific Pilot Analysis Workflows

### 5.1 Cryo-EM Pilot Workflow

**Goal:** Determine particle size, defocus range, ice thickness before full pipeline

```python
CRYO_EM_PILOT_WORKFLOW = {
    "name": "Cryo-EM Data Characterization",
    "description": "Quick analysis of raw micrographs to determine optimal SPA parameters",
    "steps": [
        {
            "name": "sample_micrographs",
            "tool": "random_sample",
            "params": {"num_samples": 10, "from_total": "all_micrographs"},
            "runtime": "~5s"
        },
        {
            "name": "quick_ctf_estimation",
            "tool": "ctffind4",
            "params": {"resolution_limit": "10A", "skip_diagnostic_plots": True},
            "input": "sampled_micrographs",
            "extract": ["defocus_min", "defocus_max", "astigmatism", "resolution_estimate"],
            "runtime": "~30s per micrograph = 5min total"
        },
        {
            "name": "quick_particle_picking",
            "tool": "cryolo_general_model",
            "params": {"confidence_threshold": 0.3, "box_size": "auto"},
            "input": "sampled_micrographs",
            "extract": ["particle_count", "median_particle_diameter"],
            "runtime": "~2min for 10 micrographs"
        },
        {
            "name": "ice_thickness_estimation",
            "tool": "analyze_micrograph_intensity",
            "input": "sampled_micrographs",
            "extract": ["mean_intensity", "std_intensity", "ice_quality_score"],
            "runtime": "~10s"
        }
    ],
    "total_runtime": "~8 minutes",
    "output_context": {
        "defocus_range": "from quick_ctf_estimation",
        "particle_diameter": "from quick_particle_picking",
        "ice_quality": "from ice_thickness_estimation",
        "recommended_box_size": "particle_diameter * 1.5",
        "recommended_downsampling": "based on resolution_estimate"
    },
    "parameter_decisions": {
        "particle_diameter < 100A": {
            "extraction_box_size": "particle_diameter * 2.0",
            "classification_box_size": "downsample to 256px"
        },
        "particle_diameter 100-300A": {
            "extraction_box_size": "particle_diameter * 1.5",
            "classification_box_size": "downsample to 360px"
        },
        "defocus_range > 3um": {
            "ctf_refinement": "enabled",
            "ctf_fit_resolution": "extend to 4A"
        },
        "ice_quality_score < 0.6": {
            "motion_correction_bfactor": "increase by 50",
            "particle_picking_threshold": "decrease by 0.1"
        }
    }
}
```

### 5.2 Genomics Pilot Workflows

**ChIP-seq Pilot:**

```python
CHIPSEQ_PILOT_WORKFLOW = {
    "name": "ChIP-seq Data Characterization",
    "steps": [
        {"name": "count_reads", "tool": "samtools_flagstat", "runtime": "~30s"},
        {"name": "fragment_size_dist", "tool": "samtools_stats", "runtime": "~1min"},
        {"name": "detect_protocol", "tool": "parse_bam_header", "runtime": "~5s"},
        {"name": "estimate_library_complexity", "tool": "preseq_lc_extrap", "runtime": "~2min"},
        {"name": "quick_peak_preview", "tool": "macs2_callpeak_sample", "params": {"subsample": "10M_reads"}, "runtime": "~30s"}
    ],
    "output_context": {
        "sequencing_depth": "from count_reads",
        "fragment_size": "from fragment_size_dist",
        "protocol_type": "from detect_protocol",
        "library_complexity": "from estimate_library_complexity",
        "preliminary_peak_count": "from quick_peak_preview"
    },
    "parameter_decisions": {
        "sequencing_depth < 20M": {
            "warning": "ENCODE minimum is 20M for TFs, 45M for broad marks",
            "qvalue": "relax to 0.05 (instead of 0.01) due to low depth"
        },
        "library_complexity < 0.8": {
            "warning": "Low complexity - may have PCR duplicates",
            "action": "enable duplicate removal"
        },
        "preliminary_peak_count < 100": {
            "suggestion": "Very few peaks - check antibody specificity or try broader settings"
        }
    }
}
```

**scRNA-seq Pilot:**

```python
SCRNASEQ_PILOT_WORKFLOW = {
    "name": "scRNA-seq Data Characterization",
    "steps": [
        {"name": "load_matrix", "tool": "scanpy_read", "runtime": "~10s per 10k cells"},
        {"name": "basic_qc", "tool": "scanpy_qc_metrics", "runtime": "~30s"},
        {"name": "estimate_complexity", "tool": "scanpy_highly_variable_genes", "runtime": "~1min"},
        {"name": "batch_detection", "tool": "check_obs_categorical", "runtime": "~5s"},
        {"name": "quick_clustering", "tool": "scanpy_leiden", "params": {"resolution": 0.5}, "runtime": "~2min"}
    ],
    "output_context": {
        "num_cells": "from load_matrix",
        "num_genes": "from load_matrix",
        "median_genes_per_cell": "from basic_qc",
        "median_counts_per_cell": "from basic_qc",
        "num_batches": "from batch_detection",
        "estimated_cell_types": "from quick_clustering",
        "heterogeneity_score": "calculated from quick_clustering silhouette"
    },
    "parameter_decisions": {
        "num_cells < 1000": {
            "integration_method": "Harmony (lightweight)",
            "scvi_n_latent": 5
        },
        "num_cells 1000-10000": {
            "integration_method": "scVI or Harmony",
            "scvi_n_latent": 10
        },
        "num_cells > 10000": {
            "integration_method": "scVI (handles large data)",
            "scvi_n_latent": 20
        },
        "num_batches > 5": {
            "integration_method": "scVI (better for strong batch effects)",
            "scvi_n_latent": "increase by 5"
        },
        "estimated_cell_types > 15": {
            "scvi_n_latent": 30,
            "clustering_resolution": "increase to 1.0"
        }
    }
}
```

### 5.3 Molecular Biology Pilot Workflows

**Primer Design Pilot:**

```python
PRIMER_DESIGN_PILOT_WORKFLOW = {
    "name": "Template Sequence Analysis for Primer Design",
    "steps": [
        {"name": "gc_analysis", "tool": "seqkit_fx2tab", "runtime": "~5s"},
        {"name": "repeat_detection", "tool": "dust_masker", "runtime": "~5s"},
        {"name": "secondary_structure", "tool": "rna_fold", "runtime": "~10s"},
        {"name": "restriction_sites", "tool": "find_restriction_enzymes", "runtime": "~5s"}
    ],
    "output_context": {
        "gc_content": "from gc_analysis",
        "at_rich_regions": "from gc_analysis",
        "gc_rich_regions": "from gc_analysis",
        "repeat_fraction": "from repeat_detection",
        "hairpin_risk": "from secondary_structure",
        "existing_restriction_sites": "from restriction_sites"
    },
    "parameter_decisions": {
        "gc_content < 35": {
            "primer_length": "22-25bp (longer for AT-rich templates)",
            "tm_target": "58-60C (lower than standard due to AT content)",
            "gc_clamp": "require GC at 3' end for stability"
        },
        "gc_content > 65": {
            "primer_length": "22-25bp (manage high Tm)",
            "tm_target": "60-62C (higher due to GC content)",
            "avoid_gc_runs": "max 3 consecutive G or C"
        },
        "repeat_fraction > 0.3": {
            "warning": "High repeat content - primers may have off-target binding",
            "specificity_stringency": "increase (max_amplicon_length = 500bp instead of 2000bp)"
        },
        "hairpin_risk == 'high'": {
            "secondary_structure_check": "enable strict deltaG threshold (-3 kcal/mol)",
            "avoid_regions": "mask hairpin regions from primer search"
        }
    }
}
```

---

## Component 6: End-to-End Integration

### 6.1 Complete Parameter Inference Pipeline

```python
class UnifiedParameterInferencer:
    """
    Orchestrates all 4 tiers of context gathering and parameter inference.
    """

    def __init__(self):
        self.context_gatherer = ContextGatherer()
        self.pilot_executor = PilotAnalysisExecutor()
        self.param_optimizer = ParameterOptimizer()
        self.expert_knowledge = load_all_expert_knowledge()

    async def infer_parameters_with_full_context(
        self,
        tool_id: str,
        initial_query: str,
        input_files: dict,
        user_answers: dict = {}
    ) -> dict:
        """
        Complete parameter inference pipeline.

        Returns:
            {
                'status': 'ready' | 'need_user_input' | 'running_pilot_analysis',
                'parameters': {...},  // If ready
                'questions': [...],   // If need_user_input
                'pilot_progress': {...}  // If running_pilot_analysis
            }
        """

        # === TIER 1: Context Gathering ===
        context_result = self.context_gatherer.gather_context(
            tool_id,
            initial_query,
            user_answers
        )

        if context_result['status'] == 'need_more_context':
            return {
                'status': 'need_user_input',
                'questions': context_result['questions'],
                'gathered_so_far': context_result['gathered_so_far']
            }

        user_context = context_result['context']

        # === TIER 2: Pilot Data Analysis ===
        pilot_context = {}

        requirements = load_context_requirements(tool_id)
        pilot_analyses_needed = [
            (param_name, param_req)
            for param_name, param_req in requirements['parameters'].items()
            if param_req['context_type'] == 'data_dependent'
        ]

        if pilot_analyses_needed:
            # Run pilot analyses in parallel
            pilot_tasks = []
            for param_name, param_req in pilot_analyses_needed:
                analysis_name = param_req['pilot_analysis']
                input_file_key = param_req['pilot_params'].get('input_file')

                if input_file_key in input_files:
                    pilot_tasks.append(
                        self.pilot_executor.analyze_async(
                            analysis_name,
                            input_files[input_file_key],
                            param_req['pilot_params']
                        )
                    )

            # Await all pilot analyses
            pilot_results = await asyncio.gather(*pilot_tasks, return_exceptions=True)

            for (param_name, _), result in zip(pilot_analyses_needed, pilot_results):
                if isinstance(result, Exception):
                    logger.warning(f"Pilot analysis for {param_name} failed: {result}")
                else:
                    pilot_context[param_name] = result

        # === TIER 3: Environment Detection ===
        env_context = self.detect_environment()

        # === TIER 4: Test Harness Query ===
        empirical_context = self.param_optimizer.get_optimal_parameters(
            tool_id,
            {**user_context, **pilot_context}
        )

        # === FINAL: Merge All Contexts and Infer ===
        all_context = {
            **user_context,
            **pilot_context,
            **env_context,
            **empirical_context
        }

        final_parameters = self.infer_from_merged_context(
            tool_id,
            all_context
        )

        return {
            'status': 'ready',
            'parameters': final_parameters,
            'context_used': all_context,
            'confidence_breakdown': self.calculate_confidence(final_parameters, all_context)
        }

    def infer_from_merged_context(self, tool_id: str, context: dict) -> dict:
        """
        Final parameter inference using merged context from all tiers.
        """
        requirements = load_context_requirements(tool_id)
        expert_knowledge = self.expert_knowledge.get(tool_id, {}).get('expert_parameters', {})

        recommendations = {}

        for param_name, param_req in requirements['parameters'].items():
            # Priority: empirical > pilot > expert > default

            # 1. Check empirical (test harness)
            if param_name in context and context[param_name].get('source') == 'test_harness_empirical':
                recommendations[param_name] = context[param_name]
                continue

            # 2. Check pilot analysis
            if param_req['context_type'] == 'data_dependent' and param_name in context:
                recommendations[param_name] = {
                    'value': context[param_name]['value'],
                    'source': 'pilot_analysis',
                    'confidence': 0.9
                }
                continue

            # 3. Check expert knowledge
            if param_name in expert_knowledge:
                matched_situation = self.match_situation(
                    context,
                    expert_knowledge[param_name]['situations']
                )
                if matched_situation:
                    recommendations[param_name] = {
                        'value': matched_situation['value_or_range'],
                        'source': 'expert_knowledge',
                        'situation': matched_situation['name'],
                        'reasoning': matched_situation['why'],
                        'confidence': 0.85
                    }
                    continue

            # 4. Fallback to default
            if 'fallback' in param_req:
                recommendations[param_name] = {
                    'value': param_req['fallback'],
                    'source': 'fallback_default',
                    'confidence': 0.5
                }

        return recommendations
```

### 6.2 API Endpoint

```python
# backend/lib/galaxy/api/parameter_inference.py

@router.post("/api/ai/parameters/infer")
async def infer_parameters(request: ParameterInferenceRequest):
    """
    Intelligent parameter inference with context gathering and pilot analysis.

    Request body:
    {
        "tool_id": "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
        "query": "Call peaks from H3K27me3 ChIP-seq in mouse brain",
        "input_files": {
            "bam_file": "/data/chip_seq/brain_h3k27me3.bam",
            "input_control": "/data/chip_seq/input_control.bam"
        },
        "user_answers": {  // Optional, from progressive dialogue
            "organism": "mouse",
            "antibody_target": "H3K27me3"
        }
    }

    Response:
    {
        "status": "ready",
        "parameters": {
            "peak_type": {
                "value": "broad",
                "source": "expert_knowledge",
                "reasoning": "H3K27me3 is a repressive histone mark with broad domains",
                "confidence": 0.95
            },
            "gsize": {
                "value": "mm",
                "source": "user_context",
                "confidence": 1.0
            },
            "extsize": {
                "value": 195,
                "source": "pilot_analysis",
                "reasoning": "Median fragment size from BAM cross-correlation: 195bp",
                "confidence": 0.9
            },
            "qvalue": {
                "value": 0.05,
                "source": "expert_knowledge",
                "situation": "broad_histone_marks",
                "confidence": 0.9
            }
        },
        "context_used": {
            "organism": "mouse",
            "antibody_target": "H3K27me3",
            "mark_type": "broad",
            "fragment_size": 195,
            "sequencing_depth": 45000000,
            "gpu_memory_gb": 0
        },
        "pilot_analyses_run": [
            "estimate_fragment_size",
            "count_reads_and_depth"
        ],
        "total_time_ms": 2500
    }
    ```

---

## Implementation Roadmap (8 Weeks)

### Week 1-2: Foundation
- [x] Design parameter context requirements schema
- [ ] Create context requirements DB for top 20 tools (genomics, molecular bio, bioimaging)
- [ ] Implement ContextGatherer class
- [ ] Build progressive question UI component
- [ ] Test: User can provide context via dialogue, get matched to expert knowledge

### Week 3-4: Pilot Analysis
- [ ] Implement PilotAnalysisExecutor framework
- [ ] Add 10 core pilot analyzers (FastQC, SAMtools stats, image header parsing, etc.)
- [ ] Create domain-specific pilot workflows (ChIP-seq, scRNA-seq, primer design, cryo-EM)
- [ ] Test: Pilot analysis correctly extracts GC content, fragment size, particle size

### Week 5-6: Integration
- [ ] Implement UnifiedParameterInferencer (4-tier system)
- [ ] Create API endpoints for parameter inference
- [ ] Build UI for pilot analysis progress tracking
- [ ] Integration testing: End-to-end from user query → pilot analysis → parameter recommendations

### Week 7: Test Harness Connection
- [ ] Extend test harness to log parameter values + context
- [ ] Implement ParameterOptimizer to query test results
- [ ] Create feedback loop: execution results → parameter updates
- [ ] Test: Empirical optima override expert knowledge when available

### Week 8: Polish & Documentation
- [ ] Add remaining 100+ tools to context requirements DB
- [ ] Create user documentation ("How BioMate learns your experiment")
- [ ] Performance optimization (cache pilot results, parallelize analyses)
- [ ] Deploy to staging for user testing

---

## Success Metrics

### Technical Metrics
- **Context collection success rate**: >90% of required context gathered
- **Pilot analysis coverage**: 80% of data-dependent parameters have working pilot analyzers
- **Parameter confidence**: Average confidence score >0.85
- **Pilot analysis speed**: <5 minutes for 90% of analyses

### User Experience Metrics
- **Question burden**: <5 questions per workflow (progressive disclosure)
- **Parameter override rate**: <20% (users accept our suggestions)
- **Time to workflow ready**: <10 minutes including pilot analysis
- **User satisfaction**: 4+/5 rating on "parameter recommendations were helpful"

### Scientific Quality Metrics
- **Workflow success rate**: 80%+ first-run success (vs. 50% baseline)
- **Result quality**: 90%+ of outputs pass validation checks
- **Parameter appropriateness**: Expert review confirms 95%+ of recommendations are scientifically sound

---

## Key Decisions & Trade-offs

### 1. When to Run Pilot Analysis?

**Option A: Always run pilot analysis upfront (proactive)**
- **Pro:** User gets complete recommendations immediately
- **Con:** Wastes compute if user changes input files

**Option B: Run on-demand when parameter is needed (lazy)**
- **Pro:** Only analyze what's needed
- **Con:** Delays parameter recommendations

**Decision: Hybrid approach**
- Quick pilots (<30s) run proactively
- Expensive pilots (>2min) run on-demand with progress indicator
- Cache results by file hash

### 2. How to Handle Pilot Analysis Failures?

**Strategy:**
1. Always have fallback values in expert knowledge
2. Show warning to user: "Could not analyze data, using defaults"
3. Log failure for later investigation
4. Allow user to manually override

### 3. User Context vs. Pilot Analysis Priority?

When they conflict (e.g., user says "human" but pilot detects "mouse"):
1. Show warning to user
2. Ask for confirmation
3. Default to user-provided context (user knows best)
4. Log discrepancy for review

---

## Conclusion

This comprehensive Phase 1 plan transforms parameter inference from a simple "ask and suggest" system into an intelligent, data-aware recommendation engine that:

1. **Systematically gathers context** through progressive LLM dialogue
2. **Analyzes data characteristics** via quick pilot workflows
3. **Learns from experience** through test harness integration
4. **Adapts to environment** by detecting system resources

By following the cryo-EM example and extending it systematically to all 18 domains, we create a **scientifically rigorous** parameter inference system that combines:
- Expert knowledge (from our 9.0/10 rated knowledge base)
- Empirical data (from user's actual input files)
- Historical performance (from test harness results)
- System constraints (GPU memory, runtime limits)

This positions BioMate as an **intelligent scientific assistant** rather than just a workflow executor.
