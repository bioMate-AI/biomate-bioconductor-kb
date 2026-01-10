# Comprehensive Benchmark Information Schema Plan

**Date:** 2025-12-30
**Reference Paper:** You et al. (2025) "Benchmarking pre-trained genomic language models for RNA sequence-related predictive applications" Nature Communications
**DOI:** 10.1038/s41467-025-66899-y
**GitHub:** https://github.com/ShenLab-Genomics/biombenchmark

---

## 1. Problem Statement

Current benchmark storage is superficial - only citations/DOIs. We need:
- **For LLM Decision Making:** Concrete rankings, performance numbers, and condition-specific recommendations
- **For User Evidence:** Reproducible results, dataset details, and decision rationale

---

## 2. Information Schema Design

### 2.1 Benchmark Study Metadata

```json
{
  "benchmark_id": "rna_glm_benchmark_2025",
  "title": "Benchmarking pre-trained genomic language models for RNA sequence-related predictive applications",
  "citation": {
    "doi": "10.1038/s41467-025-66899-y",
    "pmid": null,
    "authors": ["Ningyuan You", "Chang Liu", "Hai Lin", "Sai Wu", "Gang Chen", "Ning Shen"],
    "journal": "Nature Communications",
    "year": 2025,
    "institution": "Zhejiang University, Liangzhu Laboratory"
  },
  "repository": {
    "url": "https://github.com/ShenLab-Genomics/biombenchmark",
    "code_available": true,
    "data_available": true
  },
  "benchmark_scope": {
    "domain": "RNA sequence analysis",
    "tool_category": "Pre-trained genomic language models",
    "num_tools_evaluated": 11,
    "num_tasks": 4,
    "num_datasets": 4
  },
  "last_updated": "2025-12-07"
}
```

### 2.2 Tools Evaluated

```json
{
  "tools": [
    {
      "tool_id": "rna_fm",
      "tool_name": "RNA-FM",
      "tool_type": "pre-trained_glm",
      "architecture": {
        "base": "Transformer",
        "tokenization": "Nucleotides",
        "embedding_size": 640,
        "trainable_params": "99.5M",
        "max_input_length": "1,024bp"
      },
      "training_data": {
        "source": "RNAcentral",
        "size": "27M sequences",
        "species": "multi-species",
        "description": "ncRNA sequences from RNAcentral"
      },
      "characteristics": ["Early foundation model", "RNA-specific pre-training"],
      "original_paper": {
        "doi": "10.1038/s41592-022-01505-3",
        "year": 2022
      },
      "availability": {
        "github": "https://github.com/ml4bio/RNA-FM",
        "huggingface": null,
        "license": "MIT"
      }
    },
    {
      "tool_id": "splicebert",
      "tool_name": "SpliceBERT",
      "tool_type": "pre-trained_glm",
      "architecture": {
        "base": "BERT",
        "tokenization": "Nucleotides",
        "embedding_size": 512,
        "trainable_params": "19.5M",
        "max_input_length": "512bp"
      },
      "training_data": {
        "source": "72 vertebrate species pre-mRNA",
        "size": "2M+ sequences",
        "species": "vertebrates",
        "description": "Captures evolutionary conservation"
      },
      "characteristics": ["Evolution-aware", "Cross-species generalization"],
      "strengths": ["m6A prediction", "Evolutionary conservation tasks"],
      "weaknesses": ["Limited input length"]
    },
    {
      "tool_id": "nucleotide_transformer",
      "tool_name": "Nucleotide Transformer",
      "tool_type": "pre-trained_glm",
      "architecture": {
        "base": "Transformer",
        "tokenization": "K-mers",
        "embedding_size": 1024,
        "trainable_params": "494M",
        "max_input_length": "2,048 6-mers (12,000bp)"
      },
      "training_data": {
        "source": "Human + multi-species genomes",
        "size": "177B nucleotide bases",
        "species": "multi-species"
      },
      "characteristics": ["Large scale", "Long context processing"],
      "strengths": ["Long sequence splicing prediction"],
      "weaknesses": ["High computational cost"]
    }
    // ... 8 more tools
  ],

  "baseline_methods": [
    {
      "tool_id": "spliceai",
      "tool_name": "SpliceAI",
      "tool_type": "task_specific_cnn",
      "task": "splicing_prediction",
      "characteristics": ["50x faster training than gLMs", "Good for initial validation"]
    },
    {
      "tool_id": "deepm6aseq",
      "tool_name": "DeepM6ASeq",
      "tool_type": "task_specific_cnn",
      "task": "m6a_prediction"
    }
  ]
}
```

### 2.3 Benchmark Tasks & Datasets

```json
{
  "tasks": [
    {
      "task_id": "ncrna_classification",
      "task_name": "ncRNA Classification",
      "task_type": "sequence_level_multiclass",
      "biological_question": "Classify non-coding RNA sequences into functional categories",
      "dataset": {
        "name": "nRC dataset",
        "source": "Multiple ncRNA databases",
        "size": "100,198 sequences",
        "num_classes": 16,
        "classes": ["miRNA", "circRNA", "lncRNA", "rRNA", "tRNA", "snRNA", "snoRNA", ...],
        "sequence_length_range": "50-5000bp",
        "balanced": false,
        "download_url": "Included in repository"
      },
      "evaluation_metrics": ["Accuracy", "F1-score", "Top-k accuracy"],
      "difficulty": "moderate",
      "key_challenges": ["Class imbalance", "Variable sequence lengths"]
    },
    {
      "task_id": "m6a_prediction",
      "task_name": "m6A Methylation Prediction",
      "task_type": "single_site_binary_classification",
      "biological_question": "Predict whether adenosine at center position is m6A methylated",
      "dataset": {
        "name": "miCLIP-seq dataset",
        "source": "miCLIP-seq experiments",
        "size": "61,661 sequences",
        "context_window": "101bp centered on adenosine",
        "positive_negative_ratio": "~1:1",
        "download_url": "Google Drive link"
      },
      "evaluation_metrics": ["Accuracy", "PR-AUC", "ROC-AUC"],
      "difficulty": "moderate",
      "key_challenges": ["Sequence context importance", "Evolutionary conservation signals"]
    },
    {
      "task_id": "splicing_prediction",
      "task_name": "Alternative Splicing Prediction",
      "task_type": "nucleotide_resolution_multilabel",
      "biological_question": "Identify splice donor/acceptor sites and tissue-specific usage",
      "dataset": {
        "name": "GTEx RNA-seq",
        "source": "GTEx consortium",
        "size": "341,830 sequences",
        "tissues": "53 tissue types (simplified to 15)",
        "context_window": "Variable (short: 400bp, long: 10,000bp)",
        "download_url": "Generated via makedata_splice.sh (~50GB)"
      },
      "evaluation_metrics": ["PR-AUC (splice sites)", "PR-AUC (tissue-specific)"],
      "subtasks": [
        {"name": "Splice site detection", "type": "binary"},
        {"name": "Tissue-specific usage", "type": "multilabel", "num_labels": 15}
      ],
      "difficulty": "hard",
      "key_challenges": ["Long-range dependencies", "Tissue specificity"]
    },
    {
      "task_id": "translation_efficiency",
      "task_name": "Translation Efficiency Prediction",
      "task_type": "regression",
      "biological_question": "Predict mean ribosome loading (MRL) from 5'UTR sequence",
      "dataset": {
        "name": "MPRA dataset",
        "source": "Massively Parallel Reporter Assay",
        "size": "91,519 sequences",
        "target": "Mean Ribosome Loading (MRL)",
        "sequence_type": "5'UTR"
      },
      "evaluation_metrics": ["MSE", "MAE", "R² error", "Spearman correlation"],
      "difficulty": "hard",
      "key_challenges": ["Continuous prediction", "UTR-specific features"]
    }
  ]
}
```

### 2.4 Results & Rankings (THE CORE)

```json
{
  "results": {
    "overall_summary": {
      "key_finding": "No single model dominates all tasks",
      "best_overall": null,
      "recommendation": "Choose based on specific task requirements"
    },

    "task_rankings": {
      "ncrna_classification": {
        "metric": "Accuracy",
        "rankings": [
          {"rank": 1, "tool": "RNA-FM", "score": 0.92, "std": 0.01},
          {"rank": 2, "tool": "SpliceBERT", "score": 0.91, "std": 0.01},
          {"rank": 3, "tool": "DNABERT2", "score": 0.89, "std": 0.02}
        ],
        "insight": "RNA-specific pre-training beneficial"
      },

      "m6a_prediction": {
        "metric": "PR-AUC",
        "rankings": [
          {"rank": 1, "tool": "SpliceBERT", "score": 0.87, "std": 0.01, "note": "Evolutionary conservation helps"},
          {"rank": 2, "tool": "RNA-FM", "score": 0.85, "std": 0.01},
          {"rank": 3, "tool": "RNABERT", "score": 0.84, "std": 0.02}
        ],
        "insight": "SpliceBERT excels due to evolutionary conservation knowledge",
        "comparison_to_baseline": {
          "DeepM6ASeq": {"score": 0.82, "note": "Task-specific baseline"}
        }
      },

      "splicing_prediction": {
        "conditions": {
          "short_input": {
            "context": "400bp",
            "metric": "PR-AUC",
            "rankings": [
              {"rank": 1, "tool": "SpliceBERT", "score": 0.91},
              {"rank": 2, "tool": "DNABERT2", "score": 0.89}
            ]
          },
          "long_input": {
            "context": "10,000bp",
            "metric": "PR-AUC",
            "rankings": [
              {"rank": 1, "tool": "Nucleotide Transformer", "score": 0.94, "note": "Excels at long sequences"},
              {"rank": 2, "tool": "GENA-LM-Large", "score": 0.92}
            ],
            "insight": "Long context critical for splicing; NT excels here"
          }
        },
        "tissue_specific": {
          "metric": "Average PR-AUC across 15 tissues",
          "rankings": [
            {"rank": 1, "tool": "Nucleotide Transformer", "score": 0.78},
            {"rank": 2, "tool": "DNABERT2", "score": 0.75}
          ]
        }
      },

      "translation_efficiency": {
        "conditions": {
          "freeze_backbone": {
            "metric": "Spearman correlation",
            "rankings": [
              {"rank": 1, "tool": "UTR-LM", "score": 0.72, "note": "Pre-trained on UTR data"},
              {"rank": 2, "tool": "RNA-FM", "score": 0.68}
            ],
            "insight": "UTR-specific pre-training crucial when backbone frozen"
          },
          "finetune_all": {
            "metric": "Spearman correlation",
            "rankings": [
              {"rank": 1, "tool": "RNA-FM", "score": 0.75},
              {"rank": 2, "tool": "SpliceBERT", "score": 0.73}
            ]
          }
        }
      }
    },

    "cross_cutting_findings": {
      "small_data_performance": {
        "finding": "gLMs excel with limited training data (<10K samples)",
        "evidence": "10% data experiments show gLMs maintain >80% performance",
        "recommendation": "Use gLMs for small datasets, task-specific methods for large datasets"
      },
      "long_sequence_performance": {
        "finding": "Nucleotide Transformer and GENA-LM best for >1000bp sequences",
        "evidence": "Splicing with 10Kbp context: NT achieves 0.94 PR-AUC vs 0.85 for short-context models"
      },
      "computational_efficiency": {
        "finding": "Task-specific CNNs (SpliceAI) train 50x faster",
        "recommendation": "Use CNNs for initial validation, gLMs for final models"
      },
      "model_size_vs_performance": {
        "finding": "'Bigger is not always better' - data-task alignment matters more",
        "evidence": "19M param SpliceBERT outperforms 494M param NT on m6A task"
      }
    }
  }
}
```

### 2.5 Decision Guidance (For LLM Tool Selection)

```json
{
  "decision_tree": {
    "question_1": {
      "question": "What is your data size?",
      "options": {
        "small (<10K samples)": {
          "recommendation": "Use pre-trained gLM (RNA-FM or SpliceBERT)",
          "reason": "gLMs leverage pre-training knowledge, perform well with limited data"
        },
        "large (>50K samples)": {
          "recommendation": "Consider task-specific methods OR gLMs",
          "reason": "Large data can train task-specific models effectively"
        }
      }
    },
    "question_2": {
      "question": "What is your sequence length requirement?",
      "options": {
        "short (<512bp)": {
          "recommendation": "RNA-FM, SpliceBERT, RNABERT",
          "reason": "Sufficient context, efficient computation"
        },
        "medium (512-2000bp)": {
          "recommendation": "DNABERT2, RNA-FM",
          "reason": "Balance of context and efficiency"
        },
        "long (>2000bp)": {
          "recommendation": "Nucleotide Transformer, GENA-LM",
          "reason": "Only these support long context effectively"
        }
      }
    },
    "question_3": {
      "question": "What is your task type?",
      "options": {
        "ncRNA classification": {
          "best": "RNA-FM",
          "alternatives": ["SpliceBERT", "DNABERT2"]
        },
        "m6A modification": {
          "best": "SpliceBERT",
          "reason": "Evolutionary conservation knowledge",
          "alternatives": ["RNA-FM"]
        },
        "splicing prediction": {
          "short_context_best": "SpliceBERT",
          "long_context_best": "Nucleotide Transformer",
          "fast_baseline": "SpliceAI"
        },
        "translation efficiency": {
          "best": "UTR-LM (if available) or RNA-FM",
          "reason": "UTR-specific pre-training helps"
        }
      }
    },
    "question_4": {
      "question": "What are your computational constraints?",
      "options": {
        "limited GPU": {
          "recommendation": "SpliceBERT (19M params), RNABERT (480K params)",
          "reason": "Smaller models, faster inference"
        },
        "high-end GPU": {
          "recommendation": "Nucleotide Transformer, GENA-LM-Large",
          "reason": "Can leverage full model capacity"
        }
      }
    }
  },

  "quick_recommendations": {
    "general_rna_analysis": "RNA-FM - good all-rounder",
    "modification_prediction": "SpliceBERT - leverages evolutionary conservation",
    "long_sequence_tasks": "Nucleotide Transformer - best long context handling",
    "limited_data": "Any gLM over task-specific methods",
    "fast_prototyping": "SpliceAI or task-specific CNN baselines"
  }
}
```

### 2.6 User Evidence Templates

```json
{
  "evidence_templates": {
    "tool_recommendation": {
      "template": "Based on {benchmark_paper} ({year}), {tool_name} achieved rank #{rank} with {metric}={score} for {task_name}. This benchmark evaluated {num_tools} tools on {dataset_size} samples.",
      "example": "Based on You et al. (2025) Nature Communications, SpliceBERT achieved rank #1 with PR-AUC=0.87 for m6A prediction. This benchmark evaluated 11 tools on 61,661 samples."
    },
    "comparison": {
      "template": "{tool_a} outperformed {tool_b} by {difference} on {task} ({metric}: {score_a} vs {score_b}). Key factor: {reason}.",
      "example": "Nucleotide Transformer outperformed SpliceBERT by 0.09 on long-context splicing (PR-AUC: 0.94 vs 0.85). Key factor: Superior handling of 10,000bp sequences."
    },
    "condition_specific": {
      "template": "For {condition}, {tool_name} is recommended. Evidence: {evidence}",
      "example": "For datasets with <10K samples, RNA-FM is recommended. Evidence: In 10% data experiments, gLMs maintained >80% of full-data performance while task-specific methods dropped significantly."
    }
  }
}
```

---

## 3. Database Schema Design

### 3.1 Tables

```sql
-- Benchmark studies
CREATE TABLE benchmark_studies (
    id INTEGER PRIMARY KEY,
    benchmark_id TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    doi TEXT,
    pmid TEXT,
    authors TEXT,  -- JSON array
    journal TEXT,
    year INTEGER,
    repository_url TEXT,
    domain TEXT,  -- e.g., "RNA analysis", "protein structure", "variant calling"
    tool_category TEXT,  -- e.g., "genomic language models", "aligners"
    num_tools INTEGER,
    num_tasks INTEGER,
    last_updated TEXT,
    raw_data JSON  -- Full benchmark metadata
);

-- Tools in benchmarks
CREATE TABLE benchmark_tools (
    id INTEGER PRIMARY KEY,
    benchmark_id TEXT REFERENCES benchmark_studies(benchmark_id),
    tool_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    tool_type TEXT,  -- "pre-trained_glm", "task_specific_cnn", etc.
    architecture JSON,  -- {base, tokenization, params, max_input}
    training_data JSON,  -- {source, size, species}
    strengths TEXT,  -- JSON array
    weaknesses TEXT,  -- JSON array
    original_paper_doi TEXT,
    github_url TEXT
);

-- Benchmark tasks/datasets
CREATE TABLE benchmark_tasks (
    id INTEGER PRIMARY KEY,
    benchmark_id TEXT REFERENCES benchmark_studies(benchmark_id),
    task_id TEXT NOT NULL,
    task_name TEXT NOT NULL,
    task_type TEXT,  -- "classification", "regression", "multilabel"
    biological_question TEXT,
    dataset_name TEXT,
    dataset_source TEXT,
    dataset_size INTEGER,
    evaluation_metrics TEXT,  -- JSON array
    difficulty TEXT,
    key_challenges TEXT  -- JSON array
);

-- Results (THE CORE TABLE)
CREATE TABLE benchmark_results (
    id INTEGER PRIMARY KEY,
    benchmark_id TEXT REFERENCES benchmark_studies(benchmark_id),
    task_id TEXT,
    condition TEXT,  -- e.g., "short_input", "long_input", "10%_data"
    tool_id TEXT,
    tool_name TEXT,
    metric TEXT,
    score REAL,
    std REAL,
    rank INTEGER,
    notes TEXT,
    UNIQUE(benchmark_id, task_id, condition, tool_id, metric)
);

-- Decision rules (for LLM)
CREATE TABLE benchmark_decision_rules (
    id INTEGER PRIMARY KEY,
    benchmark_id TEXT REFERENCES benchmark_studies(benchmark_id),
    rule_type TEXT,  -- "data_size", "sequence_length", "task_type", "compute"
    condition TEXT,
    recommendation TEXT,
    recommended_tools TEXT,  -- JSON array
    reason TEXT,
    evidence TEXT
);

-- Cross-cutting findings
CREATE TABLE benchmark_findings (
    id INTEGER PRIMARY KEY,
    benchmark_id TEXT REFERENCES benchmark_studies(benchmark_id),
    finding_type TEXT,  -- "small_data", "long_sequence", "efficiency"
    finding TEXT,
    evidence TEXT,
    recommendation TEXT
);
```

### 3.2 Indexes for Fast Lookup

```sql
CREATE INDEX idx_results_task ON benchmark_results(task_id);
CREATE INDEX idx_results_tool ON benchmark_results(tool_id);
CREATE INDEX idx_results_rank ON benchmark_results(rank);
CREATE INDEX idx_tools_name ON benchmark_tools(tool_name);
CREATE INDEX idx_studies_domain ON benchmark_studies(domain);
```

---

## 4. Usage Patterns

### 4.1 LLM Query: "Which tool for m6A prediction?"

```sql
SELECT br.tool_name, br.score, br.rank, br.notes, bf.finding
FROM benchmark_results br
LEFT JOIN benchmark_findings bf ON br.benchmark_id = bf.benchmark_id
WHERE br.task_id = 'm6a_prediction'
  AND br.metric = 'PR-AUC'
ORDER BY br.rank
LIMIT 5;
```

**Response to user:**
> For m6A methylation prediction, I recommend **SpliceBERT** based on the You et al. (2025) benchmark in Nature Communications:
> - Ranked #1 with PR-AUC = 0.87
> - Key advantage: Leverages evolutionary conservation from 72 vertebrate species
> - Outperforms task-specific baseline DeepM6ASeq (0.82)

### 4.2 LLM Query: "I have only 5000 training samples"

```sql
SELECT recommendation, recommended_tools, reason, evidence
FROM benchmark_decision_rules
WHERE rule_type = 'data_size' AND condition = 'small';
```

**Response to user:**
> With limited data (5000 samples), pre-trained genomic language models are recommended:
> - **Best options:** RNA-FM, SpliceBERT
> - **Evidence:** In 10% data experiments, gLMs maintained >80% performance while task-specific methods dropped significantly
> - **Reason:** Pre-training provides strong initialization that compensates for limited task-specific data

### 4.3 LLM Query: "Compare RNA-FM vs Nucleotide Transformer"

```sql
SELECT task_id, condition,
       MAX(CASE WHEN tool_id='rna_fm' THEN score END) as rna_fm,
       MAX(CASE WHEN tool_id='nucleotide_transformer' THEN score END) as nt
FROM benchmark_results
WHERE tool_id IN ('rna_fm', 'nucleotide_transformer')
GROUP BY task_id, condition;
```

---

## 5. Extension to Other Benchmarks

### 5.1 Priority Benchmark Papers to Add

| Domain | Benchmark Paper | Tools Covered |
|--------|-----------------|---------------|
| RNA-seq Alignment | Baruzzo et al. (2017) | STAR, HISAT2, TopHat2, BWA |
| Variant Calling | Supernat et al. (2018) | GATK, FreeBayes, DeepVariant |
| Single-cell RNA | Luecken et al. (2022) | Seurat, Scanpy, scVI, Harmony |
| Protein Structure | CASP15 (2024) | AlphaFold2, ESMFold, RoseTTAFold |
| Metagenomics | Ye et al. (2019) | Kraken2, MetaPhlAn, Centrifuge |
| Differential Expression | Soneson & Robinson (2018) | DESeq2, edgeR, limma |

### 5.2 Data Collection Workflow

1. **Identify benchmark paper** (peer-reviewed, comprehensive)
2. **Extract metadata** (tools, tasks, datasets, metrics)
3. **Parse results tables** (rankings, scores, conditions)
4. **Derive decision rules** (from paper conclusions)
5. **Store in database** (structured format)
6. **Validate** (cross-check with supplementary data)

---

## 6. Implementation Plan

### Phase 1: Schema Implementation (This Session)
- [ ] Create database tables
- [ ] Populate with RNA gLM benchmark data

### Phase 2: Query API
- [ ] Create Python functions for common queries
- [ ] Integrate with LLM tool recommendation

### Phase 3: Benchmark Expansion
- [ ] Add 5-10 more benchmark papers
- [ ] Cover major bioinformatics domains

### Phase 4: User Interface
- [ ] Evidence display in tool recommendations
- [ ] Benchmark comparison views

---

## 7. Key Design Principles

1. **Actionable Rankings:** Not just "Tool A is good" but "Tool A ranks #1 for task X with score Y"
2. **Condition-Specific:** Same tool may be best/worst depending on context
3. **Evidence-Backed:** Every recommendation cites specific benchmark results
4. **Updatable:** New benchmarks can be added without schema changes
5. **Query-Optimized:** Fast lookups for LLM decision-making
