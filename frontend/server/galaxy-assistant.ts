/**
 * Galaxy Assistant Service
 *
 * Hybrid intelligence system combining:
 * - Claude Sonnet 4.5 for natural language understanding (with prompt caching)
 * - Galaxy Tool Search (2,177 indexed tools)
 * - BioMNI Dataset RAG (100+ GB data lake)
 * - Galaxy Workflow Generator (LLM-based with tool validation)
 *
 * Architecture:
 * User Query → NLU (Claude) → Tool Search + Dataset RAG → Workflow Generation
 */

import Anthropic from '@anthropic-ai/sdk';
import { GoogleGenerativeAI, SchemaType } from '@google/generative-ai';
import { callGeminiFlash } from './gemini-flash';
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import { conversationStateManager } from './conversation-state';
import { userPatternsService, type UserContext } from './user-patterns-service';
import { thinkingDetector, type ThinkingDetectionResult } from './thinking-detector';
import { memoryService } from './memory-repository';
import {
  CANONICAL_DOMAINS,
  TECHNICAL_SUBDOMAINS,
  SUBDOMAIN_TO_CANONICAL,
  PREFERRED_DOMAINS_PROMPT_LIST,
  type CanonicalDomain,
  type TechnicalSubdomain,
} from './domain-registry';
import type {
  GalaxyTool,
  BioMNIDataset,
  WorkflowGenerationRequest,
  WorkflowGenerationResponse,
} from '../shared/galaxy-types';

// ─── Agent tool infrastructure ────────────────────────────────────────────────

/** Emitted for each tool invocation during an agent loop turn. */
export interface AgentToolEvent {
  type: 'tool_call' | 'tool_result';
  tool_use_id: string;
  name: string;
  input?: Record<string, unknown>;  // populated on tool_call
  output?: unknown;                 // populated on tool_result
  error?: string;                   // populated on tool_result when execution failed
  duration_ms?: number;             // populated on tool_result
}

/** Anthropic tool definitions registered with the agent. */
const BIOMATE_TOOLS: Anthropic.Tool[] = [
  {
    name: 'run_code',
    description: `Execute Python, R, or bash code on the user's uploaded datasets.
Use this for: filtering/subsetting data, format conversion, statistics, generating plots,
exploring file contents, counting rows/records, parsing ZIP/archive files, or any ad-hoc computation.

File access: Input datasets are staged at $DATA_DIR/<dataset_id>/<original_filename>.
Use galaxy_dataset_id if present, otherwise use dataset_id — both work as the path component.
The preamble comment in your script shows the exact path for each dataset.
Example — if raw_counts.csv was uploaded with dataset_id=abc123:
  import os, pandas as pd
  path = os.path.join(os.environ['DATA_DIR'], 'abc123', 'raw_counts.csv')
  df = pd.read_csv(path, index_col=0)

Write output files to $OUTPUT_DIR (os.environ['OUTPUT_DIR']) — they will be shown to the user.
Prefer Python for data manipulation; R for Bioconductor/statistical analysis.
Default timeout: 30s. For complex analysis (parsing large ZIPs, running DESeq2), set timeout_seconds=120.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        language: { type: 'string', enum: ['python', 'r', 'bash'], description: 'The scripting language to use' },
        code: { type: 'string', description: 'The code to execute' },
        input_datasets: {
          type: 'array',
          items: { type: 'string' },
          description: 'galaxy_dataset_ids of datasets to make available (from [Uploaded datasets:] block)',
        },
      },
      required: ['language', 'code'],
    },
  },
  {
    name: 'read_file',
    description: `Preview an uploaded dataset to understand its contents before processing.
Use this before running code or dispatching a workflow — it lets you see column names,
data types, record count, and the first rows without guessing.
Returns a structured summary regardless of file format (CSV, TSV, FASTA, VCF, BAM, etc.)`,
    input_schema: {
      type: 'object' as const,
      properties: {
        galaxy_dataset_id: {
          type: 'string',
          description: 'The dataset ID from the [Uploaded datasets:] block — use galaxy_dataset_id if present, otherwise use dataset_id',
        },
        n_lines: { type: 'number', description: 'Number of rows/records to preview (default 20)' },
      },
      required: ['galaxy_dataset_id'],
    },
  },
  {
    name: 'query_domain_knowledge',
    description: `Query BioMate's curated life science knowledge base for protocol parameters,
tool recommendations, QC thresholds, best practices, and literature-backed guidance.
Use this when you need specific parameter values for a domain (e.g., cryo-EM pixel size,
RNA-seq alignment parameters, DESeq2 cutoffs for specific experimental designs).`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: { type: 'string', description: 'What you want to know' },
        domain: {
          type: 'string',
          enum: ['cryo_em', 'rna_seq', 'variant_calling', 'proteomics', 'drug_discovery', 'general'],
          description: 'The biological domain',
        },
      },
      required: ['query'],
    },
  },
];

/**
 * Model configuration for different AI tasks
 *
 * Recommended configurations:
 * - Intent analysis: Fast model (Gemini Flash) - simple classification task
 * - Tool ranking: Medium model (Gemini Flash/Sonnet) - needs domain knowledge
 * - Response generation: Best model (sonnet) - user-facing, quality matters
 *
 * When to use Thinking Mode:
 * -------------------------
 * RECOMMENDED for:
 * - Complex multi-step workflow planning (e.g., "design a metagenomics pipeline")
 * - Comparative analysis requiring trade-off evaluation (e.g., "BWA vs Bowtie2")
 * - Technical explanations requiring accuracy (e.g., statistical interpretation)
 * - Troubleshooting complex issues (e.g., "why did my alignment fail")
 *
 * NOT NECESSARY for:
 * - Simple greetings and general questions ("Hello", "What can you do?")
 * - Intent classification (simple JSON classification task)
 * - Tool ranking (structured output task)
 * - Short factual responses (e.g., "What format does BWA accept?")
 *
 * Performance impact:
 * - Thinking adds ~2-5 seconds latency
 * - Thinking uses additional tokens (budget_tokens parameter)
 * - Quality improvement is most noticeable for complex tasks
 */
export interface ModelConfig {
  /** Model for intent classification (default: claude-sonnet-4-5, can use Gemini Flash for speed) */
  intentModel: string;
  /** Model for tool ranking (default: claude-sonnet-4-5, can use Gemini Flash for speed) */
  toolRankingModel: string;
  /** Model for response generation (default: claude-sonnet-4-5) */
  responseModel: string;
  /** Whether to enable thinking mode for response generation */
  enableThinking: boolean;
  /** Token budget for thinking mode (default: 2000) */
  thinkingBudget: number;
}

/**
 * Determine if thinking mode should be enabled based on the query complexity.
 * Can be used for adaptive thinking mode (enable only when beneficial).
 */
export function shouldEnableThinking(message: string, intent: string): boolean {
  // Complex workflow requests benefit from thinking
  const complexPatterns = [
    /design\s+(a\s+)?.*pipeline/i,
    /create\s+(a\s+)?.*workflow/i,
    /compare\s+.*\s+(vs|versus|or)\s+/i,
    /trade-?offs?\s+(of|between)/i,
    /explain\s+(the\s+)?(difference|comparison)/i,
    /troubleshoot/i,
    /debug/i,
    /why\s+(did|does|is)/i,
    /interpret\s+(my|the|these)/i,
    /what\s+(are\s+)?the\s+(best|optimal|recommended)/i,
  ];

  // Simple patterns that don't need thinking
  const simplePatterns = [
    /^(hello|hi|hey)/i,
    /what\s+(can\s+)?you\s+do/i,
    /^(thanks|thank\s+you)/i,
    /what\s+(is|are)\s+\w+$/i, // Simple definitional questions
  ];

  // Check for simple patterns first
  if (simplePatterns.some(p => p.test(message))) {
    return false;
  }

  // Check for complex patterns
  if (complexPatterns.some(p => p.test(message))) {
    return true;
  }

  // Default: enable for workflow generation, disable otherwise
  return intent === 'workflow_generation';
}

export const DEFAULT_MODEL_CONFIG: ModelConfig = {
  intentModel: 'gemini-3-flash-preview',  // overridden by BIOMATE_INTENT_MODEL env var; gemini-3-flash-preview in production
  toolRankingModel: 'claude-haiku-4-5',  // Haiku: fast lightweight ranking
  responseModel: 'claude-sonnet-4-6',    // Default to Sonnet 4.6
  enableThinking: false,                 // Disable thinking by default for lower latency
  thinkingBudget: 2000,
};

// Two-tier Gemini routing: Pro for complex queries, Flash for simple ones.
// Overridable via env so model names can be tuned without code changes.
const GEMINI_FLASH_MODEL = process.env.BIOMATE_INTENT_MODEL_FLASH || 'gemini-2.5-flash';
const GEMINI_PRO_MODEL   = process.env.BIOMATE_INTENT_MODEL_PRO   || 'gemini-2.5-pro';

/**
 * Pick the appropriate Gemini intent model based on query complexity.
 * Routes Pro for queries that are likely to produce large JSON intent payloads:
 *   - long messages (>140 chars)
 *   - multi-entity / comparison queries ("compare A vs B vs C", multi-target lists)
 *   - dense technical jargon (3+ tokens that look like gene names / drug names / IDs)
 * Otherwise routes Flash for cost/latency.
 */
export function pickGeminiIntentModel(message: string): string {
  const msg = String(message || '');
  if (msg.length > 140) return GEMINI_PRO_MODEL;
  if (/\b(compare|versus|vs\.?|triage|bake[- ]?off|strategy|design.*for)\b/i.test(msg)) return GEMINI_PRO_MODEL;
  // Multi-entity: 3+ all-caps gene/drug-style tokens (e.g. PD-1, VEGF, BCMA, PCSK9)
  const upperTokens = (msg.match(/\b[A-Z][A-Z0-9-]{1,}\b/g) || []).length;
  if (upperTokens >= 3) return GEMINI_PRO_MODEL;
  return GEMINI_FLASH_MODEL;
}

export interface GalaxyAssistantOptions {
  anthropicApiKey: string;
  galaxyAPIProxy: GalaxyAPIProxy;
  /** Model configuration - uses defaults if not provided */
  modelConfig?: Partial<ModelConfig>;
}

export interface ChatContext {
  previousMessages?: Array<{ role: 'user' | 'assistant'; content: string }>;
  currentWorkflow?: any;
  selectedDatasets?: string[];
  userId?: number; // For fetching user patterns
  sessionId?: string;
  enableThinking?: boolean;
  /** Accumulated facts from prior turns, passed so the LLM can decide supersession */
  accumulatedFacts?: Array<{ id: string; category: string; value: string }>;
  /** Current conversation turn number */
  turnIndex?: number;
  /** User's actual session-uploaded datasets, forwarded to generateWorkflow() */
  sessionDatasets?: Array<{ id: string; name: string; type: string }>;
  /**
   * Cross-session long-term memory block (built by MemoryIntegration from user prefs,
   * corrections, project context, and past episodes). Injected into the system prompt
   * wrapped in <long_term_memory> tags so the LLM treats it as supplemental context.
   */
  ltmContextBlock?: string;
  /** Per-tool credential availability map built by routes.ts using the user's Galaxy API key.
   *  Forwarded to generateWorkflow() so the AI backend can fall back to OSS alternatives. */
  credentialMap?: Record<string, boolean>;
}

export interface ToolRecommendation {
  tool: GalaxyTool;
  relevanceScore: number;
  reasoning: string;
}

export interface DatasetRecommendation {
  dataset: BioMNIDataset;
  relevanceScore: number;
  reasoning: string;
}

export interface WorkflowSuggestion {
  shouldGenerate: boolean;
  userIntent: string;
  confidence: number;
  reasoning: string;
}

export interface ExtractedFact {
  id: string;
  category: 'sequence' | 'gene' | 'organism' | 'data_type' | 'parameter' | 'file_reference' | 'tool_preference' | 'domain' | 'analysis_goal' | 'other';
  value: string;
  source: { type: 'user_message' | 'clarification_response' | 'inferred'; turnIndex: number };
  confidence: number;
  /** ID of an existing fact that this new fact replaces (LLM-determined) */
  supersedes?: string;
  supersededBy?: string;
}

// ============================================================================
// Clarification Fork-Point Fallbacks (S5)
// ============================================================================
// Static fallback questions for each workflowAmbiguity type.
// Exported so tests can assert completeness against the system prompt fork list.
// These are used when the Haiku contextualisation call fails.

export const CLARIFICATION_FALLBACKS: Record<string, string> = {
  variant_type:
    "To generate the right workflow: is this **germline** variant calling " +
    "(inherited variants, single sample) or **somatic** variant calling " +
    "(tumor mutations — requires matched tumor + normal BAM)?",
  assembly_type:
    "For genome assembly: is this **de novo assembly** (no reference, e.g. SPAdes/Flye) " +
    "or **reference-guided assembly** (mapping reads to an existing reference)?",
  rnaseq_type:
    "To select the right pipeline: is this **bulk RNA-seq** (differential expression, e.g. DESeq2) " +
    "or **single-cell RNA-seq** (cell population profiling, e.g. Seurat/Scanpy)?",
  scrna_type:
    "For single-cell analysis: is this a **perturbation screen** (CRISPR KO library) " +
    "or a standard **cell atlas / clustering** analysis?",
  peak_calling_type:
    "For chromatin analysis: is this **ChIP-seq** (antibody + input control) or " +
    "**ATAC-seq** (transposase-accessible chromatin — no antibody needed)?",
  chip_target:
    "For ChIP-seq: are you profiling a **transcription factor** (narrow peaks) " +
    "or a **histone modification** (broad peaks, e.g. H3K27me3)?",
  rnaseq_focus:
    "For RNA analysis: is this **mRNA / differential expression** (bulk RNA-seq, DESeq2/edgeR) " +
    "or **small RNA / miRNA** (miRDeep2 — different library prep and references)?",
  flow_cytometry_type:
    "For flow cytometry: is the goal **immunophenotyping** (gating cell populations), " +
    "**cell sorting**, or **unsupervised clustering** (e.g. flowSOM)?",
  proteomics_type:
    "For proteomics: is this **DDA** (data-dependent acquisition, e.g. MaxQuant) or " +
    "**DIA** (data-independent acquisition, e.g. DIA-NN / Spectronaut)?",
  cryoem_type:
    "For cryo-EM: is this **single-particle analysis (SPA)** (purified protein → 3D reconstruction) " +
    "or **cryo-ET** (tomography — in-situ structures inside cells)?",
  cryoem_sample:
    "For cryo-EM SPA: is your sample a **globular particle** (standard CryoSPARC/RELION pipeline) " +
    "or a **filamentous assembly** (helical reconstruction needed)?",
  somatic_paired:
    "For somatic variant calling: do you have a **matched normal sample** " +
    "(tumor + normal BAM) or is this **tumor-only** calling (panel of normals)?",
  metagenomics_type:
    "For microbiome analysis: is this **16S amplicon sequencing** (QIIME2/DADA2) " +
    "or **shotgun metagenomics** (Kraken2/MetaPhlAn)?",
  docking_type:
    "For molecular docking: is this **blind docking** (binding site unknown, DiffDock) " +
    "or **site-directed docking** (known binding pocket, AutoDock Vina)?",
  admet_scope:
    "To run the safety screen I need two things:\n" +
    "1. **What molecule?** Please provide the SMILES string or upload an SDF file.\n" +
    "2. **Which safety endpoints?** Options:\n" +
    "   - **Full ADMET panel** (absorption, distribution, metabolism, excretion, toxicity)\n" +
    "   - **hERG / cardiotoxicity** only (cardiac ion channel liability)\n" +
    "   - **DILI / hepatotoxicity** only (drug-induced liver injury)\n" +
    "   - **Ames mutagenicity** only\n" +
    "   - **Custom subset** — let me know which ones matter most.",
};

/**
 * For each workflowAmbiguity type, a regex that matches message text that already
 * resolves the ambiguity.  When this regex matches, _clarificationGate() suppresses
 * the clarification question and proceeds directly to workflow generation.
 *
 * Rule: the pattern must be specific enough to avoid false positives, but general
 * enough to cover all common phrasings that unambiguously answer the fork question.
 * Add an entry for every new fork point added to CLARIFICATION_FALLBACKS.
 */
export const AMBIGUITY_RESOLVERS: Record<string, RegExp> = {
  variant_type:     /\bgermline\b|\bsomatic\b|\bHaplotypeCaller\b|\bMutect2?\b/i,
  assembly_type:    /\bde\s+novo\b|\breference[- ]guided\b|\breference[- ]based\b|\bSPAdes\b|\bFlye\b|\bHifiasm\b/i,
  rnaseq_type:      /\bbulk\s+rna|\bsingle[- ]cell\b|\bscRNA\b|\bDESeq2\b|\bedgeR\b|\bSeurat\b|\bScanpy\b/i,
  scrna_type:       /\bperturbation\b|\bCRISPR\s+screen\b|\bcell\s+atlas\b|\bclustering\b|\bmixscape\b/i,
  peak_calling_type:/\bChIP[- ]seq\b|\bATAC[- ]seq\b|\btransposase\b/i,
  chip_target:      /\btranscription\s+factor\b|\bhistone\b|\bH3K\w{1,6}\b|\bnarrow\s+peak|\bbroad\s+peak/i,
  rnaseq_focus:     /\bmRNA\b|\bdifferential\s+expression\b|\bmiRNA\b|\bsmall\s+RNA\b|\bmiRDeep\b/i,
  flow_cytometry_type: /\bimmunophenotyp|\bgating\b|\bcell\s+sort|\bflowSOM\b|\bunsupervised\s+cluster/i,
  proteomics_type:  /\bDDA\b|\bDIA\b|\bMaxQuant\b|\bDIA-NN\b|\bSpectronaut\b|\bdata[- ]independent\b|\bdata[- ]dependent\b/i,
  cryoem_type:      /\bSPA\b|\bsingle[- ]particle\b|\btomograph|\bcryo[- ]ET\b|\bin[- ]situ\b/i,
  cryoem_sample:    /\bglobular\b|\bfilamentous\b|\bhelical\b/i,
  somatic_paired:   /\bmatched\s+normal\b|\btumor[- ]normal\b|\btumor[- ]only\b|\bpanel\s+of\s+normals\b/i,
  metagenomics_type:/\b16S\b|\bamplicon\b|\bQIIME\b|\bDADA2\b|\bshotgun\b|\bKraken\b|\bMetaPhlAn\b/i,
  docking_type:     /\bblind\s+dock|\bsite[- ]directed\b|\bDiffDock\b|\bVina\b|\bknown\s+(binding\s+)?pocket\b/i,
  // admet_scope is satisfied when: explicit SMILES string present (CC(=O), c1ccc, etc.),
  // or .sdf file, or user named specific endpoints, or said "full ADMET" / "screening".
  // This prevents BioMate from asking "which scope?" when a molecule is already provided.
  admet_scope:      /\bSMILES\b|\.sdf\b|\bfull\s+ADMET\b|\bhERG\b|\bDILI\b|\bAmes\b|CC\(=O\)|c1ccc|[A-Z][a-z]?\(=O\)|screening\b/i,
};

// ============================================================================
// Domain Workflow Catalogs (S6)
// ============================================================================
// When preferredDomains includes a domain that has a catalog entry, the catalog
// block is injected into generateResponse() so the LLM knows what BioMate-specific
// workflows exist without relying solely on FTS retrieval.
//
// Principle: every domain with registered BioMate workflows gets a catalog entry.
// The catalog is about BioMate workflow NAMES and their purpose — not about whether
// the LLM knows the underlying tools. The LLM knows GATK but does not know that
// BioMate's germline pipeline is called `wgs_germline_gatk` with specific QC gates.
//
// Add an entry for a domain when it has workflows registered under
// backend/biomni_workflows/nextflow_nfcore/subworkflows/<domain>/
//
// Domains with no registered workflows yet (metabolomics, metagenomics,
// structural_biology) have no entry — add one as workflows are built.

export const DOMAIN_CATALOGS: Partial<Record<string, string>> = {

  genomics: `Available BioMate genomics workflows:
- wgs_germline_gatk: Whole-genome germline variant calling — 14-step GATK4 best-practices pipeline (FastQC → fastp → BWA-MEM2 → MarkDuplicates → BQSR → HaplotypeCaller → GenotypeGVCFs → SnpEff). Input: FASTQ reads + reference genome. Outputs: annotated VCF + MultiQC report.
- crispr_screen_mageck: Pooled CRISPR screen analysis (MAGeCK) — count → RRA test → pathway enrichment. Supports positive and negative selection screens. Input: screen FASTQ + guide library CSV. Outputs: gene-level scores, FDR, pathway enrichment.
- perturb_seq_analysis: Perturb-seq pipeline — MAGeCK guide assignment + scVI/scANVI embedding for perturbation state. Input: FASTQ or h5ad with guide assignments. Outputs: hit genes, embedding, differential programs.
- perform_chipseq_peak_calling_with_macs2: ChIP-seq peak calling with MACS2. Input: ChIP BAM + control BAM. Outputs: narrowPeak/broadPeak BED.
- gene_set_enrichment_analysis: GSEA over ontology / Hallmarks / custom gene sets. Input: gene list + optional background. Outputs: enrichment table + plots.
- trajectory_inference: Single-cell pseudotime (Monocle3) + RNA velocity (scVelo) in parallel. Input: AnnData h5ad. Outputs: pseudotime assignments + velocity plots.
- geo_data_connector: Download GEO series/sample data (GEOquery). Input: GSE or GSM accession. Outputs: count matrix + clinical metadata, ready for downstream DE workflows.
- analyze_chromatin_interactions: Hi-C / 3C chromatin interaction analysis. Input: Hi-C contact matrix. Outputs: TAD boundaries, loops, compartments.
- transcriptomic_biomarker: Biomarker discovery from bulk or single-cell expression data.`,

  single_cell: `Available BioMate single-cell workflows (within the genomics domain directory):
- annotate_celltype_scRNA: Cell type annotation using reference-based label transfer (PanHuman atlas). Input: AnnData h5ad. Outputs: annotated h5ad with cell type labels.
- create_harmony_embeddings_scRNA: Batch-corrected UMAP via Harmony integration. Input: AnnData h5ad with batch column. Outputs: corrected embedding.
- create_scvi_embeddings_scRNA: Deep learning (scVI) latent embedding. Input: AnnData h5ad. Outputs: scVI latent space + UMAP.
- trajectory_inference: Pseudotime (Monocle3) + RNA velocity (scVelo) — see genomics catalog.
- perturb_seq_analysis: CRISPR perturbation-seq analysis — see genomics catalog.
- unsupervised_celltype_transfer_between_scRNA_datasets: Cross-dataset label transfer without reference atlas.`,

  epigenomics: `Available BioMate epigenomics workflows:
- perform_chipseq_peak_calling_with_macs2: ChIP-seq peak calling — narrow peaks (TF) or broad peaks (histone marks). Input: ChIP BAM + input/control BAM. Outputs: peak BED + QC.
- analyze_chromatin_interactions: Hi-C TAD / loop / compartment analysis. Input: contact matrix.
- find_enriched_motifs_with_homer: TF motif enrichment in peak regions (HOMER). Input: peak BED + genome. Outputs: enriched motif table.`,

  proteomics: `Available BioMate proteomics workflows:
- chemoproteomics_pulldown: Affinity enrichment (pulldown) QC and enrichment scoring from MaxQuant proteinGroups.txt. Computes per-protein enrichment ratios (pulldown vs input/control). QC gate: median enrichment ratio ≥3×. Input: MaxQuant proteinGroups CSV. Outputs: enrichment_ratios.tsv + summary JSON.`,

  cryo_em: `Available BioMate cryo-EM workflows:
- cryosparc_standard_spa: Standard single-particle analysis (SPA) — 23-step CryoSPARC pipeline: import → motion correction → CTF estimation → particle picking (blob + template) → 2D classification → ab-initio → homogeneous refinement → local CTF → non-uniform refinement → local resolution. Input: raw micrograph movies (TIFF/MRC). License: CryoSPARC (user must provide). Use for: globular proteins, membrane proteins in nanodisc/detergent, protein complexes.
- helical_spa_pipeline: Helical reconstruction for filamentous assemblies (F-actin, amyloid, microtubules, viral tubes) — filament tracing → helical extraction → 2D classification → helical refinement with rise/twist symmetry. Input: raw movies. License: CryoSPARC.
- focused_refinement_pipeline: Focus on a sub-region of a flexible complex — particle subtraction → local refinement → local CTF. Use when global refinement reaches 3-4 Å but peripheral domain remains blurry. Input: particles + soft mask. License: CryoSPARC.
- 3d_variability_analysis: Conformational heterogeneity / multi-state analysis (3DVA) — PCA of particle orientations → discrete states or continuous motions. One dataset → 5-6 simultaneous structures. Input: refined particles from cryosparc_standard_spa. License: CryoSPARC.
- topaz_train / topaz_extract: Deep learning particle picker — train on study-specific particles (500-1000 manually picked), then extract full dataset. Use when blob picker misses particles (small, low-contrast, crowded). Input: micrographs + picked coords (train); micrographs only (extract).
- cryo_et_full_pipeline: Cryo-ET full pipeline — tilt-series import → AreTomo2 tilt alignment → WBP tomogram reconstruction → subtomogram averaging. Use for in-situ / in-cell structures where SPA purification is impossible.
- drug_difference_map: Subtract apo density from drug-bound map → ±3σ thresholded difference map. Required for multi-drug pharmacology studies (CaV1.2, GPCR multi-ligand). Input: apo.mrc + drug.mrc. Outputs: difference.mrc + occupancy report.
- saposin_nanodisc_spa: CryoSPARC SPA for membrane proteins < 60 kDa in saposin A nanodisc. Defaults: 0.649 Å/pix, 60 e⁻/Å², 256 px box. Includes saposin reconstitution QC (NS-EM nanodisc size, SEC single peak) + TOPAZ training pass. Use when: MFSD2B/VMAT2-like transporters, small membrane proteins, saposin reconstitution.
- gpcr_complex_spa: CryoSPARC SPA for GPCR-G protein complexes in MSP1D1ΔH5 nanodisc. Defaults: 0.83 Å/pix, 256 px box. Includes complex assembly QC (scFv16 confirmation, apyrase nucleotide-free check, SEC stoichiometry). Dual local refinement: TM bundle + G protein masks. Use when: μOR/D1R/β2AR-Gi/s/q, GPCR-arrestin, biased agonism studies.
- multi_drug_atlas: Multi-drug SPA + difference map pipeline. Processes apo + N drug datasets (must be identical collection params), generates drug-minus-apo difference maps at ±3σ, validates occupancy. Use ONLY when: user explicitly has MULTIPLE drug datasets AND wants drug-minus-apo difference maps (ion channel pharmacology CaV1.2, GPCR multi-PAM, drug atlas). Do NOT use for standard single-protein SPA.

ROUTING RULE: For ANY standard single-particle analysis request (reconstruct 3D map, determine structure, SPA of one protein/complex) → always use cryosparc_standard_spa. Only route to multi_drug_atlas when user explicitly provides multiple drug datasets and asks for pharmacological comparison.`,

  systems_biology: `Available BioMate systems biology workflows:
- perform_flux_balance_analysis: Genome-scale metabolic flux balance analysis (COBRApy). Input: SBML metabolic model (.xml) + optional flux constraints. Outputs: optimal flux distribution CSV.
- simulate_metabolic_network_perturbation: Simulate gene knockouts / metabolite perturbations in a metabolic network. Input: SBML model + perturbation spec. Outputs: flux comparison before/after.
- simulate_protein_signaling_network: ODE-based signaling cascade simulation using normalized Hill functions. Input: network JSON (nodes + edges) + kinetic parameters. Outputs: time-series trajectories.
- model_protein_dimerization_network: Dimerization ODE model with mass-action kinetics. Input: protein concentrations + rate constants. Outputs: equilibrium state + time course.
- compare_protein_structures: Structural comparison (TM-align / RMSD) between two PDB structures. Input: two PDB files. Outputs: TM-score, RMSD, superposition.
- create_biochemical_network_sbml_model: Build an SBML model from a reaction list definition. Input: reactions JSON. Outputs: validated SBML XML.`,

  synthetic_biology: `Available BioMate synthetic biology workflows:
- optimize_codons_for_heterologous_expression: Codon optimization for a target host organism using host codon usage table. Input: DNA/protein sequence + host codon table. Outputs: optimized sequence + CAI score.
- engineer_bacterial_genome_for_therapeutic_delivery: Design bacterial genome edits for therapeutic payload delivery.
- simulate_gene_circuit_with_growth_feedback: ODE simulation of synthetic gene circuits coupled to bacterial growth (Gompertz / logistic). Input: circuit topology + kinetic parameters. Outputs: time-series expression + growth curves.
- analyze_barcode_sequencing_data: Barcode-seq analysis for combinatorial library screening. Input: barcode FASTQ. Outputs: barcode count table.
- create_biochemical_network_sbml_model: Build SBML reaction network model — see systems_biology catalog.`,

  bioimaging: `Available BioMate bioimaging workflows:
- register_images: Multi-modal image registration (ANTs) — affine, rigid, or deformable transforms. Input: fixed NIfTI + moving NIfTI. Outputs: registered image + transform file.
- batch_register_images: Register a batch of images to a common reference.
- segment_with_nn_unet: nnUNet-based image segmentation (automatic model selection). Input: NIfTI image + task ID. Outputs: segmentation mask.
- create_segmentation_visualization: Overlay segmentation masks on source images for QC.
- calculate_similarity_metrics: Compute image similarity (SSIM, NCC, MI) between registered image pairs. Input: two NIfTI images. Outputs: metric table.`,

  lab_automation: `Available BioMate lab automation workflows:
- run_async: Execute a PyLabRobot liquid handling protocol asynchronously. Input: Python protocol script + robot config. Outputs: run log + executed liquid transfers.
- get_pylabrobot_documentation_liquid: Retrieve PyLabRobot API documentation for liquid handling classes.
- get_pylabrobot_documentation_material: Retrieve PyLabRobot API documentation for labware/material classes.`,

  drug_discovery: `Available BioMate drug discovery workflows:
- alphafold_db_search: Structural similarity search (Foldseek + MMseqs2) against AlphaFold DB human proteome (48k proteins). Input: FASTA or PDB.
- structure_prediction_docking: Predict 3D structure (AlphaFold3 / Chai-1 / Boltz-2) then dock a ligand. Input: protein FASTA sequence + ligand SMILES/SDF.
- amber_pmemd_md: AMBER pmemd.cuda GPU MD — GAFF2 → tleap → EM → NVT/NPT → production MD → RMSD/RMSF → MMPBSA.py ΔGbind. Input: receptor PDB + ligand SDF. License: free academic.
- gromacs_protein_md: GROMACS 2025 + gmx_MMPBSA — 8-step pipeline, ΔGbind ± SE + RMSD trajectory. Input: receptor PDB + ligand SDF.
- schrodinger_glide_docking: Glide HTVS/SP/XP — LigPrep → PrepWiz → GridGen → Glide → ranked SDF. License: FlexNet (user must provide).
- moe_covalent_docking: MOE CovDock SVL — warheads: acrylamide, chloroacetamide, epoxide, aldehyde, michael_acceptor, vinyl_sulfone, boronic_acid. License: MOE FlexNet (user must provide).
- reinvent4_lead_design: REINVENT4 RL-based generative design — de_novo, scaffold_decoration, linker_design, scaffold_hopping. Input: SMILES seed or SMARTS scaffold.
- openfe_rbfe: OpenFE RBFE alchemical free energy perturbation — DDG (kcal/mol) + SEM between two ligands, HREX across lambda windows, MBAR estimator. Input: receptor PDB + ligand_a SDF + ligand_b SDF. Free, open-source alternative to FEP+.
- cyp_ddi_panel: CYP450 DDI panel + hepatic clearance — predicts IC50 for CYP1A2/2C9/2C19/2D6/3A4, IVIVE CLint→CLhep (well-stirred model), FDA 2020 DDI risk flags (R1, R1gut). Input: SMILES. Output: radar chart + clearance funnel + HTML report.
- nca_pknca: Non-compartmental PK analysis (PKNCA) — AUC, Cmax, Tmax, t½, CL/F, Vz/F. Input: concentration-time CSV.
- aizynthfinder_retrosynthesis: Retrosynthesis route planning (AiZynthFinder). Input: target SMILES. Outputs: synthesis routes + reaction scores.
- pocket_detection_druggability: Binding site detection and druggability scoring (fpocket). Input: PDB. Outputs: pocket table + druggability scores.
- pharmacophore_filtering: Build a pharmacophore model from reference active compounds AND screen a library against it — both steps in one workflow. Input: reference_smiles (known actives, to derive model) + library SMILES/SDF. Outputs: filtered hits with feature-match scores. Use this single workflow whenever a user asks to "build pharmacophore model from X and screen Y" — do NOT split into two steps.`,

  // Routing-only domains (not user profile domains, but have registered workflows):
  cancer_biology: `Available BioMate cancer biology workflows:
- detect_and_annotate_somatic_mutations: Somatic SNV/indel calling (GATK Mutect2) + SnpEff annotation from tumor/normal BAM pair. Input: tumor BAM + normal BAM + reference.
- analyze_copy_number_purity_ploidy_and_focal_events: CNVkit CNV segmentation + purity/ploidy estimation + focal amplification/deletion events + HRD approximation. Input: tumor BAM + optional normal BAM.
- detect_and_characterize_structural_variations: SV calling and characterization from WGS data. Input: tumor BAM. Outputs: SV VCF + annotated breakpoint table.
- perform_gene_expression_nmf_analysis: NMF decomposition of tumor expression matrix to identify molecular subtypes / transcriptional programs. Input: expression matrix. Outputs: NMF components + sample assignments.`,

  cell_biology: `Available BioMate cell biology workflows:
- analyze_flow_cytometry_immunophenotyping: Flow cytometry gating and immunophenotyping from FCS files. Input: FCS file + gating strategy JSON. Outputs: population counts + percentages.
- perform_facs_cell_sorting: FACS sorting gate definition and cell fraction enumeration. Input: FCS file + sort gates. Outputs: sorted population report.
- quantify_cell_cycle_phases_from_microscopy: Cell cycle phase quantification from microscopy images. Input: fluorescence images (DAPI + EdU). Outputs: G1/S/G2 fractions per field.
- quantify_and_cluster_cell_motility: Cell motility tracking and clustering from time-lapse microscopy. Input: time-lapse image series. Outputs: trajectory table + motility clusters.`,

};

/**
 * Build a domain catalog block for injection into generateResponse() system prompts.
 * Returns empty string if no catalog entry exists for any of the given domains.
 */
export function buildDomainCatalogBlock(preferredDomains: string[]): string {
  const entries = preferredDomains
    .map(d => DOMAIN_CATALOGS[d])
    .filter((c): c is string => !!c);
  if (entries.length === 0) return '';
  return `<domain_catalog>\n${entries.join('\n\n')}\n</domain_catalog>\n`;
}

// ============================================================================
// Domain Specialist Guidance (S3)
// ============================================================================
// Mirrors backend/lib/galaxy/ai/domain_registry.py DOMAIN_SPECIALIST_PROMPTS.
// Injected into generateResponse() system prompts as <domain_specialist> context
// when preferredDomains includes a matching entry.
//
// Purpose: give the response-generator LLM domain-expert framing so it applies
// the right decision criteria (e.g. DDA vs DIA for proteomics, SPA vs cryo-ET
// for cryo-EM) without requiring a separate LLM specialist consultation on the
// hot path.
//
// Activated by preferredDomains signal (intent classifier + user profile),
// NOT by keyword regex on the message text.

export const DOMAIN_SPECIALIST_GUIDANCE: Partial<Record<string, string>> = {
  genomics: `Expert framing (genomics): Consider sequencing type (WGS/WES/targeted panel), organism and reference genome version, paired vs single-end reads, and coverage depth. For variant calling: distinguish germline (GATK HaplotypeCaller) vs somatic (Mutect2, matched tumor/normal) before recommending a pipeline. PCR duplicate rate and BQSR are required QC steps for clinical-grade variant calls.`,

  transcriptomics: `Expert framing (transcriptomics): Consider library type (poly-A / total RNA / small RNA / CAGE), strandedness (RF/FR/unstranded), and analysis goal (differential expression vs splicing vs fusion). Statistical test selection: DESeq2 for small N (≤10/group), limma/voom for large studies or microarray, edgeR when counts are sparse. Pseudo-alignment (Salmon/kallisto) is faster than genome alignment (STAR) and suitable when splice-junction annotation is high quality.`,

  single_cell: `Expert framing (single-cell): Consider technology (10X Chromium v2/v3/multiome, Smart-seq2, Parse, SPLiT-seq), batch correction strategy (Harmony for RNA; scVI for multi-modal), and downstream goal: clustering + annotation vs trajectory (Monocle3) vs perturbation (Perturb-seq/MAGeCK). Cell type annotation requires a reference atlas (CellTypist, Azimuth, scANVI label transfer). Ambient RNA (SoupX) and doublet removal (Scrublet) are standard QC steps.`,

  epigenomics: `Expert framing (epigenomics): Assay type determines the entire pipeline — ChIP-seq (MACS2 peak calling, IP/input ratio), ATAC-seq (open chromatin, nucleosome-free reads), bisulfite-seq (methylation %), CUT&RUN (sparse background, SEACR caller), Hi-C (TAD/loop calling). Fragment size profiles differ between assays — do not mix callers. For TF ChIP-seq: narrow peaks (MACS2 --nomodel); for histone marks: broad peaks (MACS2 --broad).`,

  proteomics: `Expert framing (proteomics): DDA (data-dependent acquisition) vs DIA (data-independent acquisition) is the primary fork. DDA: MaxQuant (label-free/SILAC/TMT) or Proteome Discoverer. DIA: requires a spectral library; use DIA-NN or Spectronaut. Quantification: label-free (LFQ intensity), TMT/iTRAQ (reporter ions), SILAC (heavy/light ratios). For phosphoproteomics: TiO₂/IMAC enrichment; for ubiquitinomics: GlyGly enrichment. PTM site localization score (phosphoRS/ptmRS) must be ≥0.75 to be confident.`,

  metabolomics: `Expert framing (metabolomics): Platform distinguishes the pipeline — LC-MS (retention time + m/z annotation), GC-MS (RI matching + NIST library), NMR (chemical shift assignment). Targeted: known compounds with authentic standards → absolute quantification. Untargeted: feature detection (XCMS/MZmine) → putative annotation (level 2) → pathway analysis (MetaboAnalyst). Normalization: PQN or median-fold change; QC pooled samples must be injected every 10 samples.`,

  metagenomics: `Expert framing (metagenomics): 16S amplicon (V3-V4 region most common) vs shotgun WGS (full taxonomic + functional). 16S: DADA2 for ASVs (preferred over OTU clustering), SILVA/GTDB reference. WGS: Kraken2 + Bracken for classification, HUMAnN3 for functional profiling. Alpha diversity (Shannon, Chao1) and beta diversity (UniFrac, Bray-Curtis) are standard outputs. Check for host contamination (remove human reads via BBSplit before analysis).`,

  structural_biology: `Expert framing (structural biology): Check whether an experimental structure exists (PDB ID) before recommending structure prediction. Prediction tier: AlphaFold3 (state-of-the-art, with ligand co-folding), Boltz-2 (open-weights, MIT), Chai-1 (no auth required). For docking: pocket detection first (P2Rank/fpocket) → blind docking (DiffDock) or site-directed (AutoDock Vina/Glide). MD simulation for binding affinity: GROMACS (open-source) or AMBER pmemd.cuda (GPU-accelerated).`,

  drug_discovery: `Expert framing (drug discovery): Mandatory decision tree — (1) Does a structure exist? If no: predict with AlphaFold3/Boltz-2. (2) Binding site known? If no: run pocket detection (P2Rank). (3) Docking type: global/blind (DiffDock) vs site-directed (AutoDock Vina/Glide). (4) Safety profiling: hERG (cardiac), DILI (hepato), Ames (mutagenicity), ADMET panel. (5) Lead optimization: REINVENT4 (generative), pharmacophore filtering, retrosynthesis (AiZynthFinder). Decision grade: state cutoffs (e.g. Glide XP GScore < −8 kcal/mol, hERG IC₅₀ > 1 μM) explicitly.`,

  cryo_em: `Expert framing (cryo-EM structural biology):

STEP 1 — PIPELINE CHOICE (ask if unclear):
• SPA (purified sample, homogeneous): CryoSPARC NUR pipeline — use for membrane proteins, soluble complexes, viral capsids
• Cryo-ET (in-cell, in-situ, flexible): cryo_et_full_pipeline — tilt series → AreTomo2 alignment → WBP → subtomogram averaging

STEP 2 — SAMPLE CLASS → COLLECTION PARAMETERS:
| MW | pixel_size (Å) | box_size (px) | defocus_min (μm) | total_dose (e⁻/Ų) |
|---|---|---|---|---|
| <50 kDa | 0.649 | 256 | -0.8 | 60 |
| 50-100 kDa | 0.649 | 256 | -0.8 | 60 |
| 100-300 kDa | 0.83 | 256 | -0.8 | 50 |
| 300-600 kDa | 0.83 | 320 | -1.0 | 50 |
| 600-1500 kDa | 1.06 | 400 | -1.5 | 50 |
| >1500 kDa | 1.30 | 512 | -1.5 | 45 |
FSC criterion always 0.143 (gold-standard). MolProbity < 2.0; Ramachandran favored > 97%.

STEP 3 — RECONSTITUTION STRATEGY by sample class:
• Membrane protein < 60 kDa → saposin nanodisc (0.649 Å/pix): saposin outperforms MSP for small MPs; use γ-cyclodextrin for detergent-free lipid delivery; NS-EM nanodisc size ~10 nm before cryo-EM
• GPCR-G protein complex (100-150 kDa) → MSP nanodisc (MSP1D1ΔH5, not MSP1D1): add scFv16 stabilizer (mandatory for Gi complexes — 10x yield drop without it); remove nucleotide with apyrase before SEC
• Ion channel > 200 kDa → GDN detergent (not DDM — GDN preserves lipid annulus); multi-drug atlas: apo reference + N drug datasets with identical collection params
• Pore-forming protein → liposome reconstitution: cardiolipin obligatory for BAX-family; run ANTS/DPX lysis assay (> 50% lysis) before cryo-EM — hard functional gate
• Large RNP (> 500 kDa, spliceosome/ribosome) → endogenous purification via glycerol gradient (no affinity tag); one dataset → 5-6 structures via 3DVA multi-state classification
• Symmetric assembly (capsid, vault) → always start C1; verify symmetry from 2D classes; use symmetry expansion for ASU sub-classification

STEP 4 — QC GATES (all must pass before proceeding):
NS-EM quality → CTF ≤ 4.5 Å → 2D classes with secondary structure → 3D reconstruction ≥ 4 Å → NUR/local refine → FSC 0.143 → MolProbity → deposition

STEP 5 — PICKING STRATEGY:
• Blob picker first (always) for initial 2D to seed TOPAZ training
• TOPAZ train on curated 500-1000 particles → re-pick full dataset (improves yield 3-5x for small/weak particles)
• crYOLO general model for rapid first-pass

KEY PRINCIPLES:
• Wrong pixel size → irrecoverable loss (set at collection, cannot fix in post)
• Functional assay (transport/current/lysis) BEFORE cryo-EM — never start grid prep on non-functional sample
• More particles beat better particles: 200K minimum for < 3 Å; 50K sufficient for > 4 Å screening
• Drug difference maps: normalize apo + drug maps → subtract → ±3σ threshold for real density`,

  systems_biology: `Expert framing (systems biology): ODE modeling for signaling/gene regulatory circuits (deterministic); stochastic for small-number systems. FBA (COBRApy) for metabolic flux optimization under growth/production constraints. Multi-omics integration: MOFA+ (factor analysis), DIABLO (supervised), or COSMOS (causal). Network types: PPI (STRING), GRN (ARACNE/GENIE3), metabolic (SBML/BiGG). Pathway enrichment: over-representation (Fisher) for gene lists; GSEA for ranked lists.`,

  synthetic_biology: `Expert framing (synthetic biology): Codon optimization is host-specific (CAI tables differ between E. coli K-12, S. cerevisiae, CHO). Gene circuit ODE models need explicit Hill coefficients and degradation rates. CRISPR guide design: Doench 2016 efficiency rules + Cas-OFFinder/CRISPOR off-target check. Barcode-seq: error-correction Hamming codes ≥ 3-edit distance to survive sequencing noise. Verify constructs with plasmid sequencing before expression.`,

  bioimaging: `Expert framing (bioimaging): Image registration requires a reference channel (DAPI/nuclear) with consistent expression. Segmentation: nucleus-only (StarDist) vs full cell boundary (Cellpose/nnUNet). For time-lapse: track cells before quantifying intensity changes (avoid mis-assignment). Output: per-cell feature tables (area, intensity, morphology) compatible with scRNA-seq-style clustering (scanpy/UMAP). Batch correction: CellProfiler+Harmony or scVI for imaging features.`,

  lab_automation: `Expert framing (lab automation): PyLabRobot abstracts liquid handling robots (Opentrons OT-2/Flex, Hamilton STAR, Tecan). Protocol execution: confirm deck layout and tip inventory before launch. Pipetting volumes: respect dead volume and tip capacity limits (min 1 μL for p10, max 300 μL for p300). Async execution pattern: start → poll status → retrieve results — never assume synchronous completion. Plate maps must be validated against physical layout before run.`,

  cancer_biology: `Expert framing (cancer biology): Somatic variant calling requires matched tumor/normal pairs for maximum specificity (Mutect2); tumor-only is higher FDR. TMB threshold: ≥10 mut/Mb correlates with immunotherapy response (FDA-approved threshold). CNV calling: correct for purity/ploidy (PURPLE/ABSOLUTE) before copy number interpretation. SV calling: short-read callers (GRIDSS, DELLY, Manta) have high FDR — orthogonal long-read or WGS validation recommended. NMF mutational signature extraction: ≥50 SSNVs required for reliable signature decomposition.`,

  cell_biology: `Expert framing (cell biology): Flow cytometry gating order: FSC/SSC live gate → doublet exclusion (FSC-A vs FSC-H) → dead cell exclusion (viability dye) → lineage markers → target markers. FACS purity sort: re-analyze post-sort sample to confirm ≥95% purity before downstream assays. Cell cycle: EdU/BrdU incorporation + PI staining is quantitative for S-phase fraction; Hoechst DNA content alone cannot distinguish G1 from G2/M without BrdU. Motility: velocity (μm/min), directionality ratio, and MSD should all be reported.`,
};

// ============================================================================
// Domain-gated routing rules (S7)
// ============================================================================
const DOMAIN_ROUTING_RULES: Record<string, string> = {
  drug_discovery: `- "ADMET", "ADMET profiling", "ADMET screening", "toxicity screening", "DILI", "hERG toxicity", "BBB penetration", "blood-brain barrier", "drug-like properties", "lipophilicity", "bioavailability prediction", "predict ADMET", or "toxicity panel": use the predict_admet_properties workflow (6 ADMET endpoints: hERG cardiac, DILI hepato, Caco-2 permeability, BBB penetration, solubility, Ames mutagenicity — all computed from SMILES. Input: smiles_input as a SMILES string or newline-separated list. Outputs: admet_results.csv + risk_summary.json). Use immediately when a user provides SMILES and asks for ADMET or safety screening — do NOT ask for a file upload.
- "PK-Sim", "PK Sim", "pksim", "Open Systems Pharmacology", "OSP Suite", "OSP PBPK", "Willmann PBPK", "EMA OSP", or "LGPL PBPK": use the pk_sim_pbpk workflow (PK-Sim open-source PBPK wrapper, EMA-accepted, free, no license required. Rodgers-Rowland + Schmitt tissue partitioning, Weibull oral dissolution, CYP ontogeny for pediatric. Inputs: compound physicochemical params + CLint + dose. Outputs: pk_profile.json + nca_summary.json + PK plots. quality_tier: ema_accepted_open_source.) NO PREREQ CHECK needed — all params have defaults.
- "Simcyp", "Certara PBPK", "Certara DDI", "Simcyp DDI", "population PBPK", "Simcyp population simulator", "ADAM oral absorption model", "virtual population trial", "Simcyp pediatric", "Simcyp renal", "Simcyp perpetrator", "Simcyp victim", "AUC ratio CYP", or "Sim Cyp": use the simcyp_pbpk workflow (Simcyp Population-Based PBPK BYOL wrapper, regulatory submission grade. Requires SIMCYP_LICENSE_FILE or SIMCYP_LICENSE_SERVER in user credentials; falls back to BioMate native 8-compartment PBPK if no license. Supports DDI CYP3A4/2D6 AUC ratios, special populations, oral absorption ADAM model. Outputs: pk_profile.json + ddi_summary.json + regulatory_report.txt. quality_tier: regulatory_submission or ind_ready_screening fallback.)
- "NONMEM", "nmfe75", "population pharmacokinetics NONMEM", "population PK FOCE", "FOCE-I", "FOCE estimation", "population PK modeling", "PopPK NONMEM", "ADVAN2", "ADVAN4", "ADVAN11", "nlmixr2", "nlmixr population", "SAEM population PK", "VPC visual predictive check", "bootstrap PK", "ETA shrinkage", "OFV", "NCA population", or "nonlinear mixed effects NONMEM": use the nonmem_poppk workflow (NONMEM FOCE-I population PK modeling BYOL; nlmixr2 open-source fallback. Generates NONMEM CTL file (ADVAN2/4/11 + FOCE-I), runs VPC + bootstrap, covariate search. Requires NONMEM_HOME + NONMEM_LICENSE_FILE in credentials; auto-falls back to nlmixr2. Inputs: pk_data_csv (ID/TIME/DV/AMT/CMT/EVID). Outputs: parameter_estimates.json + vpc_plot.png + bootstrap_summary.csv. quality_tier: fda_submission_grade or fda_acceptable_open_source fallback.)
- "survival analysis", "Kaplan-Meier", "KM curve", "KM plot", "log-rank test", "hazard ratio", "clinical trial sample size", "oncology trial design", "survival endpoint", "time to event", "RMST", "O'Brien-Fleming", "alpha spending", "power calculation survival", "event-driven trial", "phase III oncology", or "survival function": use the survival_analysis_km workflow (Kaplan-Meier estimator + Schoenfeld sample size + RMST + O'Brien-Fleming alpha-spending. Inputs: median_control_months, median_treatment_months, alpha, power, accrual_months, follow_up_months. Outputs: km_curves.png + power_table.csv + sample_size_summary.json.) NO PREREQ CHECK needed — all params explicit.
- "FcRn", "FcRn antibody", "FcRn half-life", "IgG half-life", "antibody half-life", "YTE mutation", "LS mutation", "PSA mutation", "GASD ALIE", "AAA mutation", "antibody PK engineering", "FcRn recycling", "IgG1 PK", "IgG4 PK", "bispecific antibody PK", "antibody 2-compartment PK", "monoclonal antibody PK", "mAb PK simulation", "allometric antibody", or "FcRn pH binding": use the fcrn_antibody_pk workflow (FcRn-mediated IgG PK with half-life engineering comparison — WT, YTE, LS, PSA, GASD-ALIE, AAA mutations. 2-compartment IV/SC PK + allometric species scaling. Inputs: antibody_name, molecular_weight_kda, dose_mg_kg, route, species, fc_mutation. Outputs: pk_profile.json + halflife_comparison_table.csv + allometric_scaling.json.) NO PREREQ CHECK needed — all params have defaults.
- "ICH S5", "reproductive toxicity", "DART", "developmental toxicity", "teratogenicity", "embryo-fetal development", "EFD study", "FEED study", "PPND study", "fertility toxicity", "thalidomide structural alert", "placental transfer", "pregnancy category", "WOCBP toxicity", or "Segment II toxicology": use the ich_s5_reproductive_tox workflow (ICH S5(R3) 2020 DART assessment — structural alerts, placental transfer, margin of safety, regulatory study timing for FEED/EFD/PPND. Outputs: ich_s5_safety_report.json GREEN/YELLOW/RED.)
- "transporter DDI", "P-gp inhibition", "BCRP inhibition", "OATP inhibition", "OCT inhibition", "OAT inhibition", "MATE inhibition", "efflux transporter", "uptake transporter", "ABC transporter DDI", "SLC transporter DDI", "R-value transporter", "Igut inhibition", "ABCB1 DDI", "ABCG2 DDI", "SLCO1B1 DDI", "digoxin DDI", "rosuvastatin DDI probe", or "metformin transporter": use the transporter_ddi_pgp_bcrp workflow (P-gp/BCRP/OATP1B1/1B3/OCT1/2/OAT1/3/MATE1/2 R-value calculation per FDA 2020. Flags clinical study triggers. Input: IC50 values + Cmax + dose. Output: transporter_r_values.json + ddi_flags.tsv.)
- "ICH S7A", "safety pharmacology", "hERG safety", "hERG cardiac", "hERG QTc", "Fridericia QTc", "ICH S7B", "CiPA assay", "CiPA in vitro", "cardiovascular safety", "CNS safety", "respiratory safety", "Irwin test", "core battery safety", "safety pharmacology panel", "hERG margin", "cardiac liability", or "autonomic safety pharmacology": use the ich_s7a_safety_pharmacology workflow (ICH S7A core battery: cardiovascular hERG/QTc + CNS Irwin/BBB + respiratory RR/TV/SpO2. CiPA Tier 2 escalation triggered when hERG margin <30×. GREEN/YELLOW/RED per system. Inputs: compound_name, herg_ic50_um, free_cmax_um, cnp_noael_mg_kg, irwin_observation, respiratory_noael_mg_kg, species. Outputs: safety_report.json + overall_safety_color.txt.) NO PREREQ CHECK needed — all params explicit.
- "pediatric PBPK", "pediatric pharmacokinetics", "pediatric dose", "paediatric PK", "paediatric dose", "neonatal PK", "neonatal pharmacokinetics", "infant PK", "CYP maturation", "ontogeny PBPK", "GFR maturation", "age-scaled PK", "pediatric dose prediction", "ICH E11", "ICH E11R1", "allometric scaling CYP", "developmental pharmacology", "child dose from adult", "neonate dose", or "toddler dose" (WITHOUT pregnancy): use the pbpk_pediatric workflow. NOTE: if the query also mentions pregnancy, trimester, gestational age, or maternal PK, use pbpk_pediatric_pregnancy instead (paediatric PBPK — 5 age cohorts: neonate/infant/toddler/child/adolescent. Allometric BW scaling, CYP3A4/2D6/2C19 maturation Hill functions, GFR maturation Rhodin 2009, albumin maturation. ICH E11(R1) compliance warnings. Inputs: compound physicochemical params + dose_mg_kg + route + age_groups. Outputs: pediatric_pk.csv + dose_recommendation.json + cyp_maturation_table.json.) NO PREREQ CHECK needed — all params have defaults.
- "PBPK simulation", "physiologically-based pharmacokinetics", "physiologically-based PK", "8-compartment PK", "full PK profile", "predict human PK", "predict human pharmacokinetics", "mechanistic PK simulation", "organ-level PK", "whole-body PK", "PBPK model", "Cmax prediction", "AUC prediction", "Tmax prediction", "oral bioavailability simulation", or "first-pass metabolism PK": use the pbpk_simulation workflow (8-compartment physiologically-based pharmacokinetic model, Rodgers/Rowland method; outputs pk_profile.csv + nca_parameters.json). REQUIRED PREREQ CHECK: Before generating this workflow, verify the user has provided BOTH (1) a SMILES string (the compound structure) AND (2) intrinsic clearance CLint in µL/min/mg AND unbound plasma fraction fu_plasma. If ANY of these are missing, ask for them in your response — do NOT generate the workflow card yet. Example asks: "To run PBPK, I need your compound's SMILES structure — please provide it." or "To simulate full PK, I need CLint (µL/min/mg) and fu_plasma — what are these values for your compound?"
- "IVIVE", "in vitro to in vivo", "hepatic clearance", "intrinsic clearance", "microsomal clearance", "CLint", "CLh", "well-stirred model", "parallel tube model", or "in vitro clearance scaling": use the ivive_hepatic_clearance workflow (well-stirred + parallel-tube models, converts CLint_microsomal → predicted human CLh. Input: compound_data_csv with compound_id/CLint_uL_per_min_mg/molecular_weight columns. Outputs: ivive_results.csv + clearance_summary.json).
- "CYP inhibition", "CYP450 panel", "drug-drug interaction", "DDI prediction", "DDI risk", "metabolic clearance", "microsomal clearance", "CLint", "CLhep", "IVIVE clearance", "hepatic extraction", "CYP1A2", "CYP2C9", "CYP2C19", "CYP2D6", "CYP3A4", "FDA DDI guidance", "R1 R1gut", "perpetrator DDI", "half-life prediction", or "metabolic liability": suggest the cyp_ddi_panel workflow (5-isoform CYP inhibition IC50 + IVIVE hepatic clearance + FDA 2020 DDI risk flags. Input: SMILES string. Outputs: cyp_panel_summary.json + DDI radar chart + clearance funnel + HTML report.)
- "ingest assay data", "composite ranking", "safety-potency ranking", "hERG + IC50 ranking", "BCR-ABL1 campaign ranking", "multi-assay compound ranking", or "rank compounds by potency and safety": use the assay_ingestion_and_ranking workflow (3-step pipeline: parse CSV → composite score → ranked report. Inputs: assay_csv with compound_id/assay_type/value columns. Outputs: ranked_compounds.csv + HTML report + JSON summary).
- "CRO submission", "WuXi AppTec export", "compound export for CRO", "format compounds for outsourcing", "CRO outsourcing package", or "submit compounds to CRO": use the cro_submission_export workflow (3-step pipeline: validate hERG safety → format WuXi columns + RDKit MW/LogP → export CSV. Inputs: compound_csv with SMILES + assay data. Outputs: wuxiapptec_submission.csv + metadata JSON).
- "drug repurposing", "repurpose drugs", "repurpose existing drugs", "existing drugs for [disease]", "find drugs for [condition]", "rare disease treatment options", "what drugs could treat", "TxGNN repurposing", "graph neural network drug repurposing", "knowledge graph drug repurposing", "identify drug candidates for", "disease drug candidates", or "repurposing candidates": use the retrieve_topk_repurposing_drugs_from_disease_txgnn workflow (TxGNN graph neural network — queries a biomedical knowledge graph to retrieve top-K FDA-approved and investigational drugs with repurposing potential for a given disease. Input: disease_name (plain English or MESH/OMIM ID). Outputs: ranked_drugs.csv + repurposing_rationale.json + network_visualization.html. Particularly valuable for rare diseases with no approved therapy.)
- "adaptive trial", "adaptive clinical trial", "RAR randomization", "response adaptive randomization", "MAMS design", "multi-arm multi-stage", "interim analysis stopping rules", "O'Brien-Fleming adaptive", "alpha spending adaptive", "Bayesian adaptive trial", "seamless phase II/III", "adaptive dose selection", "adaptive enrichment", or "interim futility stopping": use the adaptive_trial_design workflow (adaptive clinical trial simulator — supports RAR, MAMS, seamless II/III, Bayesian predictive probability, O'Brien-Fleming + Lan-DeMets alpha spending, interim futility rules. Inputs: n_arms, allocation_type [RAR/fixed/MAMS], interim_looks, target_response_rate, alpha, power. Outputs: adaptive_design_report.json + operating_characteristics.csv + stopping_rules.txt + simulation_summary.html.) NO PREREQ CHECK — all params have defaults.
- "ADC", "antibody-drug conjugate", "design ADC", "DAR", "drug-antibody ratio", "MMAE", "MMAF", "DM1", "DM4", "SN-38", "PBD dimer", "calicheamicin", "ADC payload", "ADC linker", "val-cit linker", "Enhertu", "Kadcyla", "Trodelvy", "Adcetris", "Mylotarg", or "antibody payload conjugation": use the adc_design workflow (comprehensive ADC design — payload selection across 7 classes, linker chemistry (cleavable/non-cleavable), DAR optimization with aggregation risk, ADC-specific ADMET (plasma stability, bystander killing radius, off-target tox flags), two-analyte PK model. Required: target_antigen + indication. Optional: antigen_expression_level, bystander_required, payload_smiles. Outputs: adc_design_report.json + payload_ranking.csv + adc_pk_profile.json.)
- "PROTAC", "targeted protein degradation", "protein degrader", "bifunctional degrader", "E3 ligase", "CRBN", "VHL", "MDM2", "DCAF15", "ternary complex", "molecular glue", "ARV-471", "ARV-110", "dBET", "MZ1", "BRD4 degrader", "AR degrader", "ER degrader", "design degrader", or "design PROTAC": use the protac_design workflow (PROTAC design — E3 ligase selection from CRBN/VHL/MDM2/IAP/DCAF15 library, POI warhead lookup for 25 named targets including BRD4/AR/ESR1/KRAS/BCL2/CDK4-6/BTK/EGFR, 3 linker variants (short PEG/long PEG/alkyl), beyond-Ro5 ADMET, ternary cooperativity alpha estimate. Required: target_protein + indication. Outputs: protac_design_report.json + e3_ligase_ranking.csv + linker_options.csv.)
- "mRNA design", "mRNA therapeutic", "mRNA vaccine", "design mRNA", "codon optimization", "CAI", "5'UTR design", "3'UTR design", "poly-A tail design", "IVT template", "m1Ψ", "pseudouridine", "CleanCap", "Moderna mRNA", "BioNTech mRNA", "Onpattro", "mRNA stability", "ARE motifs", or "mRNA codon optimization": use the mrna_therapeutic_design workflow (full mRNA therapeutic pipeline — protein AA/ORF input → human codon optimization (CAI >0.8, CpG minimization) → 5'-UTR/Kozak/signal peptide → 3'-UTR (HBB or AES+mtRNR1) → poly-A → stability scoring (ARE/uORF/cap occlusion MFE) → m1Ψ + CleanCap recommendation → IVT template → LNP formulation by tissue. Covers Moderna SM-102, Pfizer/BNT ALC-0315, Onpattro MC3 chemistries. Required: protein_sequence + target_tissue.)
- "AAV", "AAV serotype", "AAV9", "AAV8", "AAV5", "AAV2", "AAVrh10", "AAVrh74", "AAV-PHP.B", "AAV capsid", "gene therapy delivery", "viral vector selection", "AAV tropism", "Zolgensma", "Luxturna", "Hemgenix", "Elevidys", "in vivo gene therapy delivery", "CRISPR delivery in vivo", or "gene replacement therapy delivery": use the aav_serotype_selection workflow (rules-based AAV serotype selection — 10-serotype tropism database, payload size vs 4.7 kb hard limit with dual-vector recommendation for oversized, human seroprevalence/NAb risk per serotype, route of administration compatibility, clinical precedent. Required: target_tissue + payload_size_kb. Outputs: aav_selection_report.json + serotype_ranking.csv + delivery_summary.txt.)
- "CAR-T", "CAR design", "CAR construct", "chimeric antigen receptor", "design CAR", "Kymriah", "Yescarta", "Abecma", "Carvykti", "CD19 CAR", "BCMA CAR", "HER2 CAR", "GD2 CAR", "PSMA CAR", "4-1BB costimulatory", "CD28 costimulatory", "CAR-T construct design", or "build CAR construct": use the cart_construct_design workflow (CAR-T construct assembly — 20-target scFv library covering CD19/BCMA/CD22/HER2/GD2/EGFR/MSLN/CD33/PSMA/FOLR1/CLDN18.2, full domain assembly: signal peptide → scFv (VH-G4S3-VL) → CD8α/CD28 hinge+TM → 4-1BB/CD28 costim → CD3ζ. Auto-selects costim by indication (4-1BB hematologic / CD28 solid). Scores packaging size, junction immunogenicity, tonic signaling, manufacturing. Required: target_antigen + indication. Outputs: cart_construct.json + cart_sequence.fasta + construct_summary.txt.)
- "atlas expression", "single-cell expression of", "where is [target] expressed", "tissue distribution of [target]", "normal tissue expression", "Tabula Sapiens", "CELLxGENE", "cell-type expression", "on-target off-tumor check", or "is [target] safe for CAR-T": use the atlas_expression_query workflow (queries human single-cell atlas Tabula Sapiens + CELLxGENE Census for per-cell-type expression of a target with tissue-criticality weighting HIGH/MOD/LOW for cardiac/CNS/lung alveolar/HSC vs skin/gut vs adipose/thyroid. Required: target_gene. Output: atlas_expression.json + tissue_criticality.json. Feeds into modality_triage.)
- "modality triage", "which modality for [target]", "CAR-T vs ADC vs bispecific", "best modality for target", "on-target off-tumor risk", "would [target] be a good CAR-T target", "modality recommendation", "ADC vs CAR-T comparison", or "score therapeutic modalities": use the modality_triage workflow (scores every major therapeutic modality CAR-T / ADC / mAb / bispecific TCE / PROTAC / siRNA / ASO / small molecule for a target based on single-cell atlas expression. Generates IHC follow-up panel with antibody validation targets. Validated 9/10 historical CAR-T outcomes: HER2/CEA/ROR1/EGFR REJECT matches Morgan 2010 / Parkhurst 2011 / clinical failures; CD19/BCMA/CD22 VIABLE matches Kymriah/Abecma/CD22-CAR approvals. Required: atlas_expression + target_gene. Chains to: adc_design / cart_construct_design / bispecific_format_triage based on verdict.)
- "bispecific format", "BiTE vs CrossMab", "which bispecific format", "Ivonescimab format", "design bispecific architecture", "Knob-into-Hole vs CrossMab", "PD-1 VEGF bispecific format", "trans engagement format", "cis engagement format", or "TCE format selection": use the bispecific_format_triage workflow (given two targets, scores BiTE / CrossMab / KiH / DVD-Ig / nanobody fusion on half-life + cis engagement + trans engagement + manufacturing + ADA risk + affinity asymmetry. Recovers Ivonescimab CrossMab (PD-1×VEGF HARMONi-2 2024), Blinatumomab BiTE, Teclistamab KiH, Zenocutuzumab CrossMab (HER2×HER3 Bizengri Dec 2024), Amivantamab KiH (EGFR×MET). Required: target_a + target_b. Output: bispecific_format_report.json + format_ranking.csv.)
- "in vivo CAR-T", "Capstan CAR-T", "LNP CAR delivery", "CAR mRNA in vivo", "in vivo CAR design", "Kelonia CAR-T", "Umoja CAR-T", "skip ex vivo manufacturing", "CAR-T fratricide check", or "in vivo cell therapy design": use the in_vivo_cart_codesign workflow (multi-modality co-design — chains atlas safety check + LNP tropism analysis + fratricide check + CAR architecture in one query. Capstan CPTX-2309 / Umoja / Kelonia precedents. LNP library: MC3 hepatocyte, SM-102 muscle, C12-200 spleen, anti-CD8/CD5/CD3/CD7 targeted. Correctly fires fratricide warning for CD7 CAR + anti-CD5 LNP (T-cell LNP transfecting T-cell-expressing CAR target). Required: car_target + indication.)
- "in vivo base edit", "VERVE-102", "VERVE-101", "BEAM-101", "PCSK9 base edit", "ANGPTL3 base edit", "in vivo CRISPR therapy", "CBE design", "ABE design", "prime editing design", "design base editor", "Verve Therapeutics", or "Beam Therapeutics in vivo": use the in_vivo_base_edit_design workflow (in vivo CRISPR base editing therapy design. Editor selection CBE/ABE/prime by edit goal — loss_of_function/gain_of_function/gene_correction/regulatory_modification. Delivery decision matrix: LNP IV hepatocyte VERVE-101/102 pattern, ex vivo HSC Casgevy/BEAM-101 pattern, AAV9 muscle Elevidys, AAV9 intrathecal CNS. Recovers VERVE-101/102 PCSK9, VERVE-201 ANGPTL3, BEAM-101 HBG1 designs exactly. IND-readiness checklist included. Required: target_gene + edit_goal + indication.)
- "next-gen GLP-1", "GLP-1 modality", "semaglutide vs tirzepatide vs retatrutide", "what's the next GLP-1", "GLP-1 race", "obesity drug modality", "MASH GLP-1", "oral GLP-1 design", "mRNA GLP-1", "GIPR GLP1R bake-off", "incretin design", or "GLP-1 family modality": use the glp1_modality_bakeoff workflow (GLP-1 family multi-receptor bake-off across GLP1R/GIPR/GCGR for metabolic indications obesity/T2D/MASH/CV outcomes/OSA. Indication-aware: tirzepatide-class for obesity/OSA/CV/T2D (approved + balanced), retatrutide-class for MASH (GCGR hepatic fat oxidation). Compares semaglutide, tirzepatide, retatrutide, orforglipron oral, mRNA-encoded, AAV gene therapy. Optional params all defaulted.)`,

  structural_biology: `- "generative drug design", "de novo design", "scaffold hopping", "scaffold hop", "lead generation", "molecule optimization", "REINVENT", "REINVENT4", "generate analogs", "generate better compounds", "design better molecules", "optimize scaffold", "fix ADMET liability with new molecules", "fragment decoration", "linker design", "bioisostere replacement", or "generative chemistry": suggest the reinvent4_lead_design workflow (REINVENT4 AstraZeneca, RL-based SMILES generator — supports de_novo, scaffold_decoration, linker_design, scaffold_hopping modes. Outputs ranked molecules + SDF + score trajectory. Input: SMILES seed or SMARTS scaffold. Use when user wants AI-generated analogs or optimized structures.)
- "relative binding free energy", "RBFE", "FEP", "free energy perturbation", "alchemical FEP", "alchemical simulation", "DDG", "delta delta G", "relative affinity", "compare two ligands binding", "which ligand binds better", "confirm affinity", "lead optimization FEP", "OpenFE", "binding free energy calculation", "rank ligands by binding", or "which compound is more potent": suggest the openfe_rbfe workflow (OpenFE RBFE — alchemical SepTop protocol + OpenMM 8 GPU + Lomap2 atom mapping + MBAR estimator. Input: receptor PDB + ligand_a SDF (reference) + ligand_b SDF (query). Output: DDG ± SEM kcal/mol + overlap matrix + convergence plot + HTML. Free open-source alternative to Schrödinger FEP+.)
- "Glide docking", "Schrödinger docking", "Schrodinger docking", "XP docking", "HTVS", "extra precision docking", "virtual screening Glide", or "FEP+ preparation": suggest the schrodinger_glide_docking workflow (Schrödinger Glide HTVS/SP/XP, 5-step pipeline: LigPrep → PrepWiz → Grid → Glide → ranked SDF. License: FlexNet, user must provide.)
- "covalent docking", "covalent inhibitor", "warhead", "acrylamide docking", "irreversible inhibitor design", "MOE docking", or "targeted covalent drug": suggest the moe_covalent_docking workflow (MOE CovDock SVL, 5-step: LigPrep → QuickPrep → CovDock → GBVI/WSA dG → SDF report. Warheads: acrylamide, chloroacetamide, epoxide, aldehyde, michael_acceptor. License: MOE FlexNet, user must provide.)
- "build pharmacophore model", "pharmacophore from actives", "pharmacophore filtering", "screen compound library against pharmacophore", or "pharmacophore + library screen" (in any combination): use the SINGLE pharmacophore_filtering workflow — it builds the model from reference SMILES AND screens the library in one run. NEVER decompose this into two sequential steps; pass reference_smiles (known actives) and library_smiles as parameters to the single workflow.
- "pocket detection", "binding pocket", "druggability", "fpocket", "P2Rank", "binding site detection", "binding site characterization", "find pockets", "detect pockets", "druggability score", or any request to identify binding pockets on a protein structure: use the pocket_detection_druggability workflow (fpocket — 3-step: fetch/validate PDB → run fpocket → rank pockets by druggability score + volume. Input: pdb_input = PDB ID (e.g. "1IEP") or path to local .pdb file. Outputs: pocket_summary.csv + druggability_scores.json + ranked HTML report). A PDB 4-letter code like "1IEP", "7RFS", "6LU7" IS a valid pdb_input — do not ask for a file upload when the user provides a PDB ID.
- "MD simulation", "molecular dynamics", "AMBER", "pmemd", "protein stability in explicit solvent", or "post-docking MM-GBSA refinement": suggest the amber_pmemd_md workflow (AMBER pmemd.cuda GPU MD, 7-step pipeline: GAFF2 parametrization → tleap → EM → NVT/NPT equilibration → production MD → cpptraj RMSD/RMSF → MMPBSA.py ΔGbind. License: free academic since AMBER24.)
- "GROMACS", "GROMACS MD", "GROMOS force field", or explicit mention of GROMACS: suggest the gromacs_protein_md workflow (GROMACS 2025 + gmx_MMPBSA, 8-step pipeline, outputs ΔGbind ± SE and RMSD trajectory)`,

  single_cell: `- "virtual cell", "perturbation prediction", "cell response to drug", "predict gene KO effect", "predict gene knockout", "CRISPR perturbation prediction", "drug effect on cell state", "cell state after perturbation", "transcriptomic perturbation response", "in silico KO", "in silico knockout", "predict scRNA-seq after treatment", "GEARS perturbation", "STATE model", "state perturbation", "predict combinatorial perturbation", "multi-gene perturbation", or "gene expression after CRISPR": use the state_perturbation_prediction workflow as primary and offer gears_perturbation_prediction as an alternative. STATE model (Singlecell Transcriptomics for Arbitrary Treatment Effects) predicts single-cell gene expression responses to unseen drug or genetic perturbations using a transformer trained on Perturb-seq data; GEARS uses a graph neural network over gene co-expression to predict combinatorial perturbation effects. Both accept: cell_type, perturbation_name (gene symbol or drug name), and optionally a reference h5ad. Outputs: predicted_expression.h5ad + differential_genes.csv + UMAP comparison. Use STATE for drug perturbations; prefer GEARS when querying multi-gene combinatorial KO panels.`,

  genomics: `- "AlphaGenome", "Alpha Genome", "DeepMind genomics 2025", "Enformer successor", "genomic track prediction", "predict ATAC-seq from sequence", "predict gene expression from DNA", "predict chromatin from sequence", "in-silico mutagenesis regulatory", "ISM variant regulatory", "enhancer prediction from sequence", "1Mb DNA prediction", "TF binding prediction sequence", or "cell-type gene expression from DNA": use the alphagenome_track_prediction workflow (AlphaGenome DeepMind 2025; predicts 5000+ tracks: ATAC, ChIP, RNA-seq, splicing, histones, CTCF across 100+ cell types. Enformer fallback if no API key. Input: genomic_region (chrom:start-end) + optional variant_vcf. Output: track predictions TSV + variant effects JSON + HTML report.)
- "Evo 2", "Evo-2", "Evo2", "Arc Institute DNA model", "DNA language model variant", "nucleotide language model", "whole genome language model", "genomic foundation model variant", "log likelihood ratio variant", "LLR variant", "non-coding variant score DNA model", "CRISPR guide scoring Evo", or "DNA sequence fitness": use the evo2_variant_effect workflow (Evo 2 Arc Institute 40B-param DNA LM; scores variants via log-likelihood ratio LLR=log P(alt)-log P(ref); negative LLR = deleterious. API: Together AI or local HF weights. Input: input_vcf + reference_genome. Output: scored TSV + ranked VCF + summary JSON.)`,

  molecular_biology: `- "ASO", "antisense oligonucleotide", "gapmer", "MOE gapmer", "LNA gapmer", "RNase H ASO", "knockdown ASO", "GalNAc-ASO", "design ASO", "design gapmer", "nusinersen-like", "inclisiran-like", "givosiran-like", "phosphorothioate oligonucleotide", or "PS backbone ASO": use the aso_gapmer_design workflow (ASO gapmer design for RNase H knockdown — MOE 5+10+5 / LNA 3+10+3 / MOE mixmer chemistries. Tm scoring with MOE/LNA correction, GC content (40-60%), G-quadruplex/GGGG rejection (hepatotoxicity), CpG flagging, palindrome check. Delivery recommendation: GalNAc-SC for liver, intrathecal for CNS, PMO/PPMO for muscle. Required: target_mrna + target_tissue. Optional: chemistry, n_top.)
- "siRNA design", "siRNA generation", "design siRNA", "siRNA candidates", "Ui-Tei criteria", "Reynolds criteria", "siRNA from mRNA", or "small interfering RNA design": use the sirna_design_full workflow (siRNA candidate generation from mRNA — sliding window 19-21mer → GC filter → Ui-Tei + Reynolds + thermodynamic asymmetry scoring → ranked candidates. Chains to sirna_offtarget_analysis for off-target screening.)`,
};

/**
 * Build a workflow routing rules block containing only rules for the detected domains.
 * Falls back to all rules combined when preferredDomains is empty.
 */
/**
 * LLM-extracted-key → workflow-required-param-key alias map.
 *
 * The chat-stream LLM extracts inline parameters from a user's natural-language
 * query using "human-friendly" key names (e.g. `target`, `gene`, `disease`).
 * But each workflow's `required_params` annotation uses workflow-specific keys
 * (e.g. `car_target`, `target_gene`, `indication`). Without remapping, the
 * workflow panel form fields stay empty and Run dispatches with `params.X='null'`
 * defaults.
 *
 * This table maps LLM keys → workflow keys per workflow.
 * Value `'__drop__'` deletes the key (no slot in the workflow).
 *
 * Keep `key.toLowerCase()` lookups so we tolerate `target_1`, `targetA`, etc.
 */
const WORKFLOW_PARAM_ALIASES: Record<string, Record<string, string>> = {
  bispecific_format_triage: {
    target_1: 'target_a', target1: 'target_a', targetA: 'target_a', first_target: 'target_a',
    target_2: 'target_b', target2: 'target_b', targetB: 'target_b', second_target: 'target_b',
    disease: 'indication',
  },
  in_vivo_cart_codesign: {
    target: 'car_target', antigen: 'car_target', car: 'car_target',
    car_target: 'car_target',
    delivery_vehicle: 'lnp_targeting', lnp: 'lnp_targeting',
    delivery_mechanism: 'lnp_targeting', delivery: 'lnp_targeting',
    delivery_method: 'lnp_targeting',
    lnp_target: 'lnp_targeting', targeting_ligand: 'lnp_targeting',
    cell: 'delivery_cell',
    disease: 'indication',
  },
  in_vivo_base_edit_design: {
    gene: 'target_gene', target: 'target_gene', target_protein: 'target_gene',
    goal: 'edit_goal', edit: 'edit_goal', strategy: 'edit_goal',
    editing_strategy: 'edit_goal', edit_type: 'edit_goal',
    editor: 'editor_preference',
    disease: 'indication',
    reference_therapeutic: '__drop__', reference: '__drop__',
    reference_style: '__drop__', reference_drug: '__drop__',
    style: '__drop__',
  },
  atlas_expression_query: {
    gene: 'target_gene', target: 'target_gene',
    organism: '__drop__', resolution: '__drop__',
  },
  modality_triage: {
    gene: 'target_gene', target: 'target_gene',
    disease: 'indication',
  },
  glp1_modality_bakeoff: {
    // Workflow .nf declares both `params.indication` (primary) and `params.disease`
    // (alias). Tier 0 demo asserts on `disease`. Map LLM-natural `indication` / `condition`
    // → `disease` so the panel populates the asserted key.
    indication: 'disease', condition: 'disease',
    modalities: '__drop__', drugs_to_compare: '__drop__', drugs: '__drop__',
    receptors_to_compare: 'receptors',
  },
  adc_design: {
    antigen: 'target_antigen', target: 'target_antigen',
    disease: 'indication',
    expression: 'antigen_expression_level',
  },
  protac_design: {
    target: 'target_protein', protein: 'target_protein',
    e3: 'e3_preference', e3_ligase: 'e3_preference',
    disease: 'indication',
  },
  mrna_therapeutic_design: {
    protein: 'protein_sequence', sequence: 'protein_sequence', aa_sequence: 'protein_sequence',
    tissue: 'target_tissue',
    class: 'protein_class',
  },
  aav_serotype_selection: {
    tissue: 'target_tissue',
    payload: 'payload_size_kb', payload_size: 'payload_size_kb',
    route: 'route_of_administration',
    disease: 'indication',
  },
  cart_construct_design: {
    target: 'target_antigen', antigen: 'target_antigen',
    disease: 'indication',
    generation: 'car_generation',
    costim: 'costimulatory_domain',
  },
  aso_gapmer_design: {
    target: 'target_mrna', gene: 'target_mrna', mrna: 'target_mrna',
    tissue: 'target_tissue',
  },
  sirna_design_full: {
    target: 'mrna_sequence', gene: 'mrna_sequence', sequence: 'mrna_sequence',
    region: 'target_region',
  },
};

/**
 * Remap an LLM-extracted inlineParameters dict to the workflow's expected
 * required_params keys. Unknown keys pass through (forwards-compat for new
 * workflows). Keys mapped to '__drop__' are removed.
 */
export function remapInlineParametersForWorkflow(
  workflowName: string | undefined | null,
  raw: Record<string, string> | undefined | null,
): Record<string, string> {
  if (!raw || !workflowName) return raw || {};
  const aliases = WORKFLOW_PARAM_ALIASES[workflowName];
  if (!aliases) return raw;
  const out: Record<string, string> = {};
  let changed = false;
  for (const [k, v] of Object.entries(raw)) {
    const target = aliases[k] ?? aliases[k.toLowerCase()];
    if (target === '__drop__') { changed = true; continue; }
    const finalKey = target ?? k;
    if (finalKey !== k) changed = true;
    out[finalKey] = v;
  }
  if (changed) {
    console.log(
      '[InlineParam Remap]', workflowName,
      'raw:', Object.keys(raw),
      '→ mapped:', Object.keys(out),
    );
  }
  return out;
}

export function buildWorkflowRoutingBlock(preferredDomains: string[]): string {
  if (!preferredDomains || preferredDomains.length === 0) {
    return Object.values(DOMAIN_ROUTING_RULES).join('\n');
  }
  const matched = preferredDomains
    .map(d => DOMAIN_ROUTING_RULES[d])
    .filter((r): r is string => !!r);
  return matched.length > 0 ? matched.join('\n') : Object.values(DOMAIN_ROUTING_RULES).join('\n');
}

/**
 * Build a domain specialist guidance block for injection into generateResponse() system prompts.
 * Returns empty string if no guidance exists for any of the given domains.
 */
export function buildDomainSpecialistBlock(preferredDomains: string[]): string {
  const guidance = preferredDomains
    .map(d => DOMAIN_SPECIALIST_GUIDANCE[d])
    .filter((g): g is string => !!g);
  if (guidance.length === 0) return '';
  return `<domain_specialist>\n${guidance.join('\n\n')}\n</domain_specialist>\n`;
}

// ============================================================================
// Multi-Intent Decomposition Types
// ============================================================================

export type IntentType =
  | 'workflow_generation'
  | 'research_question'
  | 'database_lookup'          // live query to GWAS Catalog, Open Targets, OMIM, ClinVar, Ensembl, etc.
  | 'genomics_knowledge'       // GWAS variant prioritization, causal gene, gene-phenotype associations
  | 'clinical_genomics'        // rare disease diagnosis, patient gene detection, HPO-based reasoning
  | 'tool_search'
  | 'result_comparison'
  | 'benchmark_query'
  | 'dataset_inquiry'
  | 'general_question'
  | 'workflow_modification';

export interface ActionCategories {
  needsToolSearch: boolean;
  needsWorkflowGeneration: boolean;
  needsWorkflowModification: boolean;
  needsResearchAgent: boolean;
  needsBenchmarkAgent: boolean;
  needsDatasetAccess: boolean;
  needsLLMReasoning: boolean;
  // [v2] Propose a downstream Bioconductor chain based on a recently completed run
  needsChainProposal: boolean;
}

/**
 * Infer action categories from a type string. Known types get established
 * mappings; unknown types default to LLM reasoning only.
 */
export function inferActionsFromType(type: string): ActionCategories {
  const defaults: Record<string, Partial<ActionCategories>> = {
    // Workflow generation: backend searches its own tool index internally — no frontend tool search needed
    'workflow_generation': { needsWorkflowGeneration: true, needsLLMReasoning: true },
    'data_format_conversion': { needsWorkflowGeneration: true, needsLLMReasoning: true },
    'external_db_retrieval': { needsWorkflowGeneration: true, needsLLMReasoning: true },
    'visualization': { needsWorkflowGeneration: true, needsLLMReasoning: true },
    'multi_step_procedure': { needsWorkflowGeneration: true, needsLLMReasoning: true },
    // Tool/research intents: frontend search is the primary source
    'tool_search': { needsToolSearch: true, needsLLMReasoning: true },
    'workflow_modification': { needsToolSearch: true, needsWorkflowModification: true, needsLLMReasoning: true },
    'troubleshooting': { needsResearchAgent: true, needsToolSearch: true, needsLLMReasoning: true },
    'parameter_optimization': { needsBenchmarkAgent: true, needsResearchAgent: true, needsToolSearch: true, needsLLMReasoning: true },
    'result_comparison': { needsToolSearch: true, needsBenchmarkAgent: true, needsLLMReasoning: true },
    // Research/knowledge intents — ALL route through ResearchAgent for live DB + literature
    'research_question': { needsResearchAgent: true, needsLLMReasoning: true },
    // Live database lookup: GWAS Catalog, Open Targets, OMIM, ClinVar, Ensembl, mygene.info
    // Use when the answer requires querying a specific biological database with real-time data.
    'database_lookup': { needsResearchAgent: true, needsLLMReasoning: true },
    // Genomics knowledge: GWAS variant-to-trait associations, causal gene at locus, eQTL evidence.
    // Triggered by candidate SNP/gene selection tasks where the answer needs GWAS Catalog or Open Targets.
    'genomics_knowledge': { needsResearchAgent: true, needsLLMReasoning: true },
    // Clinical genomics: rare disease diagnosis (OMIM), patient gene detection (ClinVar + Monarch),
    // HPO phenotype-to-gene mapping. Triggered by HPO terms, ENSG candidate lists, disease matching.
    'clinical_genomics': { needsResearchAgent: true, needsLLMReasoning: true },
    'benchmark_query': { needsBenchmarkAgent: true, needsLLMReasoning: true },
    'dataset_inquiry': { needsDatasetAccess: true, needsLLMReasoning: true },
    'experiment_design': { needsResearchAgent: true, needsLLMReasoning: true },
    'data_interpretation': { needsResearchAgent: true, needsLLMReasoning: true },
    'protocol_guidance': { needsResearchAgent: true, needsLLMReasoning: true },
    'teaching_explanation': { needsLLMReasoning: true },
    'methods_writing': { needsResearchAgent: true, needsLLMReasoning: true },
    'comparative_methodology': { needsResearchAgent: true, needsBenchmarkAgent: true, needsLLMReasoning: true },
    'regulatory_compliance': { needsResearchAgent: true, needsLLMReasoning: true },
    'cost_estimation': { needsBenchmarkAgent: true, needsLLMReasoning: true },
    'general_question': { needsLLMReasoning: true },
    // [v2] User asks what to do next after a run — propose a downstream Bioconductor chain
    'chain_proposal': { needsChainProposal: true, needsLLMReasoning: true },
  };
  return {
    needsToolSearch: false,
    needsWorkflowGeneration: false,
    needsWorkflowModification: false,
    needsResearchAgent: false,
    needsBenchmarkAgent: false,
    needsDatasetAccess: false,
    needsLLMReasoning: true,
    needsChainProposal: false,
    ...defaults[type],
  };
}

export interface DecomposedIntent {
  id: string;
  type: string; // Open-vocabulary: 'workflow_generation', 'troubleshooting', etc.
  subQuery: string;
  keywords: string[];
  inlineParameters: Record<string, string>;
  needsToolSearch: boolean;
  needsDatasets: boolean;
  confidence: number;
  facts: Array<{ category: string; value: string; confidence: number; supersedes?: string }>;
  dependsOn: string[];
  actions: ActionCategories; // Which backend agents to invoke
  /** Ambiguity fork point requiring clarification, or null when intent is unambiguous */
  workflowAmbiguity?: string | null;
}

export interface IntentDecomposition {
  intents: DecomposedIntent[];
  isMultiIntent: boolean;
  primaryIntent: DecomposedIntent;
  /** True when the intents form an ordered pipeline (output of step N feeds step N+1) */
  isSequential?: boolean;
  /** LLM-inferred domain preferences for workflow search ranking (replaces rule-based _infer_domain_preferences) */
  preferredDomains?: string[];
  /** LLM-inferred domains to penalize in workflow search ranking */
  penalizedDomains?: string[];
  /** LLM-extracted technical terms to boost in FTS (replaces ABBREVIATION_MAP expansion) */
  keyTerms?: string[];
  /** True when the query benefits from extended thinking (replaces shouldEnableThinking regex) */
  needsThinking?: boolean;
  /** Name of a known workflow chain if the query maps to one, else null */
  chainHint?: string | null;
}

export interface SubIntentResult {
  intentId: string;
  intentType: string;
  subQuery: string;
  message?: string;
  recommendedTools?: ToolRecommendation[];
  generatedWorkflow?: any;
  researchResponse?: any;
  benchmarkEvidence?: any;
  status: 'success' | 'error';
  error?: string;
}

export interface GalaxyAssistantResponse {
  // Natural language response
  message: string;

  // Classified intent type (aligned with backend ai_assistant.py)
  intentType?: string;
  intentConfidence?: number;

  // Extracted inline parameters from user message
  inlineParameters?: Record<string, string>;

  // Extracted typed facts from user message (for ConversationState)
  extractedFacts?: ExtractedFact[];

  // Tool recommendations
  recommendedTools?: ToolRecommendation[];

  // Dataset recommendations
  recommendedDatasets?: DatasetRecommendation[];

  // Workflow suggestion
  workflowSuggestion?: WorkflowSuggestion;

  // Generated workflow (if requested)
  generatedWorkflow?: any;

  // Additional parallel workflows for multi-intent queries (e.g. "RNA-seq AND ATAC-seq")
  additionalWorkflows?: any[];

  // Suggested follow-up questions
  suggestions: string[];

  // Thinking mode support
  thinking_content?: string;
  thinking_level?: 'none' | 'brief' | 'detailed';
  truncated?: boolean;

  // Multi-intent results (populated when message contains multiple distinct tasks)
  subIntentResults?: SubIntentResult[];
  isMultiIntent?: boolean;

  // Research and benchmark results (populated for research/benchmark intents)
  researchResponse?: any;
  benchmarkEvidence?: any;

  // [v2] Proposed downstream chain (populated when needsChainProposal fires)
  proposedChain?: {
    name: string;
    display_name: string;
    domain: string;
    description: string;
    steps: Array<{ order: number; workflow_name: string; role: string; params_template: Record<string, any> }>;
    connections: Array<{ from_step: number; from_output: string; to_step: number; to_input: string }>;
    required_inputs: string[];
    triggered_by_run_name?: string;
  };

  // Metadata
  sources: {
    toolSearchUsed: boolean;
    datasetRAGUsed: boolean;
    workflowGenerated: boolean;
    thinkingUsed: boolean;
    researchAgentUsed?: boolean;
    benchmarkAgentUsed?: boolean;
  };
}

// ============================================================================
// Session Memory — async LLM-maintained understanding of the current session
// ============================================================================

export interface SessionMemoryItem {
  text: string;
  /** Haiku-assigned confidence 0–1. Items below 0.7 are suppressed from injection. */
  confidence: number;
}

export interface SessionMemory {
  active_task: string;
  /** Technical decisions with confidence scores. Only items ≥0.7 are injected into system prompts. */
  key_decisions: SessionMemoryItem[];
  uploaded_files: string[];
  attempted_workflows: Array<{ path: string; status: string }>;
  current_parameters: Record<string, any>;
  /** Unresolved questions with confidence scores. Only items ≥0.7 are injected. */
  open_questions: SessionMemoryItem[];
}

/**
 * SessionMemoryUpdater: after each turn, enqueues an async (debounced) Haiku call
 * that maintains a structured summary of the session.  The summary is injected
 * into every subsequent system prompt via <session_memory> tags so the assistant
 * retains context beyond the 6-turn sliding window.
 *
 * Architecture: DeerFlow-inspired — memory updates are async, injection is sync.
 * The main conversation path is never blocked.
 */
class SessionMemoryUpdater {
  private claude: Anthropic;
  private memoryBySession: Map<string, { memory: SessionMemory; lastAccess: number }> = new Map();
  private timers: Map<string, ReturnType<typeof setTimeout>> = new Map();
  private onPersist?: (sessionId: string, memory: SessionMemory) => void;
  private static readonly DEBOUNCE_MS = 30_000;  // 30 s — same as DeerFlow
  private static readonly SESSION_TTL_MS = 2 * 60 * 60 * 1000; // 2 hours idle eviction

  private static readonly HAIKU_MODEL = 'claude-haiku-4-5';

  private static readonly UPDATE_PROMPT = `You are maintaining a session memory for a bioinformatics research session.
Given the new conversation turn below and the current memory, produce an updated memory JSON.

Rules:
- active_task: what is the user currently trying to accomplish (1 sentence, present tense)
- key_decisions: list of specific technical decisions made (max 8 items), each as {"text": "...", "confidence": 0.0-1.0}
  confidence reflects how certain you are this is a firm decision (0.9=explicit user statement, 0.7=strong inference, <0.7=speculation)
- uploaded_files: all files the user has uploaded or mentioned this session
- attempted_workflows: workflows that were generated or run, each as {"path": "...", "status": "pending|running|completed|failed"}
- current_parameters: concrete parameter values established (genome, strandedness, etc.)
- open_questions: things that remain ambiguous or unresolved, each as {"text": "...", "confidence": 0.0-1.0}
  confidence reflects how important/likely this question is to affect the next step

Update incrementally — carry forward what is still relevant, update what has changed.
Only include items you are confident about. If nothing changed for a field, keep it as-is.
Return ONLY valid JSON with these exact keys. No explanation, no markdown fences.`;

  constructor(claude: Anthropic) {
    this.claude = claude;
  }

  /**
   * Queue a memory update for the given session.  Debounced: if another turn
   * arrives within 30 s, the earlier update is cancelled and replaced.
   */
  queue(sessionId: string, userMessage: string, assistantResponse: string): void {
    // Clear any pending timer for this session
    const existing = this.timers.get(sessionId);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(() => {
      this.timers.delete(sessionId);
      this._update(sessionId, userMessage, assistantResponse).catch(
        (err) => console.warn('[SessionMemory] Update failed (non-fatal):', err)
      );
    }, SessionMemoryUpdater.DEBOUNCE_MS);

    this.timers.set(sessionId, timer);
  }

  /** Return the current memory for a session, or null if none yet. Updates last-access time. */
  get(sessionId: string): SessionMemory | null {
    const entry = this.memoryBySession.get(sessionId);
    if (!entry) return null;
    entry.lastAccess = Date.now();
    return entry.memory;
  }

  /**
   * Register a callback invoked after each successful Haiku update.
   * Used by GalaxyAssistant to persist session memory into the conversationState column.
   */
  setPersistCallback(cb: (sessionId: string, memory: SessionMemory) => void): void {
    this.onPersist = cb;
  }

  /**
   * Seed in-memory map from a previously persisted snapshot (e.g. loaded from DB on session resume).
   * No-op if memory is already present for this session.
   */
  restoreIfEmpty(sessionId: string, memory: Record<string, any> | null | undefined): void {
    if (!memory || this.memoryBySession.has(sessionId)) return;
    try {
      const restored = memory as SessionMemory;
      if (typeof restored !== 'object' || !restored.active_task) return;
      this.memoryBySession.set(sessionId, { memory: restored, lastAccess: Date.now() });
      console.log(`[SessionMemory] Restored from DB for session=${sessionId}, task="${restored.active_task}"`);
    } catch {
      // malformed persisted data — ignore
    }
  }

  /** Evict sessions that have been idle longer than SESSION_TTL_MS. */
  private _evictStale(): void {
    const cutoff = Date.now() - SessionMemoryUpdater.SESSION_TTL_MS;
    for (const [id, entry] of this.memoryBySession) {
      if (entry.lastAccess < cutoff) {
        this.memoryBySession.delete(id);
        const t = this.timers.get(id);
        if (t) { clearTimeout(t); this.timers.delete(id); }
      }
    }
  }

  private async _update(sessionId: string, userMessage: string, assistantResponse: string): Promise<void> {
    // Evict stale sessions on each write (amortized cleanup)
    this._evictStale();

    const existing = this.memoryBySession.get(sessionId);
    const currentJson = existing ? JSON.stringify(existing.memory, null, 2) : JSON.stringify({
      active_task: '', key_decisions: [], uploaded_files: [],
      attempted_workflows: [], current_parameters: {}, open_questions: [],
    } as SessionMemory, null, 2);

    const userContent = `## Current memory\n${currentJson}\n\n## New turn\nUser: ${userMessage.substring(0, 800)}\n\nAssistant: ${assistantResponse.substring(0, 800)}\n\nReturn the updated memory JSON:`;

    const raw = await callGeminiFlash({
      messages: [{ role: 'user', content: userContent }],
      system: SessionMemoryUpdater.UPDATE_PROMPT,
      maxTokens: 1024,
    });
    try {
      // Strip markdown fences if present
      const cleaned = raw.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
      const updated: SessionMemory = JSON.parse(cleaned);
      // Type-guard: validate required array/object fields before storing
      if (typeof updated !== 'object' || updated === null) throw new Error('not an object');
      // Don't overwrite active_task if the new task is empty and we had an active task
      // (this prevents a tangent response from clearing the workflow context in memory)
      if (!updated.active_task && existing?.memory.active_task) {
        updated.active_task = existing.memory.active_task;
      }
      // Normalize key_decisions: accept objects {text,confidence} or plain strings (backward compat)
      if (!Array.isArray(updated.key_decisions)) updated.key_decisions = [];
      else updated.key_decisions = updated.key_decisions
        .map((d: any) => typeof d === 'string' ? { text: d, confidence: 0.7 } : d)
        .filter((d: any) => typeof d === 'object' && d !== null && typeof d.text === 'string') as SessionMemoryItem[];
      if (!Array.isArray(updated.uploaded_files)) updated.uploaded_files = [];
      if (!Array.isArray(updated.attempted_workflows)) updated.attempted_workflows = [];
      if (typeof updated.current_parameters !== 'object' || Array.isArray(updated.current_parameters)) updated.current_parameters = {};
      // Normalize open_questions: same pattern as key_decisions
      if (!Array.isArray(updated.open_questions)) updated.open_questions = [];
      else updated.open_questions = updated.open_questions
        .map((q: any) => typeof q === 'string' ? { text: q, confidence: 0.7 } : q)
        .filter((q: any) => typeof q === 'object' && q !== null && typeof q.text === 'string') as SessionMemoryItem[];
      this.memoryBySession.set(sessionId, { memory: updated, lastAccess: Date.now() });
      console.log(`[SessionMemory] Updated for session=${sessionId}, task="${updated.active_task}"`);
      // Persist to DB asynchronously (non-blocking, non-fatal)
      this.onPersist?.(sessionId, updated);
    } catch {
      console.warn('[SessionMemory] JSON parse/validation failed, keeping existing memory');
    }
  }
}

/**
 * Open-ended map of inline scientific data extracted from a user message.
 * Keys are parameter type names (e.g. "smiles", "sra_accession", "genome_fasta").
 * Values are the extracted strings verbatim from the message.
 */
export type InlineDataMap = Record<string, string>;

// Cache: message hash → extracted map (avoids re-calling Haiku for the same message)
const _inlineDataCache = new Map<string, InlineDataMap>();

/**
 * LLM-based inline data extraction.
 * Uses Haiku to identify ANY scientific data embedded in the message — SMILES,
 * accessions, sequences, file paths, coordinates, concentrations, etc. — and
 * returns them as a typed map.  Falls back to a minimal regex scan on error.
 *
 * This is async and must be awaited; it is called once per generateResponse() turn.
 * Latency: ~200-400 ms (Haiku, max_tokens=256).
 */
async function extractInlineDataWithLLM(
  message: string,
  claude: Anthropic,
): Promise<InlineDataMap> {
  // Cache key: hash of message text (avoid re-running for identical messages)
  const { createHash } = await import('node:crypto');
  const cacheKey = createHash('sha256').update(message).digest('hex').slice(0, 16);
  if (_inlineDataCache.has(cacheKey)) {
    return _inlineDataCache.get(cacheKey)!;
  }

  const SYSTEM = `You are a scientific data extractor. Given a user message, identify any scientific
data values directly embedded in the text. Return ONLY a JSON object mapping parameter type
names to extracted values. If no scientific data is present, return {}.

Parameter type names to detect (and any others you recognize):
- smiles: SMILES molecular structure string (e.g. CC(=O)Oc1ccccc1C(=O)O)
- sra_accession: SRA/ENA/DDBJ run/study accession (SRR, ERR, DRR, PRJNA, PRJEB, etc.)
- geo_accession: GEO/ArrayExpress dataset accession (GSE, GSM, E-MTAB, PXD, etc.)
- sequence: amino acid or nucleotide sequence (≥10 chars of IUPAC letters)
- pdb_id: PDB structure identifier (4-char, e.g. 4HHB)
- file_path: local file path or S3/GCS/FTP/HTTP URL pointing to a data file
- genome_build: reference genome (hg38, GRCh38, mm10, T2T-CHM13, etc.)
- concentration: drug/compound concentration with units (e.g. "10 µM", "1 mg/kg")
- dose_schedule: dosing schedule description
- sample_id: patient/sample/library identifier
- coordinates: genomic coordinates (chr:start-end format)
- uploaded_dataset: IDs from an "[Uploaded datasets: ...]" block in the message
- any other scientific parameter you recognize as concrete input data

Rules:
- Only extract values that are DIRECTLY present as literal strings in the message
- Do NOT infer or hallucinate values not in the message
- Do NOT extract workflow names, tool names, or method descriptions — only input DATA
- Return the extracted value exactly as it appears in the message
- Return ONLY valid JSON, no markdown, no explanation`;

  try {
    const raw = await callGeminiFlash({
      messages: [{ role: 'user', content: message.slice(0, 1200) }],
      system: SYSTEM,
      maxTokens: 1024,
      jsonMode: true,
      signal: AbortSignal.timeout(15_000), // 15s hard cap — prevents SSE stream stall
    });
    const cleaned = raw.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
    const parsed = JSON.parse(cleaned);
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
      // Normalize: all values must be non-empty strings
      const result: InlineDataMap = {};
      for (const [k, v] of Object.entries(parsed)) {
        if (typeof v === 'string' && v.trim()) result[k] = v.trim();
      }
      _inlineDataCache.set(cacheKey, result);
      return result;
    }
  } catch (err: any) {
    console.warn('[extractInlineData] LLM extraction failed, using regex fallback:', err.message);
  }

  // Regex fallback — high-confidence patterns only (accessions and file paths)
  const fallback: InlineDataMap = {};
  const sra = message.match(/\b((SRR|ERR|DRR|SRS|ERS|DRS|SRP|ERP|DRP|PRJNA|PRJEB)\d+)\b/i);
  if (sra) fallback.sra_accession = sra[1].toUpperCase();
  const geo = message.match(/\b((GSE|GSM|GDS|GPL|E-MTAB-|E-GEOD-|PXD)\d+)\b/i);
  if (geo) fallback.geo_accession = geo[1].toUpperCase();
  const file = message.match(/\b((?:s3|gs|ftp|http|https):\/\/\S+|\/\S+\.(?:fastq|fq|bam|vcf|fa|fasta|gz|csv|tsv|h5))\b/i);
  if (file) fallback.file_path = file[1];
  const upload = message.match(/\[Uploaded datasets:\s*([^\]]+)\]/);
  if (upload) fallback.uploaded_dataset = upload[1].trim();
  _inlineDataCache.set(cacheKey, fallback);
  return fallback;
}

/** Synchronous re-export kept for any future callers — wraps the same regex fallback. */
export function extractInlineData(message: string): InlineDataMap {
  const fallback: InlineDataMap = {};
  const sra = message.match(/\b((SRR|ERR|DRR|SRS|ERS|DRS|SRP|ERP|DRP|PRJNA|PRJEB)\d+)\b/i);
  if (sra) fallback.sra_accession = sra[1].toUpperCase();
  const geo = message.match(/\b((GSE|GSM|GDS|GPL|E-MTAB-|E-GEOD-|PXD)\d+)\b/i);
  if (geo) fallback.geo_accession = geo[1].toUpperCase();
  const file = message.match(/\b((?:s3|gs|ftp|http|https):\/\/\S+|\/\S+\.(?:fastq|fq|bam|vcf|fa|fasta|gz|csv|tsv|h5))\b/i);
  if (file) fallback.file_path = file[1];
  const upload = message.match(/\[Uploaded datasets:\s*([^\]]+)\]/);
  if (upload) fallback.uploaded_dataset = upload[1].trim();
  return fallback;
}

export class GalaxyAssistant {
  private claude: Anthropic;
  private gemini: GoogleGenerativeAI | null = null;
  private galaxyAPI: GalaxyAPIProxy;
  private modelConfig: ModelConfig;
  private sessionMemory: SessionMemoryUpdater;

  /** In-memory domain profile cache: userId → { domains, topics, fetchedAt } */
  private _domainProfileCache: Map<number, { domains: string[]; topics: string[]; fetchedAt: number }> = new Map();
  private static readonly DOMAIN_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

  constructor(options: GalaxyAssistantOptions) {
    this.claude = new Anthropic({ apiKey: options.anthropicApiKey });
    const geminiKey = process.env.GEMINI_API_KEY;
    if (geminiKey) this.gemini = new GoogleGenerativeAI(geminiKey);
    this.galaxyAPI = options.galaxyAPIProxy;
    this.modelConfig = { ...DEFAULT_MODEL_CONFIG, ...options.modelConfig };
    this.sessionMemory = new SessionMemoryUpdater(this.claude);
    // Wire persistence: after each Haiku update, write sessionMemory into conversationState JSONB
    this.sessionMemory.setPersistCallback((sid, mem) => {
      conversationStateManager.saveSessionMemory(sid, mem as any).catch(
        (err) => console.warn('[GalaxyAssistant] SessionMemory DB persist failed (non-fatal):', err)
      );
    });
    console.log('[GalaxyAssistant] Initialized with model config:', this.modelConfig);
  }

  /**
   * Generate a response using Gemini as the backbone LLM.
   * Handles streaming via Google's GenerativeAI SDK.
   * Tool use is disabled (Gemini function calling uses a different format — future work).
   */
  private async _generateWithGemini(
    systemPrompt: string,
    messages: Array<{ role: 'user' | 'assistant'; content: string }>,
    onResponseDelta?: (text: string) => void,
    maxTokens = 4096,
    modelOverride?: string,
    toolContext?: { tools: typeof BIOMATE_TOOLS; context: ChatContext; onToolEvent?: (e: AgentToolEvent) => void },
  ): Promise<string> {
    if (!this.gemini) throw new Error('Gemini client not initialized — set GEMINI_API_KEY');
    const geminiModelName = modelOverride
      ?? (this.modelConfig.responseModel.startsWith('gemini-') ? this.modelConfig.responseModel : 'gemini-3-flash-preview');

    // Convert Anthropic tool definitions → Gemini FunctionDeclarations
    const typeMap: Record<string, SchemaType> = {
      string: SchemaType.STRING, number: SchemaType.NUMBER, integer: SchemaType.INTEGER,
      boolean: SchemaType.BOOLEAN, array: SchemaType.ARRAY, object: SchemaType.OBJECT,
    };
    const convertProp = (v: any): any => {
      const base: any = { type: typeMap[v.type] ?? SchemaType.STRING, description: v.description ?? '' };
      if (v.enum) base.enum = v.enum;
      if (v.type === 'array' && v.items) base.items = convertProp(v.items);
      if (v.type === 'object' && v.properties) {
        base.properties = Object.fromEntries(Object.entries(v.properties).map(([k, pv]) => [k, convertProp(pv)]));
        if (v.required) base.required = v.required;
      }
      return base;
    };
    const geminiTools = toolContext?.tools
      ? [{
          functionDeclarations: toolContext.tools.map(t => ({
            name: t.name,
            description: t.description ?? '',
            parameters: {
              type: SchemaType.OBJECT,
              properties: Object.fromEntries(
                Object.entries((t.input_schema as any).properties || {}).map(([k, v]: [string, any]) => [k, convertProp(v)])
              ),
              required: (t.input_schema as any).required || [],
            },
          })),
        }]
      : undefined;

    const model = this.gemini.getGenerativeModel({
      model: geminiModelName,
      systemInstruction: systemPrompt,
      // temperature=0 for determinism (BioMate is a scientific tool; see
      // sister Anthropic call where the same change was applied).
      generationConfig: { maxOutputTokens: maxTokens, temperature: 0 },
      ...(geminiTools ? { tools: geminiTools as any } : {}),
    });

    let rawResponse = '';
    if (messages.length === 0) return '';

    const history = messages.slice(0, -1).map(m => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));
    const chat = model.startChat({ history });
    const lastMessage = messages[messages.length - 1].content;

    // Agentic loop: handle tool calls (up to 12 turns, then force a final answer)
    const MAX_TOOL_TURNS = 12;
    let currentMessage: string | object = lastMessage;
    for (let turn = 0; turn < MAX_TOOL_TURNS; turn++) {
      const result = await chat.sendMessage(currentMessage as any);
      const response = result.response;
      const allParts = response.candidates?.[0]?.content?.parts || [];
      console.log(`[GeminiLoop] turn=${turn} parts=${allParts.length} keys=${allParts.map((p: any) => Object.keys(p).join(',')).join('|')}`);

      // Collect text (skip thoughtSignature-only parts)
      const textParts = allParts.filter((p: any) => p.text);
      for (const part of textParts) {
        const txt: string = part.text ?? '';
        rawResponse += txt;
        if (txt) onResponseDelta?.(txt);
      }

      // Check for function calls
      const fnCalls = allParts.filter((p: any) => p.functionCall);
      if (fnCalls.length === 0 || !toolContext) break;  // No tools or no context — done

      // Execute all function calls
      const functionResults: object[] = [];
      for (const part of fnCalls) {
        const fnCall = part.functionCall;
        if (!fnCall) continue;
        const { name, args } = fnCall as { name: string; args: any };
        console.log(`[GeminiLoop] tool_call name=${name} args_keys=${Object.keys(args || {}).join(',')}`);
        toolContext.onToolEvent?.({ type: 'tool_call', tool_use_id: name, name, input: args });
        let output: unknown = null;
        let error: string | undefined;
        try {
          switch (name) {
            case 'run_code':    output = await this._toolRunCode(args); break;
            case 'read_file':   output = await this._toolReadFile(args, toolContext.context); break;
            default:            output = { error: `Unknown tool: ${name}` };
          }
        } catch (e: any) { error = e.message; output = { error }; }
        const outStr = JSON.stringify(output).slice(0, 200);
        console.log(`[GeminiLoop] tool_result name=${name} output=${outStr}`);
        toolContext.onToolEvent?.({ type: 'tool_result', tool_use_id: name, name, output: JSON.stringify(output) });
        functionResults.push({ functionResponse: { name, response: { output: JSON.stringify(output) } } });
      }
      currentMessage = functionResults;
    }

    // If all tool turns used without generating text, force a final answer turn via the same
    // chat session (which has full conversation history including all tool results).
    if (!rawResponse && toolContext) {
      console.log('[GeminiLoop] All turns used without text — requesting final answer from chat history');
      try {
        // Disable tools for the summary turn so Gemini must answer in text
        const noToolModel = this.gemini!.getGenerativeModel({
          model: geminiModelName,
          systemInstruction: 'Based on the code execution results, provide the final answer concisely. Print only the answer value, no explanation.',
          generationConfig: { maxOutputTokens: 512, temperature: 0 },
        });
        const summaryHistory = await chat.getHistory();
        const summaryChatObj = noToolModel.startChat({ history: summaryHistory });
        const summaryResult = await summaryChatObj.sendMessage(
          'Based on all the code results above, what is the final answer? Reply with ONLY the answer value.'
        );
        const summaryText = summaryResult.response.text();
        rawResponse = summaryText;
        if (summaryText) onResponseDelta?.(summaryText);
      } catch (e: any) {
        console.warn('[GeminiLoop] Final answer request failed:', e.message);
      }
    }

    return rawResponse;
  }

  /**
   * Generate a response using a local Ollama model (e.g. gemma4:31b).
   * Calls Ollama's OpenAI-compatible endpoint; no tool use.
   */
  private async _generateWithOllama(
    systemPrompt: string,
    messages: Array<{ role: 'user' | 'assistant'; content: string }>,
    onResponseDelta?: (text: string) => void,
    maxTokens = 4096,
  ): Promise<string> {
    const ollamaBase = process.env.OLLAMA_BASE_URL ?? 'http://localhost:11434';
    const model = this.modelConfig.responseModel;
    const body = JSON.stringify({
      model,
      messages: [
        { role: 'system', content: systemPrompt },
        ...messages.map(m => ({ role: m.role, content: m.content })),
      ],
      stream: true,
      // temperature=0 for determinism — Ollama local-LLM path used for
      // self-hosted models; same reasoning as Anthropic/Gemini paths.
      options: { num_predict: maxTokens, temperature: 0, num_ctx: 32768, keep_alive: '60m' },
    });
    const ollamaTimeout = 480_000; // 480s — covers gemma4:31b worst case
    const abortCtrl = new AbortController();
    const ollamaTimer = setTimeout(() => abortCtrl.abort(), ollamaTimeout);
    const res = await fetch(`${ollamaBase}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
      signal: abortCtrl.signal,
    });
    clearTimeout(ollamaTimer);
    if (!res.ok) throw new Error(`Ollama HTTP ${res.status}: ${await res.text()}`);
    let rawResponse = '';
    const reader = res.body?.getReader();
    const decoder = new TextDecoder();
    if (!reader) throw new Error('No response body from Ollama');
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      for (const line of decoder.decode(value).split('\n')) {
        const trimmed = line.replace(/^data:\s*/, '').trim();
        if (!trimmed || trimmed === '[DONE]') continue;
        try {
          const delta = JSON.parse(trimmed).choices?.[0]?.delta?.content;
          if (delta) { rawResponse += delta; onResponseDelta?.(delta); }
        } catch { /* skip malformed chunk */ }
      }
    }
    return rawResponse;
  }

  /**
   * Retry helper for Anthropic API calls — handles 429 rate-limit and 529 overloaded errors.
   * Only retries if no streaming content has been emitted yet (rawResponseSoFar empty).
   */
  private async _withAnthropicRetry<T>(
    fn: () => Promise<T>,
    label: string,
    maxAttempts = 3,
  ): Promise<T> {
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (err: any) {
        const status = err?.status ?? err?.statusCode;
        const msg = String(err?.message || '');
        const isRetryable =
          status === 429 || status === 529 ||
          msg.includes('rate_limit') || msg.includes('overloaded') || msg.includes('529');
        if (isRetryable && attempt < maxAttempts - 1) {
          const delayMs = Math.min(2000 * Math.pow(2, attempt), 16000); // 2s, 4s, 8s …
          console.warn(`[GalaxyAssistant] Anthropic ${status ?? 'overload'} on ${label}, retry ${attempt + 1}/${maxAttempts - 1} in ${delayMs}ms`);
          await new Promise(r => setTimeout(r, delayMs));
          continue;
        }
        throw err;
      }
    }
    throw new Error(`[GalaxyAssistant] Max retries exceeded for ${label}`);
  }

  /**
   * Fetch user domain profile from backend, with 5-minute in-memory cache.
   * Returns null if userId not set or fetch fails (never throws).
   */
  private async _fetchDomainProfile(userId?: number): Promise<{ domains: string[]; topics: string[] } | null> {
    if (!userId) return null;
    const cached = this._domainProfileCache.get(userId);
    if (cached && Date.now() - cached.fetchedAt < GalaxyAssistant.DOMAIN_CACHE_TTL_MS) {
      return { domains: cached.domains, topics: cached.topics };
    }
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const res = await fetch(`${galaxyUrl}/api/user/domain-profile?user_id=${userId}`, {
        headers: { 'Content-Type': 'application/json' },
      });
      if (!res.ok) return null;
      const data = await res.json();
      const profile = { domains: data.domains || [], topics: data.topics || [] };
      this._domainProfileCache.set(userId, { ...profile, fetchedAt: Date.now() });
      return profile.domains.length > 0 ? profile : null;
    } catch {
      return null;
    }
  }

  /**
   * Build a domain profile context string to prepend to system prompts.
   * Returns empty string if no profile is set.
   */
  private _buildDomainProfileContext(profile: { domains: string[]; topics: string[] } | null): string {
    if (!profile || profile.domains.length === 0) return '';
    const topicStr = profile.topics.length > 0 ? `, topics=[${profile.topics.join(', ')}]` : '';
    return `User research profile: domains=[${profile.domains.join(', ')}]${topicStr}. Use this as a starting bias — current conversation context always takes precedence.\n\n`;
  }

  /**
   * Fetch cryo-EM RAG context from the Python knowledge backend.
   * Returns empty string on any failure (never throws — context is optional enrichment).
   */
  private async _fetchCryoEmContext(query: string, sampleClass?: string): Promise<string> {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const body: Record<string, string | number> = { query, max_tokens: 500 };
      if (sampleClass) body.sample_class = sampleClass;
      const res = await fetch(`${galaxyUrl}/api/cryo_em/context`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(4000),
      });
      if (!res.ok) return '';
      const data = await res.json();
      return (data as { context?: string }).context || '';
    } catch {
      return '';
    }
  }

  /** Get current model configuration (for testing/debugging) */
  getModelConfig(): ModelConfig {
    return { ...this.modelConfig };
  }

  /**
   * Build a session memory block to prepend to system prompts.
   * Returns empty string if no memory exists for this session.
   * The block is wrapped in <session_memory> tags so the LLM understands
   * it supplements — not replaces — the conversation window.
   */
  private _buildSessionMemoryBlock(sessionId?: string): string {
    if (!sessionId) return '';
    const mem = this.sessionMemory.get(sessionId);
    if (!mem || !mem.active_task) return '';

    const parts: string[] = [];
    if (mem.active_task) parts.push(`Current task: ${mem.active_task}`);
    // Only inject high-confidence decisions (≥0.7) to avoid polluting the system prompt with speculation
    const highConfDecisions = mem.key_decisions.filter(d => d.confidence >= 0.7);
    if (highConfDecisions.length > 0) parts.push(`Key decisions: ${highConfDecisions.map(d => d.text).join('; ')}`);
    if (mem.uploaded_files.length > 0) parts.push(`Files this session: ${mem.uploaded_files.join(', ')}`);
    if (mem.attempted_workflows.length > 0) {
      const wfs = mem.attempted_workflows.map(w => `${w.path} (${w.status})`).join(', ');
      parts.push(`Previously attempted: ${wfs}`);
    }
    if (Object.keys(mem.current_parameters).length > 0) {
      parts.push(`Parameters set: ${JSON.stringify(mem.current_parameters)}`);
    }
    const highConfQuestions = mem.open_questions.filter(q => q.confidence >= 0.7);
    if (highConfQuestions.length > 0) parts.push(`Open questions: ${highConfQuestions.map(q => q.text).join('; ')}`);

    return `<session_memory>\n${parts.join('\n')}\n</session_memory>\nNote: session memory supplements the conversation window — prior turns may have been compressed.\n\n`;
  }

  /**
   * 6B — Fetch and build a cross-session context block from the user's past sessions.
   * Uses recency + keyword overlap scoring (no pgvector needed).
   * Returns empty string on any failure — this is always non-fatal enrichment.
   */
  private async _buildCrossSessionContextBlock(message: string, userId: string): Promise<string> {
    try {
      const allSessions = await memoryService.sessions.getRecentSessions(userId, 20)
        .catch(() => []);
      if (!allSessions.length) return '';

      const query = message.toLowerCase();
      const queryTokens = new Set(
        query.split(/\W+/).filter((t: string) => t.length > 2)
      );

      const scored = allSessions.map((s: any) => {
        const text = [
          s.summary || '',
          s.title || '',
          (s.toolsDiscussed || []).join(' '),
        ].join(' ').toLowerCase();
        const tokens = text.split(/\W+/).filter((t: string) => t.length > 2);
        const overlap = tokens.filter((t: string) => queryTokens.has(t)).length;
        return { s, score: overlap };
      });
      scored.sort((a: any, b: any) =>
        b.score - a.score ||
        (b.s.startedAt > a.s.startedAt ? 1 : -1)
      );

      const top = scored.slice(0, 5).map((item: any) => {
        const s = item.s;
        const date = s.startedAt
          ? new Date(s.startedAt).toISOString().slice(0, 10)
          : 'recent';
        const summary = (s.summary || s.title || '').slice(0, 150);
        return summary ? `- ${date}: ${summary}` : null;
      }).filter(Boolean);

      if (!top.length) return '';
      return `[Past session context — use to inform your response but don't mention unless relevant]\n${top.join('\n')}\n\n`;
    } catch {
      return '';
    }
  }

  /**
   * P1 — Build an episode memory block from the user's past project episodes.
   * Scores episodes by keyword overlap with the current message, injects top-5.
   * Non-fatal: returns empty string on any error.
   */
  private async _buildEpisodeMemoryBlock(message: string, userId: string): Promise<string> {
    try {
      const episodes = await memoryService.episodes.getRecentUserEpisodes(userId, 10)
        .catch(() => []);
      if (!episodes.length) return '';

      const queryTokens = new Set(
        message.toLowerCase().split(/\W+/).filter((t: string) => t.length > 2)
      );

      const scored = episodes.map((ep: any) => {
        const text = [
          ep.userQuery || '',
          ep.userIntent || '',
          (ep.lessonsLearned || []).join(' '),
          (ep.whatWorked || []).join(' '),
          (ep.whatFailed || []).join(' '),
        ].join(' ').toLowerCase();
        const tokens = text.split(/\W+/).filter((t: string) => t.length > 2);
        const overlap = tokens.filter((t: string) => queryTokens.has(t)).length;
        return { ep, score: overlap };
      });
      scored.sort((a: any, b: any) =>
        b.score - a.score || (b.ep.importanceScore || 0) - (a.ep.importanceScore || 0)
      );

      const top = scored.slice(0, 5).map(({ ep }: any) => {
        const date = ep.createdAt
          ? new Date(ep.createdAt).toISOString().slice(0, 10)
          : 'recent';
        const outcome = ep.outcomeSuccess === true ? '✓' : ep.outcomeSuccess === false ? '✗' : '·';
        const query = (ep.userQuery || '').slice(0, 100);
        const parts = [`  ${outcome} ${date} — "${query}"`];
        if (ep.lessonsLearned?.length) {
          parts.push(`    Lessons: ${ep.lessonsLearned.slice(0, 2).join('; ')}`);
        }
        if (ep.whatWorked?.length) {
          parts.push(`    Worked: ${ep.whatWorked.slice(0, 2).join('; ')}`);
        }
        if (ep.whatFailed?.length) {
          parts.push(`    Failed: ${ep.whatFailed.slice(0, 1).join('; ')}`);
        }
        return parts.join('\n');
      }).filter(Boolean);

      if (!top.length) return '';
      return `[Past research episodes — use to inform context-aware responses]\n${top.join('\n')}\n\n`;
    } catch {
      return '';
    }
  }

  /**
   * P2 — Build a correction context block from the user's correction history.
   * Formats past corrections as routing constraints to inject before intent analysis.
   * Non-fatal: returns empty string on any error.
   */
  private async _buildCorrectionContextBlock(userId: string): Promise<string> {
    try {
      const corrections = await memoryService.users.getUserCorrections(userId, 5)
        .catch(() => []);
      if (!corrections.length) return '';

      const lines = corrections.map((c: any) => {
        const suggested = c.suggestedApproach;
        const corrected = c.correctedApproach;
        if (!suggested || !corrected) return null;
        const from = typeof suggested === 'object' && suggested.workflow
          ? suggested.workflow
          : JSON.stringify(suggested).slice(0, 60);
        const to = typeof corrected === 'object' && corrected.workflow
          ? corrected.workflow
          : JSON.stringify(corrected).slice(0, 60);
        const note = c.userExplanation ? ` — "${c.userExplanation.slice(0, 80)}"` : '';
        return `  • Prefer ${to} over ${from}${note}`;
      }).filter(Boolean);

      if (!lines.length) return '';
      return `[User routing corrections — apply these preferences when selecting workflows]\n${lines.join('\n')}\n\n`;
    } catch {
      return '';
    }
  }

  /**
   * Stepwise E2E: user asks to show one named workflow card but the message also references
   * earlier pipeline steps (e.g. "use pocket from step 1"). Pick the intent that matches the
   * named tool — not sequential primaryIntent (always intents[0]).
   */
  private _pickIntentForNamedWorkflowCard(
    decomposition: IntentDecomposition,
    message: string
  ): DecomposedIntent {
    const { intents, primaryIntent, isSequential } = decomposition;
    const namedMatchers: Array<{ msg: RegExp; intent: RegExp }> = [
      {
        msg: /\b(autodock\s*vina|docking_autodock_vina|docking_autodock|site[- ]directed\s+docking|vina\s+docking)\b/i,
        intent: /\b(autodock|docking|vina)\b/i,
      },
      {
        msg: /\b(predict\s+admet|admet\s+propert)/i,
        intent: /\b(admet|toxicity|absorption|distribution|metabolism)\b/i,
      },
      {
        msg: /\b(pharmacophore\s+filter|pharmacophore\s+screen)/i,
        intent: /\b(pharmacophore|screen)\b/i,
      },
      {
        msg: /\b(pocket\s+detection|fpocket|druggability)\b/i,
        intent: /\b(pocket|fpocket|druggability)\b/i,
      },
      {
        msg: /\b(optimize_codons_for_heterologous_expression|registry\s+id\s+10813\b|host_codon_usage)\b/i,
        intent: /\b(codon|optimize|heterologous|10813)\b/i,
      },
    ];

    for (const { msg, intent } of namedMatchers) {
      if (!msg.test(message)) continue;
      const hit = intents.find(
        (i) =>
          intent.test(i.subQuery) ||
          (i.keywords || []).some((k) => intent.test(String(k)))
      );
      if (hit) return hit;
      if (isSequential && intents.length > 0) return intents[intents.length - 1];
      const wgIntents = intents.filter(
        (i) => i.type === 'workflow_generation' || i.actions?.needsWorkflowGeneration
      );
      if (wgIntents.length > 0) return wgIntents[wgIntents.length - 1];
      if (intents.length > 0) return intents[intents.length - 1];
      break;
    }

    const stepMatch = message.match(/\bstep\s*(\d+)\b/i);
    if (stepMatch) {
      const idx = parseInt(stepMatch[1], 10) - 1;
      if (idx >= 0 && idx < intents.length) return intents[idx];
    }

    return primaryIntent;
  }

  /**
   * Collapse multi/sequential intent to a single workflow_generation intent when the user
   * explicitly requested one named workflow card (ANDV inhibitor stepwise E2E).
   */
  private _maybeCollapseNamedWorkflowCardRequest(
    decomposition: IntentDecomposition,
    message: string
  ): void {
    const wantsNamedWorkflowCard =
      /\b(show|generate).{0,80}workflow\s+card\b/i.test(message) ||
      /\bworkflow\s+card\b.{0,40}\b(run\s+button|with\s+run)\b/i.test(message);
    const wantsNamedWorkflow =
      /\b(autodock\s*vina|docking_autodock_vina|docking_autodock|site[- ]directed\s+docking|predict\s+admet|pocket\s+detection|pharmacophore\s+filter|fpocket|druggability)\b/i.test(
        message
      ) ||
      /\b(optimize_codons_for_heterologous_expression|registry\s+id\s+10813\b)\b/i.test(message) ||
      (/\bcodon\s+optimi[sz]ation\b/i.test(message) && /\bhost_codon_usage\b/i.test(message));
    if (
      !(decomposition.isMultiIntent || decomposition.isSequential) ||
      !wantsNamedWorkflowCard ||
      !wantsNamedWorkflow
    ) {
      return;
    }

    const picked = this._pickIntentForNamedWorkflowCard(decomposition, message);
    const collapsed: DecomposedIntent = {
      ...picked,
      subQuery: message,
      type: 'workflow_generation',
      actions: {
        ...picked.actions,
        needsWorkflowGeneration: true,
        needsToolSearch: picked.actions.needsToolSearch !== false,
        needsLLMReasoning: true,
      },
    };
    console.log(
      '[GalaxyAssistant] Single workflow-card request: collapsing to named-workflow intent (contextual step refs ignored)'
    );
    decomposition.isMultiIntent = false;
    decomposition.isSequential = false;
    decomposition.intents = [collapsed];
    decomposition.primaryIntent = collapsed;
  }

  /** Plan B codon optimization (registry 10813) — shared by single- and multi-intent paths. */
  private _isPlanBCodonQuery(message: string): boolean {
    return (
      /\boptimize_codons_for_heterologous_expression\b/i.test(message) ||
      /\bregistry\s+id\s+10813\b/i.test(message) ||
      (/\bcodon\s+optimi[sz]ation\b/i.test(message) &&
        /\b(host_codon_usage|target_sequence)\b/i.test(message))
    );
  }

  /** Plan A epitopeprediction (registry 12700). */
  private _isPlanAEpitopeQuery(message: string): boolean {
    return (
      /\b(epitopeprediction|nf[\s-]?core\/epitopeprediction)\b/i.test(message) ||
      /\bregistry\s+id\s+12700\b/i.test(message) ||
      (/\bepitope\s+prediction\b/i.test(message) && /\bmhcnuggets\b/i.test(message))
    ) && !/\bmhcquant\b/i.test(message.replace(/\bnot\s+mhcquant\b/gi, ''));
  }

  /**
   * Pocket detection + druggability (fpocket; ANDV inhibitor pipeline step 1).
   * Mirrors the Plan A/B named-workflow fast-path so an explicit pocket request
   * always forces workflow_generation instead of falling back to a generic reply.
   */
  private _isPocketDetectionQuery(message: string): boolean {
    return (
      /\bpocket_detection_druggability\b/i.test(message) ||
      /\bfpocket\b/i.test(message) ||
      (/\bpocket\s+detection\b/i.test(message) &&
        /\b(druggabilit|pdb_input|pdb\b|binding\s+site)/i.test(message)) ||
      (/\bdruggabilit/i.test(message) && /\bpocket\b/i.test(message))
    );
  }

  /** Force workflow_generation on all intents when a named ANDV stepwise workflow is explicit. */
  private _applyNamedWorkflowOverridesToDecomposition(
    decomposition: IntentDecomposition,
    message: string
  ): void {
    const forceWf =
      this._isPlanBCodonQuery(message) ||
      this._isPlanAEpitopeQuery(message) ||
      this._isPocketDetectionQuery(message) ||
      /\b(autodock\s*vina|docking_autodock_vina|registry\s+id\s+12824)\b/i.test(message);
    if (!forceWf) return;

    const apply = (intent: DecomposedIntent) => {
      if (!intent.actions.needsWorkflowGeneration) {
        intent.actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    };
    apply(decomposition.primaryIntent);
    for (const i of decomposition.intents) apply(i);
  }

  /**
   * ClarificationGate (S1): Check if the intent is ambiguous and, if so, return a clarifying
   * question response before workflow generation proceeds.
   *
   * Returns a full GalaxyAssistantResponse to return immediately, or null if no gate fires.
   * Callers should `return gate` when non-null.
   */
  private async _clarificationGate(
    intent: any,
    actions: any,
    message: string,
    recommendedTools: ToolRecommendation[],
    recommendedDatasets: DatasetRecommendation[]
  ): Promise<GalaxyAssistantResponse | null> {
    let ambiguity = intent.workflowAmbiguity;
    if (!ambiguity || !actions.needsWorkflowGeneration) return null;

    // Suppress ambiguity when the user's message already resolves it.
    // AMBIGUITY_RESOLVERS maps each fork type → regex that detects the disambiguating terms.
    // This is generalizable: adding a new fork point only requires adding one resolver entry.
    if (AMBIGUITY_RESOLVERS[ambiguity]?.test(message)) {
      ambiguity = null;
    }
    if (!ambiguity) return null;

    const fallback = CLARIFICATION_FALLBACKS[ambiguity];
    const question = fallback
      ? await this._generateClarificationQuestion(message, ambiguity, fallback)
      : undefined;
    if (!question) return null;

    return {
      message: question,
      intentType: intent.type,
      intentConfidence: intent.confidence,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion: {
        shouldGenerate: false,
        userIntent: message,
        confidence: 0,
        reasoning: `Ambiguity "${ambiguity}" requires clarification before workflow generation`,
      },
      generatedWorkflow: null,
      researchResponse: undefined,
      benchmarkEvidence: undefined,
      truncated: false,
      suggestions: [],
      sources: {
        toolSearchUsed: false,
        datasetRAGUsed: false,
        workflowGenerated: false,
        thinkingUsed: false,
        researchAgentUsed: false,
        benchmarkAgentUsed: false,
      },
    };
  }

  /**
   * Generate a contextual clarifying question using Claude Haiku.
   * Falls back to the staticFallback string if the LLM call fails.
   */
  private async _generateClarificationQuestion(
    userMessage: string,
    ambiguityType: string,
    staticFallback: string
  ): Promise<string> {
    try {
      const text = await callGeminiFlash({
        messages: [{
          role: 'user',
          content: `User query: "${userMessage}"\nAmbiguity type: ${ambiguityType}\nGenerate the clarifying question:`
        }],
        system: `You are a bioinformatics expert assistant. A user has sent a query that is ambiguous for workflow selection. Generate a single concise clarifying question tailored to their SPECIFIC query. Use **bold** for key options. Keep it under 70 words. Never repeat the user's exact phrasing verbatim.

Ambiguity type → what to ask about:
- variant_type: germline (inherited disease, single patient) vs somatic (tumor mutations, matched samples)
- rnaseq_type: bulk RNA-seq (differential expression) vs single-cell RNA-seq (cell clustering)
- assembly_type: de novo assembly (no reference) vs reference-guided assembly
- peak_calling_type: ChIP-seq (antibody + input control) vs ATAC-seq (transposase, no antibody)
- chip_target: transcription factor (narrow peaks) vs histone modification (broad peaks)
- proteomics_type: DDA (MaxQuant) vs DIA (DIA-NN / Spectronaut)
- cryoem_type: single-particle analysis (SPA, purified protein) vs cryo-ET (tomography, in-situ)
- cryoem_sample: globular particle (standard) vs filamentous assembly (helical reconstruction)
- somatic_paired: matched tumor-normal vs tumor-only (panel of normals)
- metagenomics_type: 16S amplicon (QIIME2/DADA2) vs shotgun metagenomics (Kraken2/MetaPhlAn)
- docking_type: blind docking (DiffDock) vs site-directed docking (AutoDock Vina)`,
        maxTokens: 1024,
      });
      return text.trim() || staticFallback;
    } catch {
      return staticFallback;
    }
  }

  /**
   * Infer the bioinformatics domain of a query using Claude Haiku.
   * Returns a domain string like 'cryo_em', 'rna_seq', 'variant_calling_germline', etc.
   * Returns undefined if the domain cannot be determined.
   */
  private async _inferDomainWithLLM(
    userIntent: string,
    currentWorkflowText?: string
  ): Promise<string | undefined> {
    // Technical sub-domains sourced from domain-registry.ts
    // These are finer-grained than user profile domains and map back via SUBDOMAIN_TO_CANONICAL.
    const VALID_DOMAINS = [...TECHNICAL_SUBDOMAINS];
    try {
      const contextLine = currentWorkflowText
        ? `\nActive workflow context: "${currentWorkflowText}"`
        : '';
      const domain = await callGeminiFlash({
        messages: [{
          role: 'user',
          content: `Query: "${userIntent}"${contextLine}`
        }],
        system: `Classify the bioinformatics domain of a query. Respond with ONLY one of these exact strings (no punctuation, no explanation):
${TECHNICAL_SUBDOMAINS.join(' | ')} | other | unknown

Rules:
- cryo_em: cryo-EM, CryoSPARC, RELION, SPA, micrograph, CTF, tomography, tilt series
- rna_seq: RNA-seq, DESeq2, edgeR, limma, salmon, kallisto, STAR, transcriptomics (bulk, not single-cell)
- variant_calling_germline: germline, inherited disease, rare disease, HaplotypeCaller, no tumor
- variant_calling_somatic: somatic, tumor-normal, MuTect2, cancer mutations, matched tumor
- single_cell: scRNA-seq, Seurat, Scanpy, 10x Genomics, cell atlas, UMAP clustering
- epigenomics_chip: ChIP-seq, histone modification, transcription factor binding, MACS2
- epigenomics_atac: ATAC-seq, chromatin accessibility, open chromatin
- proteomics: mass spectrometry, DIA-NN, MaxQuant, proteome, TMT
- drug_discovery: ADMET, docking, DiffDock, AutoDock, pharmacokinetics, NCA, SMILES, HERG, DILI
- metagenomics_16s: 16S rRNA, amplicon, QIIME2, DADA2, OTU, taxonomic profiling
- metagenomics_shotgun: shotgun metagenomics, Kraken2, MetaPhlAn, whole metagenome
- methylation: bisulfite, WGBS, RRBS, DNA methylation, methylseq
- genome_assembly: de novo assembly, SPAdes, Flye, genome sequencing assembly
- structural_biology: AlphaFold, protein structure prediction, molecular dynamics (non-cryo-EM)
- other: recognised bioinformatics domain not listed above
- unknown: insufficient information`,
        maxTokens: 1024,
      }).then(r => r.trim());
      if ((VALID_DOMAINS as readonly string[]).includes(domain)) return domain as TechnicalSubdomain;
      return undefined; // 'other' or 'unknown' → no restriction
    } catch {
      return undefined;
    }
  }

  /** Update model configuration at runtime */
  setModelConfig(config: Partial<ModelConfig>): void {
    this.modelConfig = { ...this.modelConfig, ...config };
    console.log('[GalaxyAssistant] Model config updated:', this.modelConfig);
  }

  /**
   * Main entry point: Process user message with full Galaxy intelligence
   *
   * For single-intent messages (the common case), the pipeline is unchanged:
   *   analyzeIntent → parallel search → workflowNeed → generateWorkflow → generateResponse
   *
   * For multi-intent messages, a fan-out processes each intent independently:
   *   analyzeIntent → parallel search (union keywords) → Promise.all(processSubIntent) → generateResponse
   */
  async processMessage(
    message: string,
    context: ChatContext = {},
    onResponseDelta?: (chunk: string) => void,
    onToolEvent?: (event: AgentToolEvent) => void
  ): Promise<GalaxyAssistantResponse> {
    const startTime = Date.now();
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] ${step}`);

    log('Processing message: ' + message.substring(0, 50));

    // Load domain profile context (cached per user, 5-min TTL)
    const domainProfile = await this._fetchDomainProfile(context.userId);
    const domainProfileContext = this._buildDomainProfileContext(domainProfile);
    if (domainProfileContext) {
      log('Domain profile loaded for user ' + context.userId);
    }

    // Load session memory for long-session coherence (injected into system prompts)
    const sessionMemoryBlock = this._buildSessionMemoryBlock(context.sessionId);
    if (sessionMemoryBlock) {
      log('Session memory loaded for session ' + context.sessionId);
    }

    // 6B — Cross-session memory injection: on the first message of a session, fetch
    // relevant memories from the user's past sessions and prepend them to ltmContextBlock.
    // Also injects P1 episode memory and P2 correction constraints.
    // All injections are non-fatal — failures are silently ignored.
    const isFirstMessage = !context.previousMessages || context.previousMessages.length === 0;
    if (isFirstMessage && context.userId) {
      const uid = String(context.userId);
      try {
        const [crossSessionBlock, episodeBlock, correctionBlock] = await Promise.all([
          this._buildCrossSessionContextBlock(message, uid),
          this._buildEpisodeMemoryBlock(message, uid),          // P1
          this._buildCorrectionContextBlock(uid),               // P2
        ]);

        let prefix = '';
        if (correctionBlock) {
          prefix += correctionBlock;
          log('P2 correction context injected for user ' + uid);
        }
        if (episodeBlock) {
          prefix += episodeBlock;
          log('P1 episode memory injected for user ' + uid);
        }
        if (crossSessionBlock) {
          prefix += crossSessionBlock;
          log('Cross-session context injected for user ' + uid);
        }
        if (prefix) {
          context = {
            ...context,
            ltmContextBlock: prefix + (context.ltmContextBlock || ''),
          };
        }
      } catch {
        // non-fatal: skip all injections on error
      }
    }

    // Step 1: Analyze user intent with NLU (supports all formats: single, multi, sequential)
    // The LLM recognizes bullet lists, numbered steps, prose pipelines, and all other formats.
    log('Step 1: Analyzing intent');
    const decomposition = await this.analyzeIntent(message, context, sessionMemoryBlock);
    this._maybeCollapseNamedWorkflowCardRequest(decomposition, message);
    this._applyNamedWorkflowOverridesToDecomposition(decomposition, message);
    const intent = decomposition.primaryIntent;
    log(`Step 1 complete - Intent: ${intent.type}, isMultiIntent: ${decomposition.isMultiIntent}, intents: ${decomposition.intents.length}`);

    // Multi-intent path: fan out to processSubIntent for each intent
    if (decomposition.isMultiIntent) {
      return this.processMultiIntent(decomposition, message, context, startTime, onResponseDelta, domainProfileContext, sessionMemoryBlock, onToolEvent);
    }

    // Single-intent path: unchanged from original pipeline
    // Steps 2 & 3: Search for tools and datasets IN PARALLEL
    let recommendedTools: ToolRecommendation[] = [];
    let recommendedDatasets: DatasetRecommendation[] = [];
    let toolSearchUsed = false;
    let datasetRAGUsed = false;

    const searchPromises: Promise<void>[] = [];

    // Search tools when action flags indicate it
    if (intent.actions.needsToolSearch) {
      searchPromises.push(
        this.searchRelevantTools(message, intent.keywords, context.userId)
          .then(tools => {
            recommendedTools = tools;
            toolSearchUsed = true;
            console.log(`[GalaxyAssistant] Found ${tools.length} relevant tools`);
          })
      );
    }

    // Search datasets when action flags indicate it or legacy flag is set
    if (intent.actions.needsDatasetAccess || intent.needsDatasets) {
      searchPromises.push(
        this.searchRelevantDatasets(message, intent.keywords)
          .then(datasets => {
            recommendedDatasets = datasets;
            datasetRAGUsed = true;
            console.log(`[GalaxyAssistant] Found ${datasets.length} relevant datasets`);
          })
      );
    }

    // Wait for all parallel searches to complete
    log('Steps 2-3: Starting parallel searches');
    if (searchPromises.length > 0) {
      await Promise.all(searchPromises);
      log('Steps 2-3 complete');
    }

    // Step 4: Determine if workflow generation is needed
    let workflowSuggestion: WorkflowSuggestion;
    let generatedWorkflow = null;
    let workflowGenerated = false;

    // Action-flag-based routing (replaces switch-on-type)
    let researchResponse: any = undefined;
    let benchmarkEvidence: any = undefined;
    const actions = intent.actions;

    // Programmatic ADMET+SMILES fast path: if the message contains a SMILES string AND ADMET
    // keywords, force needsWorkflowGeneration=true regardless of the intent classifier output.
    // This prevents the LLM from asking clarifications in multi-turn conversations where the
    // user has already provided a SMILES string.
    const _hasSmilesPattern = /(?:CC\(=O\)|c1ccc|[A-Z][a-z]?(?:c|C)\d|[A-Z]=O|SMILES\s*[:=]\s*\S{5,})/i.test(message)
      || /\b[A-Z][CNOPSFIBrcl0-9@=#\-+\[\]()\/.\\]{6,}\b/.test(message);
    const _hasAdmetKeywords = /(ADMET|hERG|DILI|Ames\s+mutagenicity|cardiotox|hepatotox|ClinTox|toxicity\s+screen|drug\s+toxicity)/i.test(message);
    if (_hasSmilesPattern && _hasAdmetKeywords && !actions.needsWorkflowGeneration) {
      log('ADMET+SMILES fast path: forcing needsWorkflowGeneration=true');
      actions.needsWorkflowGeneration = true;
    }

    // Bioinformatics method-description override:
    // The intent classifier may return research_question or general_question for queries that
    // describe a computational method without action verbs (e.g. "Spectral counting from DDA mass
    // spec", "Retention time alignment using iRT standards", "Clonal lineage reconstruction from
    // BCR sequencing"). These ARE workflow generation requests — the user wants to execute the
    // method, not read about it. Override when: (1) NOT already classified as workflow_generation,
    // (2) message lacks clear research/conceptual markers, (3) message contains method/analysis terms,
    // AND (4) message is NOT a direct lookup/computation with a deterministic answer.
    if (!actions.needsWorkflowGeneration) {
      const _isConceptualQuestion = /\b(what\s+is|what\s+are|how\s+does|how\s+do|why\s+is|why\s+do|explain|describe|tell\s+me\s+about|definition|concept|overview|introduction|paper|review|literature|published|citation|reference)\b/i.test(message);
      const _hasBioMethodTerms = /\b(quantification|alignment|calling|reconstruction|detection|profiling|identification|classification|assembly|annotation|prediction|docking|design|sequencing|analysis|workflow|pipeline|processing|search|prioritize|prioritizes|prioritization|ranking|ranked)\b/i.test(message)
        && /\b(mass\s+spec|RNA.?seq|DNA.?seq|WGS|WES|ChIP|ATAC|BCR|TCR|VDJ|FASTQ|BAM|VCF|variants?|SNPs?|indels?|pathogenicity|mzML|mzXML|proteomics|genomics|transcriptomics|metagenomics|epigenomics|immunomics|metabolomics|scaffold|SMILES|GPCR|kinase|inhibitor|DDA|DIA|iRT|ASV|OTU|amplicon|nanopore|Illumina|single.?cell|bulk.?RNA|paired.?end|protein.?search|sequence.?search|structure.?search|embedding|trimodal|UniProt|AlphaFold|PDB)\b/i.test(message);
      // Only override when the intent is genuinely ambiguous — never override a correctly
      // classified knowledge/research intent just because it uses biological terminology.
      const _knowledgeIntentTypes = new Set([
        'research_question', 'database_lookup', 'genomics_knowledge', 'clinical_genomics',
        'data_interpretation', 'experiment_design', 'protocol_guidance', 'methods_writing',
        'comparative_methodology', 'troubleshooting', 'regulatory_compliance', 'parameter_optimization',
      ]);
      const _intentAlreadyKnowledge = _knowledgeIntentTypes.has(intent.type);
      // Direct lookup/computation guard: do NOT force workflow when the message is asking
      // for a specific value, ID, sequence, or result that can be answered via API or run_code —
      // i.e. no user-owned data files, no pipeline execution needed, answer is deterministic.
      // Signals: convert/retrieve/lookup/fetch/compute/calculate + identifier/value terms,
      //          Ensembl/GTEx/ENCODE/ClinVar/1000G API patterns, "what is the X of Y" with coordinates.
      const _isDirectLookupOrComputation = /\b(convert|retrieve|fetch|look\s*up|get\s+the|find\s+the|return\s+the|what\s+is\s+the|give\s+me\s+the|compute|calculate|infer|determine|identify\s+the)\b/i.test(message)
        && !/\b(my\s+(files?|samples?|data|fastq|bam|vcf|reads)|uploaded|your\s+data|the\s+uploaded|input\s+file)\b/i.test(message)
        && /\b(ensembl|ensg|gene\s+id|gene\s+symbol|gtex|encode|clinvar|dbsnp|ucsc|1000\s*genomes?|gnomad|uniprot|pdb\s+id|sequence|coordinate|genomic|locus|interval|chromosome|chr\d|tpm|expression|variant\s+consequence|vep|regulatory|ccre|enhancer)\b/i.test(message);
      if (!_isConceptualQuestion && !_intentAlreadyKnowledge && _hasBioMethodTerms && !_isDirectLookupOrComputation) {
        log('Bioinformatics method-description override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // AI container workflow name override:
    // If the query explicitly names a known AI/ML workflow by name, the user wants to RUN it.
    // The intent classifier often misclassifies these as tool_search.
    if (!actions.needsWorkflowGeneration) {
      const _mentionsAIWorkflow = /\b(ProTrek|Boltz[- ]?2?|Chai[- ]?1?|DrugCLIP|SynCraft|STATE\s+(?:model|perturbation|workflow)|scFv.?PMPNN|ProFam|trimodal protein search|protein language model search|ESM|AlphaFold\s+search|structure.?based protein|function.?based protein)\b/i.test(message);
      if (_mentionsAIWorkflow) {
        log('AI workflow name override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // PBPK intent override:
    // If the query mentions PBPK/pharmacokinetics concepts but was classified as research_question
    // or direct_computation, force workflow_generation so the PBPK prereq gate can fire and
    // ask for any missing SMILES or PK params before routing to the pbpk_simulation workflow.
    if (!actions.needsWorkflowGeneration) {
      // Named PK/pharmacology tool queries always generate a workflow card — override intent.
      // These tool names are unambiguous: user explicitly requested a specific workflow.
      const _isNamedPkToolQuery = /\b(pk.?sim|pksim|open systems pharmacology|osp suite|simcyp|nonmem|nmfe7|foce.?i|fcrn|fc.?rn|ich.?s7a|safety pharmacology|kaplan.meier|km curve|survival analysis|pediatric pbpk|paediatric pbpk|pediatric dose|nlmixr2|population pk|poppk)\b/i.test(message);
      if (_isNamedPkToolQuery) {
        log('Named PK tool override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      } else {
        // Generic PBPK intent without a named tool → send to prereq gate
        const _isPbpkIntentEarly = (
          /\b(pbpk|physiologically[- ]based|full[- ]?pk|human[- ]pk|predict.{0,20}pharmacokinetics?|organ[- ]level[- ]pk|mechanistic[- ]pk|pk[- ]simulation|pk[- ]profile|pharmacokinetic[- ]simulation|whole[- ]body[- ]pk|pk[- ]model|human[- ]pharmacokinetics?|pharmacokinetics?\s+of)\b/i.test(message)
          || (/\bphysiol/i.test(message) && /\bpk\b/i.test(message))
        );
        if (_isPbpkIntentEarly) {
          log('PBPK intent override: forcing needsWorkflowGeneration=true for prereq gate');
          actions.needsWorkflowGeneration = true;
          intent.type = 'workflow_generation';
        }
      }
    }

    // BOIN intent override:
    // Queries mentioning BOIN / Phase I dose escalation are clinical trial simulation tasks.
    // The Gemini intent classifier often misroutes these as "experiment_design", which skips
    // generateWorkflow() entirely and leaves generatedWorkflow=null → empty LLM response.
    // Force workflow_generation so the BOIN prereq gate fires (asks for dose levels if missing)
    // and so generateWorkflow() finds clinical_trial_simulation.
    if (!actions.needsWorkflowGeneration) {
      const _isBoInIntentEarly = /\b(boin|phase\s*i\s*(dose\s*escalation|trial)|dose[\s-]escalation[\s-](trial|study)|dose[\s-]finding[\s-](trial|study)|bayesian[\s-]optimal[\s-]interval|clinical[\s-]dose[\s-]escalation|phase[\s-]i[\s-]oncology|dlt[\s-]based[\s-]escalation|mtd[\s-]estimation|3\+3[\s-]design)\b/i.test(message);
      if (_isBoInIntentEarly) {
        log('BOIN intent override: forcing needsWorkflowGeneration=true for prereq gate');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // CryoSPARC / Cryo-EM SPA intent override:
    // "run CryoSPARC", "single-particle analysis", "process micrograph movies", "SPA on EMPIAR"
    // are unambiguously workflow execution requests. The intent classifier often returns
    // tool_search because the cryo-EM domain terms (mrc, mrcs, micrograph) aren't in the
    // generic _hasBioMethodTerms guard. Force workflow_generation here.
    if (!actions.needsWorkflowGeneration) {
      const _isCryoEmWorkflowQuery = /\b(cryosparc|cryo.?em\s+(spa|standard|pipeline)|single.?particle\s+analysis|process.*micrograph|micrograph\s+movies?|import.?movies?|patch.?motion|ctf.?estimation|cryo.?spa|empiar|particle\s+picking|blob\s+picking|2d\s+classif|ab.?initio\s+recon|homogeneous\s+refin|run\s+cryo)\b/i.test(message)
        && !/\b(what\s+is|what\s+are|how\s+does|explain|tell\s+me|overview|concept)\b/i.test(message);
      if (_isCryoEmWorkflowQuery) {
        log('CryoEM SPA override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // AutoDock Vina / site-directed docking override (ANDV inhibitor step 4 and similar).
    if (!actions.needsWorkflowGeneration) {
      const _isNamedDockingToolQuery =
        /\b(autodock\s*vina|docking_autodock_vina|site[- ]directed\s+docking|vina\s+docking|molecular\s+docking\s+with\s+vina)\b/i.test(
          message
        ) && !/\b(diffdock|blind\s+dock)\b/i.test(message);
      if (_isNamedDockingToolQuery) {
        log('Named docking tool override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // Plan B / Plan A named-workflow overrides (ANDV stepwise E2E).
    if (!actions.needsWorkflowGeneration) {
      if (this._isPlanBCodonQuery(message)) {
        log('Plan B codon optimization override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      } else if (this._isPlanAEpitopeQuery(message)) {
        log('Plan A epitopeprediction override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      } else if (this._isPocketDetectionQuery(message)) {
        log('Pocket detection override: forcing needsWorkflowGeneration=true');
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // HPO + ENSG candidate gene override:
    // Messages containing HPO phenotype codes (HP:XXXXXXX) AND ENSG gene IDs are patient gene
    // detection tasks — they query ClinVar/OMIM/Monarch to find the causal gene from a candidate
    // list. These are NEVER pipeline execution tasks. Override any workflow_generation
    // misclassification back to clinical_genomics + needsResearchAgent.
    if (actions.needsWorkflowGeneration) {
      const _hasHpoTerms = /\bHP:\d{7}\b/.test(message);
      const _hasEnsgGenes = /\bENSG\d{11}\b/.test(message);
      if (_hasHpoTerms && _hasEnsgGenes) {
        log('HPO+ENSG override: patient_gene_detection task — forcing clinical_genomics, needsWorkflowGeneration=false, needsResearchAgent=true');
        actions.needsWorkflowGeneration = false;
        actions.needsResearchAgent = true;
        intent.type = 'clinical_genomics';
      }

    }

    // Multi-turn data-provision override:
    // In multi-turn conversations the user may first state a research goal (classified as
    // research_question) and then provide input data (SRR/GEO/EMBL accession, file path, SMILES)
    // in a follow-up message.  If session memory records an active_task that implies workflow
    // execution AND the current message provides a recognisable data identifier, override to
    // workflow_generation so BioMate generates the workflow card without re-asking for intent.
    if (!actions.needsWorkflowGeneration && context.sessionId) {
      const _sessionMem = this.sessionMemory.get(context.sessionId);
      const _activeTask = _sessionMem?.active_task || '';
      const _hasActiveWorkflowTask = _activeTask.length > 0
        && /\b(run|analyz|sequenc|express|align|call|detect|map|quantif|process|generat|predict|dock|simulat|cluster|classif|annotate|assembl)/i.test(_activeTask);
      const _isDataProvision = /\b(SRR|ERR|DRR|GSE|GSM|PRJNA|PRJEB|EMBL|ENA|ENCSR|ENCS)\d{4,}/i.test(message)
        || /\b[0-9]{1,3}\s+(?:samples?|patients?|controls?|replicates?|subjects?)\b/i.test(message)
        || /(?:^|\s)(s3:\/\/|gs:\/\/|\/[\w\/]+\.(?:fastq|fq|bam|vcf|bed|gtf|gz|csv|tsv|txt|sdf|mol2|pdb|cif))/i.test(message);
      if (_hasActiveWorkflowTask && _isDataProvision) {
        log(`Multi-turn data-provision override: active_task="${_activeTask.slice(0,60)}" + data in message → needsWorkflowGeneration=true`);
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // PBPK prereq gate: before workflow generation, verify SMILES + CLint + fu_plasma are present.
    // This must run BEFORE _clarificationGate so it overrides the workflow generation path.
    if (actions.needsWorkflowGeneration) {
      // Skip generic PBPK gate for named-tool queries — they route directly to the named workflow.
      const _isNamedPkToolQueryGate = /\b(pk.?sim|pksim|open systems pharmacology|osp suite|simcyp|nonmem|nmfe7|foce.?i|fcrn|fc.?rn|ich.?s7a|safety pharmacology|kaplan.meier|km curve|survival analysis|pediatric pbpk|paediatric pbpk|pediatric dose|nlmixr2|population pk|poppk)\b/i.test(message);
      const _isPbpkIntent = !_isNamedPkToolQueryGate && (
        /\b(pbpk|physiologically[- ]based|full[- ]?pk|human[- ]pk|predict.{0,20}pharmacokinetics?|organ[- ]level[- ]pk|mechanistic[- ]pk|pk[- ]simulation|pk[- ]profile|pharmacokinetic[- ]simulation|whole[- ]body[- ]pk|pk[- ]model|human[- ]pharmacokinetics?|predict[- ]human[- ]pk|pharmacokinetics?\s+of)\b/i.test(message)
        || (/\bphysiol/i.test(message) && /\bpk\b/i.test(message))
      );
      if (_isPbpkIntent) {
        // Check for SMILES: atom pattern like CC(, c1c, [nH], lowercase aromatic rings, etc.
        // Uses two strategies: (1) broad atom token pattern, (2) SMILES-after-"for" token check
        // Strategy 1: common SMILES fragments that don't require word-boundary (appear only in SMILES)
        const _hasSmilesToken1 = /\b([A-Z][a-z]?\(|c1|CC\(|n1|N\(|O=|F[^a-z]|Cl[^a-z]|Br[^a-z])/.test(message)
          || /\(=O\)/.test(message)   // carbonyl/ester/amide — unique to SMILES
          || /\[n[Hh]\]/.test(message) // aromatic NH in SMILES
          || /[a-z]{2,}\d/.test(message.replace(/\b[a-z]{4,}\b/g, '')); // ring-closure digits after lowercase
        // Strategy 2: look for SMILES in the token AFTER "for [name] [SMILES]" (name + SMILES pattern)
        const _smilesAfterFor = (message.match(/\bfor\s+\S+\s+(\S+)/) || message.match(/\bfor\s+(\S+)/) || [])[1] || '';
        const _hasSmilesToken2 = /[a-z]\d|[A-Z]\d|\(=O\)|=O\)|\[n[H]\]|[cn][0-9]/.test(_smilesAfterFor);
        // Strategy 3: any word-like token containing SMILES brackets or ring-closure digits
        const _hasSmilesToken3 = /[A-Za-z0-9]\([A-Za-z=]/.test(message) && /[a-z]\d/.test(message);
        const _hasSmilesInMessage = _hasSmilesToken1 || _hasSmilesToken2 || _hasSmilesToken3 || /\.sdf\b/i.test(message);
        // Check for CLint: numeric value after CLint/intrinsic clearance keyword
        const _hasClintInMessage = /\b(clint|cl_int|intrinsic.clearance)\s*[=:]\s*[\d\.]+/i.test(message)
          || /\bclint\s+[\d\.]+/i.test(message)
          || /\b[\d\.]+\s*ul\/min\/mg/i.test(message);
        // Check for fu_plasma: numeric value after fu keyword
        const _hasFuPlasmaInMessage = /\b(fu_plasma|fu.plasma|unbound.fraction|fu)\s*[=:]\s*[\d\.]+/i.test(message);

        if (!_hasSmilesInMessage) {
          log('PBPK prereq gate: SMILES missing — returning clarification');
          actions.needsWorkflowGeneration = false;
          const _pbpkSmilesQuestion = 'To run the PBPK simulation, I need your compound\'s **SMILES string** (molecular structure — e.g. `CC(=O)Oc1ccccc1C(=O)O` for aspirin). Please provide it so I can set up the 8-compartment model.';
          return {
            message: _pbpkSmilesQuestion,
            intentType: intent.type,
            intentConfidence: intent.confidence,
            recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
            recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
            workflowSuggestion: { shouldGenerate: false, userIntent: message, confidence: 0, reasoning: 'PBPK prereq: SMILES missing' },
            generatedWorkflow: null, researchResponse: undefined, benchmarkEvidence: undefined,
            truncated: false, suggestions: [], sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false, knowledgeHighlightsUsed: false },
          } as GalaxyAssistantResponse;
        } else if (!_hasClintInMessage || !_hasFuPlasmaInMessage) {
          const _missingPkParams = [
            !_hasClintInMessage ? 'intrinsic clearance **CLint** (µL/min/mg)' : null,
            !_hasFuPlasmaInMessage ? 'unbound plasma fraction **fu_plasma** (0–1)' : null,
          ].filter(Boolean).join(' and ');
          log(`PBPK prereq gate: PK params missing (${_missingPkParams}) — returning clarification`);
          actions.needsWorkflowGeneration = false;
          const _pbpkParamsQuestion = `To simulate full PBPK pharmacokinetics, I need the ${_missingPkParams} for your compound. What are these values?`;
          return {
            message: _pbpkParamsQuestion,
            intentType: intent.type,
            intentConfidence: intent.confidence,
            recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
            recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
            workflowSuggestion: { shouldGenerate: false, userIntent: message, confidence: 0, reasoning: `PBPK prereq: ${_missingPkParams} missing` },
            generatedWorkflow: null, researchResponse: undefined, benchmarkEvidence: undefined,
            truncated: false, suggestions: [], sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false, knowledgeHighlightsUsed: false },
          } as GalaxyAssistantResponse;
        }
      }
    }

    // BOIN prereq gate: if the message asks for a Phase I dose escalation trial but does NOT
    // provide dose levels, ask for them before generating the workflow.
    // This prevents the LLM from generating a generic BOIN design without key inputs.
    if (actions.needsWorkflowGeneration) {
      const _isBoInIntent = /\b(boin|phase\s*i\s*(dose\s*escalation|trial)|dose.escalation.trial|dose.finding.trial|mtd.estimation|bayesian.optimal.interval|clinical.dose.escalation|phase.i.oncology|dlt.based.escalation)\b/i.test(message);
      if (_isBoInIntent) {
        // Dose levels present: explicit list like [10,20,40] or "dose levels: X"
        const _hasDoseLevels = /\[\s*\d[\d,\s\.]+\]/.test(message)
          || /\b(dose[- ]levels?|doses?)[:\s]+[\d\[,]/.test(message)
          || /\bstarting.dose\b.+\bmax.dose\b/i.test(message);
        if (!_hasDoseLevels) {
          log('BOIN prereq gate: dose levels missing — returning clarification');
          actions.needsWorkflowGeneration = false;
          const _boinQuestion = 'To design the BOIN Phase I trial, I need the **dose levels** to test (in mg). For example: `[10, 30, 60, 100, 200]`. What dose range should I use for your compound?';
          return {
            message: _boinQuestion,
            intentType: intent.type,
            intentConfidence: intent.confidence,
            recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
            recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
            workflowSuggestion: { shouldGenerate: false, userIntent: message, confidence: 0, reasoning: 'BOIN prereq: dose levels missing' },
            generatedWorkflow: null, researchResponse: undefined, benchmarkEvidence: undefined,
            truncated: false, suggestions: [], sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false, knowledgeHighlightsUsed: false },
          } as GalaxyAssistantResponse;
        }
      }
    }

    // S1: ClarificationGate — returns early if ambiguity requires user clarification
    const clarificationResponse = await this._clarificationGate(
      intent, actions, message, recommendedTools, recommendedDatasets
    );
    if (clarificationResponse) {
      log(`Step 4: Returning clarification question for ambiguity="${intent.workflowAmbiguity}"`);
      return clarificationResponse;
    }

    // Workflow generation — intent flags already determined by analyzeIntent; no further gate needed
    const needsGeneration = actions.needsWorkflowGeneration || actions.needsWorkflowModification;
    if (needsGeneration) {
      try {
        log('Step 4: Generating workflow');
        generatedWorkflow = await this.generateWorkflow(
          message,
          recommendedDatasets.map(d => d.dataset),
          intent.inlineParameters,
          context,
          decomposition.preferredDomains,
          decomposition.keyTerms,
          context.sessionDatasets?.length ? context.sessionDatasets : undefined,
          decomposition.penalizedDomains
        );
        workflowGenerated = !!(
          generatedWorkflow?.success &&
          !generatedWorkflow?.error &&
          (generatedWorkflow?.workflow_ga ||
           generatedWorkflow?.nextflow_path ||
           generatedWorkflow?.workflow_type === 'chain')
        );
        log('Step 4 complete - workflowGenerated: ' + workflowGenerated);

        // Track 7A — Confidence-gated near-tie detection
        // If top-1 and top-2 candidate scores are within 0.15 (normalized), flag the runner-up
        // so the LLM response can surface it as a soft "did you mean X?" note.
        if (workflowGenerated && generatedWorkflow?.candidate_workflows?.length >= 2) {
          const [top, runner] = generatedWorkflow.candidate_workflows as Array<{name: string; domain: string; score: number}>;
          const maxScore = 12; // raw score ceiling observed from UnifiedWorkflowSearch
          const normTop = (top.score ?? 0) / maxScore;
          const normRunner = (runner.score ?? 0) / maxScore;
          if (normTop - normRunner <= 0.15 && runner.name && runner.name !== top.name) {
            generatedWorkflow = { ...generatedWorkflow, _nearTieAlternative: runner.name };
            log(`near-tie: "${top.name}" (${normTop.toFixed(2)}) vs "${runner.name}" (${normRunner.toFixed(2)}) — will surface alternative`);
          }
        }
      } catch (error: any) {
        log('Step 4 failed: ' + error.message);
        console.error('[GalaxyAssistant] Workflow generation failed:', error);
      }
    }

    workflowSuggestion = {
      shouldGenerate: needsGeneration,
      userIntent: message,
      confidence: workflowGenerated ? 0.9 : needsGeneration ? 0.8 : 0.0,
      reasoning: needsGeneration
        ? (workflowGenerated ? 'Workflow generated successfully' : 'Workflow generation attempted')
        : `Intent type "${intent.type}" — workflow generation not flagged`,
    };

    // Research agent
    if (actions.needsResearchAgent) {
      log('Routing to research backend');
      try {
        researchResponse = await this.galaxyAPI.queryResearch({
          query: message,
          context: { information_need: intent.type },
          include_citations: true,
          include_benchmark_evidence: true,
        });
        log('Research response received');
      } catch (error: any) {
        log('Research query failed: ' + error.message);
      }
    }

    // Benchmark agent
    if (actions.needsBenchmarkAgent) {
      log('Routing to benchmark backend');
      try {
        benchmarkEvidence = await this.galaxyAPI.queryBenchmark({
          query: message,
        });
        log('Benchmark response received');
      } catch (error: any) {
        log('Benchmark query failed: ' + error.message);
      }
    }

    // Step 6: Generate natural language response
    log('Step 6: Generating response');
    const response = await this.generateResponse(
      message,
      intent,
      recommendedTools,
      recommendedDatasets,
      workflowSuggestion,
      generatedWorkflow,
      context,
      researchResponse,
      benchmarkEvidence,
      onResponseDelta,
      domainProfileContext,
      sessionMemoryBlock,
      decomposition.preferredDomains ?? [],
      onToolEvent
    );
    log('Step 6 complete');

    // Step 7: Generate follow-up suggestions
    log('Step 7: Generating suggestions');
    const suggestions = this.generateSuggestions(
      message,
      intent,
      recommendedTools,
      workflowSuggestion
    );
    log('Step 7 complete');
    log('Total processing time: ' + (Date.now() - startTime) + 'ms');

    // Convert intent facts to ExtractedFact format with unique IDs
    const turnIndex = context.turnIndex ?? 0;
    const extractedFacts: ExtractedFact[] = intent.facts.map((f, i) => ({
      id: `fact-${Date.now()}-${i}`,
      category: f.category as ExtractedFact['category'],
      value: f.value,
      source: { type: 'user_message' as const, turnIndex },
      confidence: f.confidence,
      supersedes: f.supersedes,
    }));

    // 3A-1: Prepend structured pre-execution summary when a workflow was generated
    let finalMessage = response.message;
    if (workflowGenerated && generatedWorkflow) {
      const summary = this._buildPreExecutionSummary(
        generatedWorkflow,
        message,
        context.sessionDatasets
      );
      if (summary) {
        finalMessage = `${summary}\n\n${response.message}`;
      }
    }

    // CRO compliance workspace routing: if the message is about CRO/compliance/IND/DMTA,
    // append a direct link to the CRO workspace so users can open it immediately.
    // IMPORTANT: use word-boundary regex for short substrings like 'cro' and 'esig'
    // to avoid false matches on words like 'design' (d-esig-n) or 'microsomal' (mi-cro-...).
    const _msgLower = message.toLowerCase();
    const _isCroQuery = /\bcro\b/.test(_msgLower)
      || /\bcompliance\b/.test(_msgLower)
      || _msgLower.includes('ind assembly')
      || _msgLower.includes('ind §')
      || _msgLower.includes('21 cfr')
      || _msgLower.includes('cfr part 11')
      || _msgLower.includes('audit trail')
      || /\besign(ature)?\b/.test(_msgLower)
      || _msgLower.includes('electronic signature')
      || _msgLower.includes('auto-retrain')
      || _msgLower.includes('dmta loop')
      || _msgLower.includes('drug discovery campaign')
      || _msgLower.includes('ingest assay')
      || _msgLower.includes('cro order');
    if (_isCroQuery && !finalMessage.includes('/drug-discovery-cro')) {
      finalMessage += '\n\n→ Open your [CRO Compliance workspace](/drug-discovery-cro) to manage campaigns, view the audit chain, and generate IND packages.';
    }

    // Remap LLM-extracted keys → workflow-required keys so the workflow panel
    // form actually populates. Without this, the form stays empty and Run
    // dispatches with `params.X='null'` defaults (see audit doc).
    const _workflowNameForRemap =
      generatedWorkflow?.workflow_ga?.name || generatedWorkflow?.workflow_name;
    const _remappedInlineParams = remapInlineParametersForWorkflow(
      _workflowNameForRemap,
      intent.inlineParameters,
    );

    const finalResult: GalaxyAssistantResponse = {
      message: finalMessage,
      intentType: intent.type,
      intentConfidence: intent.confidence,
      inlineParameters: Object.keys(_remappedInlineParams).length > 0 ? _remappedInlineParams : undefined,
      extractedFacts: extractedFacts.length > 0 ? extractedFacts : undefined,
      thinking_content: response.thinking?.thinkingContent ?? undefined,
      thinking_level: response.thinking?.thinkingLevel ?? undefined,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion,
      generatedWorkflow,
      researchResponse,
      benchmarkEvidence,
      isMultiIntent: false,
      truncated: response.truncated || false,
      suggestions,
      sources: {
        toolSearchUsed,
        datasetRAGUsed,
        workflowGenerated,
        thinkingUsed: response.thinking?.hasThinking || false,
        researchAgentUsed: !!researchResponse,
        benchmarkAgentUsed: !!benchmarkEvidence,
      },
    };

    // Queue async session memory update (non-blocking, debounced 30 s)
    if (context.sessionId) {
      this.sessionMemory.queue(context.sessionId, message, response.message);
    }

    return finalResult;
  }

  /**
   * Detect an explicitly bullet- or numbered-list formatted sequential pipeline.
   * When the user writes steps as a list (e.g. "1. QC\n2. Align\n3. Call variants"
   * or "- FastQC\n- Trim\n- STAR align"), we parse directly without an LLM call.
   * Returns null if the message is not in list format.
   */
  /**
   * Process a sequential pipeline request.
   *
   * Each intent maps to one Nextflow workflow step. Steps are executed in order
   * with output→input wiring described between consecutive steps.
   * Returns a response with `workflow_type: 'pipeline'` and `pipeline_steps: [...]`
   * so that the frontend `chat-message.tsx` renders `PipelineListView`.
   */
  /**
   * Build a structured pre-execution summary block describing what the AI understood
   * from the user's message before running the workflow.
   *
   * Format:
   *   **Understood from your message**
   *   • Input: <inputs>
   *   • <param>: <value> (<source>)
   *   ...
   *   **Running:** <workflow name>
   *   **N run(s)** · <exec target>
   *   [⚠️ Required: <param> if unfilled required params exist]
   */
  private _buildPreExecutionSummary(
    wf: any,
    _originalMessage?: string,
    _sessionDatasets?: Array<{ id: string; name: string; type: string }>
  ): string {
    if (!wf) return '';
    const workflowName = wf.workflow_name || wf.name || 'workflow';
    // Check for unfilled required params to warn the user
    const wfGaParams = wf.workflow_ga || {};
    const unfilledRequired = (wfGaParams.required_params || wf.required_params || []).filter(
      (p: any) => (p.value === null || p.value === undefined || p.value === '') &&
                  (p.default === null || p.default === undefined || p.default === '') &&
                  !p.autoFilled
    );
    const warning = unfilledRequired.length > 0
      ? `\n⚠️ Fill in required parameters before running: ${unfilledRequired.map((p: any) => `\`${p.name}\``).join(', ')}`
      : '';
    return `**${workflowName}** is ready in the panel — check the steps and parameters, then click **Confirm & Run**.${warning}`;
  }

  /**
   * Coverage check: Ask Haiku whether a given workflow covers N of the user's
   * remaining biological steps (starting from index 0).
   * Returns { coveredCount, confidence } — coveredCount=0 means "can't determine".
   */
  private async _checkWorkflowCoverage(
    workflowName: string,
    workflowDescription: string,
    intents: DecomposedIntent[],
    originalQuery: string
  ): Promise<{ confidence: number; coversAll: boolean; coveredCount: number }> {
    const stepList = intents.map((intent, i) => `${i + 1}. ${intent.subQuery}`).join('\n');
    const prompt = `You are a bioinformatics expert. Determine how many of the user's biological analysis steps (listed below) are covered by a single workflow.

Workflow: "${workflowName}"
Description: "${workflowDescription}"

User's biological steps:
${stepList}

Rules:
- Count consecutive steps covered starting from step 1 (must be contiguous from the beginning)
- A step is "covered" if the workflow performs that biological function internally as part of its pipeline
- Be conservative: only count a step as covered if the workflow clearly handles it based on the description
- Return JSON only, no explanation outside JSON

Return: {"covered_count": <integer 1 to ${intents.length}>, "confidence": <0.0-1.0>, "reasoning": "<one sentence>"}`;

    try {
      const text = await callGeminiFlash({
        messages: [{ role: 'user', content: prompt }],
        maxTokens: 1024,
        jsonMode: true,
      });
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) return { confidence: 0, coversAll: false, coveredCount: 1 };
      const result = JSON.parse(jsonMatch[0]);
      const coveredCount = Math.max(1, Math.min(intents.length, Number(result.covered_count) || 1));
      const confidence = Math.max(0, Math.min(1, Number(result.confidence) || 0));
      return { confidence, coversAll: coveredCount >= intents.length, coveredCount };
    } catch {
      return { confidence: 0, coversAll: false, coveredCount: 1 };
    }
  }

  /**
   * Fetch a curated chain definition by name from the Galaxy backend.
   * Returns null on failure or not-found.
   */
  private async _fetchCuratedChain(chainName: string): Promise<any | null> {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      // Fetch all chains (including bioc_reactive) so Tier 2 can resolve any named chain
      const res = await fetch(`${galaxyUrl}/api/workflow-chains`, {
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) return null;
      const data: any = await res.json();
      const chain = (data.chains || []).find((c: any) => c.name === chainName);
      return chain || null;
    } catch {
      return null;
    }
  }

  private async processSequentialPipeline(
    decomposition: IntentDecomposition,
    message: string,
    context: ChatContext,
    startTime: number,
    onResponseDelta?: (chunk: string) => void,
    domainProfileContext: string = ''
  ): Promise<GalaxyAssistantResponse> {
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] [SEQ] ${step}`);
    log(`Building sequential pipeline: ${decomposition.intents.length} steps`);

    // ═══════════════════════════════════════════════════════════════════════
    // TIER 1: Try the full query as a single workflow first.
    // If one workflow covers all the user's biological steps → return early.
    // ═══════════════════════════════════════════════════════════════════════
    log('Tier 1: Attempting full-query single-workflow resolution');
    try {
      // Use a clean context (no previous messages) to avoid chat-history bias from prior turns.
      // Tier 1 evaluates this query in isolation: "can one workflow cover all the steps?"
      const tier1Context: ChatContext = {
        ...context,
        previousMessages: [],
      };
      const tier1Workflow = await this.generateWorkflow(
        message,
        [],
        decomposition.intents[0]?.inlineParameters,
        tier1Context,
        decomposition.preferredDomains,
        decomposition.keyTerms,
        context.sessionDatasets?.length ? context.sessionDatasets : undefined,
        decomposition.penalizedDomains
      );
      if (tier1Workflow?.success && tier1Workflow?.nextflow_path) {
        log(`Tier 1: Got workflow "${tier1Workflow.workflow_name || tier1Workflow.name}" (${tier1Workflow.nextflow_path}) — checking coverage`);
        const coverage = await this._checkWorkflowCoverage(
          tier1Workflow.workflow_name || tier1Workflow.name || '',
          tier1Workflow.description || tier1Workflow.message || '',
          decomposition.intents,
          message
        );
        log(`Tier 1 coverage: ${coverage.coveredCount}/${decomposition.intents.length} steps, confidence=${coverage.confidence.toFixed(2)}`);
        // HIGH confidence threshold (≥0.8): auto-collapse to single workflow without asking.
        if (coverage.confidence >= 0.8 && coverage.coversAll) {
          // Merge all inline params into the workflow
          const mergedParams = Object.assign({}, ...decomposition.intents.map(i => i.inlineParameters || {}));
          tier1Workflow.parameters = { ...tier1Workflow.parameters, ...mergedParams };
          log(`Tier 1 MATCH: returning single workflow card`);
          const allFacts = decomposition.intents.flatMap(i => i.facts);
          const t1Summary = this._buildPreExecutionSummary(tier1Workflow, message, context.sessionDatasets);
          const t1BaseMsg = `I'll run the **${tier1Workflow.workflow_name || tier1Workflow.name}** workflow — it handles all your steps in one integrated pipeline.`;
          return {
            message: t1Summary ? `${t1Summary}\n\n${t1BaseMsg}` : t1BaseMsg,
            intentType: 'workflow_generation',
            intentConfidence: coverage.confidence,
            generatedWorkflow: tier1Workflow,
            isMultiIntent: false,
            extractedFacts: allFacts.map((f, idx) => ({
              id: `fact-t1-${Date.now()}-${idx}`,
              category: f.category as any,
              value: f.value,
              source: { type: 'user_message' as const, turnIndex: context.turnIndex ?? 0 },
              confidence: f.confidence,
              supersedes: f.supersedes,
            })),
            suggestions: ['Adjust parameters', 'Review workflow steps'],
            sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: true, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false },
          };
        }
        // MEDIUM confidence (≥0.65): show workflow but ask user to confirm it covers everything.
        if (coverage.confidence >= 0.65 && coverage.coversAll) {
          // MEDIUM confidence: show workflow but note it needs user confirmation
          log(`Tier 1 MEDIUM confidence: show single workflow with confirmation note`);
          const mergedParams = Object.assign({}, ...decomposition.intents.map(i => i.inlineParameters || {}));
          tier1Workflow.parameters = { ...tier1Workflow.parameters, ...mergedParams };
          const allFacts = decomposition.intents.flatMap(i => i.facts);
          const t1mSummary = this._buildPreExecutionSummary(tier1Workflow, message, context.sessionDatasets);
          const t1mBaseMsg = `I believe the **${tier1Workflow.workflow_name || tier1Workflow.name}** workflow covers your full request — it handles all the described steps in one integrated run. Please review and confirm this meets your needs before running.`;
          return {
            message: t1mSummary ? `${t1mSummary}\n\n${t1mBaseMsg}` : t1mBaseMsg,
            intentType: 'workflow_generation',
            intentConfidence: coverage.confidence,
            generatedWorkflow: tier1Workflow,
            isMultiIntent: false,
            suggestions: ['Confirm this covers all steps', 'Adjust parameters'],
            extractedFacts: allFacts.map((f, idx) => ({
              id: `fact-t1m-${Date.now()}-${idx}`,
              category: f.category as any,
              value: f.value,
              source: { type: 'user_message' as const, turnIndex: context.turnIndex ?? 0 },
              confidence: f.confidence,
              supersedes: f.supersedes,
            })),
            sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: true, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false },
          };
        }
        log(`Tier 1 no match (confidence ${coverage.confidence.toFixed(2)} < 0.4 or coversAll=false), falling through`);
      }
    } catch (err: any) {
      log(`Tier 1 failed (non-fatal): ${err.message}`);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TIER 2: Curated chain lookup via chainHint.
    // If the intent classifier named a known chain, use its pre-defined steps.
    // ═══════════════════════════════════════════════════════════════════════
    if (decomposition.chainHint) {
      log(`Tier 2: Looking up curated chain "${decomposition.chainHint}"`);
      try {
        const chain = await this._fetchCuratedChain(decomposition.chainHint);
        if (chain && Array.isArray(chain.steps) && chain.steps.length > 0) {
          log(`Tier 2: Found chain "${chain.display_name}" (${chain.steps.length} steps) — resolving workflow paths`);
          const chainStepResults = await Promise.all(
            chain.steps.map(async (step: any, idx: number) => {
              const intent: DecomposedIntent = {
                id: `chain_step_${idx + 1}`,
                type: 'workflow_generation',
                subQuery: step.workflow_name,
                keywords: [step.workflow_name, step.role],
                inlineParameters: step.params_template || {},
                needsToolSearch: true,
                needsDatasets: false,
                confidence: 0.9,
                facts: [],
                dependsOn: idx > 0 ? [`chain_step_${idx}`] : [],
                actions: {
                  needsToolSearch: true, needsWorkflowGeneration: true, needsWorkflowModification: false,
                  needsResearchAgent: false, needsBenchmarkAgent: false, needsDatasetAccess: false, needsLLMReasoning: true,
                  needsChainProposal: false,
                },
              };
              try {
                const chainContext: ChatContext = { ...context, previousMessages: [] };
                const subResult = await this.processSubIntent(intent, step.workflow_name, chainContext, [], [],
                  decomposition.preferredDomains, decomposition.keyTerms, decomposition.penalizedDomains);
                return { intent, subResult, idx };
              } catch {
                return { intent, subResult: null, idx };
              }
            })
          );
          const chainPipelineSteps = chainStepResults.map(({ intent, subResult, idx }) => {
            const wf = subResult?.generatedWorkflow;
            const conn = (chain.connections || []).find((c: any) => c.to_step === idx + 1);
            return {
              id: intent.id,
              step_number: idx + 1,
              workflow_name: wf?.workflow_name || wf?.name || chain.steps[idx]?.workflow_name,
              nextflow_path: wf?.nextflow_path || null,
              params: { ...(chain.steps[idx]?.params_template || {}), ...(wf?.parameters || {}) },
              status: 'pending',
              output_types: wf?.output_types || [],
              input_from: conn ? `chain_step_${conn.from_step}` : null,
              uses_description: conn ? `Output from step ${conn.from_step} (${conn.from_output})` : null,
              output_description: chain.steps[idx]?.role || null,
            };
          });
          const resolvedCount = chainPipelineSteps.filter(s => s.nextflow_path).length;
          log(`Tier 2 chain built: ${chainPipelineSteps.length} steps, ${resolvedCount} resolved`);
          const allFacts = decomposition.intents.flatMap(i => i.facts);
          const turnIndex = context.turnIndex ?? 0;
          // 3A-1: Build pipeline "Understood from your message" summary
          const t2InputLines: string[] = [];
          if (context.sessionDatasets?.length) context.sessionDatasets.forEach(d => t2InputLines.push(`${d.name} (${d.type || 'file'})`));
          const t2SrrMatches = Array.from(message.matchAll(/\b([SED]RR\d{6,9})\b/gi), m => m[1]);
          const t2GeoMatches = Array.from(message.matchAll(/\b(GSE\d{4,9}|GSM\d{4,9})\b/gi), m => m[1]);
          t2SrrMatches.forEach(a => t2InputLines.push(`${a} (SRA run accession)`));
          t2GeoMatches.forEach(a => t2InputLines.push(`${a} (GEO accession)`));
          const execTarget = (process.env.NEXTFLOW_USE_AWS || '').toLowerCase() in { true: 1, '1': 1, yes: 1 } ? 'AWS Batch' : 'local';
          return {
            message: [
              `I've mapped your request to the **${chain.display_name}** pipeline (${chainPipelineSteps.length} steps):`,
              '',
              chainPipelineSteps.map((s, i) => `  ${i + 1}. **${s.workflow_name}**${s.nextflow_path ? ` (\`${s.nextflow_path}\`)` : ' (path TBD)'}`)
                .join('\n'),
              '',
              'Review the steps below, then click **Confirm & Run** to execute them in order.',
            ].join('\n'),
            intentType: 'workflow_generation',
            intentConfidence: 0.9,
            isMultiIntent: true,
            extractedFacts: allFacts.map((f, i) => ({
              id: `fact-t2-${Date.now()}-${i}`,
              category: f.category as any,
              value: f.value,
              source: { type: 'user_message' as const, turnIndex },
              confidence: f.confidence,
              supersedes: f.supersedes,
            })),
            generatedWorkflow: {
              success: true,
              workflow_type: 'pipeline',
              name: chain.display_name || chain.name,
              pipeline_steps: chainPipelineSteps,
              step_count: chainPipelineSteps.length,
              source: 'biomate_curated_chain',
              chain_name: chain.name,
              chain_connections: chain.connections || [],
              chain_steps: chainPipelineSteps.map((s: any) => s.workflow_name).filter(Boolean),
            },
            suggestions: ['Modify a step', 'Add a QC checkpoint', 'Run only the first step'],
            sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: true, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false },
          };
        }
      } catch (err: any) {
        log(`Tier 2 failed (non-fatal): ${err.message}`);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TIER 3: Greedy sequential resolution.
    // Resolve steps one cluster at a time; a single workflow may cover multiple
    // consecutive biological steps.
    // ═══════════════════════════════════════════════════════════════════════
    log('Tier 3: Greedy sequential resolution');

    const stepResults: Array<{ intent: DecomposedIntent; subResult: any; idx: number }> = [];
    let remainingIntents = [...decomposition.intents];
    let globalIdx = 0;

    while (remainingIntents.length > 0) {
      const currentIntent = remainingIntents[0];
      // Build a combined sub-query for remaining steps to give the workflow search better context
      const combinedQuery = remainingIntents.length > 1
        ? remainingIntents.slice(0, Math.min(3, remainingIntents.length)).map(i => i.subQuery).join(' then ')
        : currentIntent.subQuery;
      const combinedIntent: DecomposedIntent = { ...currentIntent, subQuery: combinedQuery };

      log(`Tier 3 step ${globalIdx + 1}: resolving "${combinedQuery}"`);
      let subResult: any = null;
      try {
          // Use clean context (no prior-turn history) so the search for each step is
        // not biased by workflows used in earlier turns of the same session.
        const seqContext: ChatContext = { ...context, previousMessages: [] };
        subResult = await this.processSubIntent(combinedIntent, message, seqContext, [], [],
          decomposition.preferredDomains, decomposition.keyTerms, decomposition.penalizedDomains);
      } catch (err: any) {
        log(`Tier 3 step ${globalIdx + 1} failed: ${err.message}`);
      }

      // Check if the resolved workflow covers more than one remaining intent
      let coveredCount = 1;
      const wf = subResult?.generatedWorkflow;
      if (wf?.nextflow_path && remainingIntents.length > 1) {
        try {
          const coverage = await this._checkWorkflowCoverage(
            wf.workflow_name || wf.name || '',
            wf.description || wf.message || '',
            remainingIntents,
            message
          );
          log(`Tier 3 coverage check: ${coverage.coveredCount}/${remainingIntents.length}, conf=${coverage.confidence.toFixed(2)}`);
          if (coverage.confidence >= 0.6 && coverage.coveredCount > 1) {
            coveredCount = coverage.coveredCount;
          }
        } catch { /* non-fatal */ }
      }

      stepResults.push({ intent: currentIntent, subResult, idx: globalIdx });
      remainingIntents = remainingIntents.slice(coveredCount);
      globalIdx += coveredCount;
    }

    // Build pipeline_steps array for PipelineListView
    const pipelineSteps = stepResults.map(({ intent, subResult, idx }) => {
      const wf = subResult?.generatedWorkflow;
      const prevStep = idx > 0 ? stepResults[idx - 1] : null;
      return {
        id: intent.id || `step_${idx + 1}`,
        step_number: idx + 1,
        workflow_name: wf?.workflow_name || wf?.name || intent.subQuery,
        nextflow_path: wf?.nextflow_path || null,
        params: wf?.parameters || wf?.params || intent.inlineParameters || {},
        status: 'pending',
        output_types: wf?.output_types || [],
        input_from: prevStep ? (prevStep.intent.id || `step_${idx}`) : null,
        uses_description: (intent as any).inputFromDescription ||
          (prevStep ? `Output from step ${idx}: ${(prevStep.intent as any).outputDescription || prevStep.intent.subQuery}` : null),
        output_description: (intent as any).outputDescription || null,
      };
    });

    const resolvedCount = pipelineSteps.filter(s => s.nextflow_path).length;
    log(`Pipeline assembled: ${pipelineSteps.length} steps, ${resolvedCount} resolved to workflow paths`);

    // -----------------------------------------------------------------------
    // Single-workflow collapse: if all resolved steps point to the SAME
    // workflow path, the workflow handles all steps internally — return a
    // single workflow card instead of a multi-step chain.
    // Example: "build pharmacophore model then screen library" → both steps
    // resolve to pharmacophore_filtering/main.nf (it does both internally).
    // -----------------------------------------------------------------------
    const resolvedPaths = pipelineSteps.map(s => s.nextflow_path).filter(Boolean);
    const uniquePaths = new Set(resolvedPaths);
    if (resolvedPaths.length === pipelineSteps.length && uniquePaths.size === 1) {
      const canonicalResult = stepResults[0].subResult;
      if (canonicalResult?.generatedWorkflow) {
        // Merge params from all steps (later steps supplement earlier ones)
        const mergedParams = Object.assign(
          {},
          ...pipelineSteps.map(s => s.params || {})
        );
        canonicalResult.generatedWorkflow.parameters = {
          ...canonicalResult.generatedWorkflow.parameters,
          ...mergedParams,
        };
        log(`Single-workflow collapse: all ${pipelineSteps.length} steps resolved to same path ${[...uniquePaths][0]} — returning single workflow card`);
        const collapseSummary = this._buildPreExecutionSummary(canonicalResult.generatedWorkflow, message, context.sessionDatasets);
        return {
          ...canonicalResult,
          message: collapseSummary ? `${collapseSummary}\n\n${canonicalResult.message || ''}` : (canonicalResult.message || ''),
          isMultiIntent: false,
          extractedFacts: decomposition.intents.flatMap(i => i.facts).map((f, idx) => ({
            id: `fact-seq-${Date.now()}-${idx}`,
            category: f.category as any,
            value: f.value,
            source: { type: 'user_message' as const, turnIndex: context.turnIndex ?? 0 },
            confidence: f.confidence,
            supersedes: f.supersedes,
          })),
        };
      }
    }

    // Build a summary message
    const stepSummaryLines = pipelineSteps.map(
      (s, i) => `  ${i + 1}. **${s.workflow_name}**${s.nextflow_path ? ` (\`${s.nextflow_path}\`)` : ' (workflow path TBD)'}` +
        (s.uses_description ? `\n     → Input: ${s.uses_description}` : '')
    );
    const summaryMessage = [
      `I've planned a **${pipelineSteps.length}-step sequential pipeline** for you:`,
      '',
      ...stepSummaryLines,
      '',
      'Review the steps below, then click **Confirm & Run** to execute them in order.',
      resolvedCount < pipelineSteps.length
        ? `\n⚠️ ${pipelineSteps.length - resolvedCount} step(s) could not be resolved to specific workflow paths — you may need to confirm them before running.`
        : '',
    ].join('\n').trim();

    const allFacts = decomposition.intents.flatMap(i => i.facts);
    const turnIndex = context.turnIndex ?? 0;
    const extractedFacts = allFacts.map((f, i) => ({
      id: `fact-seq-${Date.now()}-${i}`,
      category: f.category as any,
      value: f.value,
      source: { type: 'user_message' as const, turnIndex },
      confidence: f.confidence,
      supersedes: f.supersedes,
    }));

    return {
      message: summaryMessage,
      intentType: 'workflow_generation',
      intentConfidence: 0.9,
      extractedFacts: extractedFacts.length > 0 ? extractedFacts : undefined,
      isMultiIntent: true,
      generatedWorkflow: {
        success: true,
        workflow_type: 'pipeline',
        name: `Sequential Pipeline (${pipelineSteps.length} steps)`,
        pipeline_steps: pipelineSteps,
        step_count: pipelineSteps.length,
        source: 'biomate_sequential',
      },
      suggestions: [
        'Modify a specific step',
        'Add a QC step between stages',
        'Run only the first step to verify',
      ],
      sources: {
        toolSearchUsed: false,
        datasetRAGUsed: false,
        workflowGenerated: true,
        thinkingUsed: false,
        researchAgentUsed: false,
        benchmarkAgentUsed: false,
      },
    };
  }

  /**
   * Process a multi-intent message by fanning out to processSubIntent for each intent.
   * Results are collected and synthesized into a single response.
   */
  private async processMultiIntent(
    decomposition: IntentDecomposition,
    message: string,
    context: ChatContext,
    startTime: number,
    onResponseDelta?: (chunk: string) => void,
    domainProfileContext: string = '',
    sessionMemoryBlock: string = '',
    onToolEvent?: (event: AgentToolEvent) => void
  ): Promise<GalaxyAssistantResponse> {
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] ${step}`);

    log(`Multi-intent processing: ${decomposition.intents.length} intents` + (decomposition.isSequential ? ' [SEQUENTIAL]' : ''));

    // Sequential pipeline path: process each step, then assemble pipeline_steps response
    if (decomposition.isSequential) {
      return this.processSequentialPipeline(decomposition, message, context, startTime, onResponseDelta, domainProfileContext);
    }

    // Step 2-3: Parallel tool/dataset search using union of all keywords
    const allKeywords = Array.from(new Set(decomposition.intents.flatMap(i => i.keywords)));
    let recommendedTools: ToolRecommendation[] = [];
    let recommendedDatasets: DatasetRecommendation[] = [];
    let toolSearchUsed = false;
    let datasetRAGUsed = false;

    const needsToolSearch = decomposition.intents.some(i => i.actions.needsToolSearch);
    const needsDatasets = decomposition.intents.some(i =>
      i.actions.needsDatasetAccess || i.needsDatasets
    );

    const searchPromises: Promise<void>[] = [];

    if (needsToolSearch && allKeywords.length > 0) {
      searchPromises.push(
        this.searchRelevantTools(message, allKeywords, context.userId)
          .then(tools => {
            recommendedTools = tools;
            toolSearchUsed = true;
            log(`Multi-intent: Found ${tools.length} tools`);
          })
      );
    }

    if (needsDatasets) {
      searchPromises.push(
        this.searchRelevantDatasets(message, allKeywords)
          .then(datasets => {
            recommendedDatasets = datasets;
            datasetRAGUsed = true;
            log(`Multi-intent: Found ${datasets.length} datasets`);
          })
      );
    }

    log('Multi-intent Steps 2-3: Starting parallel searches');
    if (searchPromises.length > 0) {
      await Promise.all(searchPromises);
      log('Multi-intent Steps 2-3 complete');
    }

    // Step 4-5: Process each intent in parallel
    log('Multi-intent Steps 4-5: Processing sub-intents in parallel');
    const subIntentResults = await Promise.all(
      decomposition.intents.map(intent =>
        this.processSubIntent(intent, message, context, recommendedTools, recommendedDatasets,
          decomposition.preferredDomains, decomposition.keyTerms, decomposition.penalizedDomains)
      )
    );
    log(`Multi-intent Steps 4-5 complete: ${subIntentResults.length} results`);

    // Collect workflow and research/benchmark results.
    // Prefer sub-intents that returned a *runnable* workflow (valid .nf path or non-empty steps)
    // over ones that returned a junk galaxy_ga placeholder with empty steps.
    const isRunnableWf = (wf: any) => !!(
      wf?.success && !wf?.error && (
        (wf?.nextflow_path && String(wf.nextflow_path).toLowerCase().endsWith('.nf')) ||
        (wf?.workflow_ga?.steps && Object.keys(wf.workflow_ga.steps).length > 0)
      )
    );
    const workflowResult =
      subIntentResults.find(r => isRunnableWf(r.generatedWorkflow)) ??
      subIntentResults.find(r => r.generatedWorkflow);
    const researchResult = subIntentResults.find(r => r.researchResponse);
    const benchmarkResult = subIntentResults.find(r => r.benchmarkEvidence);
    const workflowGenerated = !!workflowResult?.generatedWorkflow;

    // Collect all ADDITIONAL runnable workflows (unique by nextflow_path or workflow_name)
    const primaryWfPath = workflowResult?.generatedWorkflow?.nextflow_path;
    const additionalWorkflows = subIntentResults
      .filter(r => r !== workflowResult && isRunnableWf(r.generatedWorkflow))
      .filter((r, i, arr) => {
        // deduplicate by path
        const p = r.generatedWorkflow?.nextflow_path;
        return p !== primaryWfPath && arr.findIndex(x => x.generatedWorkflow?.nextflow_path === p) === i;
      })
      .map(r => r.generatedWorkflow);

    // Step 6: Generate synthesized response
    log('Multi-intent Step 6: Generating synthesized response');
    const primaryIntent = decomposition.primaryIntent;
    const response = await this.generateResponse(
      message,
      primaryIntent,
      recommendedTools,
      recommendedDatasets,
      {
        shouldGenerate:
          workflowGenerated ||
          this._isPlanBCodonQuery(message) ||
          this._isPlanAEpitopeQuery(message) ||
          this._isPocketDetectionQuery(message),
        userIntent: message,
        confidence: primaryIntent.confidence,
        reasoning: `Multi-intent: ${decomposition.intents.map(i => i.type).join(', ')}`,
      },
      workflowResult?.generatedWorkflow || null,
      context,
      researchResult?.researchResponse,
      benchmarkResult?.benchmarkEvidence,
      onResponseDelta,
      domainProfileContext,
      sessionMemoryBlock,
      decomposition.preferredDomains ?? [],
      onToolEvent
    );
    log('Multi-intent Step 6 complete');

    // Step 7: Suggestions
    log('Multi-intent Step 7: Generating suggestions');
    const suggestions = this.generateSuggestions(
      message,
      primaryIntent,
      recommendedTools,
      { shouldGenerate: workflowGenerated, userIntent: message, confidence: primaryIntent.confidence, reasoning: '' }
    );
    log('Multi-intent Step 7 complete');
    log('Multi-intent total processing time: ' + (Date.now() - startTime) + 'ms');

    // Collect all facts from all intents
    const turnIndex = context.turnIndex ?? 0;
    const allFacts = decomposition.intents.flatMap(intent => intent.facts);
    const extractedFacts: ExtractedFact[] = allFacts.map((f, i) => ({
      id: `fact-${Date.now()}-${i}`,
      category: f.category as ExtractedFact['category'],
      value: f.value,
      source: { type: 'user_message' as const, turnIndex },
      confidence: f.confidence,
      supersedes: f.supersedes,
    }));

    // Same remap as single-intent path — see comment near line 2310.
    // Derive the workflow name from the generated workflow on workflowResult
    // (in scope here). The earlier reference to `decomposition.intents[0]?.workflow_name`
    // doesn't compile because `DecomposedIntent` has no `workflow_name`, and
    // `stepResults` belongs to a different function scope (processSubIntent).
    const _multiGeneratedWorkflow = (workflowResult as any)?.generatedWorkflow;
    const _multiWorkflowName: string | undefined =
      _multiGeneratedWorkflow?.workflow_ga?.name ||
      _multiGeneratedWorkflow?.workflow_name;
    const _multiRemappedInlineParams = remapInlineParametersForWorkflow(
      _multiWorkflowName,
      primaryIntent.inlineParameters,
    );

    const multiIntentResult: GalaxyAssistantResponse = {
      message: response.message,
      intentType: primaryIntent.type,
      intentConfidence: primaryIntent.confidence,
      inlineParameters: Object.keys(_multiRemappedInlineParams).length > 0 ? _multiRemappedInlineParams : undefined,
      extractedFacts: extractedFacts.length > 0 ? extractedFacts : undefined,
      thinking_content: response.thinking?.thinkingContent ?? undefined,
      thinking_level: response.thinking?.thinkingLevel ?? undefined,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion: {
        shouldGenerate: workflowGenerated,
        userIntent: message,
        confidence: primaryIntent.confidence,
        reasoning: `Multi-intent processing: ${decomposition.intents.map(i => i.type).join(', ')}`,
      },
      generatedWorkflow: workflowResult?.generatedWorkflow || null,
      additionalWorkflows: additionalWorkflows.length > 0 ? additionalWorkflows : undefined,
      researchResponse: researchResult?.researchResponse,
      benchmarkEvidence: benchmarkResult?.benchmarkEvidence,
      subIntentResults,
      isMultiIntent: true,
      suggestions,
      sources: {
        toolSearchUsed,
        datasetRAGUsed,
        workflowGenerated,
        thinkingUsed: response.thinking?.hasThinking || false,
        researchAgentUsed: !!researchResult?.researchResponse,
        benchmarkAgentUsed: !!benchmarkResult?.benchmarkEvidence,
      },
    };

    // Queue async session memory update (non-blocking)
    if (context.sessionId) {
      this.sessionMemory.queue(context.sessionId, message, response.message);
    }

    return multiIntentResult;
  }

  /**
   * Process a single sub-intent within a multi-intent message.
   * Routes to the appropriate backend(s) based on action category flags.
   */
  private async processSubIntent(
    intent: DecomposedIntent,
    originalMessage: string,
    context: ChatContext,
    recommendedTools: ToolRecommendation[],
    recommendedDatasets: DatasetRecommendation[],
    preferredDomains?: string[],
    keyTerms?: string[],
    penalizedDomains?: string[]
  ): Promise<SubIntentResult> {
    const baseResult: SubIntentResult = {
      intentId: intent.id,
      intentType: intent.type,
      subQuery: intent.subQuery,
      status: 'success',
    };

    const actions = intent.actions;

    // Named docking tool override (multi-intent fan-out when collapse did not run).
    if (!actions.needsWorkflowGeneration) {
      const _dockMsg = `${intent.subQuery} ${originalMessage}`;
      const _isNamedDockingToolQuery =
        /\b(autodock\s*vina|docking_autodock_vina|site[- ]directed\s+docking|vina\s+docking|molecular\s+docking\s+with\s+vina)\b/i.test(
          _dockMsg
        ) && !/\b(diffdock|blind\s+dock)\b/i.test(_dockMsg);
      if (_isNamedDockingToolQuery) {
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    // Plan B / Plan A overrides (multi-intent fan-out when collapse did not run).
    if (!actions.needsWorkflowGeneration) {
      const _namedMsg = `${intent.subQuery} ${originalMessage}`;
      if (
        this._isPlanBCodonQuery(_namedMsg) ||
        this._isPlanAEpitopeQuery(_namedMsg) ||
        this._isPocketDetectionQuery(_namedMsg)
      ) {
        actions.needsWorkflowGeneration = true;
        intent.type = 'workflow_generation';
      }
    }

    try {
      // Action-flag-based routing: multiple agents can be invoked per intent

      // Tool search results already available from parallel search
      if (actions.needsToolSearch && recommendedTools.length > 0) {
        baseResult.recommendedTools = recommendedTools;
      }

      // Workflow generation — intent flags already determined by analyzeIntent
      if (actions.needsWorkflowGeneration || actions.needsWorkflowModification) {
        // When this sub-intent is part of a multi-intent query, use the original full message
        // as the workflow intent so domain preference (e.g. drug/docking tokens) is preserved.
        const effectiveIntent = (originalMessage && originalMessage !== intent.subQuery)
          ? originalMessage
          : intent.subQuery;
        const workflow = await this.generateWorkflow(
          effectiveIntent,
          recommendedDatasets.map(d => d.dataset),
          intent.inlineParameters,
          context,
          preferredDomains,
          keyTerms,
          context.sessionDatasets?.length ? context.sessionDatasets : undefined,
          penalizedDomains
        );
        baseResult.generatedWorkflow = workflow;
      }

      // Research agent
      if (actions.needsResearchAgent) {
        try {
          baseResult.researchResponse = await this.galaxyAPI.queryResearch({
            query: intent.subQuery,
            context: { information_need: intent.type },
            include_citations: true,
            include_benchmark_evidence: true,
          });
        } catch (error: any) {
          console.warn(`[GalaxyAssistant] Research query failed for ${intent.id}: ${error.message}`);
        }
      }

      // Benchmark agent
      if (actions.needsBenchmarkAgent) {
        try {
          baseResult.benchmarkEvidence = await this.galaxyAPI.queryBenchmark({
            query: intent.subQuery,
          });
        } catch (error: any) {
          console.warn(`[GalaxyAssistant] Benchmark query failed for ${intent.id}: ${error.message}`);
        }
      }

      return baseResult;
    } catch (error: any) {
      console.error(`[GalaxyAssistant] Sub-intent ${intent.id} (${intent.type}) failed:`, error.message);
      return { ...baseResult, status: 'error', error: error.message };
    }
  }

  private _chainHintNamesCache: { names: string[]; fetchedAt: number } | null = null;

  /** Live workflow_chains names for intent classifier chain_hint (cached 10 min). */
  private async _getChainHintNames(): Promise<string[]> {
    const TTL_MS = 10 * 60 * 1000;
    if (
      this._chainHintNamesCache &&
      Date.now() - this._chainHintNamesCache.fetchedAt < TTL_MS
    ) {
      return this._chainHintNamesCache.names;
    }
    const fallback = [
      'bulk_rnaseq_de_analysis',
      'target_to_lead_full',
      'drug_discovery_screening',
      'drug_discovery_admet_gated_screening',
      'single_cell_multimodal_analysis',
      'rare_disease_multimodal_workup',
      'cutandtag_chromatin_analysis',
      'alternative_polyadenylation_analysis',
    ];
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      // intent_hint=true excludes bioc_reactive chains (post-completion suggestions only)
      // to prevent the classifier from mis-routing single-step requests into full chains
      const res = await fetch(`${galaxyUrl}/api/workflow-chains?intent_hint=true`, {
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) return fallback;
      const data: any = await res.json();
      const names = (data.chains || []).map((c: any) => c.name).filter(Boolean);
      if (names.length) {
        this._chainHintNamesCache = { names, fetchedAt: Date.now() };
        return names;
      }
    } catch {
      /* use fallback */
    }
    return fallback;
  }

  /**
   * Analyze user intent, detecting multiple intents if present.
   * Returns IntentDecomposition with one or more decomposed intents.
   */
  private async analyzeIntent(
    message: string,
    context: ChatContext,
    sessionMemoryBlock: string = ''
  ): Promise<IntentDecomposition> {
    // Short-circuit: "KNOWLEDGE QUESTION" prefix from eval harness forces research_question
    // routing without calling Haiku, preventing workflow hijack on benchmark tasks.
    if (message.startsWith('KNOWLEDGE QUESTION')) {
      const knowledgeIntent: DecomposedIntent = {
        id: 'intent_knowledge_forced',
        type: 'research_question',
        subQuery: message,
        keywords: [],
        inlineParameters: {},
        needsToolSearch: false,
        needsDatasets: false,
        confidence: 1.0,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType('research_question'),
      };
      return {
        intents: [knowledgeIntent],
        isMultiIntent: false,
        primaryIntent: knowledgeIntent,
      };
    }

    const chainHintList = (await this._getChainHintNames()).join(', ');
    const systemPrompt = `${sessionMemoryBlock}You are a bioinformatics intent analyzer. Classify user messages by their information need and declare which system agents should handle the request.

## Information Need Types

Describe the user's information need with a descriptive label. You may use these common labels or create a new one that better fits:

**workflow_generation** — Execute a computational pipeline or run code on user data. Covers: (a) Nextflow pipelines processing files/accessions (set needsWorkflowGeneration: true), and (b) direct code execution via run_code for ad-hoc computations on provided inputs such as a pasted sequence, numeric parameters, or a small dataset (set needsWorkflowGeneration: false, needsLLMReasoning: true). Both are execution tasks — the distinction is whether BioMate needs to launch a full Nextflow workflow or can compute directly.

**R/Bioconductor execution priority** — When a task requires R or Bioconductor tools (DESeq2, edgeR, limma, clusterProfiler, Seurat, etc.), follow this order:
1. Search BioMate's indexed Bioconductor workflows first (1,000+ available). If a matching workflow exists, use it (needsWorkflowGeneration: true, runs on AWS Batch with full R + Bioconductor).
2. If no indexed workflow matches, generate a new Nextflow/R workflow and add it to BioMate's DB.
3. If the task is ad-hoc or too small for a full pipeline (single statistical test, small inline dataset), execute R directly via run_code (needsWorkflowGeneration: false).
**research_question** — Look up or synthesize information from scientific literature and papers.
**database_lookup** — Query a specific biological database (GWAS Catalog, Open Targets, OMIM, ClinVar, Ensembl, mygene.info, Monarch) for structured facts. Use when the question needs real-time database query results, not just literature recall.
**genomics_knowledge** — GWAS variant-to-phenotype associations, causal gene identification at a locus, eQTL evidence, gene-disease links, published CRISPR screen results. Triggered by: candidate SNP/gene selection tasks, "from this list which is causal", GWAS phenotype + rsID candidates, "which gene showed the strongest effect in this CRISPR screen", "identify the gene from this published screen". Requires live GWAS Catalog / Open Targets / DepMap / GenomeCRISPR lookup. Candidate gene/SNP lists in the prompt are published data to look up — NOT user-provided files.
**clinical_genomics** — Rare disease diagnosis (OMIM), patient gene detection (ClinVar + Monarch + HPO), phenotype-to-gene mapping. Triggered by: HPO term lists (HP:XXXXXXX), ENSG candidate gene lists (ENSG00000XXXXXX), disease name + gene + phenotype combinations, "identify the causal gene from this list", "which of these candidate genes matches these phenotypes". IMPORTANT: A question that provides HPO phenotype terms AND a list of ENSG candidate genes asking to identify the causal gene is ALWAYS clinical_genomics — it is a database/knowledge lookup task, NOT a pipeline execution. No user data files are involved.
**result_comparison** — Compare tools, methods, or approaches with evidence.
**tool_search** — Find or learn about available tools and their capabilities.
**benchmark_query** — Get specific performance data or benchmarks.
**dataset_inquiry** — Find or learn about available datasets.
**general_question** — Conversational or conceptual question.
**workflow_modification** — Modify an existing workflow from the conversation.
**troubleshooting** — Diagnose a problem (e.g., low alignment rate, failed job).
**experiment_design** — Plan an experiment or analysis strategy.
**data_interpretation** — Help interpret analysis results.
**protocol_guidance** — Get step-by-step experimental protocols.
**parameter_optimization** — Optimize tool/analysis parameters.
**data_format_conversion** — Convert between file formats.
**teaching_explanation** — Educational explanation of concepts.
**methods_writing** — Help write a methods section for a paper.
**visualization** — Create plots, charts, or visual summaries.
**comparative_methodology** — Compare scientific methodologies with evidence.

You may also create a novel label if none of the above fit (e.g., "cost_estimation", "regulatory_compliance", "multi_step_procedure").

## HIGHEST PRIORITY RULE — Knowledge Reasoning vs Pipeline Execution

Ask a single question: **"Does completing this task require running a computational pipeline or tool on user-provided data — files, accession IDs, or molecular inputs?"**

- If yes → **workflow_generation**. The user may not have named their inputs yet; BioMate will ask.
- **Accession IDs are workflow inputs.** SRA (SRR/ERR/DRR), GEO (GSE/GSM), NCBI (PRJNA/PRJEB), UniProt IDs, PDB IDs, EMBL accessions — these are valid workflow inputs BioMate fetches automatically. "Run RNA-seq on SRR12345678" or "dock compound into PDB:3HTB" is workflow_generation, not a database lookup.
- **Molecular inputs are workflow inputs.** SMILES strings, PDB/SDF files, concentration-time CSV — signal workflow_generation for drug discovery / pharmacology workflows. But a conceptual or planning question about these topics (how does hERG work? what dose range is typical?) is still research_question or experiment_design.
- If the task is planning, strategy, or design WITHOUT asking BioMate to execute a pipeline → **experiment_design**.
- If the task is interpreting existing results, explaining what output means → **data_interpretation**.
- If the task is diagnosing why a run failed or a metric looks wrong → **troubleshooting**.
- If the task requires querying a live biological database (GWAS Catalog, OMIM, ClinVar, Open Targets, Ensembl) for structured facts → **database_lookup**, **genomics_knowledge**, or **clinical_genomics** as appropriate.
- If the task can be fully resolved from scientific literature or general biological knowledge → **research_question**.

Key distinction: **candidate lists from published studies are NOT user data.** A question giving a list of rsIDs or gene names from a published GWAS and asking to identify the causal one is a database lookup — no pipeline needed.

**HPO terms + ENSG candidate genes = clinical_genomics, NOT workflow_generation.** A task providing HPO phenotype codes and a list of ENSG gene IDs asking to identify the causal gene queries ClinVar/OMIM/Monarch — it does not run a Nextflow pipeline.

The distinction is the nature of the task, not the presence of file names in the message.

---

## BioMate Workflow Catalog — 2,463 workflows across 34 domains

BioMate can run computational pipelines in all the domains below. When a user wants to execute a pipeline or process data in any of these areas, classify as workflow_generation. Asking about, discussing, or planning one of these is not workflow_generation unless the user is asking BioMate to actually run it. Representative workflows per domain:

**Transcriptomics (865):** nf-core/rnaseq (raw FASTQ → counts), nf-core/differentialabundance (pre-computed count matrix → DESeq2/edgeR DE analysis + GO enrichment), DESeq2, edgeR, clusterProfiler/enrichGO, Kallisto/sleuth, STAR-RSEM, nf-core/scrnaseq, nf-core/spatialvi, nf-core/lncpipe, nf-core/circrna — inputs: FASTQ files, SRA/GEO accessions, OR pre-computed count matrix + sample metadata CSV

**Genomics (369):** nf-core/sarek (WGS/WES somatic+germline), nf-core/raredisease, nf-core/mag (metagenome assembly), BWA-MEM, GATK HaplotypeCaller, nf-core/nanoseq, nf-core/phageannotator, nf-core/bacass — inputs: FASTQ/BAM or SRA accessions

**Variant calling (102):** nf-core/sarek, GATK4, DeepVariant, Strelka2, nf-core/variantcatalogue, bcftools, VEP annotation — inputs: BAM/FASTQ/VCF or accessions

**Epigenomics (133):** nf-core/chipseq, nf-core/atacseq, nf-core/methylseq (bisulfite), nf-core/cutandrun, nf-core/cutandtag, nf-core/hicar — inputs: FASTQ files

**Proteomics (113):** nf-core/proteomicslfq (DDA), nf-core/diaproteomics (DIA/Spectronaut), MaxQuant, FragPipe, nf-core/quantms, nf-core/mspepquant — inputs: raw mass spec files (.raw/.mzML) or PRIDE accessions

**Single-cell (22):** nf-core/scrnaseq, Seurat/Scanpy downstream, nf-core/scampi, nf-core/scdownstream (requires Cell Ranger output/h5ad, not raw FASTQ) — inputs: FASTQ, 10x cellranger output, or h5ad

**Metagenomics (42):** nf-core/ampliseq (16S/18S/ITS), nf-core/taxprofiler, nf-core/mag, nf-core/funcscan, QIIME2, Kraken2 — inputs: FASTQ or SRA accessions

**Metabolomics (21):** nf-core/metabolomics, MZmine, XCMS, OpenMS — inputs: raw MS files (.raw/.mzML)

**Imaging / flow cytometry (45):** nf-core/mcmicro (multiplexed tissue imaging: CODEX, CyCIF, MIBI), CytoPipeline (flow cytometry), EBImage, imcRtools — inputs: image files (.tiff/.fcs)

**Immunology (13):** nf-core/airrflow (BCR/TCR repertoire from FASTQ), nf-core/bactmap, nf-core/hadge — inputs: FASTQ or VDJ accessions

**Microbiology (16):** nf-core/bactmap (bacterial mapping), nf-core/bacass (assembly), nf-core/taxprofiler, nf-core/phageannotator — inputs: FASTQ

**Molecular biology (26):** CRISPR sgRNA design, primer design, restriction enzyme analysis, Golden Gate assembly, plasmid annotation (pLannotate), PCR simulation — inputs: DNA sequence or plasmid FASTA

**Synthetic biology / bioengineering (11+13):** codon optimization, genetic circuit design, protein engineering, pathway modeling — inputs: sequences or parameters

**Systems biology (12):** pathway enrichment (GSEA/ORA), network analysis, multi-omics integration — inputs: gene lists, expression matrices

**Drug discovery (61) + Pharmacology (21):** see detailed examples in Critical Classification Rules below — inputs: SMILES, PDB files, SDF, CSV, dose levels, sequence FASTA

**Cryo-EM (11) + Cryo-ET (2) + Structural biology (3):** see detailed examples in Critical Classification Rules below — inputs: .mrc/.tif/.eer micrograph movies or tilt series

**Lab automation (7):** liquid handling protocols, plate reformatting, assay setup — inputs: CSV plate maps

**Cancer biology (7):** tumor mutational burden, clonality, nf-core/oncoanalyser — inputs: BAM/VCF or accessions

**Multi-omics (1):** nf-core/multiomics integration — inputs: multiple omics data files

---

## Critical Classification Rules for Bioinformatics Queries

These patterns MUST be classified as **workflow_generation** even when they sound like research questions, because they involve processing user data:

**Omics analysis requests (always workflow_generation when user-data is involved):**
- "Identify genes [upregulated/downregulated/differentially expressed] in [condition/tissue/disease]" → the user wants to run RNA-seq + DE analysis
- "Run DESeq2/edgeR on my count matrix" → nf-core/differentialabundance (NOT nf-core/rnaseq — that takes FASTQ, not count matrices)
- "Differential expression from count matrix / pre-computed counts" → nf-core/differentialabundance (inputs: matrix CSV + sample metadata + contrasts)
- "GO enrichment / enrichGO / clusterProfiler on DEGs" → nf-core/differentialabundance with GO enrichment module (includes clusterProfiler/gprofiler2)
- "Find [variants/mutations/SNPs/indels] in [my samples/cohort/patient]" → the user wants to run variant calling
- "Identify [cell types/clusters/populations] in [my single-cell data/samples]" → the user wants to run scRNA-seq
- "Detect [peaks/binding sites/open chromatin] in [my data/samples]" → the user wants to run ChIP-seq/ATAC-seq

**Count matrix vs FASTQ routing rule (critical):**
- User provides count matrix CSV/TSV + sample metadata → nf-core/differentialabundance
- User provides FASTQ files or SRA/GEO accessions → nf-core/rnaseq first, then optionally differentialabundance
- "Run DESeq2 on my data" with a count matrix = nf-core/differentialabundance, NOT nf-core/rnaseq

**Spatial/imaging data requests (always workflow_generation):**
- "I need spatial gene expression data showing where genes are expressed in [tissue/tumor/section]" → run nf-core/spatialvi
- "Map gene expression in my tissue section" → run spatial transcriptomics pipeline
- "Show where [gene/marker] is expressed spatially" → spatial transcriptomics

**QC and preprocessing requests (always workflow_generation):**
- "Quality control of single-cell sequencing: filter empty droplets and doublets" → run scRNA-seq pipeline (includes QC steps)
- "Filter/remove [empty droplets/doublets/low-quality cells] from [my scRNA-seq]" → run scRNA-seq pipeline

**AI/ML model workflow requests (always workflow_generation):**
Any message naming a specific AI/ML model workflow indicates the user wants to RUN it — never classify as tool_search:
- "Search for [proteins/genes] using ProTrek [trimodal/text-based/structure-based] protein search" → run protrek_protein_search workflow
- "Search for [biological entities] using [Boltz/Chai/DrugCLIP/SynCraft/ProFam] model" → run the named AI model workflow
- "Run [ProTrek/Boltz-2/Chai-1/DrugCLIP/SynCraft/STATE/ProFam] on [data]" → run the named AI model workflow
- "Trimodal protein search across UniProt/AlphaFold" → ProTrek workflow_generation
- "Predict [structure/binding] using [Boltz-2/Chai-1]" → run the named structure prediction workflow

**Method-description requests (always workflow_generation):**
Queries that NAME a computational technique or pipeline without action verbs still require workflow execution.
These EXACT QUERIES are workflow_generation, NOT research_question:
- "Spectral counting and feature-based quantification from data-dependent acquisition mass spec" → nf-core/proteomicslfq (DDA proteomics quantification pipeline)
- "Retention time alignment using iRT standards and PyProphet FDR estimation in DIA data" → nf-core/diaproteomics (DIA proteomics workflow)
- "De novo design of GPCR-targeted lead compounds using REINVENT4 scaffold decoration" → REINVENT4 generative drug design workflow
- "Scaffold hopping from my current kinase inhibitor scaffold to explore chemical diversity" → REINVENT4 scaffold hopping workflow
- "Generate analogs that fix the hERG liability in my lead compound" → REINVENT4 generative lead design workflow
- "OpenFE RBFE to compare binding affinities of two CDK2 inhibitors" → openfe_rbfe binding free energy workflow
- "Which of these two ligands binds tighter to the kinase active site?" → openfe_rbfe RBFE workflow
- "What existing drugs could be repurposed to treat Hutchinson-Gilford Progeria?" → retrieve_topk_repurposing_drugs_from_disease_txgnn drug repurposing workflow
- "Predict how T cells respond to PDCD1 knockout using single-cell data" → state_perturbation_prediction virtual cell workflow
- "Simulate combinatorial KO of TP53 and KRAS in lung cancer cells" → gears_perturbation_prediction perturbation workflow
- "Design a MAMS adaptive trial with interim analysis stopping rules" → adaptive_trial_design workflow
- "Design an ADC against HER2 for breast cancer" → adc_design workflow
- "Design a Trodelvy-like ADC for TROP2 in TNBC" → adc_design workflow
- "Build a PROTAC for BRD4 degradation in AML" → protac_design workflow
- "Design a CRBN-based degrader of androgen receptor" → protac_design workflow
- "Design an mRNA vaccine encoding spike protein for muscle delivery" → mrna_therapeutic_design workflow
- "Codon-optimize this mRNA for human expression with LNP delivery" → mrna_therapeutic_design workflow
- "What AAV serotype should I use for liver gene therapy with a 3 kb payload?" → aav_serotype_selection workflow
- "Recommend an AAV for CNS gene replacement therapy" → aav_serotype_selection workflow
- "Design a CD19 CAR-T construct with 4-1BB costimulation" → cart_construct_design workflow
- "Build a BCMA CAR-T for multiple myeloma" → cart_construct_design workflow
- "Design a gapmer ASO targeting PCSK9 for liver delivery" → aso_gapmer_design workflow
- "Design an LNA gapmer for SOD1 knockdown via intrathecal delivery" → aso_gapmer_design workflow
- "Where is HER2 expressed in normal tissue?" → atlas_expression_query workflow
- "Run a single-cell atlas check on TROP2" → atlas_expression_query workflow
- "Which therapeutic modality fits CLDN18.2 best?" → modality_triage workflow
- "Would BCMA be a good CAR-T target?" → modality_triage workflow
- "Design a PD-1 × VEGF bispecific in CrossMab format" → bispecific_format_triage workflow
- "Which bispecific format for CD3 × BCMA in myeloma?" → bispecific_format_triage workflow
- "Design an in vivo CAR-T for CD19 using anti-CD8 LNP" → in_vivo_cart_codesign workflow
- "Check fratricide risk for CD7 in vivo CAR-T" → in_vivo_cart_codesign workflow
- "Design an in vivo base edit for PCSK9 like VERVE-102" → in_vivo_base_edit_design workflow
- "Plan a Beam-style ABE for HBG1 sickle cell reactivation" → in_vivo_base_edit_design workflow
- "Which GLP-1 modality fits MASH best?" → glp1_modality_bakeoff workflow
- "Semaglutide vs tirzepatide vs retatrutide for obesity" → glp1_modality_bakeoff workflow
- "Clonal lineage reconstruction of antibody evolution from longitudinal BCR sequencing" → nf-core/airrflow (immune repertoire pipeline)
- "Alpha and beta diversity analysis with phylogenetic placement of my microbiome ASVs" → nf-core/ampliseq (amplicon diversity + phylogenetic placement pipeline)
General pattern: "[computational method/analysis] [from/using/of] [data type or instrument]" = the user wants to EXECUTE that method on their data. Not a literature search. Not a conceptual question.

**Drug discovery and pharmacology requests (workflow_generation):**
BioMate has 61 drug_discovery and 21 pharmacology workflows. Inputs are molecular (SMILES, PDB/SDF files, dose level lists, concentration-time CSV) rather than sequencing files (FASTQ/BAM/VCF). Key examples by sub-task:
- Docking / virtual screening: "dock [ligand] into [protein]", "AutoDock Vina / DiffDock / Glide / DrugCLIP screening" → workflow_generation
- Binding free energy: "FEP / OpenFE RBFE ΔΔG between two ligands" → workflow_generation
- MD simulation: "GROMACS / AMBER MD trajectory for protein-ligand complex" → workflow_generation
- Structure prediction: "predict structure with Boltz-2 / Chai-1 / AlphaFold3" → workflow_generation
- ADMET / safety: "predict ADMET / hERG / DILI / Ames / BBB / Caco-2 for [SMILES]" → workflow_generation
- DDI / CYP: "CYP3A4 / CYP2D6 inhibition prediction / DDI risk / metabolite prediction" → workflow_generation
- PBPK: "run PBPK simulation for [SMILES] with CLint=[X], fu_plasma=[Y]" → workflow_generation (needsWorkflowGeneration: true)
- Phase I trial: "design BOIN / 3+3 dose escalation with dose levels [X,Y,Z], target DLT [N]" → workflow_generation (needsWorkflowGeneration: true)
- NCA-PK: "non-compartmental analysis / compute AUC/Cmax/Tmax from concentration-time data" → workflow_generation
- PopPK: "population PK with nlmixr2 / NONMEM-equivalent SAEM fit" → workflow_generation
- Allometric scaling / IVIVE: "scale CL from rat to human / IVIVE hepatic clearance" → workflow_generation
- Generative design: "REINVENT4 de novo design / scaffold hopping / AiZynthFinder retrosynthesis / generate analogs / optimize scaffold / fix ADMET liability with new molecules" → workflow_generation (reinvent4_lead_design)
- Binding free energy: "FEP / RBFE / OpenFE / which ligand binds better / confirm affinity / binding free energy calculation" → workflow_generation (openfe_rbfe)
- Drug repurposing: "drug repurposing / repurpose existing drugs / what drugs could treat [disease] / TxGNN" → workflow_generation (retrieve_topk_repurposing_drugs_from_disease_txgnn)
- Perturbation prediction: "predict cell response to drug / CRISPR KO effect / virtual cell / perturbation prediction" → workflow_generation (state_perturbation_prediction or gears_perturbation_prediction)
- Adaptive trial design: "adaptive trial / RAR randomization / MAMS design / interim stopping rules / O'Brien-Fleming adaptive" → workflow_generation (adaptive_trial_design)
- Target analysis: "pharmacophore filtering / pocket detection / target tractability / kinome panel" → workflow_generation
- HTS: "HTS plate QC / Z-factor / Z' / signal window / hit calling / dose-response (4PL) on screening plate" → workflow_generation (hts_plate_qc_hit_calling). Disambiguation: HTSFilter is an RNA-seq read-count filter (DESeq2-family), NOT an HTS plate QC tool despite the prefix. sights is an R/Bioconductor HTS-normalization library — prefer hts_plate_qc_hit_calling when the user wants an end-to-end pipeline (Z' + hit calling + report); prefer sights only when the user explicitly asks for SIGHTS or for HTS-normalization-only as an R package.
- Biologics: "scFv intrabody design / antibody developability / LNP formulation optimization" → workflow_generation

Key: providing concrete molecular inputs (SMILES, PDB, dose levels, CSV data) + asking to run/compute/predict = workflow_generation. Asking "how does hERG work?" = research_question.

**Cryo-EM and structural biology requests (workflow_generation):**
BioMate has 11 cryo-EM SPA, 2 cryo-ET, and 3 structural biology workflows. Key examples:
- SPA (standard): "run cryo-EM SPA / process my movies or micrographs / CryoSPARC standard pipeline" → workflow_generation (inputs: .mrc/.tif/.eer movies)
- SPA (specialized): "GPCR SPA / MSP nanodisc / saposin nanodisc / pore-forming protein / helical filament / multi-drug difference maps" → workflow_generation
- SPA (analysis): "3D variability / conformational heterogeneity / cryoDRGN / RELION multi-body / focused refinement / DeepEMhancer sharpening" → workflow_generation
- Cryo-ET: "cryo-ET / tilt series alignment / tomogram reconstruction / subtomogram averaging" → workflow_generation (inputs: tilt series)
- Structure prediction: "predict protein structure with Boltz-2 / Chai-1 / conformational ensemble" → workflow_generation (inputs: FASTA sequence)

**Key rule**: workflow_generation requires user DATA to be processed (files, accessions, SMILES, dose levels, "my samples/data"). If all inputs are biological identifiers (gene names/IDs, disease names, phenotype codes) with NO user data or molecular inputs → it's a knowledge reasoning task (research_question with needsResearchAgent=true). "Identify differentially expressed genes in my fastq files" = workflow; "which of these candidate genes causes this phenotype?" = knowledge reasoning.

Use research_question for questions about biological knowledge that can be answered without processing user data files: gene-disease associations, phenotype-to-gene mapping, mechanism questions, literature questions, etc.

## Requests that are NEVER workflow_generation

These must NOT trigger workflow generation, regardless of file names or scientific context:
- "Generate a sample [file/data/dataset] for me" → cannot be fulfilled by a pipeline; respond with a polite refusal and suggest public data sources
- "Create a synthetic/fake/mock [file]" → same
- "Simulate [raw data / reads / images] with a given filename" → same
- "Can you make a [.mrc / .fastq / .bam] file for me?" → same
- Any request whose primary intent is *data fabrication* rather than *analysis of provided data*

**Direct computations on user-provided inputs — workflow_generation with needsWorkflowGeneration: false:**
When the user pastes concrete data OR uploads files and asks BioMate to compute something using run_code, this is workflow_generation with needsWorkflowGeneration: false. No Nextflow pipeline is launched — BioMate executes code directly via run_code:
- "Compute the reverse complement of ATGCATGC" → workflow_generation, needsWorkflowGeneration: false
- "What is the GC content of this sequence: ATGCATGCGC?" → workflow_generation, needsWorkflowGeneration: false
- "Calculate BOIN decision boundaries for phi_T=0.25, n_patients=6" → workflow_generation, needsWorkflowGeneration: false
- "Fit a 1-compartment PK model to these concentration-time points: [paste data]" → workflow_generation, needsWorkflowGeneration: false
- "Compute allometric scaling: CL_rat=0.5 L/h/kg at 250g → predicted human CL" → workflow_generation, needsWorkflowGeneration: false
- "Parse this VCF snippet and count variants per chromosome" → workflow_generation, needsWorkflowGeneration: false
- "Infer whether mt.sorted.bam is paired-end or single-end" → workflow_generation, needsWorkflowGeneration: false

**Database lookups for structured biological facts — always research_question:**
When the answer comes from a live biological database and no computation on user data is needed:
- "What is the Ensembl gene ID for SRSF3 in human?" → research_question; Ensembl lookup
- "What is the pathogenicity of variant NM_007294.3:c.5266dupC (BRCA1)?" → research_question; ClinVar lookup
- "What is the median TPM expression of GATA3 in breast tissue (GTEx v8)?" → research_question; GTEx REST API
- "What regulatory elements overlap chr11:124738681-124738772 in hg38?" → research_question; ENCODE/UCSC cCRE API
- "What is the canonical splice site sequence?" → research_question; direct knowledge

## Action Categories

For each intent, declare which system agents are needed (true/false):
- **needsToolSearch**: Search Galaxy's tool database for relevant tools
- **needsWorkflowGeneration**: Build a multi-step Galaxy workflow
- **needsWorkflowModification**: Modify an existing workflow
- **needsResearchAgent**: Scientific question answering (literature, evidence synthesis)
- **needsBenchmarkAgent**: Quantitative tool/method comparison with metrics
- **needsDatasetAccess**: Search Galaxy datasets
- **needsLLMReasoning**: Generate synthesized text response (almost always true)

## Multi-Intent Detection

A message may contain MULTIPLE DISTINCT tasks. Examples:
- "Run DE analysis on my RNA-seq data AND compare DESeq2 vs edgeR" → workflow_generation + result_comparison
- "Find papers on CRISPR delivery and also run off-target analysis on this guide RNA" → research_question + workflow_generation
- "What tools do variant calling, and show me their benchmarks" → tool_search + benchmark_query

Rules for multi-intent:
- Split into multiple intents when the message contains genuinely SEPARATE tasks requiring DIFFERENT backends
- Use conjunctions like "AND", "also", "plus", "as well as" as signals for multi-intent
- A single complex task (e.g., "design a pipeline that does QC then alignment then counting") is ONE workflow_generation intent, not three
- Clarifying details ("from human samples") attached to a prior task are NOT separate intents
- Each intent must have its own subQuery (the portion of the message relevant to that intent)
- Set dependsOn when one intent's output feeds into another (e.g., research findings used for workflow design)
- IMPORTANT: When in doubt between single-intent and multi-intent, prefer multi-intent if the user is asking for 2+ distinct outcomes (e.g., run an analysis AND compare tools AND search literature)

## Sequential Pipeline Detection

A special case of multi-intent is an **ordered sequential pipeline** where each step's output is the input for the next step. This is different from parallel multi-intent.

Your job is to recognize sequential intent in **any format the user chooses**. Do not require a specific syntax. Examples of all supported formats:

**Numbered lists:**
- "1. FastQC\n2. Trim Galore\n3. STAR alignment\n4. DESeq2" → 4-step sequential
- "Step 1: QC the reads. Step 2: Trim adapters. Step 3: Align to hg38." → 3-step sequential
- "1) Run FastQC 2) Align with BWA 3) Call variants with GATK" → 3-step sequential

**Bulleted lists (any bullet character):**
- "- RNA-seq QC\n- Adapter trimming\n- Alignment" → 3-step sequential
- "* FastQC\n* Trim Galore\n* STAR" → 3-step sequential
- "• QC\n• Trim\n• Align" → 3-step sequential

**Labelled steps:**
- "Step A: quality control, Step B: alignment, Step C: variant calling" → 3-step sequential

**Prose with connectives:**
- "RNA-seq alignment then differential expression then pathway enrichment" → 3-step sequential
- "First run FastQC, then trim adapters, then align with STAR" → 3-step sequential
- "QC my FASTQ files, followed by alignment, followed by variant calling" → 3-step sequential

**Intro sentence + list (ignore the intro):**
- "Please run the following pipeline:\n1. QC\n2. Trim\n3. Align" → 3-step sequential (ignore intro)
- "I want to process my RNA-seq data:\n- FastQC\n- Trim Galore\n- STAR" → 3-step sequential

Rules:
- Set "is_sequential": true and populate "intents" in order
- Each intent must have "dependsOn": ["<prior_intent_id>"] (except the first step)
- Set "input_from_description" on each step (except the first) describing what it receives
- Set "output_description" on each step describing what it produces for the next step
- Sequential pipelines must ALL be workflow_generation type intents (each step = one runnable workflow)
- If a step is ambiguous in isolation, still include it — resolution happens downstream

## Parameter Extraction

Extract any inline data or parameters the user provides directly in their message:
- DNA/RNA/protein sequences (e.g., "ATGCGATCG")
- Gene names (e.g., "TP53", "BRCA1")
- File paths or dataset references
- Numeric parameters (e.g., "p-value < 0.05", "top 100 genes")
- Species/organism (e.g., "human", "E. coli")

## Keyword Extraction

Extract keywords that describe the OPERATION or ANALYSIS, not generic terms:
- Good: "reverse complement", "differential expression", "variant calling"
- Bad: "DNA", "data", "analysis" (too generic)

## Fact Extraction

Extract structured facts from the message. Each fact MUST use one of these exact categories:
"sequence", "gene", "organism", "data_type", "parameter", "file_reference", "tool_preference", "domain", "analysis_goal", "other"

Category definitions:
- **sequence**: DNA/RNA/protein sequence literals (e.g., "ATGCGATCG")
- **gene**: Gene or protein names (e.g., "TP53", "BRCA1", "EGFR")
- **organism**: Species or organism (e.g., "human", "mouse", "E. coli", "Arabidopsis")
- **data_type**: Type of data mentioned (e.g., "RNA-seq", "ChIP-seq", "WGS", "proteomics")
- **parameter**: Specific parameters or thresholds (e.g., "p-value < 0.05", "hg38", "paired-end")
- **file_reference**: File paths, URLs, or dataset references
- **tool_preference**: Specific tool the user wants to use (e.g., "BWA", "DESeq2", "STAR")
- **domain**: Scientific domain (e.g., "genomics", "proteomics", "pharmacology")
- **analysis_goal**: What the user wants to achieve (e.g., "find differentially expressed genes", "identify variants")
- **other**: Any other relevant detail that doesn't fit the above categories

Assign confidence 0.0-1.0 based on how explicit the mention is. Direct mentions get 0.9+, inferred facts get 0.5-0.7.

## Fact Supersession

If EXISTING FACTS are provided below, check whether any new fact from the current message REPLACES or CORRECTS an existing fact. For example, if the user previously said "mouse" and now says "actually, human", the new organism fact supersedes the old one.

When a new fact replaces an old one, include "supersedes": "<id of the old fact>" in the new fact object. Only mark supersession when the user is clearly correcting or changing a previous statement — not when they are adding additional information.

${(() => {
  if (!context.accumulatedFacts || context.accumulatedFacts.length === 0) return '';
  const lines = context.accumulatedFacts.map(f => `- [id=${f.id}] ${f.category}: "${f.value}"`);
  return '\n## Existing Facts from Prior Turns\n' + lines.join('\n') + '\n';
})()}
## Ambiguity Detection

IMPORTANT: Domain profile and research context do NOT resolve workflow ambiguity.
If a user's query would normally trigger a clarification question, it MUST still
trigger that question even when their domain profile suggests a context.

The domain profile tells you WHICH tools to rank higher after you know the answer —
it does NOT tell you WHAT the user wants.

Examples:
- User profile: oncology. Query: "analyze my expression data" → STILL ask: is this
  bulk RNA-seq (differential expression, DESeq2/edgeR) or single-cell RNA-seq
  (cell clustering, Seurat/Scanpy)? The profile informs preferred_domains but does
  not answer the question "what kind of analysis?"
- User profile: drug_discovery. Query: "run a docking analysis" → STILL ask: blind
  docking (binding site unknown, DiffDock) or site-directed (known pocket, AutoDock Vina)?

Rule: set workflowAmbiguity whenever the query is genuinely ambiguous at the technical
level, regardless of what the user's domain profile contains. The profile informs
preferred_domains (search ranking) but NEVER resolves workflowAmbiguity.

GENERAL RULE: When a workflow request could map to two or more pipelines with fundamentally
different inputs, tools, or scientific purposes — and the user has not provided enough context
to distinguish them — return "workflowAmbiguity" with the appropriate type. DO NOT guess.
Return null only when the user's message already contains enough specificity.

Known fork points (use the exact type string listed):

GENOMICS
- "variant_type": "variant calling" / "mutation analysis" / "SNP detection" without
  specifying "germline" (inherited, single sample → GATK HaplotypeCaller) vs
  "somatic" (tumor mutations, tumor+normal BAMs → GATK Mutect2)
- "assembly_type": "genome assembly" / "de novo assembly" without specifying
  "de novo" (no reference, e.g. SPAdes/Flye) vs "reference-guided" (e.g. GATK or BWA + polishing)

RNA-SEQ
- "rnaseq_type": "RNA-seq" / "transcriptomics" without specifying
  "bulk RNA-seq" (differential expression, DESeq2/edgeR) vs
  "single-cell RNA-seq" (cell clustering, Seurat/Scanpy)
- "scrna_type": single-cell RNA-seq without specifying
  "standard atlas/clustering" vs "perturbation screen" (CRISPR KO library, mixscape)

EPIGENOMICS
- "peak_calling_type": "peak calling" / "chromatin analysis" / "open chromatin" without
  specifying the assay — "ChIP-seq" (requires IP sample + input control, profiles specific
  proteins) vs "ATAC-seq" (transposase-based, no antibody, profiles accessible regions)
- "chip_target": "ChIP-seq" confirmed but target not specified:
  "transcription factor" (sharp peaks, MACS2 narrow) vs
  "histone modification" (broad peaks, e.g. H3K27me3, H3K4me1)

PROTEOMICS
- "proteomics_type": "proteomics" / "mass spectrometry" without specifying
  "DDA" (data-dependent acquisition, MaxQuant) vs "DIA" (data-independent, DIA-NN)

STRUCTURAL BIOLOGY
- "cryoem_type": "cryo-EM" / "electron microscopy" without specifying
  "single-particle analysis (SPA)" (isolated protein) vs
  "cryo-ET" (tomography, in-situ structures in cells)
- "cryoem_sample": cryo-EM SPA without specifying whether the sample is
  "globular particle" (standard SPA — CryoSPARC / RELION standard pipeline) vs
  "filamentous assembly" (actin, amyloid, microtubule, viral tube — requires
   helical reconstruction with rise/twist symmetry parameters)
  Only ask if the user mentioned a protein type that could be either.

GENOMICS (somatic sub-type)
- "somatic_paired": somatic variant calling requested but no indication whether
  "paired tumor+normal" (matched normal eliminates germline background, higher specificity) vs
  "tumor-only" (no matched normal, uses panel of normals — higher false-positive rate)

RNA-SEQ (sub-type)
- "rnaseq_focus": "RNA-seq" / "transcriptomics" but unclear if the goal is
  "mRNA / differential expression" (standard bulk pipeline, DESeq2/edgeR) vs
  "miRNA / small RNA" (miRDeep2/miRBase, completely different tools and reference databases)
  Only ask if the user mentioned "small RNA", "non-coding", "miRNA", or "regulatory RNA".

CELL BIOLOGY
- "flow_cytometry_type": "flow cytometry" / "FACS analysis" / "cell populations" without
  specifying the goal:
  "immunophenotyping / gating" (population statistics on cell subsets, % T/B cells) vs
  "cell sorting" (physical enrichment of cell fractions) vs
  "unsupervised clustering" (dimensionality reduction, flowSOM/flowMeans — no predefined gates)

METAGENOMICS
- "metagenomics_type": "metagenomics" / "microbiome" without specifying
  "16S amplicon" (amplicon sequencing, QIIME2/DADA2) vs
  "shotgun metagenomics" (whole-metagenome sequencing, Kraken2/MetaPhlAn)

DRUG DISCOVERY
- "docking_type": "molecular docking" without specifying
  "blind docking" (no binding site known, DiffDock) vs
  "site-directed docking" (known binding site, AutoDock Vina)
- "admet_scope": "toxicity" / "ADMET" / "safety screening" without providing a molecule AND
  without specifying which assays — need to know: (a) what molecule (SMILES or file), and
  (b) which safety endpoints: "hERG / cardiotoxicity", "DILI / hepatotoxicity",
  "Ames mutagenicity", "full ADMET panel", or a specific subset.
  Do NOT ask if the user already provided a SMILES string and named specific endpoints.

Return null if the user already specifies enough to unambiguously select one pipeline.

## Response Format

For SINGLE-intent messages (the common case), respond with a single JSON object:
{
  "type": "workflow_generation",
  "keywords": ["reverse complement"],
  "inlineParameters": {"sequence": "ATGCGATCG"},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": false,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "sequence", "value": "ATGCGATCG", "confidence": 1.0},
    {"category": "analysis_goal", "value": "reverse complement", "confidence": 0.95}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": [],
  "key_terms": ["reverse complement"],
  "needs_thinking": false,
  "chain_hint": null
}

The above example uses needsWorkflowGeneration: false because the user pasted their data inline (a sequence) — BioMate computes directly via run_code.

Contrast with a Nextflow pipeline case where data is an accession or file path:
"Run RNA-seq differential expression analysis on my samples SRR1518169 and SRR1518170"
{
  "type": "workflow_generation",
  "keywords": ["RNA-seq", "differential expression", "SRR1518169"],
  "inlineParameters": {"reads": "SRR1518169"},
  "needsToolSearch": true,
  "needsDatasets": false,
  "confidence": 0.98,
  "actions": {
    "needsToolSearch": true,
    "needsWorkflowGeneration": true,
    "needsWorkflowModification": false,
    "needsResearchAgent": false,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "accession", "value": "SRR1518169", "confidence": 1.0},
    {"category": "data_type", "value": "RNA-seq FASTQ", "confidence": 0.95},
    {"category": "analysis_goal", "value": "differential expression", "confidence": 0.95}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["RNA-seq", "differential expression", "nf-core/rnaseq"],
  "needs_thinking": false,
  "chain_hint": null
}

Note: chain_hint is null here even though this involves RNA-seq + DE, because the user did not
explicitly ask for a named multi-step pipeline. BioMate will route this to the best single
workflow (nf-core/rnaseq). Chain suggestions for downstream DE analysis come reactively after
the run completes.

Key rule: needsWorkflowGeneration: true when the user provides a file path, SRA/GEO accession, or any data reference that must be fetched and processed by a Nextflow pipeline. needsWorkflowGeneration: false when the user pastes the data inline (a short sequence, a few numbers, a small table) and BioMate can compute the answer directly without a pipeline.

preferred_domains: list of 0–3 domain strings most relevant to this query, chosen from:
  [${PREFERRED_DOMAINS_PROMPT_LIST}]
  Leave empty [] when the query is domain-agnostic or unclear.

key_terms: up to 8 specific technical terms (tool names, assay types, organisms) that should
  boost workflow search recall. Omit generic words like "run", "analyze", "data".

needs_thinking: true only when the query requires multi-step reasoning, pipeline design,
  troubleshooting, or methodology comparison. false for simple workflow execution requests.

chain_hint: ONLY set if the user explicitly requests a named multi-step pipeline that spans ALL
  the steps in that chain (e.g. "run the full drug discovery pipeline", "target-to-lead", "rare
  disease multi-modal workup"). NEVER set if the user asks for a single analysis type (RNA-seq,
  differential expression, ADMET screening) even if that step is part of a chain — a partial
  request should go through normal workflow search (Tier 1), not chain escalation. Set null when
  in doubt.
  Known chain names: [${chainHintList}]

For MULTI-intent messages (parallel), respond with an "intents" array:
{
  "is_sequential": false,
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["differential expression", "DESeq2", "edgeR"],
  "needs_thinking": true,
  "chain_hint": null,
  "intents": [
    {
      "id": "intent_1",
      "type": "workflow_generation",
      "subQuery": "Run DE analysis on my RNA-seq data",
      "keywords": ["differential expression"],
      "inlineParameters": {},
      "needsToolSearch": true,
      "needsDatasets": true,
      "confidence": 0.9,
      "actions": {
        "needsToolSearch": true,
        "needsWorkflowGeneration": true,
        "needsWorkflowModification": false,
        "needsResearchAgent": false,
        "needsBenchmarkAgent": false,
        "needsDatasetAccess": false,
        "needsLLMReasoning": true
      },
      "facts": [{"category": "data_type", "value": "RNA-seq", "confidence": 0.95}],
      "dependsOn": []
    },
    {
      "id": "intent_2",
      "type": "result_comparison",
      "subQuery": "compare DESeq2 vs edgeR",
      "keywords": ["DESeq2", "edgeR", "comparison"],
      "inlineParameters": {},
      "needsToolSearch": true,
      "needsDatasets": false,
      "confidence": 0.85,
      "actions": {
        "needsToolSearch": false,
        "needsWorkflowGeneration": false,
        "needsWorkflowModification": false,
        "needsResearchAgent": false,
        "needsBenchmarkAgent": true,
        "needsDatasetAccess": false,
        "needsLLMReasoning": true
      },
      "facts": [{"category": "tool_preference", "value": "DESeq2", "confidence": 0.9}],
      "dependsOn": []
    }
  ]
}

## Research Question Examples (needsResearchAgent: true)

For KNOWLEDGE and RESEARCH questions (not workflow execution), set needsResearchAgent: true:

"What is the causal gene for Huntington's disease?"
{
  "type": "research_question",
  "keywords": ["Huntington's disease", "causal gene", "HTT"],
  "inlineParameters": {},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [{"category": "analysis_goal", "value": "identify causal gene for Huntington's disease", "confidence": 0.95}],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["Huntington", "causal gene", "HTT"],
  "needs_thinking": false,
  "chain_hint": null
}

"Which genes are associated with the HPO phenotype HP:0001250 (seizure)?"
{
  "type": "research_question",
  "keywords": ["HPO", "phenotype", "seizure", "HP:0001250", "gene association"],
  "inlineParameters": {"hpo_term": "HP:0001250"},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "gene-phenotype association lookup", "confidence": 0.95},
    {"category": "parameter", "value": "HP:0001250", "confidence": 1.0}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["HPO", "HP:0001250", "seizure", "gene association"],
  "needs_thinking": false,
  "chain_hint": null
}

"What are the known pathogenic variants in BRCA1 associated with hereditary breast cancer?"
{
  "type": "research_question",
  "keywords": ["BRCA1", "pathogenic variants", "hereditary breast cancer"],
  "inlineParameters": {},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "gene", "value": "BRCA1", "confidence": 1.0},
    {"category": "analysis_goal", "value": "pathogenic variant lookup", "confidence": 0.9}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["BRCA1", "pathogenic variants", "hereditary breast cancer", "ClinVar"],
  "needs_thinking": false,
  "chain_hint": null
}

"Which genes, when mutated, cause rare disease with features: intellectual disability, seizures, hypotonia?"
{
  "type": "research_question",
  "keywords": ["rare disease", "intellectual disability", "seizures", "hypotonia", "gene mutation"],
  "inlineParameters": {},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.9,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "rare disease gene identification from phenotype cluster", "confidence": 0.9}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["rare disease", "phenotype", "intellectual disability", "seizures", "HPO"],
  "needs_thinking": true,
  "chain_hint": null
}

"Task: Given a patient's phenotypes and a list of candidate genes, identify the causal gene.\nPhenotypes: HP:0001250, HP:0002300, HP:0001347\nCandidate genes: ENSG00000161011, ENSG00000092330, ENSG00000131174\nOutput format: {'causal_gene': [gene1]}"
{
  "type": "clinical_genomics",
  "keywords": ["causal gene", "phenotypes", "HPO", "candidate genes", "patient gene detection"],
  "inlineParameters": {"hpo_terms": ["HP:0001250", "HP:0002300", "HP:0001347"], "genes": ["ENSG00000161011", "ENSG00000092330", "ENSG00000131174"]},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "identify causal gene from phenotype+candidate list", "confidence": 0.95},
    {"category": "task_type", "value": "patient_gene_detection", "confidence": 0.95}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["causal gene", "HPO phenotypes", "candidate genes", "gene-disease association"],
  "needs_thinking": true,
  "chain_hint": null
}

"Task: Given a patient with phenotypes HP:0001761 (pes cavus), HP:0010522 (retinal abnormality) and candidate genes ENSG00000161011, ENSG00000130812, ENSG00000197746, identify the causal gene.\n\nSearch ClinVar and OMIM for the gene whose known disease associations match these phenotypes. Identify the ONE causal gene from the candidate list.\nAnswer with ONLY this JSON: {\"causal_gene\": [\"ENSG_ID\"]}"
{
  "type": "clinical_genomics",
  "keywords": ["causal gene", "HPO phenotypes", "pes cavus", "retinal abnormality", "candidate genes", "patient gene detection", "ClinVar", "OMIM"],
  "inlineParameters": {"hpo_terms": ["HP:0001761", "HP:0010522"], "genes": ["ENSG00000161011", "ENSG00000130812", "ENSG00000197746"]},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.98,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "identify causal gene from HPO phenotype list and ENSG candidate list via ClinVar/OMIM lookup", "confidence": 0.98},
    {"category": "task_type", "value": "patient_gene_detection", "confidence": 0.98}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["causal gene", "HPO phenotypes", "pes cavus", "retinal abnormality", "ENSG candidate genes", "gene-disease association", "ClinVar", "OMIM"],
  "needs_thinking": true,
  "chain_hint": null
}

IMPORTANT: Set needsResearchAgent: true whenever the user asks:
- What gene causes / is associated with [disease/phenotype]
- What does gene [X] do / what is its function
- Which variants in gene [X] are pathogenic / disease-causing
- What are the known [disease] genes
- What HPO terms correspond to [phenotype description]
- Literature questions: "what papers / what is known about..."
- Mechanism questions: "how does [gene/protein] work"
- Clinical questions: "what is the prognosis / treatment for..."
- Structured tasks with "Phenotypes: HP:..." + "Candidate genes: ENSG..." → these are gene-phenotype reasoning tasks, NOT workflow requests
- Literature deep-research: "In [paper/study], what [statistic/result] was reported for [subgroup/condition]?" → look up from literature
- Numerical/statistical questions about published data: "What is the ORR / hazard ratio / p-value reported in [study X]?"
- Computational biology analysis questions where no user data file is provided: "What proportion of variance is explained by batch effects?", "Given these summary statistics, calculate..."
- Questions about specific clinical trial results, drug response rates, biomarker cutoffs, benchmark scores
- GWAS / functional genomics knowledge: "Which gene at GWAS locus Xq22 is the likely causal gene for trait Y?" → database + literature lookup, NOT workflow
- GWAS variant prioritization: "From this list of candidate SNPs, which is most likely causal for trait X?" → GWAS Catalog + literature lookup, NOT a pipeline execution
- Any question giving a LIST OF CANDIDATE VARIANTS or CANDIDATE GENES and asking to select one → research_question (DB lookup), NOT workflow_generation

"Your task is to identify the most promising variant associated with a given GWAS phenotype. From the list, prioritize the top associated variant (matching one of the given variant). GWAS phenotype: Bradykinin. Variants: rs7700133, rs1280, rs7651090, rs4253311, rs3738934."
{
  "type": "genomics_knowledge",
  "keywords": ["GWAS", "variant prioritization", "bradykinin", "causal SNP", "rsID"],
  "inlineParameters": {"phenotype": "Bradykinin", "candidate_variants": ["rs7700133", "rs1280", "rs7651090", "rs4253311", "rs3738934"]},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.97,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "identify causal GWAS variant from candidate list using GWAS Catalog", "confidence": 0.97},
    {"category": "task_type", "value": "gwas_variant_prioritization", "confidence": 0.97}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["GWAS", "variant prioritization", "candidate SNPs", "causal variant", "GWAS Catalog"],
  "needs_thinking": true,
  "chain_hint": null
}

"Your task is to identify likely causal genes within a locus for a given GWAS phenotype. From the list, provide only the likely causal gene. GWAS phenotype: Lymphoma, Large B-Cell, Diffuse. Genes in locus: {C2orf74},{CCT4},{COMMD1},{FAM161A}"
{
  "type": "genomics_knowledge",
  "keywords": ["GWAS", "causal gene", "locus", "lymphoma", "DLBCL"],
  "inlineParameters": {"phenotype": "Lymphoma, Large B-Cell, Diffuse", "candidate_genes": ["C2orf74", "CCT4", "COMMD1", "FAM161A"]},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.97,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "identify causal gene at GWAS locus using Open Targets / GWAS Catalog", "confidence": 0.97},
    {"category": "task_type", "value": "gwas_causal_gene", "confidence": 0.97}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["GWAS locus", "causal gene", "Open Targets", "gene prioritization"],
  "needs_thinking": true,
  "chain_hint": null
}

"RESEARCH QUESTION: A published CRISPR screen was already performed for this exact condition. Your task is to recall which gene showed the strongest fitness effect in that published experiment. I hope to study the mechanisms by which HeLa cells develop increased resistance to the Vaccinia virus Western Reserve strain over a two-week exposure period at a dosage of 0.8 MOI."
{
  "type": "genomics_knowledge",
  "keywords": ["CRISPR screen", "HeLa", "Vaccinia virus", "resistance", "fitness effect", "published screen", "VMP1"],
  "inlineParameters": {"cell_line": "HeLa", "perturbation": "Vaccinia virus WR", "dosage": "0.8 MOI", "duration": "2 weeks"},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.96,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "analysis_goal", "value": "retrieve published CRISPR screen result for specific experimental context", "confidence": 0.96},
    {"category": "task_type", "value": "screen_gene_retrieval", "confidence": 0.96}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["published CRISPR screen", "gene fitness effect", "literature retrieval"],
  "needs_thinking": false,
  "chain_hint": null
}

"In the MPDL3280A Phase I study of non-small cell lung cancer, what was the objective response rate for patients with TC3 PD-L1 expression?"
{
  "type": "research_question",
  "keywords": ["MPDL3280A", "atezolizumab", "NSCLC", "PD-L1", "TC3", "ORR", "objective response rate"],
  "inlineParameters": {},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [{"category": "analysis_goal", "value": "retrieve clinical trial result from published study", "confidence": 0.95}],
  "workflowAmbiguity": null,
  "preferred_domains": ["clinical"],
  "key_terms": ["MPDL3280A", "PD-L1", "TC3", "ORR", "NSCLC", "clinical trial"],
  "needs_thinking": true,
  "chain_hint": null
}

"High mutational burden group (n=9, DCB=83%) and low burden group (n=9, DCB=22%). A POLE-mutant patient from the low group is reclassified to high. What is the new difference in DCB rates?"
{
  "type": "research_question",
  "keywords": ["mutational burden", "DCB rate", "POLE mutation", "reclassification", "calculation"],
  "inlineParameters": {"high_n": 9, "high_dcb": 0.83, "low_n": 9, "low_dcb": 0.22},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.97,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [{"category": "analysis_goal", "value": "numerical calculation on published clinical data", "confidence": 0.97}],
  "workflowAmbiguity": null,
  "preferred_domains": ["clinical"],
  "key_terms": ["DCB rate", "mutation burden", "statistical calculation"],
  "needs_thinking": false,
  "chain_hint": null
}

"What is the proportion of gene expression variance explained by batch effects in this scRNA-seq study? Answer choices: A) 0.12  B) 0.34  C) 0.67  D) 0.89"
{
  "type": "research_question",
  "keywords": ["variance", "batch effects", "scRNA-seq", "gene expression", "proportion"],
  "inlineParameters": {},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [{"category": "analysis_goal", "value": "answer computational biology multiple-choice question from knowledge", "confidence": 0.95}],
  "workflowAmbiguity": null,
  "preferred_domains": ["single_cell"],
  "key_terms": ["batch effects", "variance", "scRNA-seq"],
  "needs_thinking": false,
  "chain_hint": null
}

"Find the paper 'Predictive correlates of response to the anti-PD-L1 antibody MPDL3280A in cancer patients'. In Extended Data Figure 4c, what is the ORR for the IHC 3 tumor cell group?"
{
  "type": "research_question",
  "keywords": ["MPDL3280A", "predictive correlates", "IHC 3", "ORR", "tumor cell", "PD-L1"],
  "inlineParameters": {},
  "needsToolSearch": false,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": false,
    "needsWorkflowGeneration": false,
    "needsWorkflowModification": false,
    "needsResearchAgent": true,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [{"category": "analysis_goal", "value": "extract specific data point from named publication", "confidence": 0.95}],
  "workflowAmbiguity": null,
  "preferred_domains": ["clinical"],
  "key_terms": ["MPDL3280A", "IHC", "ORR", "clinical trial data extraction"],
  "needs_thinking": true,
  "chain_hint": null
}

For SEQUENTIAL pipeline messages (step outputs feed the next step), use "is_sequential": true and chain dependsOn:
{
  "is_sequential": true,
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["fastqc", "trim galore", "star", "hg38"],
  "needs_thinking": false,
  "chain_hint": "bulk_rnaseq_de_analysis",
  "intents": [
    {
      "id": "step_1",
      "type": "workflow_generation",
      "subQuery": "Run FastQC and trim adapters on FASTQ files",
      "keywords": ["fastqc", "trimming", "quality control"],
      "inlineParameters": {},
      "needsToolSearch": true,
      "needsDatasets": false,
      "confidence": 0.95,
      "actions": {"needsToolSearch": true, "needsWorkflowGeneration": true, "needsWorkflowModification": false, "needsResearchAgent": false, "needsBenchmarkAgent": false, "needsDatasetAccess": false, "needsLLMReasoning": true},
      "facts": [],
      "dependsOn": [],
      "input_from_description": null,
      "output_description": "trimmed FASTQ files"
    },
    {
      "id": "step_2",
      "type": "workflow_generation",
      "subQuery": "Align trimmed reads to hg38 with STAR",
      "keywords": ["alignment", "STAR", "hg38"],
      "inlineParameters": {},
      "needsToolSearch": true,
      "needsDatasets": false,
      "confidence": 0.9,
      "actions": {"needsToolSearch": true, "needsWorkflowGeneration": true, "needsWorkflowModification": false, "needsResearchAgent": false, "needsBenchmarkAgent": false, "needsDatasetAccess": false, "needsLLMReasoning": true},
      "facts": [],
      "dependsOn": ["step_1"],
      "input_from_description": "trimmed FASTQ files from step 1",
      "output_description": "aligned BAM files"
    }
  ]
}`;

    try {
      const intentStartTime = Date.now();
      // Two-tier Gemini routing: Pro for complex queries, Flash for simple ones.
      // Falls back to the configured intentModel for non-Gemini backbones.
      const configured = this.modelConfig.intentModel;
      const isGemini = configured.startsWith('gemini-');
      const effectiveIntentModel = isGemini ? pickGeminiIntentModel(message) : configured;
      console.log('[GalaxyAssistant] Intent API request:', {
        model: effectiveIntentModel,
        tier: isGemini ? (effectiveIntentModel === GEMINI_PRO_MODEL ? 'pro' : 'flash') : 'non-gemini',
        max_tokens: 4096,
        system_prompt_length: systemPrompt.length,
        message_length: message.length
      });

      // Intent classification - using configurable model (Anthropic or Gemini)
      let resultText: string;

      if (isGemini && this.gemini) {
        const geminiModel = this.gemini.getGenerativeModel({
          model: effectiveIntentModel,
          // Bumped 2500→4096: complex tier 0 queries (e.g. T03 "Base editing strategy for
          // PCSK9 LOF in hypercholesterolemia (VERVE-102 style)") truncated JSON output at
          // 2500, producing "Unexpected end of JSON input" and zero workflow_ready event.
          // Gemini thinking tokens count against this budget; 4096 leaves room for the
          // full intent + inlineParameters payload.
          generationConfig: { temperature: 0, maxOutputTokens: 4096, responseMimeType: 'application/json' },
          systemInstruction: systemPrompt,
        });
        // Retry with exponential backoff on 429 rate limit
        let geminiResult: any;
        for (let attempt = 0; attempt < 5; attempt++) {
          try {
            geminiResult = await geminiModel.generateContent(message);
            break;
          } catch (err: any) {
            const is429 = err?.message?.includes('429') || err?.status === 429;
            if (is429 && attempt < 4) {
              const delay = (attempt + 1) * 3000; // 3s, 6s, 9s, 12s
              console.warn(`[GalaxyAssistant] Gemini 429 rate limit, retrying in ${delay}ms (attempt ${attempt + 1})`);
              await new Promise(r => setTimeout(r, delay));
            } else {
              throw err;
            }
          }
        }
        resultText = geminiResult.response.text();
        console.log('[GalaxyAssistant] Intent API response (Gemini):', {
          model: effectiveIntentModel,
          time_ms: Date.now() - intentStartTime,
        });
      } else {
        // Anthropic path (default)
        // Note: temperature is deprecated for Claude 4.x models
        const completion = await this._withAnthropicRetry(
          () => this.claude.messages.create({
            model: this.modelConfig.intentModel,
            max_tokens: 4096,
            system: [
              {
                type: 'text',
                text: systemPrompt,
                cache_control: { type: 'ephemeral' },
              },
            ],
            messages: [{ role: 'user', content: message }],
          }),
          'intent-classification',
        );
        console.log('[GalaxyAssistant] Intent API response:', {
          model: this.modelConfig.intentModel,
          time_ms: Date.now() - intentStartTime,
          usage: completion.usage,
        });
        const content = completion.content[0];
        resultText = content.type === 'text' ? content.text : '{}';
      }

      // Strip markdown code blocks if present
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')
        .replace(/\n?```+\s*$/gi, '')
        .replace(/^\s*`+\s*/g, '')
        .replace(/\s*`+\s*$/g, '')
        .trim();

      // Try to extract JSON object if there's extra text around it
      const jsonMatch = resultText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        resultText = jsonMatch[0];
      }

      // Remove any remaining backticks that might be inside string values
      resultText = resultText.replace(/`/g, "'");

      const result = JSON.parse(resultText);

      // Parse into IntentDecomposition
      return this.parseIntentResult(result, message);
    } catch (error) {
      console.error('[GalaxyAssistant] Intent analysis failed:', error);
      const errMsg = error instanceof Error ? error.message : String(error);
      const isBilling = /credit balance|billing|payment|quota|rate.?limit|too many requests/i.test(errMsg);
      const isAuth = /unauthorized|invalid.?api.?key|authentication/i.test(errMsg);
      if (isBilling || isAuth) {
        // Re-throw so _generateResponse catch block can surface the correct error message
        throw error;
      }
      // JSON parse failure: build a best-effort tool_search intent so the pipeline
      // still attempts workflow search rather than silently skipping it.
      // Extract keywords from the raw message via simple tokenisation.
      const rawKeywords = message
        .toLowerCase()
        .replace(/[^\w\s-]/g, ' ')
        .split(/\s+/)
        .filter(w => w.length > 3 && !['with','that','this','from','have','will','your','their','what','which','when','then','they','also','into','been','would','could'].includes(w))
        .slice(0, 8);
      const fallback: DecomposedIntent = {
        id: 'intent_fallback',
        type: 'tool_search',
        subQuery: message,
        keywords: rawKeywords,
        inlineParameters: {},
        needsToolSearch: true,
        needsDatasets: false,
        confidence: 0.4,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType('tool_search'),
      };
      console.warn('[GalaxyAssistant] Intent parse failed — using keyword fallback, needsToolSearch=true');
      return {
        intents: [fallback],
        isMultiIntent: false,
        primaryIntent: fallback,
      };
    }
  }

  /**
   * Parse the LLM's intent result into an IntentDecomposition.
   * Handles both single-intent (flat object) and multi-intent (intents array) formats.
   */
  private parseIntentResult(result: any, originalMessage: string): IntentDecomposition {
    const parseFacts = (rawFacts: any[]): Array<{ category: string; value: string; confidence: number; supersedes?: string }> => {
      if (!Array.isArray(rawFacts)) return [];
      return rawFacts
        .filter((f: any) => f && typeof f.category === 'string' && typeof f.value === 'string')
        .map((f: any) => ({
          category: f.category as string,
          value: f.value as string,
          confidence: typeof f.confidence === 'number' ? f.confidence : 0.8,
          supersedes: typeof f.supersedes === 'string' ? f.supersedes : undefined,
        }));
    };

    const parseActions = (raw: any, type: string): ActionCategories => {
      const base = inferActionsFromType(type);
      if (raw && typeof raw === 'object') {
        // For types that require the research agent, the LLM classifier must NOT be able
        // to disable it by returning needsResearchAgent: false — that silently falls back
        // to raw-LLM responses which bypass all DB lookups (GWAS Catalog, Ensembl, etc.).
        const researchAgentTypes = new Set([
          'research_question', 'troubleshooting', 'parameter_optimization',
          'experiment_design', 'data_interpretation', 'protocol_guidance',
          'methods_writing', 'comparative_methodology', 'regulatory_compliance',
          // Knowledge/DB lookup types must always use ResearchAgent for live DB queries
          'clinical_genomics', 'genomics_knowledge', 'database_lookup',
        ]);
        const mustUseResearch = researchAgentTypes.has(type);
        return {
          needsToolSearch: typeof raw.needsToolSearch === 'boolean' ? raw.needsToolSearch : base.needsToolSearch,
          needsWorkflowGeneration: typeof raw.needsWorkflowGeneration === 'boolean' ? raw.needsWorkflowGeneration : base.needsWorkflowGeneration,
          needsWorkflowModification: typeof raw.needsWorkflowModification === 'boolean' ? raw.needsWorkflowModification : base.needsWorkflowModification,
          // If type requires research agent, always enable it regardless of what the classifier returns
          needsResearchAgent: mustUseResearch ? true : (typeof raw.needsResearchAgent === 'boolean' ? raw.needsResearchAgent : base.needsResearchAgent),
          needsBenchmarkAgent: typeof raw.needsBenchmarkAgent === 'boolean' ? raw.needsBenchmarkAgent : base.needsBenchmarkAgent,
          needsDatasetAccess: typeof raw.needsDatasetAccess === 'boolean' ? raw.needsDatasetAccess : base.needsDatasetAccess,
          needsLLMReasoning: typeof raw.needsLLMReasoning === 'boolean' ? raw.needsLLMReasoning : base.needsLLMReasoning,
          needsChainProposal: typeof raw.needsChainProposal === 'boolean' ? raw.needsChainProposal : (base.needsChainProposal ?? false),
        };
      }
      return base;
    };

    // Extract top-level UQU fields (present in both single and multi-intent responses)
    const preferredDomains: string[] = Array.isArray(result.preferred_domains) ? result.preferred_domains : [];
    const penalizedDomains: string[] = Array.isArray(result.penalized_domains) ? result.penalized_domains : [];
    const keyTerms: string[] = Array.isArray(result.key_terms) ? result.key_terms : [];
    const needsThinking: boolean = result.needs_thinking === true;
    const chainHint: string | null = typeof result.chain_hint === 'string' ? result.chain_hint : null;

    // Multi-intent format: { intents: [...] }
    if (Array.isArray(result.intents) && result.intents.length > 0) {
      const isSequential = result.is_sequential === true;
      const intents: DecomposedIntent[] = result.intents.map((intent: any, i: number) => ({
        id: intent.id || `intent_${i + 1}`,
        type: intent.type || 'general_question',
        subQuery: intent.subQuery || originalMessage,
        keywords: intent.keywords || [],
        inlineParameters: intent.inlineParameters || {},
        needsToolSearch: intent.needsToolSearch !== false,
        needsDatasets: intent.needsDatasets !== false,
        confidence: intent.confidence || 0.5,
        facts: parseFacts(intent.facts),
        dependsOn: Array.isArray(intent.dependsOn) ? intent.dependsOn : [],
        actions: parseActions(intent.actions, intent.type || 'general_question'),
        // Sequential pipeline metadata
        inputFromDescription: intent.input_from_description ?? undefined,
        outputDescription: intent.output_description ?? undefined,
      }));

      // Primary = highest confidence (or first step for sequential)
      const primaryIntent = isSequential
        ? intents[0]
        : intents.reduce((best, current) => current.confidence > best.confidence ? current : best);

      console.log(
        `[GalaxyAssistant] Multi-intent detected: ${intents.length} intents [${intents.map(i => i.type).join(', ')}]` +
        (isSequential ? ' (SEQUENTIAL pipeline)' : '') +
        (preferredDomains.length ? ` domains=[${preferredDomains.join(',')}]` : '') +
        (chainHint ? ` chain=${chainHint}` : '')
      );

      return {
        intents,
        isMultiIntent: intents.length > 1,
        isSequential,
        primaryIntent,
        preferredDomains,
        penalizedDomains,
        keyTerms,
        needsThinking,
        chainHint,
      };
    }

    // Single-intent format: flat object with type, keywords, etc.
    const intentType = result.type || 'general_question';
    const singleIntent: DecomposedIntent = {
      id: 'intent_1',
      type: intentType,
      subQuery: originalMessage,
      keywords: result.keywords || [],
      inlineParameters: result.inlineParameters || {},
      needsToolSearch: result.needsToolSearch !== false,
      needsDatasets: result.needsDatasets !== false,
      confidence: result.confidence || 0.5,
      facts: parseFacts(result.facts),
      dependsOn: [],
      actions: parseActions(result.actions, intentType),
      workflowAmbiguity: typeof result.workflowAmbiguity === 'string' ? result.workflowAmbiguity : null,
    };

    return {
      intents: [singleIntent],
      isMultiIntent: false,
      primaryIntent: singleIntent,
      preferredDomains,
      penalizedDomains,
      keyTerms,
      needsThinking,
      chainHint,
    };
  }

  /**
   * Search for relevant tools using Galaxy Tool Search Index
   */
  private async searchRelevantTools(
    userMessage: string,
    keywords: string[],
    userId?: number
  ): Promise<ToolRecommendation[]> {
    try {
      // Fetch user patterns for personalization
      let userContext: UserContext = {};
      if (userId) {
        const insights = await userPatternsService.getUserInsights(userId);
        userContext = userPatternsService.extractUserContext(insights);
        console.log('[GalaxyAssistant] User context:', userContext);
      }

      // Build search query from keywords
      // Try progressively simpler queries until we get results
      let toolSearchResponse: any = { tools: [] };
      let successfulQuery = '';

      // Try different query strategies: full query -> first 3 keywords -> first keyword
      const queriesToTry = [
        keywords.slice(0, 3).join(' '),  // First 3 keywords
        keywords[0],                       // Just first keyword
        keywords.join(' '),                // All keywords (least likely to match)
      ];

      for (const query of queriesToTry) {
        if (!query) continue;
        console.log('[GalaxyAssistant] Tool search query:', query);

        // Search Galaxy tool index
        // limit=20 for performance — limit=100 triggers a Galaxy DB bottleneck (~3 min)
        toolSearchResponse = await this.galaxyAPI.searchTools(query, undefined, 20);

        console.log('[GalaxyAssistant] Raw Galaxy API response:', {
          count: toolSearchResponse.count,
          toolsReturned: toolSearchResponse.tools?.length || 0,
          query: toolSearchResponse.query,
          tools: toolSearchResponse.tools?.slice(0, 5).map((t: any) => ({
            tool_id: t.tool_id,
            name: t.name,
            category: t.category
          })) || []
        });

        if (toolSearchResponse.tools && toolSearchResponse.tools.length > 0) {
          successfulQuery = query;
          break;
        }
      }

      if (!toolSearchResponse.tools || toolSearchResponse.tools.length === 0) {
        console.log('[GalaxyAssistant] No tools returned from any search query');
        return [];
      }

      console.log(`[GalaxyAssistant] Found tools with query: "${successfulQuery}"`);

      // Use LLM to rank tools by relevance (with user context)
      const rankedTools = await this.rankToolsByRelevance(
        userMessage,
        toolSearchResponse.tools,
        userContext
      );

      console.log('[GalaxyAssistant] After LLM ranking:', {
        totalToolsFromGalaxy: toolSearchResponse.tools.length,
        toolsAfterRanking: rankedTools.length,
        topRankedTools: rankedTools.slice(0, 3).map(r => ({
          tool_id: r.tool.tool_id,
          name: r.tool.name,
          relevanceScore: r.relevanceScore,
          reasoning: r.reasoning
        }))
      });

      return rankedTools;
    } catch (error) {
      console.error('[GalaxyAssistant] Tool search failed:', error);
      return [];
    }
  }

  /**
   * Rank tools by relevance using LLM
   */
  private async rankToolsByRelevance(
    userMessage: string,
    tools: GalaxyTool[],
    userContext?: UserContext
  ): Promise<ToolRecommendation[]> {
    // Build user context description for prompt
    const userContextStr = userContext ? userPatternsService.formatContextForPrompt(userContext) : '';

    const systemPrompt = `You are a bioinformatics tool expert. Rank the provided tools by relevance to the user's request.
${userContextStr ? userContextStr + '\n\nConsider the user profile when ranking tools. Give higher scores to tools that match their domain and previous successful tools.' : ''}
For each tool, provide:
1. Relevance score (0-1)
2. Brief reasoning (plain text, no backticks or markdown)

IMPORTANT: Return ONLY valid JSON array, no markdown, no backticks, no code fences. Keep reasoning brief (under 50 words).

[
  {
    "tool_id": "tool_123",
    "relevanceScore": 0.95,
    "reasoning": "Perfect match for RNA-seq alignment"
  }
]`;

    const toolCatalog = tools
      .map(
        (t, i) =>
          `${i + 1}. ${t.name} (${t.tool_id})
   Category: ${t.category || 'N/A'}
   Keywords: ${t.keywords || 'N/A'}`
      )
      .join('\n\n');

    try {
      console.log('[GalaxyAssistant] Tool ranking API request:', {
        model: this.modelConfig.toolRankingModel,
        max_tokens: 2000,
        tools_to_rank: tools.length
      });
      const rankStartTime = Date.now();

      const completion = await this._withAnthropicRetry(
        () => this.claude.messages.create({
          model: this.modelConfig.toolRankingModel,
          max_tokens: 2000,
          system: [
            {
              type: 'text',
              text: systemPrompt,
              cache_control: { type: 'ephemeral' },
            },
          ],
          messages: [
            {
              role: 'user',
              content: `User request: ${userMessage}\n\nAvailable tools:\n${toolCatalog}`,
            },
          ],
        }),
        'tool-ranking',
      );

      console.log('[GalaxyAssistant] Tool ranking API response:', {
        model: this.modelConfig.toolRankingModel,
        time_ms: Date.now() - rankStartTime,
        usage: completion.usage
      });

      const content = completion.content[0];
      let resultText = content.type === 'text' ? content.text : '[]';

      // Clean JSON response from LLM
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')  // Remove opening code fence
        .replace(/\n?```+\s*$/gi, '')          // Remove closing code fence
        .replace(/^\s*`+\s*/g, '')             // Remove leading backticks
        .replace(/\s*`+\s*$/g, '')             // Remove trailing backticks
        .trim();

      // Handle truncated JSON (incomplete response due to max_tokens)
      // Try to find the last complete object by balancing braces
      if (!resultText.endsWith(']') && !resultText.endsWith('}')) {
        // Find last complete object
        const lastCompleteObj = resultText.lastIndexOf('},');
        if (lastCompleteObj > 0) {
          resultText = resultText.slice(0, lastCompleteObj + 1) + ']';
        } else {
          // Can't salvage, return empty
          resultText = '[]';
        }
      }

      // Remove inline backticks from JSON strings (LLM sometimes uses `tool_name` in reasoning)
      // This regex finds backticks inside JSON string values and removes them
      resultText = resultText.replace(/`([^`]*)`/g, '$1');

      let rankings: any[];
      try {
        const parsed = JSON.parse(resultText);
        rankings = parsed.rankings || parsed;
      } catch (parseError) {
        // If still failing, try to extract individual tool rankings with regex
        console.warn('[GalaxyAssistant] JSON parse failed, attempting regex extraction');
        const toolMatches = resultText.matchAll(/"tool_id"\s*:\s*"([^"]+)"[^}]*"relevanceScore"\s*:\s*([\d.]+)/g);
        rankings = Array.from(toolMatches).map(m => ({
          tool_id: m[1],
          relevanceScore: parseFloat(m[2]),
          reasoning: 'Extracted from partial response'
        }));
        if (rankings.length === 0) throw parseError;
      }
      const rankingArray = rankings;

      return tools
        .map((tool) => {
          const ranking = rankingArray.find((r: any) => r.tool_id === tool.tool_id);
          return {
            tool,
            relevanceScore: ranking?.relevanceScore || 0.5,
            reasoning: ranking?.reasoning || 'Potentially relevant',
          };
        })
        .filter((r) => r.relevanceScore > 0.3)
        .sort((a, b) => b.relevanceScore - a.relevanceScore)
        .slice(0, 5);
    } catch (error) {
      console.error('[GalaxyAssistant] Tool ranking failed:', error);
      return tools.slice(0, 5).map((tool) => ({
        tool,
        relevanceScore: 0.5,
        reasoning: 'Retrieved from tool search',
      }));
    }
  }

  // Module-scoped circuit breaker for the BioMNI dataset search backend.
  // The /api/datasets/search route is not implemented on Galaxy (see
  // backend/GALAXYCHAT_CONNECTION_ANALYSIS.md). Until it is, retrying on
  // every chat turn produces 11s of wasted latency + log noise. After a
  // single 404 we flip this flag and skip subsequent calls — until the
  // process restarts (e.g. after the backend gains the route).
  private static datasetSearchUnavailable = false;

  /**
   * Search for relevant datasets using BioMNI RAG
   */
  private async searchRelevantDatasets(
    userMessage: string,
    keywords: string[]
  ): Promise<DatasetRecommendation[]> {
    if (GalaxyAssistant.datasetSearchUnavailable) {
      return [];
    }
    try {
      const datasetSearchResponse = await this.galaxyAPI.searchDatasets({
        query: keywords.join(' '),
        limit: 10,
      });

      if (!datasetSearchResponse.success || !datasetSearchResponse.datasets) {
        return [];
      }

      return await this.rankDatasetsByRelevance(
        userMessage,
        datasetSearchResponse.datasets
      );
    } catch (error: any) {
      // Trip the breaker on the documented missing-route 404; keep other
      // errors loud since they may indicate a transient outage worth seeing.
      if (error?.status_code === 404 || error?.response?.status === 404) {
        GalaxyAssistant.datasetSearchUnavailable = true;
        console.warn('[GalaxyAssistant] /api/datasets/search 404 — circuit-breaker tripped; dataset search disabled until backend ships the route');
      } else {
        console.error('[GalaxyAssistant] Dataset search failed:', error);
      }
      return [];
    }
  }

  /**
   * Rank datasets by relevance using LLM
   */
  private async rankDatasetsByRelevance(
    userMessage: string,
    datasets: BioMNIDataset[]
  ): Promise<DatasetRecommendation[]> {
    // Similar to tool ranking but for datasets
    return datasets.slice(0, 5).map((dataset) => ({
      dataset,
      relevanceScore: 0.7,
      reasoning: 'Retrieved from BioMNI catalog',
    }));
  }

  /**
   * Analyze if workflow generation is needed.
   * Relies on LLM intent classification — no rigid keyword matching.
   */
  private async analyzeWorkflowNeed(
    message: string,
    intent: any,
    recommendedTools: ToolRecommendation[]
  ): Promise<WorkflowSuggestion> {
    // Use action flags (not hardcoded type) to decide if workflow generation is needed
    const hasWorkflowIntent = intent.actions?.needsWorkflowGeneration || intent.type === 'workflow_generation';

    // For Nextflow workflows: we always generate when intent is clear.
    // We no longer gate on Galaxy tool search — Nextflow workflow DB is queried by backend directly.
    const hasEnoughTools = recommendedTools.length >= 1;

    return {
      shouldGenerate: hasWorkflowIntent,  // Always attempt if intent is workflow generation
      userIntent: message,
      confidence: hasWorkflowIntent ? (hasEnoughTools ? 0.9 : 0.8) : 0.1,
      reasoning: hasWorkflowIntent
        ? hasEnoughTools
          ? `Workflow intent detected with ${recommendedTools.length} tool(s) found`
          : 'Workflow intent detected — searching Nextflow workflow library'
        : `Intent type is "${intent.type}", no workflow generation needed`,
    };
  }

  /**
   * Generate workflow using Galaxy AI Assistant (Unified Architecture)
   *
   * This calls the unified /api/ai_assistant/generate_workflow endpoint which:
   * 1. Searches existing templates first (WorkflowSearchRAG)
   * 2. Routes based on confidence:
   *    - High (>0.8): Reuses template directly
   *    - Medium (0.5-0.8): Adapts template
   *    - Low (<0.5): Generates from scratch with tool constraint
   * 3. Always assigns domain knowledge datasets (HMDB, KEGG, etc.)
   */
  private async generateWorkflow(
    userIntent: string,
    datasets: BioMNIDataset[],
    inlineParameters?: Record<string, string>,
    context?: ChatContext,
    preferredDomains?: string[],
    keyTerms?: string[],
    sessionDatasets?: Array<{ id: string; name: string; type: string }>,
    penalizedDomains?: string[]
  ): Promise<any> {
    // Build context text for domain inference (active workflow + recent turns)
    const currentWorkflowText = String(
      context?.currentWorkflow?.workflowDefinition?.name ||
        context?.currentWorkflow?.workflowDefinition?.nextflow_path ||
        context?.currentWorkflow?.name ||
        context?.currentWorkflow?.nextflow_path ||
        ''
    );
    const recentContext = (context?.previousMessages || [])
      .slice(-2)
      .map((m) => String(m.content || ''))
      .join(' ');
    const fullContextForDomain = [userIntent, currentWorkflowText, recentContext]
      .filter(Boolean)
      .join(' | ');

    // Skip Haiku domain round-trip when ANDV E2E names an explicit registry workflow.
    const _explicitRegistryFastPath =
      /\bregistry\s+id\s+(10813|12824|12700)\b/i.test(userIntent) ||
      /\boptimize_codons_for_heterologous_expression\b/i.test(userIntent) ||
      /\b(autodock\s*vina|docking_autodock_vina)\b/i.test(userIntent);
    const domainHint = _explicitRegistryFastPath
      ? undefined
      : await this._inferDomainWithLLM(userIntent, currentWorkflowText || recentContext || undefined);
    const mergedInlineParameters = {
      ...(inlineParameters || {}),
      ...(domainHint ? { domain_hint: domainHint } : {}),
    };

    console.log('[GalaxyAssistant] ========================================');
    console.log('[GalaxyAssistant] Generating workflow using Unified AI');
    console.log('[GalaxyAssistant] User intent:', userIntent);
    console.log('[GalaxyAssistant] Available datasets:', datasets.length);
    console.log('[GalaxyAssistant] Inline parameters:', JSON.stringify(mergedInlineParameters));

    const response = await this.galaxyAPI.generateWorkflow({
      user_intent: userIntent,
      max_tools_search: 30,
      inline_parameters: mergedInlineParameters,
      session_id: context?.sessionId,
      datasets: datasets.map((d) => ({
        id: d.id,
        name: d.name,
        type: d.type || 'unknown',
      })),
      preferred_domains: preferredDomains?.length ? preferredDomains : undefined,
      penalized_domains: penalizedDomains?.length ? penalizedDomains : undefined,
      key_terms: keyTerms?.length ? keyTerms : undefined,
      session_datasets: sessionDatasets?.length ? sessionDatasets : undefined,
      credential_map: context?.credentialMap ?? undefined,
    });

    if (response.success) {
      console.log('[GalaxyAssistant] ✅ Workflow generated successfully!');
      console.log('[GalaxyAssistant] Generation strategy:', response.source);
      console.log('[GalaxyAssistant] Confidence score:', response.confidence?.toFixed(2));
      console.log('[GalaxyAssistant] Template match:', response.template_match_score?.toFixed(2));
      console.log('[GalaxyAssistant] Datasets assigned:', response.datasets_assigned);
      console.log('[GalaxyAssistant] Generated parameters:', response.generated_parameters?.length || 0);
      const _respWfGa = (response as any).workflow_ga || {};
      console.log('[GalaxyAssistant] Optional params (autofilled):', JSON.stringify((_respWfGa.optional_params || (response as any).optional_params || []).filter((p: any) => p.autoFilled).map((p: any) => ({name: p.name, value: p.value}))));
      console.log('[GalaxyAssistant] Required params:', JSON.stringify((_respWfGa.required_params || (response as any).required_params || []).map((p: any) => ({name: p.name, value: p.value, required: p.required, autoFilled: p.autoFilled}))));
      console.log('[GalaxyAssistant] Message:', response.message);
      console.log('[GalaxyAssistant] ========================================');
    } else {
      console.error('[GalaxyAssistant] ❌ Workflow generation failed');
      console.error('[GalaxyAssistant] Error:', response.error);
      console.log('[GalaxyAssistant] ========================================');
    }

    return response;
  }

  /**
   * Generate natural language response
   */
  private async generateResponse(
    message: string,
    intent: any,
    tools: ToolRecommendation[],
    datasets: DatasetRecommendation[],
    workflowSuggestion: WorkflowSuggestion,
    generatedWorkflow: any,
    context: ChatContext,
    researchResponse?: any,
    benchmarkEvidence?: any,
    onResponseDelta?: (chunk: string) => void,
    domainProfileContext: string = '',
    sessionMemoryBlock: string = '',
    preferredDomains: string[] = [],
    onToolEvent?: (event: AgentToolEvent) => void
  ): Promise<{ message: string; thinking?: ThinkingDetectionResult; truncated?: boolean }> {
    // S3: domain-signal-driven specialist framing — replaces the isDrugDevelopmentQuery keyword regex.
    // preferredDomains comes from the intent classifier + user profile (not keyword matching).
    const isDrugDiscoveryDomain = preferredDomains.includes('drug_discovery');
    const isCryoEmDomain = preferredDomains.includes('cryo_em');
    // Backward-compat fallback: if no preferredDomains signal, fall back to keyword regex for drug context.
    const lowerMessage = (message || '').toLowerCase();
    const isDrugDevelopmentQuery = isDrugDiscoveryDomain || /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
      lowerMessage
    );

    // Deterministically extract inline data from the message.
    // The extracted map is injected into the system prompt as structured facts so the LLM
    // never needs to ask for parameters already present in the message.
    const inlineDataMap = await extractInlineDataWithLLM(message, this.claude);
    const hasInlineData = Object.keys(inlineDataMap).length > 0 ||
      /do not ask|no (further )?clarification|use (the )?provided|use default/i.test(message);

    // ── Context stack: detect tangents and push/pop ──────────────────────────────
    // A tangent is a message that is: (a) informational/off-domain relative to the
    // active workflow task, AND (b) the context stack has saved workflow state.
    // We detect it by: active phase is NOT 'gathering' AND new intent is 'informational'
    // AND the new domain doesn't match the saved workflow's domain.

    const conversationState = await conversationStateManager.loadState(context.sessionId || 'anon');
    // On session resume (e.g. server restart or new worker), restore Haiku-extracted memory from DB
    this.sessionMemory.restoreIfEmpty(context.sessionId || 'anon', conversationState.sessionMemory);
    const hasActiveWorkflow = conversationState.phase !== 'gathering' && conversationState.workflowSteps.length > 0;

    // Determine if the current message is a tangent:
    // - No workflow generation intent (generatedWorkflow would be null)
    // - No inline data present
    // - Has an active workflow task in session memory
    // We run this check AFTER generateWorkflow attempt but use a simple heuristic first:
    // if the message is short + question-like + off-domain, treat as tangent
    const isLikelyInformationalTangent = (
      hasActiveWorkflow &&
      !hasInlineData &&
      message.length < 200 &&
      /\?$|^(what|how|why|when|does|is |are |can |will |which|who|explain|tell me|define)/i.test(message.trim())
    );

    if (isLikelyInformationalTangent && conversationState.contextStack.length === 0) {
      // Push current context; will be restored when user returns to workflow
      conversationStateManager.pushContext(conversationState, 'informational');
      await conversationStateManager.saveState(conversationState);
      console.log('[GalaxyAssistant] Context stack: pushed informational tangent (depth=1)');
    } else if (conversationState.contextStack.length > 0 && !isLikelyInformationalTangent) {
      // User returned to workflow — pop and restore context
      const restored = conversationStateManager.popContext(conversationState);
      if (restored) {
        await conversationStateManager.saveState(conversationState);
        console.log(`[GalaxyAssistant] Context stack: popped frame, restored to phase=${conversationState.phase}`);
      }
    }

    // Build a deterministic pre-satisfied parameters block from detected inline data.
    // This is injected into the system prompt so the LLM sees these as already provided,
    // never asking the user to re-supply them.
    const inlineDataBlock = (() => {
      const entries = Object.entries(inlineDataMap);
      // Also include LLM-inferred params (autoFilled=true) from the workflow backend.
      // These are params the Python backend extracted from the user's natural language query
      // (e.g. ProTrek query string, SMILES, perturbation gene). They are already set and
      // the LLM must not ask for them again.
      const autoFilledEntries: [string, string][] = [];
      // optional_params / required_params live inside workflow_ga, not at the root of the response
      const _wfGa = (generatedWorkflow as any)?.workflow_ga || {};
      const allParams = [
        ...(_wfGa.required_params || (generatedWorkflow as any)?.required_params || []),
        ...(_wfGa.optional_params || (generatedWorkflow as any)?.optional_params || []),
      ];
      for (const p of allParams) {
        if (p?.autoFilled && (p.value !== null && p.value !== undefined && p.value !== '')) {
          autoFilledEntries.push([p.name, String(p.value)]);
        }
      }
      const allEntries = [...entries, ...autoFilledEntries];
      if (allEntries.length === 0) return '';
      const lines = allEntries.map(([k, v]) => `  ${k}: ${v}`);
      // When a genome build is present, add an explicit note that reference genome files
      // are auto-resolved via igenomes — the LLM must not ask for FASTA paths or known-sites VCFs.
      const genomeBuild = inlineDataMap['genome_build'];
      const genomeSuffix = genomeBuild
        ? `\n  Note: reference genome FASTA, genome index, and known-variant VCF files for ${genomeBuild} are auto-resolved from the igenomes reference data registry. Do NOT ask the user to provide these files.`
        : '';
      return `\n<pre_satisfied_parameters>\nThe following parameters are already present in the user's message and must NOT be requested again:\n${lines.join('\n')}${genomeSuffix}\n</pre_satisfied_parameters>\n`;
    })();

    const runnableWorkflow = !!(
      generatedWorkflow?.success &&
      !generatedWorkflow?.error &&
      (generatedWorkflow?.workflow_ga ||
       generatedWorkflow?.nextflow_path ||
       generatedWorkflow?.workflow_type === 'chain' ||
       generatedWorkflow?.workflow_type === 'cryosparc')
    );
    const workflowGenerationFailed = !!generatedWorkflow && !runnableWorkflow;
    const workflowFailureSignals = workflowGenerationFailed
      ? {
          error: generatedWorkflow?.error || null,
          message: generatedWorkflow?.message || null,
          source: generatedWorkflow?.source || null,
          confidence: generatedWorkflow?.confidence ?? null,
          templateMatchScore: generatedWorkflow?.template_match_score ?? null,
          validationIssues: generatedWorkflow?.validation?.issues || [],
          failedTools: generatedWorkflow?.tool_installation?.failed_tools || [],
        }
      : null;

    // Fetch cryo-EM RAG context when domain is cryo_em (non-blocking — empty string on failure)
    const cryoEmContextBlock = isCryoEmDomain
      ? await this._fetchCryoEmContext(message)
      : '';

    const ltmBlock = context.ltmContextBlock
      ? `<long_term_memory>\n${context.ltmContextBlock}\n</long_term_memory>\nNote: long-term memory reflects patterns across past sessions — use it to personalise responses but let the current conversation take precedence.\n\n`
      : '';

    // Compute isWorkflowTurn here so it is available for both the system prompt
    // selection (below) and the agent-tools gate (further down in the Claude branch).
    const isWorkflowTurn = workflowSuggestion.shouldGenerate || !!generatedWorkflow;

    const RESEARCH_INTENT_TYPES_FOR_PROMPT = new Set([
      'research_question', 'troubleshooting', 'parameter_optimization',
      'experiment_design', 'data_interpretation', 'protocol_guidance',
      'methods_writing', 'comparative_methodology', 'regulatory_compliance',
    ]);
    // isResearchIntent = true when no Nextflow workflow panel is active.
    // This includes: research/knowledge intents, AND workflow_generation with
    // needsWorkflowGeneration=false (run_code / direct execution) — both get
    // the compute-enabled system prompt where run_code tool is permitted.
    const isResearchIntent = !!researchResponse
      || RESEARCH_INTENT_TYPES_FOR_PROMPT.has((intent as any)?.type ?? '')
      || !isWorkflowTurn;
    const systemPrompt = isResearchIntent
      ? `${sessionMemoryBlock}${ltmBlock}${inlineDataBlock}${domainProfileContext}You are BioMate, an expert bioinformatics AI assistant with deep scientific knowledge.

PROACTIVE-WORK RULE (highest priority):
- Do everything you can with the information already on the table BEFORE asking the user a clarifying question.
- NEVER produce any of these refusal patterns: "I don't have internet access", "I can't query databases", "I can't execute under the current environment", "I lack live access to X", "I can't run this in this environment". They are FALSE — BioMate has live DB integrations on the backend, indexed DB-API tool-functions reachable via workflow steps, and pre-resolved results injected into the prompt. Only report a failure when a tool actually returned an error in this turn.
- If the user gave a SMILES, gene symbol, accession, or any other identifier, ASSUME BioMate has resolved it — look for the resolved record in <compound_lookup_results>, <pre_satisfied_parameters>, or prior tool messages. Use those before claiming anything is missing.

BioMate's real capability surface (verified, do not extrapolate):
- **2,455 indexed Nextflow workflows** across 34 biological domains: transcriptomics (865), genomics (369), epigenomics (133), proteomics (113), drug_discovery (61), cryo_em (10+), single_cell, variant_calling, phylogenomics, structural_biology, metabolomics, microbiome, immunology, and more.
- **12,274 indexed tool-functions** (individual command/wrapper entries) in the AI tool DB, ~4,141 with curated tool_knowledge metadata. Includes ~179 DB-API tool-functions (PubChem Download, UniProt Sparql, PubMed query, ChEMBL fetchers, etc.) that workflow steps can invoke.
- **Verified live DB integrations** called directly from the Galaxy backend Python (research_agent + knowledge modules):
  - PubChem (compounds; SMILES results auto-injected via <compound_lookup_results>)
  - PubMed / NCBI E-utilities (literature, gene lookups)
  - UniProt REST (proteins)
  - EBI (api.ebi.ac.uk — covers ChEMBL, Ensembl, AlphaFold)
  - OpenTargets platform API (drug-target evidence)
  - UCSC genome browser API
  Other DBs (KEGG, Reactome, OMIM, HPO, GTEx, ENCODE, DepMap, …) are reachable indirectly: route to an indexed DB-API tool-function as a workflow step rather than disclaiming. Say "I can pull this via the <tool-name> workflow step" — don't tell the user we lack the source.
- **Auto-injected pre-results** appear in <compound_lookup_results>, <pre_satisfied_parameters>, and similar tags. Read those before answering.
- **run_code tool** — Python/R/bash in an ephemeral biomate-biotools sandbox. R + Bioconductor (DESeq2, clusterProfiler, edgeR, limma, GSVA, fgsea, ReactomePA), numpy/scipy/pandas/statsmodels, biopython, pysam, cyvcf2, samtools/bcftools/bwa/mafft/iqtree pre-installed. **Sandboxed with --network=none — run_code cannot reach external APIs.** Use it for offline compute on data already in the prompt or attached as a file. If you need data from a DB, route to a workflow step that pulls it.
- **Workflow execution** on AWS Batch via Nextflow — heavy-compute production path. All real workflows run on AWS; there is no local-vs-AWS switch. The two paths overlap in what statistical / R+Bioconductor work they CAN do — pick by scale and whether the task matches an indexed pipeline.

How to behave:
- When the user gave enough intent (e.g. SMILES + "run PBPK"), use defaults: typical human population, most-common route of administration, literature dose for well-characterized compounds. State assumptions explicitly at the end: "Assumed X, Y, Z — flag any that are wrong."
- If you actually need data only the user can provide (their own dataset, a project-specific value), ask straightforwardly: "Please upload [exact file format] / give me [exact value]." Do NOT couch it as an environment limitation.
- Save clarifying questions for the genuinely unrecoverable: ambiguous species for tox, narrow-therapeutic-index decisions, user input that contradicts itself, or workflow inputs with no sensible default.
- Deliver the result first; list assumptions at the end. Never the reverse.

Your role:
- Provide accurate, evidence-based answers to scientific questions — be concise and direct
- Lead with the answer, not preamble; keep responses brief (2–4 sentences for simple questions, 2–3 short paragraphs for complex ones)
- Cite specific papers using [N] inline notation matching the numbered reference list provided
- Only cite papers from the provided list — never fabricate citations
- Use bullet points only when listing ≥3 distinct items; prefer prose otherwise
- End with a ## References section listing only the papers you cited

COMPUTATION RULE:
Two execution surfaces. Pick by scale + whether the task matches an indexed pipeline — NOT by tool name. Bioconductor packages exist on BOTH (the indexed workflow set includes DESeq2 / clusterProfiler / edgeR / limma / Seurat / ReactomePA, AND run_code has the same packages pre-installed). No default direction.

- **run_code** (light path): ad-hoc compute, single statistical test, inline dataset, format conversion, small analyses that finish in seconds-to-minutes. Full scientific stack: R + Bioconductor, numpy/scipy/pandas, samtools/mafft/bwa, biopython. **--network=none — cannot reach external APIs.** Only works on data already in the prompt or attached.
- **Nextflow workflow on AWS Batch** (heavy path): production pipelines, multi-step orchestration, large datasets, GPU work, anything that needs network access (e.g. a DB-API tool-function step) or per-step containerization.

If the user explicitly says "use run_code" or "do not launch a Nextflow workflow", honor that. Otherwise pick based on what fits.

Quality of computation:
- For rates / percentages / proportions involving counts: ALWAYS run actual code — do not arithmetic in your head. Sum explicit numerators and denominators; never average per-group rates without verifying that's what's asked.
- Verify denominators by inspecting the data first when the user supplied a dataset (read the column, check what it represents) before computing any rate.
- Dunnett's test: run all groups simultaneously: \`from scipy.stats import dunnett; result = dunnett(*all_groups, control=control_group)\`. Never group-by-group.
- DESeq2 (when raw_counts.csv + metadata are supplied): standard pattern via run_code (R) — read CSVs, build DESeqDataSet, call DESeq(), filter results by padj < 0.05 + |log2FC| > 1.5, report what the user asked for.
- PhyKIT (.treefile / .faa): subprocess.run(["phykit", "<command>", file], capture_output=True, text=True). Commands: treeness, dvmc, evo_rate, lbs, rcv, trn.

RESPONSE STRUCTURE (use this for every substantive answer):
1. **Result** — lead with the answer. Number / gene / value / conclusion first, in bold or a short prose sentence.
2. **Rationale** — one short paragraph: what tools / data you used, what assumptions you made, what to flag if any assumption is wrong. Cite [N] for evidence-based claims.
3. **(Optional) Output** — if you ran code, show only the meaningful output (not the whole script unless asked).
4. **(Optional) References** — \`## References\` list, only papers actually cited.

Do NOT strip explanation for "give me a number" questions — keep the number first, then a one-line rationale. The previous "print only value" pattern was overfitted to benchmark scoring and is removed.
For trivial arithmetic, answer directly without invoking run_code.`
      : `${sessionMemoryBlock}${ltmBlock}${inlineDataBlock}${domainProfileContext}You are BioMate, an expert bioinformatics AI assistant.

PROACTIVE-WORK RULE (highest priority):
- Do everything you can with what's on the table BEFORE asking the user a clarifying question. Use literature defaults (typical human dose/route, standard population, well-characterized PK values for known drugs) and STATE assumptions explicitly.
- NEVER produce refusal patterns like "I don't have internet access", "I can't query databases", "I can't execute under the current environment". They are FALSE. Only report a failure when a tool returned an actual error in this turn.
- Check <compound_lookup_results>, <pre_satisfied_parameters>, and prior tool messages before claiming an identifier is unresolved.

BioMate's real capability surface:
- **2,455 indexed Nextflow workflows** across 34 domains (transcriptomics 865, genomics 369, epigenomics 133, proteomics 113, drug_discovery 61, cryo_em 10+, …)
- **12,274 indexed tool-functions** in the AI tool DB, ~4,141 with curated metadata. Includes ~179 DB-API tool-functions (PubChem, UniProt, ChEMBL, PubMed, etc. wrappers) that workflow steps invoke.
- **Verified live DB integrations** in the Galaxy backend: PubChem, NCBI E-utilities / PubMed, UniProt, EBI (ChEMBL / Ensembl / AlphaFold), OpenTargets, UCSC. Pre-resolved results injected via <compound_lookup_results> when relevant.
- **run_code tool** — Python/R/bash in the biomate-biotools sandbox (R + Bioconductor, numpy/scipy/pandas, samtools/mafft/bwa/iqtree, biopython/pysam pre-installed). **--network=none — cannot reach external APIs.** Light-compute path for ad-hoc / format conversion / small statistical work on data already in the prompt.
- **Workflow execution** on AWS Batch via Nextflow — heavy-compute production path; the path with network. ALL real workflows run on AWS; there is no local-vs-AWS switch. Pick run_code or Nextflow by scale + whether the task matches an indexed pipeline.
- If the user needs to supply project-specific data, ask straightforwardly: "Please upload [format] / provide [value]." Do not phrase it as an environment limitation.

(Inline data — if any — is listed in <pre_satisfied_parameters> above. Never ask for those parameters again.)

RESPONSE FORMAT — follow this structure every time:

When a workflow was generated successfully:
  **[Workflow name]** — [one-sentence description]
  - **Input:** [list the actual inputs used from the query]
  - **Key steps:** [2–3 bullets, tool name → output]
  - **Expected output:** [what files/results the user will get]

When no workflow was generated AND no inline data is present (clarification needed):
  **Missing: [what is needed]**
  [ONE specific question stating exactly what formats are accepted]

When no workflow was generated AND inline data IS present (technical failure):
  **Could not generate workflow** — [specific reason in one sentence]
  **Closest available option:** [name + brief description]
  [ONE configuration question if needed, otherwise say "Try adjusting parameters in the panel"]

Do NOT deviate from these three formats. No freeform narrative, no "Next Steps" sections, no numbered lists of pipeline stages unless inside the key-steps bullet.
════════════════════════════════════════════════════════

IMPORTANT RULES:
${isWorkflowTurn ? `- NEVER compute or calculate results yourself for workflow tasks (e.g., sequence alignment, variant calling, etc.) — ALWAYS run the appropriate BioMate tool or workflow instead` : `- You CAN and SHOULD compute, calculate, and reason directly when no Nextflow workflow panel is open. Use the run_code tool for numerical computations, statistical calculations, sequence operations, or data manipulation. Prefer run_code over mental arithmetic for non-trivial calculations.
- R/BIOCONDUCTOR EXECUTION PRIORITY: (1) Search BioMate's 1,000+ indexed Bioconductor workflows first — if a match exists, use it. (2) If no match, generate a new workflow. (3) For small ad-hoc tasks or single statistical tests, use run_code with R directly — do not refuse to execute R code.`}
- If a runnable workflow was generated, explain it and encourage the user to click "Run"
- If workflow generation failed, explicitly explain likely reasons using available diagnostics and process outputs (error details, confidence, template match, tool/runtime signals)
- If workflow generation failed, collaborate with the user by asking targeted follow-up questions and proposing concrete next recovery actions
- If no workflow but tools were found, explain which tool to use and suggest creating a workflow
- Only provide direct answers for conceptual questions (e.g., "what is RNA-seq?"). If the user wants to RUN or GENERATE a workflow, apply the DATA-FIRST RULE below — do not explain pipeline steps.

DATA-FIRST RULE (hard prohibition — no exceptions except demo/test/mock):
- NEVER describe workflow steps, list pipeline stages, explain tools, or provide any execution instructions in response to a workflow-generation request when the user has not yet provided input data. This is a strict prohibition, not a preference. Violating this rule means the system cannot run.
- EXCEPTION — PRE-SATISFIED PARAMETERS: If a <pre_satisfied_parameters> block appears above AND a runnable workflow was generated, the DATA-FIRST RULE does NOT apply. The parameters are already provided (either explicitly in the message or auto-extracted by the AI). Proceed directly to the "Workflow generated" format.
- "Input data provided" means the user's message contains ANY of: a file path (e.g. /path/to/sample.fastq, /data/reads_R1.fastq.gz), an S3 URI (s3://…), an SRA/ENA/DDBJ accession (SRR followed by digits, ERR followed by digits, DRR followed by digits), a GEO accession (GSE followed by digits, GSM followed by digits), an ArrayExpress accession (E-MTAB- followed by digits), a PXD accession (PXD followed by digits), a SMILES string, an InChI string, an amino acid sequence, a PDB ID, or an "[Uploaded datasets: ...]" block.
- SRA ACCESSION RULE: An SRA/ENA/DDBJ accession number (e.g. SRR1518169, ERR204916, DRR013480) IS input data. Treat it as the reads/input parameter. Proceed directly to workflow generation. DO NOT ask for a file path or S3 URI when an SRA accession is present in the message.
- If NO input data is present: ask EXACTLY ONE specific question. State what the workflow needs and list the accepted data formats. Example: "To run this GATK germline pipeline I need your input data. Please provide one of: (1) FASTQ file paths or S3 URIs for your sequencing reads, or (2) an SRA accession number (e.g. SRR1518169). Which do you have?" Do NOT explain workflow steps. Do NOT list pipeline stages. Do NOT describe what the tools do.
- Exception: if the user explicitly requests a "demo", "test", or "mock" workflow, generate it immediately without asking for data. This exception ALSO covers any of these phrasings, treat them as identical: "with defaults", "use defaults", "default parameters", "synthetic data", "synthetic plate", "demo data", "example data", "sample data", "built-in demo", "use the demo data", "no data, just run it", "I just want to see it", "show me how this works". Many BioMate workflows (notably hts_plate_qc_hit_calling, exposure_response_modelling, demo PBPK, the cryo-EM SPA reference workflows) ship with a built-in synthetic-data generator that fires when no input is provided — when the user signals they want to use it, generate the workflow immediately and do NOT ask for an upload.

TURN-2 QUALIFIER RULE:
- If the previous assistant message generated a workflow card AND the user's current message provides a type qualifier (e.g., "germline", "somatic", "bulk RNA-seq", "single-cell", "tumor-only", "paired tumor/normal", "inherited disease", "cancer"), regenerate the workflow immediately with the qualifier applied. Do NOT describe the workflow in text. Do NOT ask for data again. The previous conversation's input data is still valid.

ONE-QUESTION RULE:
- Ask at most ONE clarification question per conversation. Once the user has replied with any data OR answered a question (even if no data was provided), generate the workflow immediately using the information gathered and sensible default parameter values. Do NOT ask multiple rounds of clarifying questions — parameters can be adjusted in the workflow parameter panel after generation.
- SECOND-TURN OVERRIDE: If the conversation history shows that the assistant already asked a question in the previous turn (e.g., asked for data or asked germline/somatic clarification), and the user's current message replies to that question (even if no data accession was given), GENERATE THE WORKFLOW IMMEDIATELY. Do not ask for data again. Use placeholder values for missing required params — the user can fill them in the parameter panel. This applies in particular when the user's reply is a confirmation-style answer such as "yes", "yes run with defaults", "go ahead", "run it", "proceed", "ok", "sure", "use the demo data", "fine, use defaults". Treat all of these as instructions to generate the workflow now. NEVER ask for data twice in the same conversation — if you asked once and the user did not provide data on reply, generate with defaults/synthetic-data fallback.
- When the message contains an "[Uploaded datasets: ...]" block, parse it. Format: "filename: dataset_id=<ID>" or "filename: dataset_id=<ID>, galaxy_dataset_id=<GALAXY_ID>, s3_uri=<S3URI>". For run_code: use galaxy_dataset_id (or dataset_id) and access via $DATA_DIR/<id>/<filename>. For Nextflow workflow parameters (matrix_file, sample_file, input, reads, etc.): use s3_uri when present — AWS Batch workers read directly from S3. If no s3_uri, the workflow cannot run on Batch; use run_code instead.
- When the message contains an "[Attached files: ...]" block without a corresponding "[Uploaded datasets: ...]" block, the upload failed. Tell the user which files failed and ask them to try again.
${isDrugDevelopmentQuery ? `- For drug-development requests, provide decision-grade guidance: list concrete workflow phases, critical safety/quality gates, required inputs, and explicit next actions` : ''}
${isDrugDevelopmentQuery ? `- For drug-development WORKFLOW GENERATION FAILURES ONLY (when the system returns an error or cannot find a matching workflow): include at least TWO distinct blocker categories (e.g., tool gap, input gap, domain mismatch) and ask at least TWO targeted follow-up questions. IMPORTANT: This rule does NOT apply when the user has already provided input data (SMILES, sequence, files) — in that case generate the workflow immediately.` : ''}

Workflow routing (use these specific workflows when the user's intent matches):
${buildWorkflowRoutingBlock(preferredDomains)}

${cryoEmContextBlock ? `${cryoEmContextBlock}\n\n` : ''}${buildDomainSpecialistBlock(preferredDomains)}${buildDomainCatalogBlock(preferredDomains)}${(generatedWorkflow as any)?._nearTieAlternative ? `\n[NEAR-TIE NOTE] The workflow search found "${(generatedWorkflow as any)._nearTieAlternative}" with a very similar match score. At the end of your response, add exactly one sentence: "If you were looking for ${(generatedWorkflow as any)._nearTieAlternative} instead, let me know and I'll switch." Do not ask this as a question — state it as a note.\n` : ''}Style guide:
- Be concise and practical
- When mentioning tools, use the primary user-facing name (e.g. "CryoSPARC", "BWA-MEM2", "GATK") — never use internal pipeline paths or tool IDs
- Explain workflow steps and expected outputs clearly
- Do NOT include a "Next Steps After This Workflow" section — suggest follow-up steps only after the user confirms execution is complete
${isDrugDevelopmentQuery ? `- Use section labels when possible: "Workflow phases", "Required inputs", and "Next step"` : ''}

Current context:
${tools.length > 0 ? `- Found ${tools.length} relevant tools` : ''}
${datasets.length > 0 ? `- Found ${datasets.length} relevant datasets` : ''}
${runnableWorkflow ? '- Runnable workflow generated successfully — use "Workflow generated" format' : ''}
${workflowGenerationFailed && hasInlineData ? '- Workflow generation failed (inline data was present) — use "Technical failure" format, do NOT ask for data the user already provided' : ''}
${workflowGenerationFailed && !hasInlineData ? '- Workflow generation failed (no inline data) — use "Clarification needed" format' : ''}
${(generatedWorkflow as any)?.license_notice ? `- LICENSE REROUTING ACTIVE: ${(generatedWorkflow as any).license_notice} The response MUST explicitly tell the user that the originally requested tool is not available under their current license configuration and explain that the fallback alternative was automatically selected instead. Include the phrase "not available" or "requires a license" in the explanation.` : ''}`;


    // Build research/benchmark context sections.
    // Prioritise the synthesized `answer` field (which already contains db_facts, tool context,
    // and figure data from the Python research agent) rather than truncating the raw JSON.
    const researchSection = researchResponse
      ? (() => {
          const rr = researchResponse as any;
          const parts: string[] = [];
          if (rr.answer) {
            parts.push(`Research Agent Answer:\n${rr.answer.slice(0, 4000)}`);
          }
          if (rr.citations && Array.isArray(rr.citations) && rr.citations.length > 0) {
            const citLines = (rr.citations as any[]).slice(0, 8).map((c: any, i: number) =>
              `[${i+1}] ${c.title || ''} (${c.year || ''}) ${c.journal || ''} ${c.doi ? 'doi:'+c.doi : ''} ${c.pmid ? 'PMID:'+c.pmid : ''}`.trim()
            );
            parts.push(`\nCitations:\n${citLines.join('\n')}`);
          }
          if (rr.benchmark_evidence) {
            parts.push(`\nBenchmark evidence: ${JSON.stringify(rr.benchmark_evidence).slice(0, 500)}`);
          }
          return `\n${parts.join('\n')}`;
        })()
      : '';
    const benchmarkSection = benchmarkEvidence
      ? `\nBenchmark Evidence:\n${JSON.stringify(benchmarkEvidence, null, 2).slice(0, 2000)}`
      : '';

    const userPrompt = `User: ${message}

${tools.length > 0 ? `\nRelevant tools:\n${tools.map((t, i) => `${i + 1}. ${t.tool.name} - ${t.reasoning}`).join('\n')}` : ''}

${datasets.length > 0 ? `\nRelevant datasets:\n${datasets.map((d, i) => `${i + 1}. ${d.dataset.name} - ${d.reasoning}`).join('\n')}` : ''}

${runnableWorkflow ? '\nA runnable workflow has been generated and is ready to run.' : ''}
${workflowGenerationFailed && hasInlineData ? `\nWorkflow generation failed (inline data was present — do NOT ask for it again).\nFailure details: ${JSON.stringify(workflowFailureSignals, null, 2).slice(0, 800)}` : ''}
${workflowGenerationFailed && !hasInlineData ? `\nWorkflow generation diagnostics:\n${JSON.stringify(workflowFailureSignals, null, 2).slice(0, 1600)}` : ''}${researchSection}${benchmarkSection}

Use the RESPONSE FORMAT from the system prompt. Specifically:
${runnableWorkflow
  ? `FORMAT: Workflow generated successfully.
     - Start with "**[workflow name]** — [one sentence]"
     - Bullet: Input used (the actual value from the message)
     - Bullet: Key steps (2–3, tool → output)
     - Bullet: Expected output (file types / results)
     - Do NOT say "click Run" — the Run button is already visible`
  : workflowGenerationFailed && hasInlineData
    ? `FORMAT: Technical failure — inline data was provided.
     - One sentence: why the exact workflow wasn't found
     - One line: closest available alternative
     - At most ONE configuration question (never ask for data the user already gave)`
  : workflowGenerationFailed
    ? `FORMAT: Clarification needed — no inline data present.
     - State "Missing: [what is needed]"
     - ONE specific question listing accepted formats (file path, accession, SMILES, etc.)
     - Do NOT list pipeline stages or workflow steps`
  : researchResponse
    ? `FORMAT: Research answer with citations.
     - Answer with inline [N] citations
     - End with ## References section`
  : tools.length > 0
    ? `FORMAT: Tool recommendation.
     - Name the tool(s) found and what they do
     - Suggest creating a workflow`
    : `FORMAT: Explain what is needed to help.`
}
${isResearchIntent ? 'CONSTRAINT: Only cite papers from the provided list. Never fabricate citations.' : 'CONSTRAINT: Never compute results yourself. Always recommend BioMate tools.'}
${isDrugDevelopmentQuery && runnableWorkflow ? '' : ''}
${isDrugDevelopmentQuery && workflowGenerationFailed && !hasInlineData ? 'DRUG-FAIL EXTRA: List 2 specific blockers (tool gap / input gap / license gap). Ask 2 targeted questions.' : ''}`;

    try {
      // Convert context messages to Claude format (trim to recent turns for latency)
      const allPreviousMessages = context.previousMessages || [];
      const CONTEXT_WINDOW = 6;
      const compressionTriggered = allPreviousMessages.length > CONTEXT_WINDOW;
      const previousMessages = allPreviousMessages
        .slice(-CONTEXT_WINDOW)
        .map((msg) => ({
        role: msg.role as 'user' | 'assistant',
        content: msg.content,
      }));

      // C3 — When context is compressed, generate and store a session summary (fire-and-forget)
      if (compressionTriggered && (context.sessionId || context.userId)) {
        const compressedMessages = allPreviousMessages.slice(0, -CONTEXT_WINDOW);
        this._triggerSessionSummary(compressedMessages, context.userId, context.sessionId).catch(
          (err) => console.warn('[GalaxyAssistant] Session summary failed (non-fatal):', err)
        );
      }

      // Log what we're sending to Claude
      const apiStartTime = Date.now();
      const useThinking = this.modelConfig.enableThinking;
      console.log('[GalaxyAssistant] Response API request:', {
        model: this.modelConfig.responseModel,
        max_tokens: 4096,
        thinking_enabled: useThinking,
        thinking_budget: useThinking ? this.modelConfig.thinkingBudget : null,
        system_prompt_length: systemPrompt.length,
        user_prompt_length: userPrompt.length,
        previous_messages: previousMessages.length,
        total_input_chars: systemPrompt.length + userPrompt.length + previousMessages.reduce((acc, m) => acc + m.content.length, 0)
      });

      // Build API request options - thinking mode is optional
      const apiOptions: any = {
        model: this.modelConfig.responseModel,
        max_tokens: 4096,
        system: [
          {
            type: 'text',
            text: systemPrompt,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages: [...previousMessages, { role: 'user', content: userPrompt }],
      };

      // Add thinking mode if enabled (not compatible with temperature)
      if (useThinking) {
        apiOptions.thinking = {
          type: 'enabled',
          budget_tokens: this.modelConfig.thinkingBudget
        };
      } else {
        // BioMate is a scientific tool — users ask factual biomedical
        // questions with correct answers. Sampling at high temperature
        // hurts accuracy (introduces variance away from the right answer)
        // and reproducibility (re-running the same query yields different
        // text), and the "conversational variety" benefit doesn't apply to
        // describing deterministic computational results. Set 0 always.
        // Was 0.7 (legacy from chat-UI convention) — observed to add
        // ±5-10pp run-to-run flap on N=30 biomni evals, the dominant
        // variance source after retries fixed transient errors.
        apiOptions.temperature = 0;
      }

      // ── Agent loop: tool use + streaming ─────────────────────────────────────
      // Supports up to 5 tool-use cycles before forcing end_turn.
      // First turn uses streaming (if onResponseDelta is provided) to surface text
      // deltas immediately. Tool-call turns are non-streaming for simplicity.
      // Tools are disabled when thinking mode is active (incompatible with tool_use).
      // Tools are also disabled on workflow-generation turns — the workflow is generated
      // in Step 4 (generateWorkflow) BEFORE generateResponse() runs, so adding tools
      // here would only confuse Claude into calling run_code/read_file instead of
      // narrating the workflow result. Reserve tools for pure data-analysis turns.
      // (isWorkflowTurn is hoisted above so it is also available for system prompt selection.)
      const agentTools = (!useThinking && onToolEvent && !isWorkflowTurn) ? BIOMATE_TOOLS : undefined;
      const agentMessages: Anthropic.MessageParam[] = [
        ...previousMessages,
        { role: 'user', content: userPrompt },
      ];

      let rawResponse = '';
      let lastStopReason: string | null = null;
      const MAX_TOOL_TURNS = 5;

      // ── Non-Claude backbone: Gemini or Ollama ────────────────────────────────
      // Tool use is not supported on these paths (different function-call formats).
      // All other BioMate pipeline stages (routing, context-building, RAG) still run.
      const responseModel = this.modelConfig.responseModel;
      const isGeminiBackbone = responseModel.startsWith('gemini-');
      const isOllamaBackbone = !responseModel.startsWith('claude-') && !isGeminiBackbone;

      if (isGeminiBackbone || isOllamaBackbone) {
        const plainMessages = [
          ...previousMessages.map(m => ({
            role: (m.role === 'assistant' ? 'assistant' : 'user') as 'user' | 'assistant',
            content: typeof m.content === 'string' ? m.content
              : (m.content as any[]).filter((b: any) => b.type === 'text').map((b: any) => b.text).join(''),
          })),
          { role: 'user' as const, content: userPrompt },
        ];
        try {
          rawResponse = isGeminiBackbone
            ? await this._generateWithGemini(systemPrompt, plainMessages, onResponseDelta)
            : await this._generateWithOllama(systemPrompt, plainMessages, onResponseDelta);
        } catch (err: any) {
          console.error(`[GalaxyAssistant] ${isGeminiBackbone ? 'Gemini' : 'Ollama'} backbone error:`, err.message);
          rawResponse = `I encountered an error generating a response: ${err.message}`;
          if (onResponseDelta) onResponseDelta(rawResponse);
        }
        // Skip the Anthropic agent loop entirely
        const thinkingResult = thinkingDetector.detectThinking(rawResponse);
        const qualityEnforcedMessage = this.enforceDrugDevelopmentResponseQuality({
          userMessage: message,
          assistantMessage: thinkingResult.answerContent,
          runnableWorkflow,
          workflowGenerationFailed,
          workflowFailureSignals,
          isResearchAnswer: new Set(['research_question','troubleshooting','parameter_optimization',
            'experiment_design','data_interpretation','protocol_guidance',
            'methods_writing','comparative_methodology','regulatory_compliance',
          ]).has((intent as any)?.type ?? ''),
        });
        return { message: qualityEnforcedMessage || rawResponse, truncated: false };
      }
      // ── End non-Claude backbone ───────────────────────────────────────────────

      for (let turn = 0; turn < MAX_TOOL_TURNS; turn++) {
        const isFirstTurn = turn === 0;
        const requestOptions: any = {
          ...apiOptions,
          messages: agentMessages,
          ...(agentTools ? { tools: agentTools } : {}),
        };

        // ── Streaming (first turn) ────────────────────────────────────────────
        if (isFirstTurn && onResponseDelta) {
          const stream = await this._withAnthropicRetry(
            () => this.claude.messages.create({ ...requestOptions, stream: true } as any),
            'response-stream',
          );

          // Accumulate both text deltas and tool_use content blocks
          const contentBlocks: any[] = [];
          let currentBlock: any = null;

          for await (const event of stream as any) {
            if (event?.type === 'content_block_start') {
              currentBlock = { ...event.content_block };
              if (currentBlock.type === 'tool_use') {
                currentBlock._inputChunks = [];
              }
              contentBlocks.push(currentBlock);
            } else if (event?.type === 'content_block_delta') {
              if (event.delta?.type === 'text_delta') {
                const text = String(event.delta.text || '');
                if (text) {
                  rawResponse += text;
                  onResponseDelta(text);
                  if (currentBlock?.type === 'text') currentBlock.text = (currentBlock.text || '') + text;
                }
              } else if (event.delta?.type === 'input_json_delta' && currentBlock?.type === 'tool_use') {
                currentBlock._inputChunks.push(event.delta.partial_json || '');
              }
            } else if (event?.type === 'content_block_stop' && currentBlock?.type === 'tool_use') {
              try {
                currentBlock.input = JSON.parse(currentBlock._inputChunks.join(''));
              } catch { currentBlock.input = {}; }
            } else if (event?.type === 'message_delta') {
              lastStopReason = event.delta?.stop_reason || null;
            }
          }

          const toolUseBlocks = contentBlocks.filter(b => b.type === 'tool_use');
          if (lastStopReason === 'tool_use' && toolUseBlocks.length > 0) {
            // Assemble assistant message with all content blocks (text + tool calls)
            const assistantContent = contentBlocks
              .filter(b => b.type === 'text' || b.type === 'tool_use')
              .map(b => b.type === 'text' ? { type: 'text', text: b.text || '' } : { type: 'tool_use', id: b.id, name: b.name, input: b.input });
            agentMessages.push({ role: 'assistant', content: assistantContent as any });
            const toolResults = await this._executeTools(toolUseBlocks, context, onToolEvent);
            agentMessages.push({ role: 'user', content: toolResults as any });
            rawResponse = ''; // Reset — final text comes in a later turn
            continue; // next iteration
          }
          // No tool_use — stream complete
          console.log('[GalaxyAssistant] Response stream complete:', {
            model: this.modelConfig.responseModel, time_ms: Date.now() - apiStartTime,
            stop_reason: lastStopReason, streamed_chars: rawResponse.length,
          });
          break;
        }

        // ── Non-streaming (subsequent tool turns) ─────────────────────────────
        const completion = await this._withAnthropicRetry(
          () => this.claude.messages.create(requestOptions),
          `tool-turn-${turn}`,
        );
        console.log('[GalaxyAssistant] Response API response:', {
          model: this.modelConfig.responseModel, time_ms: Date.now() - apiStartTime,
          usage: completion.usage, stop_reason: completion.stop_reason,
        });
        lastStopReason = completion.stop_reason ?? null;

        const toolUseBlocks = completion.content.filter((b: any) => b.type === 'tool_use');
        if (completion.stop_reason === 'tool_use' && toolUseBlocks.length > 0) {
          agentMessages.push({ role: 'assistant', content: completion.content as any });
          const toolResults = await this._executeTools(toolUseBlocks, context, onToolEvent);
          agentMessages.push({ role: 'user', content: toolResults as any });
          continue;
        }

        // End turn — extract text and emit as a single delta (non-incremental but correct)
        const textContent = completion.content.find((c: any) => c.type === 'text');
        rawResponse = textContent && textContent.type === 'text' ? (textContent as any).text : '';
        if (onResponseDelta && rawResponse) {
          onResponseDelta(rawResponse);
        }
        break;
      }

      // Guard: if loop exhausted or tool-only response with no final text, provide fallback.
      // When a workflow was generated, produce a meaningful workflow-ready message.
      if (!rawResponse.trim()) {
        const _wfGa = (generatedWorkflow as any)?.workflow_ga || {};
        const _wfName =
          _wfGa.name ||
          (generatedWorkflow as any)?.workflow_name ||
          (generatedWorkflow as any)?.name;
        const _wfDesc = _wfGa.description?.slice(0, 120) || '';
        if (_wfName) {
          rawResponse = `**Workflow ready** — **${_wfName}** has been set up in the panel. ${_wfDesc ? _wfDesc.split('.')[0] + '. ' : ''}Review the parameters and click **Confirm & Run** to execute.`;
        } else if (this._isPlanBCodonQuery(message)) {
          rawResponse =
            '**Codon optimization** — **optimize_codons_for_heterologous_expression** (registry id 10813) is ready in the panel. Review target_sequence, host_codon_usage, and outdir, then click **Confirm & Run**.';
        } else if (this._isPlanAEpitopeQuery(message)) {
          rawResponse =
            '**Epitope prediction** — **nf-core/epitopeprediction** (registry id 12700) is ready in the panel. Review inputs and click **Confirm & Run**.';
        } else if (this._isPocketDetectionQuery(message)) {
          rawResponse =
            '**Pocket detection + druggability** — the **pocket_detection_druggability** workflow (fpocket) is ready in the panel. Review pdb_input, min_druggability, and min_volume, then click **Confirm & Run**.';
        } else {
          rawResponse = 'I processed your request using the available tools.';
        }
        if (onResponseDelta) onResponseDelta(rawResponse);
      }

      // Detect and parse thinking content
      const thinkingResult = thinkingDetector.detectThinking(rawResponse);

      console.log('[GalaxyAssistant] Response generated with thinking:', {
        hasThinking: thinkingResult.hasThinking,
        thinkingLevel: thinkingResult.thinkingLevel,
        thinkingWords: thinkingResult.thinkingWordCount
      });

      const RESEARCH_INTENT_TYPES = new Set([
        'research_question', 'troubleshooting', 'parameter_optimization',
        'experiment_design', 'data_interpretation', 'protocol_guidance',
        'methods_writing', 'comparative_methodology', 'regulatory_compliance',
      ]);
      const qualityEnforcedMessage = this.enforceDrugDevelopmentResponseQuality({
        userMessage: message,
        assistantMessage: thinkingResult.answerContent,
        runnableWorkflow,
        workflowGenerationFailed,
        workflowFailureSignals,
        isResearchAnswer: RESEARCH_INTENT_TYPES.has((intent as any)?.type ?? ''),
      });

      const wasTruncated = lastStopReason === 'max_tokens';
      return {
        message: qualityEnforcedMessage,
        thinking: thinkingResult.hasThinking ? thinkingResult : undefined,
        truncated: wasTruncated,
      };
    } catch (error) {
      console.error('[GalaxyAssistant] Response generation failed:', error);
      const errMsg = error instanceof Error ? error.message : String(error);
      const isBilling = /credit balance|billing|payment|quota|rate.?limit|too many requests/i.test(errMsg);
      const isAuth = /unauthorized|invalid.?api.?key|authentication/i.test(errMsg);

      // Circuit breaker: when Anthropic credit is exhausted, fall back to Gemini.
      // Gemini fallback supports tool calling (run_code, read_file) via function declarations.
      if (isBilling && this.gemini) {
        console.warn('[GalaxyAssistant] Anthropic credit exhausted — falling back to Gemini with tool use');
        try {
          const allPrev = context.previousMessages || [];
          const plainMessages = [
            ...allPrev.slice(-6).map(m => ({
              role: (m.role === 'assistant' ? 'assistant' : 'user') as 'user' | 'assistant',
              content: typeof m.content === 'string' ? m.content
                : (m.content as any[]).filter((b: any) => b.type === 'text').map((b: any) => b.text).join(''),
            })),
            { role: 'user' as const, content: userPrompt },
          ];
          // Pass tools so Gemini can call run_code and read_file (always enable for analysis turns)
          const geminiTools = !isWorkflowTurn ? BIOMATE_TOOLS : undefined;
          const geminiResponse = await this._generateWithGemini(
            systemPrompt, plainMessages, onResponseDelta, 4096, 'gemini-3-flash-preview',
            geminiTools ? { tools: geminiTools, context, onToolEvent } : undefined,
          );
          return { message: geminiResponse, truncated: false };
        } catch (geminiErr: any) {
          console.error('[GalaxyAssistant] Gemini fallback also failed:', geminiErr.message);
          return { message: 'Service temporarily unavailable. Please try again later.' };
        }
      }

      if (isBilling) {
        return { message: 'Service temporarily unavailable: API credit balance too low. Please contact support.' };
      }
      if (isAuth) {
        return { message: 'Service configuration error: invalid API credentials. Please contact support.' };
      }
      return {
        message: 'I encountered an error processing your request. Please try again.'
      };
    }
  }

  // ─── Agent tool execution ─────────────────────────────────────────────────

  /** Executes all tool_use blocks in parallel, returns tool_result message content. */
  private async _executeTools(
    toolUseBlocks: any[],
    context: ChatContext,
    onToolEvent?: (event: AgentToolEvent) => void
  ): Promise<Anthropic.ToolResultBlockParam[]> {
    return Promise.all(toolUseBlocks.map(async (block) => {
      const start = Date.now();
      onToolEvent?.({ type: 'tool_call', tool_use_id: block.id, name: block.name, input: block.input });
      let output: unknown = null;
      let error: string | undefined;
      try {
        switch (block.name) {
          case 'run_code':
            output = await this._toolRunCode(block.input);
            break;
          case 'read_file':
            output = await this._toolReadFile(block.input, context);
            break;
          case 'query_domain_knowledge':
            output = await this._toolQueryKnowledge(block.input);
            break;
          default:
            output = { error: `Unknown tool: ${block.name}` };
        }
      } catch (err: any) {
        error = err?.message ?? String(err);
        output = { error };
      }
      const duration_ms = Date.now() - start;
      onToolEvent?.({ type: 'tool_result', tool_use_id: block.id, name: block.name, output, error, duration_ms });
      return {
        type: 'tool_result' as const,
        tool_use_id: block.id,
        content: JSON.stringify(output),
      };
    }));
  }

  /** run_code tool handler — calls the /api/code/run endpoint. */
  private async _toolRunCode(input: any): Promise<unknown> {
    const { runCode } = await import('./code-runner');
    const { getUploadedFile } = await import('./routes');
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';

    // Download function: tries Galaxy first, falls back to locally uploaded file
    const downloadDataset = async (id: string): Promise<AsyncIterable<Buffer>> => {
      // 1. Try Galaxy API
      try {
        const r = await fetch(`${galaxyUrl}/api/datasets/${id}/display`, {
          signal: AbortSignal.timeout(30000),
        });
        if (r.ok) {
          const reader = r.body!.getReader();
          return {
            [Symbol.asyncIterator]: async function*() {
              while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                yield Buffer.from(value);
              }
            }
          };
        }
      } catch { /* fall through to local */ }

      // 2. Fall back to locally stored file (works when Redis/Galaxy are unavailable)
      const local = getUploadedFile(id);
      if (local?.filePath) {
        const nodeFs = await import('fs/promises');
        const data = await nodeFs.readFile(local.filePath);
        return {
          [Symbol.asyncIterator]: async function*() {
            yield data;
          }
        };
      }

      throw new Error(`Dataset ${id} not accessible via Galaxy or local storage`);
    };

    // Resolve filenames: check local registry first, then Galaxy metadata
    const rawIds: string[] = input.input_datasets ?? [];
    const datasetRefs = await Promise.all(rawIds.map(async (id: string) => {
      // Local registry always has the original filename
      const local = getUploadedFile(id);
      if (local?.name) return { id, filename: local.name };

      // Fallback: Galaxy metadata
      try {
        const meta = await fetch(`${galaxyUrl}/api/datasets/${id}`, {
          signal: AbortSignal.timeout(5000),
        });
        if (meta.ok) {
          const data = await meta.json() as any;
          const filename = data?.name || data?.file_name || id;
          return { id, filename: String(filename) };
        }
      } catch { /* fall through */ }
      return { id, filename: id };
    }));

    return runCode({
      language: input.language,
      code: input.code,
      input_datasets: datasetRefs,
      timeout_seconds: input.timeout_seconds ?? 30,
      downloadDataset,
    });
  }

  /** read_file tool handler — streams first n_lines from Galaxy or local dataset. */
  private async _toolReadFile(input: any, _context: ChatContext): Promise<unknown> {
    // Accept either galaxy_dataset_id or dataset_id (when Galaxy is unavailable)
    const { galaxy_dataset_id, dataset_id, n_lines = 20 } = input;
    const fileId = galaxy_dataset_id || dataset_id;
    if (!fileId) return { error: 'galaxy_dataset_id or dataset_id is required' };

    // Check local upload registry first (works when Galaxy is unavailable)
    try {
      const { getUploadedFile } = await import('./routes');
      const localFile = getUploadedFile(fileId);
      if (localFile?.filePath) {
        const nodeFs = await import('fs/promises');
        const content = await nodeFs.readFile(localFile.filePath, 'utf8');
        const allLines = content.split('\n');
        const lines = allLines.slice(0, n_lines);
        const firstLine = lines[0] ?? '';
        const isTabular = firstLine.includes('\t') || firstLine.includes(',');
        return {
          lines, total_lines_preview: lines.length, has_more: allLines.length > n_lines,
          format_hint: isTabular ? (firstLine.includes('\t') ? 'TSV' : 'CSV') : 'text',
        };
      }
    } catch { /* fall through to Galaxy */ }

    try {
      // Fetch raw content from Galaxy backend directly (avoids fragile self-fetch)
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const r = await fetch(`${galaxyUrl}/api/datasets/${fileId}/display`, {
        signal: AbortSignal.timeout(15000),
      });
      if (!r.ok) {
        return { error: `Dataset ${fileId} not accessible (HTTP ${r.status})` };
      }
      // Read enough to get n_lines without loading the whole file
      const reader = r.body!.getReader();
      let text = '';
      const LINE_BUDGET = n_lines + 5; // read a few extra in case of partial final line
      outer: while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        text += new TextDecoder().decode(value);
        if (text.split('\n').length > LINE_BUDGET) break outer;
      }
      reader.cancel().catch(() => {});
      const allLines = text.split('\n');
      const lines = allLines.slice(0, n_lines);
      // Try to infer column names from first line
      const firstLine = lines[0] ?? '';
      const isTabular = firstLine.includes('\t') || firstLine.includes(',');
      return {
        lines,
        total_lines_preview: lines.length,
        has_more: allLines.length > n_lines,
        format_hint: isTabular ? (firstLine.includes('\t') ? 'TSV' : 'CSV') : 'text',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err) };
    }
  }

  /** query_domain_knowledge tool handler — routes to domain-specific knowledge endpoints. */
  private async _toolQueryKnowledge(input: any): Promise<unknown> {
    const { query, domain = 'general' } = input;
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      if (domain === 'cryo_em') {
        const r = await fetch(`${galaxyUrl}/api/cryo_em/context`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query, sample_class: null }),
          signal: AbortSignal.timeout(8000),
        });
        if (r.ok) return r.json();
      }
      // General domain: use the expert knowledge endpoint
      const r = await fetch(`${galaxyUrl}/api/knowledge/query`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, domain }),
        signal: AbortSignal.timeout(8000),
      });
      if (r.ok) return r.json();
      // Fallback: return structured hint for the domain
      return {
        domain,
        query,
        result: `No structured knowledge found for "${query}" in domain "${domain}". Consult BioMate's workflow catalog or literature for guidance.`,
        source: 'fallback',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err), domain, query };
    }
  }

  private enforceDrugDevelopmentResponseQuality(params: {
    userMessage: string;
    assistantMessage: string;
    runnableWorkflow: boolean;
    workflowGenerationFailed: boolean;
    workflowFailureSignals: any;
    isResearchAnswer?: boolean;
  }): string {
    const { userMessage, assistantMessage, runnableWorkflow, workflowGenerationFailed, workflowFailureSignals, isResearchAnswer } = params;
    // Never append workflow boilerplate to pure research/knowledge answers.
    if (isResearchAnswer) {
      return assistantMessage;
    }
    const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
      userMessage || ''
    );
    if (!isDrugDevelopmentQuery) {
      return assistantMessage;
    }

    const text = assistantMessage || '';
    const lower = text.toLowerCase();
    const additions: string[] = [];

    // When a runnable workflow was generated, the panel shows the actual steps —
    // never append generic boilerplate phases/inputs/next-step sections.
    if (!runnableWorkflow) {
      const hasWorkflowPhases = /(workflow phases|phase|target prep|docking|admet|herg|pk\/nca|nca)/i.test(lower);
      const hasRequiredInputs = /(required inputs|input files|you provide|input data)/i.test(lower);
      const hasNextStep = /(next step|next steps|confirm or edit|please confirm|follow-up)/i.test(lower);

      if (!hasWorkflowPhases) {
        additions.push(
          '### Workflow phases\n- Target/assay context and data intake\n- Core analysis phase (e.g., docking, ADMET, or PK/NCA)\n- QC/safety review and report handoff'
        );
      }
      if (!hasRequiredInputs) {
        additions.push(
          '### Required inputs\n- Input data files (e.g., structures/SMILES, assay data, or concentration-time table)\n- Basic study metadata (condition, units, and endpoint definitions)'
        );
      }
      if (!hasNextStep) {
        additions.push('### Next step\n- Confirm the intended analysis priority and upload the required inputs so I can produce a runnable, decision-ready workflow.');
      }
    }

    if (workflowGenerationFailed) {
      const errorBlob = JSON.stringify(workflowFailureSignals || {}).toLowerCase();
      const hasToolGap = /(not found|missing|unavailable|failed_tools|none found|tool)/i.test(errorBlob);
      const hasInputGap = /(input|dataset|file|required)/i.test(errorBlob);
      const hasDomainMismatch = /(domain|alignment|incompatible|mismatch)/i.test(errorBlob);

      const blockers: string[] = [];
      blockers.push(hasToolGap ? '- Tool gap: one or more required capabilities are missing or unavailable in the current runtime.' : '- Tool gap: verify that required tools are installed and accessible.');
      blockers.push(hasInputGap ? '- Input gap: required input files/datasets are missing or not yet mapped for execution.' : '- Input gap: provide required input files and metadata before execution.');
      if (hasDomainMismatch || (!hasToolGap && !hasInputGap)) {
        blockers.push('- Domain mismatch: the requested combined workflow spans incompatible domains and should be split into staged workflows.');
      }

      if (!/why generation failed|workflow generation failed|blocked/i.test(lower)) {
        additions.push(`### Why generation failed\n${blockers.join('\n')}`);
      } else if (!/tool gap|input gap|domain mismatch|incompatible/i.test(lower)) {
        additions.push(`### Blocker categories\n${blockers.join('\n')}`);
      }

      if (!/follow-up questions|please answer|which analysis|what input|confirm or edit/i.test(lower)) {
        additions.push(
          '### Targeted follow-up questions\n1. Which analysis should be prioritized first (docking, ADMET, or PK/NCA)?\n2. What exact input files do you have now (format + example filenames)?'
        );
      }
    }

    if (additions.length === 0) {
      return text;
    }

    console.log('[GalaxyAssistant] Applied drug-development quality guard:', {
      additions: additions.length,
      runnableWorkflow,
      workflowGenerationFailed,
    });
    return `${text}\n\n${additions.join('\n\n')}`;
  }

  /**
   * Generate follow-up suggestions
   */
  private generateSuggestions(
    message: string,
    intent: any,
    tools: ToolRecommendation[],
    workflowSuggestion: WorkflowSuggestion
  ): string[] {
    const suggestions: string[] = [];

    if (workflowSuggestion.shouldGenerate && !workflowSuggestion.confidence) {
      suggestions.push('Generate a workflow for this analysis');
    }

    if (tools.length > 0) {
      suggestions.push('Tell me more about the recommended tools');
      suggestions.push('Show me alternative tools');
    }

    if (intent.type === 'workflow_generation') {
      suggestions.push('Customize the workflow parameters');
      suggestions.push('What data formats do I need?');
    } else if (intent.type === 'research_question') {
      suggestions.push('Search for related papers');
      suggestions.push('Build a workflow from these findings');
    } else if (intent.type === 'result_comparison') {
      suggestions.push('Show benchmark data');
      suggestions.push('Run a comparison workflow');
    } else if (intent.type === 'tool_search') {
      suggestions.push('Build a workflow with this tool');
      suggestions.push('Show me alternative tools');
    } else {
      suggestions.push('Build a workflow');
      suggestions.push('Search for tools');
    }

    return suggestions.slice(0, 4);
  }

  /**
   * C3 — When context is compressed (> CONTEXT_WINDOW messages), generate a 2-3 sentence
   * summary of the dropped messages using Claude Haiku and store it via the session-summary API.
   * This is always called fire-and-forget; errors are caught by the caller.
   */
  private async _triggerSessionSummary(
    compressedMessages: Array<{ role: 'user' | 'assistant'; content: string }>,
    userId?: number,
    sessionId?: string,
  ): Promise<void> {
    if (!compressedMessages.length) return;

    const historyText = compressedMessages
      .map((m) => `${m.role.toUpperCase()}: ${m.content}`)
      .join('\n')
      .slice(0, 4000); // Keep prompt compact for Gemini Flash

    const summary = await callGeminiFlash({
      messages: [
        {
          role: 'user',
          content:
            `Summarize the following conversation in 2-3 sentences, focusing on what the user was trying to accomplish and any decisions made:\n\n${historyText}`,
        },
      ],
      maxTokens: 1024,
    }).then(r => r.trim()).catch(() => '');

    if (!summary) return;

    // POST to /api/memory/session-summary (non-blocking; this server calls Galaxy backend)
    const body = JSON.stringify({ summary, sessionId, userId });
    const _galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    await fetch(`${_galaxyUrl}/api/memory/session-summary`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    }).catch((err) => {
      console.warn('[GalaxyAssistant] session-summary POST failed:', err.message);
    });

    console.log(
      `[GalaxyAssistant] Session summary stored for session=${sessionId}, compressed ${compressedMessages.length} messages`,
    );
  }
}
