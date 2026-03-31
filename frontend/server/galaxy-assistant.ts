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
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import { userPatternsService, type UserContext } from './user-patterns-service';
import { thinkingDetector, type ThinkingDetectionResult } from './thinking-detector';
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

/**
 * Model configuration for different AI tasks
 *
 * Recommended configurations:
 * - Intent analysis: Fast model (haiku) - simple classification task
 * - Tool ranking: Medium model (haiku/sonnet) - needs domain knowledge
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
  /** Model for intent classification (default: claude-sonnet-4-5, can use haiku for speed) */
  intentModel: string;
  /** Model for tool ranking (default: claude-sonnet-4-5, can use haiku for speed) */
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
  intentModel: 'claude-haiku-4-5',       // Haiku: same 94% accuracy, 2x faster, 11.5x cheaper
  toolRankingModel: 'claude-haiku-4-5',  // Haiku: 1.4x faster for ranking
  responseModel: 'claude-sonnet-4-6',    // Default to Sonnet 4.6
  enableThinking: false,                 // Disable thinking by default for lower latency
  thinkingBudget: 2000,
};

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
- cryosparc_standard_spa: Standard single-particle analysis (SPA) — 23-step CryoSPARC pipeline: import → motion correction → CTF estimation → particle picking (blob + template) → 2D classification → ab-initio → homogeneous refinement → local CTF → non-uniform refinement → local resolution. Input: raw micrograph movies (TIFF/MRC). License: CryoSPARC (user must provide).
- helical_spa_pipeline: Helical reconstruction for filamentous assemblies (F-actin, amyloid, microtubules, viral tubes) — filament tracing → helical extraction → 2D classification → helical refinement with rise/twist symmetry. Input: raw movies. License: CryoSPARC.
- focused_refinement_pipeline: Focus on a sub-region of a complex — particle subtraction → local refinement. For flexible multi-domain complexes. Input: particles + mask volume. License: CryoSPARC.
- 3d_variability_analysis: Conformational heterogeneity analysis (3DVA) — PCA of particle orientations to reveal discrete states or continuous motions. Input: refined particles. License: CryoSPARC.
- topaz_train / topaz_extract: Deep learning particle picker training and inference (Topaz). Input: micrographs + manually picked coordinates (train) or micrographs only (extract).
- et_full_pipeline: Cryo-ET full pipeline — tilt-series import → tilt alignment → tomogram reconstruction → subtomogram averaging.`,

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
- nca_pknca: Non-compartmental PK analysis (PKNCA) — AUC, Cmax, Tmax, t½, CL/F, Vz/F. Input: concentration-time CSV.
- aizynthfinder_retrosynthesis: Retrosynthesis route planning (AiZynthFinder). Input: target SMILES. Outputs: synthesis routes + reaction scores.
- pocket_detection_druggability: Binding site detection and druggability scoring (fpocket). Input: PDB. Outputs: pocket table + druggability scores.
- pharmacophore_filtering: Filter compound libraries against a pharmacophore model. Input: pharmacophore + SMILES/SDF library. Outputs: filtered hits.`,

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

  cryo_em: `Expert framing (cryo-EM): SPA vs cryo-ET distinction is critical — wrong pipeline wastes weeks. For SPA: MotionCor2 → CTFFIND4 → Topaz/crYOLO picking → CryoSPARC 2D/3D → non-uniform refinement. For tomography: IMOD alignment → AreTomo → Dynamo/STOPGAP subtomogram averaging. Key QC gates: motion correction B-factor < 80 Å²/frame; CTF resolution ≤ 4Å; 2D class fraction ≥ 60% should have secondary structure visible. Gold-standard FSC at 0.143 threshold is the resolution metric.`,

  systems_biology: `Expert framing (systems biology): ODE modeling for signaling/gene regulatory circuits (deterministic); stochastic for small-number systems. FBA (COBRApy) for metabolic flux optimization under growth/production constraints. Multi-omics integration: MOFA+ (factor analysis), DIABLO (supervised), or COSMOS (causal). Network types: PPI (STRING), GRN (ARACNE/GENIE3), metabolic (SBML/BiGG). Pathway enrichment: over-representation (Fisher) for gene lists; GSEA for ranked lists.`,

  synthetic_biology: `Expert framing (synthetic biology): Codon optimization is host-specific (CAI tables differ between E. coli K-12, S. cerevisiae, CHO). Gene circuit ODE models need explicit Hill coefficients and degradation rates. CRISPR guide design: Doench 2016 efficiency rules + Cas-OFFinder/CRISPOR off-target check. Barcode-seq: error-correction Hamming codes ≥ 3-edit distance to survive sequencing noise. Verify constructs with plasmid sequencing before expression.`,

  bioimaging: `Expert framing (bioimaging): Image registration requires a reference channel (DAPI/nuclear) with consistent expression. Segmentation: nucleus-only (StarDist) vs full cell boundary (Cellpose/nnUNet). For time-lapse: track cells before quantifying intensity changes (avoid mis-assignment). Output: per-cell feature tables (area, intensity, morphology) compatible with scRNA-seq-style clustering (scanpy/UMAP). Batch correction: CellProfiler+Harmony or scVI for imaging features.`,

  lab_automation: `Expert framing (lab automation): PyLabRobot abstracts liquid handling robots (Opentrons OT-2/Flex, Hamilton STAR, Tecan). Protocol execution: confirm deck layout and tip inventory before launch. Pipetting volumes: respect dead volume and tip capacity limits (min 1 μL for p10, max 300 μL for p300). Async execution pattern: start → poll status → retrieve results — never assume synchronous completion. Plate maps must be validated against physical layout before run.`,

  cancer_biology: `Expert framing (cancer biology): Somatic variant calling requires matched tumor/normal pairs for maximum specificity (Mutect2); tumor-only is higher FDR. TMB threshold: ≥10 mut/Mb correlates with immunotherapy response (FDA-approved threshold). CNV calling: correct for purity/ploidy (PURPLE/ABSOLUTE) before copy number interpretation. SV calling: short-read callers (GRIDSS, DELLY, Manta) have high FDR — orthogonal long-read or WGS validation recommended. NMF mutational signature extraction: ≥50 SSNVs required for reliable signature decomposition.`,

  cell_biology: `Expert framing (cell biology): Flow cytometry gating order: FSC/SSC live gate → doublet exclusion (FSC-A vs FSC-H) → dead cell exclusion (viability dye) → lineage markers → target markers. FACS purity sort: re-analyze post-sort sample to confirm ≥95% purity before downstream assays. Cell cycle: EdU/BrdU incorporation + PI staining is quantitative for S-phase fraction; Hoechst DNA content alone cannot distinguish G1 from G2/M without BrdU. Motility: velocity (μm/min), directionality ratio, and MSD should all be reported.`,
};

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
}

/**
 * Infer action categories from a type string. Known types get established
 * mappings; unknown types default to LLM reasoning only.
 */
export function inferActionsFromType(type: string): ActionCategories {
  const defaults: Record<string, Partial<ActionCategories>> = {
    'workflow_generation': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'research_question': { needsResearchAgent: true, needsLLMReasoning: true },
    'result_comparison': { needsToolSearch: true, needsBenchmarkAgent: true, needsLLMReasoning: true },
    'benchmark_query': { needsBenchmarkAgent: true, needsLLMReasoning: true },
    'tool_search': { needsToolSearch: true, needsLLMReasoning: true },
    'dataset_inquiry': { needsDatasetAccess: true, needsLLMReasoning: true },
    'general_question': { needsLLMReasoning: true },
    'workflow_modification': { needsToolSearch: true, needsWorkflowModification: true, needsLLMReasoning: true },
    // Novel information need types from flexible intent brainstorm
    'troubleshooting': { needsResearchAgent: true, needsToolSearch: true, needsLLMReasoning: true },
    'experiment_design': { needsResearchAgent: true, needsLLMReasoning: true },
    'data_interpretation': { needsResearchAgent: true, needsLLMReasoning: true },
    'protocol_guidance': { needsResearchAgent: true, needsLLMReasoning: true },
    'parameter_optimization': { needsBenchmarkAgent: true, needsResearchAgent: true, needsToolSearch: true, needsLLMReasoning: true },
    'data_format_conversion': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'external_db_retrieval': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'teaching_explanation': { needsLLMReasoning: true },
    'methods_writing': { needsResearchAgent: true, needsLLMReasoning: true },
    'visualization': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'comparative_methodology': { needsResearchAgent: true, needsBenchmarkAgent: true, needsLLMReasoning: true },
    'regulatory_compliance': { needsResearchAgent: true, needsLLMReasoning: true },
    'cost_estimation': { needsBenchmarkAgent: true, needsLLMReasoning: true },
    'multi_step_procedure': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
  };
  return {
    needsToolSearch: false,
    needsWorkflowGeneration: false,
    needsWorkflowModification: false,
    needsResearchAgent: false,
    needsBenchmarkAgent: false,
    needsDatasetAccess: false,
    needsLLMReasoning: true,
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
  private static readonly DEBOUNCE_MS = 30_000;  // 30 s — same as DeerFlow
  private static readonly SESSION_TTL_MS = 2 * 60 * 60 * 1000; // 2 hours idle eviction

  private static readonly HAIKU_MODEL = 'claude-haiku-4-5-20251001';

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

    const response = await this.claude.messages.create({
      model: SessionMemoryUpdater.HAIKU_MODEL,
      max_tokens: 600,
      system: SessionMemoryUpdater.UPDATE_PROMPT,
      messages: [{ role: 'user', content: userContent }],
    });

    const raw = (response.content as any[]).find((b: any) => b.type === 'text')?.text ?? '';
    try {
      // Strip markdown fences if present
      const cleaned = raw.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
      const updated: SessionMemory = JSON.parse(cleaned);
      // Type-guard: validate required array/object fields before storing
      if (typeof updated !== 'object' || updated === null) throw new Error('not an object');
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
    } catch {
      console.warn('[SessionMemory] JSON parse/validation failed, keeping existing memory');
    }
  }
}

export class GalaxyAssistant {
  private claude: Anthropic;
  private galaxyAPI: GalaxyAPIProxy;
  private modelConfig: ModelConfig;
  private sessionMemory: SessionMemoryUpdater;

  /** In-memory domain profile cache: userId → { domains, topics, fetchedAt } */
  private _domainProfileCache: Map<number, { domains: string[]; topics: string[]; fetchedAt: number }> = new Map();
  private static readonly DOMAIN_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

  constructor(options: GalaxyAssistantOptions) {
    this.claude = new Anthropic({ apiKey: options.anthropicApiKey });
    this.galaxyAPI = options.galaxyAPIProxy;
    this.modelConfig = { ...DEFAULT_MODEL_CONFIG, ...options.modelConfig };
    this.sessionMemory = new SessionMemoryUpdater(this.claude);
    console.log('[GalaxyAssistant] Initialized with model config:', this.modelConfig);
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
    const ambiguity = intent.workflowAmbiguity;
    if (!ambiguity || !actions.needsWorkflowGeneration) return null;

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
      const resp = await this.claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
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
        messages: [{
          role: 'user',
          content: `User query: "${userMessage}"\nAmbiguity type: ${ambiguityType}\nGenerate the clarifying question:`
        }]
      });
      const text = resp.content[0].type === 'text' ? resp.content[0].text.trim() : '';
      return text || staticFallback;
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
      const resp = await this.claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 30,
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
        messages: [{
          role: 'user',
          content: `Query: "${userIntent}"${contextLine}`
        }]
      });
      const domain = resp.content[0].type === 'text' ? resp.content[0].text.trim() : 'unknown';
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
    onResponseDelta?: (chunk: string) => void
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

    // Step 1: Analyze user intent with NLU (supports all formats: single, multi, sequential)
    // The LLM recognizes bullet lists, numbered steps, prose pipelines, and all other formats.
    log('Step 1: Analyzing intent');
    const decomposition = await this.analyzeIntent(message, context, sessionMemoryBlock);
    const intent = decomposition.primaryIntent;
    log(`Step 1 complete - Intent: ${intent.type}, isMultiIntent: ${decomposition.isMultiIntent}, intents: ${decomposition.intents.length}`);

    // Multi-intent path: fan out to processSubIntent for each intent
    if (decomposition.isMultiIntent) {
      return this.processMultiIntent(decomposition, message, context, startTime, onResponseDelta, domainProfileContext, sessionMemoryBlock);
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

    // S1: ClarificationGate — returns early if ambiguity requires user clarification
    const clarificationResponse = await this._clarificationGate(
      intent, actions, message, recommendedTools, recommendedDatasets
    );
    if (clarificationResponse) {
      log(`Step 4: Returning clarification question for ambiguity="${intent.workflowAmbiguity}"`);
      return clarificationResponse;
    }

    // Workflow generation / modification
    if (actions.needsWorkflowGeneration || actions.needsWorkflowModification) {
      log('Step 4: Analyzing workflow need');
      workflowSuggestion = await this.analyzeWorkflowNeed(
        message,
        intent,
        recommendedTools
      );
      log('Step 4 complete - shouldGenerate: ' + workflowSuggestion.shouldGenerate);

      if (workflowSuggestion.shouldGenerate && workflowSuggestion.confidence > 0.7) {
        try {
          log('Step 5: Generating workflow');
          generatedWorkflow = await this.generateWorkflow(
            workflowSuggestion.userIntent,
            recommendedDatasets.map(d => d.dataset),
            intent.inlineParameters,
            context,
            decomposition.preferredDomains,
            decomposition.keyTerms
          );
           workflowGenerated = !!(
             generatedWorkflow?.success &&
             !generatedWorkflow?.error &&
             (generatedWorkflow?.workflow_ga ||
              generatedWorkflow?.nextflow_path ||
              generatedWorkflow?.workflow_type === 'chain')
           );
          if (workflowGenerated) {
            log('Step 5 complete - Workflow generated');
          } else {
            log('Step 5 complete - Generation returned no runnable workflow');
          }
        } catch (error: any) {
          log('Step 5 failed: ' + error.message);
          console.error('[GalaxyAssistant] Workflow generation failed:', error);
        }
      } else {
        log('Step 5: Skipped (workflow not needed based on analysis)');
      }
    } else {
      workflowSuggestion = {
        shouldGenerate: false,
        userIntent: message,
        confidence: 0,
        reasoning: `Intent type "${intent.type}" — workflow generation not flagged`,
      };
    }

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
      decomposition.preferredDomains ?? []
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

    const finalResult: GalaxyAssistantResponse = {
      message: response.message,
      intentType: intent.type,
      intentConfidence: intent.confidence,
      inlineParameters: Object.keys(intent.inlineParameters).length > 0 ? intent.inlineParameters : undefined,
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

    // Resolve each step to a workflow in parallel using the unified search
    const stepResults = await Promise.all(
      decomposition.intents.map(async (intent, idx) => {
        try {
          log(`Step ${idx + 1}: resolving "${intent.subQuery}"`);
          const subResult = await this.processSubIntent(
            intent, message, context, [], []
          );
          return { intent, subResult, idx };
        } catch (err: any) {
          log(`Step ${idx + 1} failed: ${err.message}`);
          return { intent, subResult: null, idx };
        }
      })
    );

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
    sessionMemoryBlock: string = ''
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
          decomposition.preferredDomains, decomposition.keyTerms)
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
        shouldGenerate: workflowGenerated,
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
      decomposition.preferredDomains ?? []
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

    const multiIntentResult: GalaxyAssistantResponse = {
      message: response.message,
      intentType: primaryIntent.type,
      intentConfidence: primaryIntent.confidence,
      inlineParameters: Object.keys(primaryIntent.inlineParameters).length > 0 ? primaryIntent.inlineParameters : undefined,
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
    keyTerms?: string[]
  ): Promise<SubIntentResult> {
    const baseResult: SubIntentResult = {
      intentId: intent.id,
      intentType: intent.type,
      subQuery: intent.subQuery,
      status: 'success',
    };

    const actions = intent.actions;

    try {
      // Action-flag-based routing: multiple agents can be invoked per intent

      // Tool search results already available from parallel search
      if (actions.needsToolSearch && recommendedTools.length > 0) {
        baseResult.recommendedTools = recommendedTools;
      }

      // Workflow generation
      if ((actions.needsWorkflowGeneration || actions.needsWorkflowModification) && recommendedTools.length > 0) {
        const workflowSuggestion = await this.analyzeWorkflowNeed(
          intent.subQuery,
          intent,
          recommendedTools
        );
        if (workflowSuggestion.shouldGenerate && workflowSuggestion.confidence > 0.7) {
          // When this sub-intent is part of a multi-intent query, use the original full message
          // as the workflow intent so domain preference (e.g. drug/docking tokens) is preserved.
          // This prevents e.g. a "predict structure" sub-intent from losing the "docking/drug"
          // context that the full query carries, which would otherwise pick a microbiology tool.
          const effectiveIntent = (originalMessage && originalMessage !== intent.subQuery)
            ? originalMessage
            : workflowSuggestion.userIntent;
          const workflow = await this.generateWorkflow(
            effectiveIntent,
            recommendedDatasets.map(d => d.dataset),
            intent.inlineParameters,
            context,
            preferredDomains,
            keyTerms
          );
          baseResult.generatedWorkflow = workflow;
          if (!baseResult.recommendedTools) baseResult.recommendedTools = recommendedTools;
        }
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

  /**
   * Analyze user intent, detecting multiple intents if present.
   * Returns IntentDecomposition with one or more decomposed intents.
   */
  private async analyzeIntent(
    message: string,
    context: ChatContext,
    sessionMemoryBlock: string = ''
  ): Promise<IntentDecomposition> {
    const systemPrompt = `${sessionMemoryBlock}You are a bioinformatics intent analyzer. Classify user messages by their information need and declare which system agents should handle the request.

## Information Need Types

Describe the user's information need with a descriptive label. You may use these common labels or create a new one that better fits:

**workflow_generation** — Execute a computational task, run a tool, process data, perform an analysis.
**research_question** — Search/review scientific literature, papers, databases.
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
  "needsToolSearch": true,
  "needsDatasets": false,
  "confidence": 0.95,
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
    {"category": "sequence", "value": "ATGCGATCG", "confidence": 1.0},
    {"category": "analysis_goal", "value": "reverse complement", "confidence": 0.95}
  ],
  "workflowAmbiguity": null,
  "preferred_domains": [],
  "key_terms": ["reverse complement"],
  "needs_thinking": false,
  "chain_hint": null
}

preferred_domains: list of 0–3 domain strings most relevant to this query, chosen from:
  [${PREFERRED_DOMAINS_PROMPT_LIST}]
  Leave empty [] when the query is domain-agnostic or unclear.

key_terms: up to 8 specific technical terms (tool names, assay types, organisms) that should
  boost workflow search recall. Omit generic words like "run", "analyze", "data".

needs_thinking: true only when the query requires multi-step reasoning, pipeline design,
  troubleshooting, or methodology comparison. false for simple workflow execution requests.

chain_hint: if the query clearly maps to one of these curated workflow chains, return its name;
  otherwise null.
  Known chain names: [bulk_rnaseq_de_analysis, chip_seq_peak_calling, atac_seq_chromatin,
  wgs_variant_calling, target_to_lead_full, scrnaseq_seurat_full, metagenomics_diversity,
  proteomics_dda_full]

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
      console.log('[GalaxyAssistant] Intent API request:', {
        model: this.modelConfig.intentModel,
        max_tokens: 2500,
        system_prompt_length: systemPrompt.length,
        message_length: message.length
      });

      // Intent classification - using configurable model
      // 2500 tokens to accommodate multi-intent responses with full action objects
      const completion = await this.claude.messages.create({
        model: this.modelConfig.intentModel,
        max_tokens: 2500,
        temperature: 0.3,
        system: [
          {
            type: 'text',
            text: systemPrompt,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages: [{ role: 'user', content: message }],
      });

      console.log('[GalaxyAssistant] Intent API response:', {
        model: this.modelConfig.intentModel,
        time_ms: Date.now() - intentStartTime,
        usage: completion.usage
      });

      const content = completion.content[0];
      let resultText = content.type === 'text' ? content.text : '{}';

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
      const fallback: DecomposedIntent = {
        id: 'intent_fallback',
        type: 'general_question',
        subQuery: message,
        keywords: [],
        inlineParameters: {},
        needsToolSearch: false,
        needsDatasets: false,
        confidence: 0.5,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType('general_question'),
      };
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
      if (raw && typeof raw === 'object') {
        const base = inferActionsFromType(type);
        return {
          needsToolSearch: typeof raw.needsToolSearch === 'boolean' ? raw.needsToolSearch : base.needsToolSearch,
          needsWorkflowGeneration: typeof raw.needsWorkflowGeneration === 'boolean' ? raw.needsWorkflowGeneration : base.needsWorkflowGeneration,
          needsWorkflowModification: typeof raw.needsWorkflowModification === 'boolean' ? raw.needsWorkflowModification : base.needsWorkflowModification,
          needsResearchAgent: typeof raw.needsResearchAgent === 'boolean' ? raw.needsResearchAgent : base.needsResearchAgent,
          needsBenchmarkAgent: typeof raw.needsBenchmarkAgent === 'boolean' ? raw.needsBenchmarkAgent : base.needsBenchmarkAgent,
          needsDatasetAccess: typeof raw.needsDatasetAccess === 'boolean' ? raw.needsDatasetAccess : base.needsDatasetAccess,
          needsLLMReasoning: typeof raw.needsLLMReasoning === 'boolean' ? raw.needsLLMReasoning : base.needsLLMReasoning,
        };
      }
      return inferActionsFromType(type);
    };

    // Extract top-level UQU fields (present in both single and multi-intent responses)
    const preferredDomains: string[] = Array.isArray(result.preferred_domains) ? result.preferred_domains : [];
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

      const completion = await this.claude.messages.create({
        model: this.modelConfig.toolRankingModel,
        max_tokens: 2000, // Increased to handle ranking many tools
        temperature: 0.3,
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
      });

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

  /**
   * Search for relevant datasets using BioMNI RAG
   */
  private async searchRelevantDatasets(
    userMessage: string,
    keywords: string[]
  ): Promise<DatasetRecommendation[]> {
    try {
      // Search BioMNI dataset catalog
      const datasetSearchResponse = await this.galaxyAPI.searchDatasets({
        query: keywords.join(' '),
        limit: 10,
      });

      if (!datasetSearchResponse.success || !datasetSearchResponse.datasets) {
        return [];
      }

      // Rank datasets by relevance
      const rankedDatasets = await this.rankDatasetsByRelevance(
        userMessage,
        datasetSearchResponse.datasets
      );

      return rankedDatasets;
    } catch (error) {
      console.error('[GalaxyAssistant] Dataset search failed:', error);
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
    keyTerms?: string[]
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

    // LLM-based domain classification (Claude Haiku, cached per query)
    const domainHint = await this._inferDomainWithLLM(userIntent, currentWorkflowText || recentContext || undefined);
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
      key_terms: keyTerms?.length ? keyTerms : undefined,
    });

    if (response.success) {
      console.log('[GalaxyAssistant] ✅ Workflow generated successfully!');
      console.log('[GalaxyAssistant] Generation strategy:', response.source);
      console.log('[GalaxyAssistant] Confidence score:', response.confidence?.toFixed(2));
      console.log('[GalaxyAssistant] Template match:', response.template_match_score?.toFixed(2));
      console.log('[GalaxyAssistant] Datasets assigned:', response.datasets_assigned);
      console.log('[GalaxyAssistant] Generated parameters:', response.generated_parameters?.length || 0);
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
    preferredDomains: string[] = []
  ): Promise<{ message: string; thinking?: ThinkingDetectionResult; truncated?: boolean }> {
    // S3: domain-signal-driven specialist framing — replaces the isDrugDevelopmentQuery keyword regex.
    // preferredDomains comes from the intent classifier + user profile (not keyword matching).
    const isDrugDiscoveryDomain = preferredDomains.includes('drug_discovery');
    // Backward-compat fallback: if no preferredDomains signal, fall back to keyword regex for drug context.
    const lowerMessage = (message || '').toLowerCase();
    const isDrugDevelopmentQuery = isDrugDiscoveryDomain || /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
      lowerMessage
    );
    const runnableWorkflow = !!(
      generatedWorkflow?.success &&
      !generatedWorkflow?.error &&
      (generatedWorkflow?.workflow_ga ||
       generatedWorkflow?.nextflow_path ||
       generatedWorkflow?.workflow_type === 'chain')
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

    const isResearchIntent = !!researchResponse;
    const systemPrompt = isResearchIntent
      ? `${sessionMemoryBlock}${domainProfileContext}You are BioMate, an expert bioinformatics AI assistant with deep scientific knowledge.

Your role:
- Provide accurate, evidence-based answers to scientific questions
- Cite specific papers using [N] inline notation matching the numbered reference list provided
- Only cite papers from the provided list — never fabricate citations
- Structure answers clearly with headings and bullet points
- End with a ## References section listing only the papers you cited`
      : `${sessionMemoryBlock}${domainProfileContext}You are BioMate, an expert bioinformatics AI assistant.

Your capabilities:
- Access to 2,177 bioinformatics tools (real-time search)
- Access to 100+ GB BioMNI dataset catalog
- Workflow generation with automatic tool/dataset selection

IMPORTANT RULES:
- NEVER compute or calculate results yourself (e.g., reverse complement, sequence alignment, etc.)
- ALWAYS recommend running the appropriate BioMate tool or workflow instead
- If a runnable workflow was generated, explain it and encourage the user to click "Run"
- If workflow generation failed, explicitly explain likely reasons using available diagnostics and process outputs (error details, confidence, template match, tool/runtime signals)
- If workflow generation failed, collaborate with the user by asking targeted follow-up questions and proposing concrete next recovery actions
- If no workflow but tools were found, explain which tool to use and suggest creating a workflow
- Only provide direct answers for conceptual questions (e.g., "what is RNA-seq?"). If the user wants to RUN or GENERATE a workflow, apply the DATA-FIRST RULE below — do not explain pipeline steps.

DATA-FIRST RULE (hard prohibition — no exceptions except demo/test/mock):
- NEVER describe workflow steps, list pipeline stages, explain tools, or provide any execution instructions in response to a workflow-generation request when the user has not yet provided input data. This is a strict prohibition, not a preference. Violating this rule means the system cannot run.
- "Input data provided" means the user's message contains ANY of: a file path (e.g. /path/to/sample.fastq, /data/reads_R1.fastq.gz), an S3 URI (s3://…), an SRA/ENA/DDBJ accession (SRR followed by digits, ERR followed by digits, DRR followed by digits), a GEO accession (GSE followed by digits, GSM followed by digits), an ArrayExpress accession (E-MTAB- followed by digits), a PXD accession (PXD followed by digits), a SMILES string, an InChI string, an amino acid sequence, a PDB ID, or an "[Uploaded datasets: ...]" block.
- SRA ACCESSION RULE: An SRA/ENA/DDBJ accession number (e.g. SRR1518169, ERR204916, DRR013480) IS input data. Treat it as the reads/input parameter. Proceed directly to workflow generation. DO NOT ask for a file path or S3 URI when an SRA accession is present in the message.
- If NO input data is present: ask EXACTLY ONE specific question. State what the workflow needs and list the accepted data formats. Example: "To run this GATK germline pipeline I need your input data. Please provide one of: (1) FASTQ file paths or S3 URIs for your sequencing reads, or (2) an SRA accession number (e.g. SRR1518169). Which do you have?" Do NOT explain workflow steps. Do NOT list pipeline stages. Do NOT describe what the tools do.
- Exception: if the user explicitly requests a "demo", "test", or "mock" workflow, generate it immediately without asking for data.

TURN-2 QUALIFIER RULE:
- If the previous assistant message generated a workflow card AND the user's current message provides a type qualifier (e.g., "germline", "somatic", "bulk RNA-seq", "single-cell", "tumor-only", "paired tumor/normal", "inherited disease", "cancer"), regenerate the workflow immediately with the qualifier applied. Do NOT describe the workflow in text. Do NOT ask for data again. The previous conversation's input data is still valid.

ONE-QUESTION RULE:
- Ask at most ONE clarification question per conversation. Once the user has replied with any data OR answered a question (even if no data was provided), generate the workflow immediately using the information gathered and sensible default parameter values. Do NOT ask multiple rounds of clarifying questions — parameters can be adjusted in the workflow parameter panel after generation.
- SECOND-TURN OVERRIDE: If the conversation history shows that the assistant already asked a question in the previous turn (e.g., asked for data or asked germline/somatic clarification), and the user's current message replies to that question (even if no data accession was given), GENERATE THE WORKFLOW IMMEDIATELY. Do not ask for data again. Use placeholder values for missing required params — the user can fill them in the parameter panel.
- SMILES strings (e.g. CC(=O)Oc1ccccc1C(=O)O), InChI strings, compound names with structures, and amino acid sequences all count as input data — if the user provides ANY of these, generate the workflow immediately without asking ANY clarifying questions.
- When the message contains an "[Uploaded datasets: ...]" block, it means the user has already provided their input data via the file attachment button. Parse it: the format is "filename: dataset_id=<ID>, galaxy_dataset_id=<GALAXY_ID>". Use the galaxy_dataset_id values as the workflow input parameters (e.g. input_bam, reads, input_vcf). Do NOT ask the user for data again — proceed directly to workflow generation using those IDs.
- When the message contains an "[Attached files: ...]" block without a corresponding "[Uploaded datasets: ...]" block, the upload failed. Tell the user which files failed and ask them to try again.
${isDrugDevelopmentQuery ? `- For drug-development requests, provide decision-grade guidance: list concrete workflow phases, critical safety/quality gates, required inputs, and explicit next actions` : ''}
${isDrugDevelopmentQuery ? `- For drug-development WORKFLOW GENERATION FAILURES ONLY (when the system returns an error or cannot find a matching workflow): include at least TWO distinct blocker categories (e.g., tool gap, input gap, domain mismatch) and ask at least TWO targeted follow-up questions. IMPORTANT: This rule does NOT apply when the user has already provided input data (SMILES, sequence, files) — in that case generate the workflow immediately.` : ''}

Workflow routing (use these specific workflows when the user's intent matches):
- "MD simulation", "molecular dynamics", "AMBER", "pmemd", "protein stability in explicit solvent", or "post-docking MM-GBSA refinement": suggest the amber_pmemd_md workflow (AMBER pmemd.cuda GPU MD, 7-step pipeline: GAFF2 parametrization → tleap → EM → NVT/NPT equilibration → production MD → cpptraj RMSD/RMSF → MMPBSA.py ΔGbind. License: free academic since AMBER24.)
- "GROMACS", "GROMACS MD", "GROMOS force field", or explicit mention of GROMACS: suggest the gromacs_protein_md workflow (GROMACS 2025 + gmx_MMPBSA, 8-step pipeline, outputs ΔGbind ± SE and RMSD trajectory)
- "Glide docking", "Schrödinger docking", "Schrodinger docking", "XP docking", "HTVS", "extra precision docking", "virtual screening Glide", or "FEP+ preparation": suggest the schrodinger_glide_docking workflow (Schrödinger Glide HTVS/SP/XP, 5-step pipeline: LigPrep → PrepWiz → Grid → Glide → ranked SDF. License: FlexNet, user must provide.)
- "covalent docking", "covalent inhibitor", "warhead", "acrylamide docking", "irreversible inhibitor design", "MOE docking", or "targeted covalent drug": suggest the moe_covalent_docking workflow (MOE CovDock SVL, 5-step: LigPrep → QuickPrep → CovDock → GBVI/WSA dG → SDF report. Warheads: acrylamide, chloroacetamide, epoxide, aldehyde, michael_acceptor. License: MOE FlexNet, user must provide.)
- "generative drug design", "de novo design", "scaffold hopping", "lead generation", "molecule optimization", "REINVENT", or "fragment decoration": suggest the reinvent4_lead_design workflow (REINVENT4 AstraZeneca, RL-based SMILES generator, outputs ranked molecules + SDF + score trajectory)

${buildDomainSpecialistBlock(preferredDomains)}${buildDomainCatalogBlock(preferredDomains)}Style guide:
- Be concise and practical
- When mentioning tools, use the primary user-facing name (e.g. "CryoSPARC", "BWA-MEM2", "GATK") — never use internal pipeline paths or tool IDs
- Explain workflow steps and expected outputs clearly
- Do NOT include a "Next Steps After This Workflow" section — suggest follow-up steps only after the user confirms execution is complete
${isDrugDevelopmentQuery ? `- Use section labels when possible: "Workflow phases", "Decision gates", "Required inputs", and "Next step"` : ''}

Current context:
${tools.length > 0 ? `- Found ${tools.length} relevant tools` : ''}
${datasets.length > 0 ? `- Found ${datasets.length} relevant datasets` : ''}
${runnableWorkflow ? '- Runnable workflow generated successfully - user can click Run to execute' : ''}
${workflowGenerationFailed ? '- Workflow generation attempt failed and needs collaborative recovery' : ''}`;

    // Build research/benchmark context sections
    const researchSection = researchResponse
      ? `\nResearch Results:\n${JSON.stringify(researchResponse, null, 2).slice(0, 2000)}`
      : '';
    const benchmarkSection = benchmarkEvidence
      ? `\nBenchmark Evidence:\n${JSON.stringify(benchmarkEvidence, null, 2).slice(0, 2000)}`
      : '';

    const userPrompt = `User: ${message}

${tools.length > 0 ? `\nRelevant tools:\n${tools.map((t, i) => `${i + 1}. ${t.tool.name} - ${t.reasoning}`).join('\n')}` : ''}

${datasets.length > 0 ? `\nRelevant datasets:\n${datasets.map((d, i) => `${i + 1}. ${d.dataset.name} - ${d.reasoning}`).join('\n')}` : ''}

${runnableWorkflow ? '\nA runnable workflow has been generated and is ready to run.' : ''}
${workflowGenerationFailed ? `\nWorkflow generation diagnostics:\n${JSON.stringify(workflowFailureSignals, null, 2).slice(0, 1600)}` : ''}${researchSection}${benchmarkSection}

Provide a helpful response that:
1. ${runnableWorkflow ? 'Briefly describes the generated workflow (steps, inputs, expected outputs). Do NOT say "click Run" — the Run button is already visible in the workflow panel rendered separately' : workflowGenerationFailed ? 'Explains why generation likely failed using the provided diagnostics and context' : researchResponse ? 'Presents the research findings with inline [N] citations referencing the numbered list' : benchmarkEvidence ? 'Presents the benchmark comparison with evidence' : tools.length > 0 ? 'Recommends the relevant tool(s) and explains how they will help' : 'Explains what tools or data would be needed'}
2. ${tools.length > 0 ? 'References the specific tools found and their capabilities' : researchResponse ? 'Includes relevant citations and sources' : benchmarkEvidence ? 'Provides structured comparison data' : 'Suggests what the user could search for or ask about'}
3. ${runnableWorkflow ? 'Describes what output to expect after running' : workflowGenerationFailed ? 'Asks 2-4 targeted follow-up questions and gives a concrete recovery plan the user can confirm or edit' : researchResponse ? 'Ends with a ## References section listing only the papers cited (numbered, with authors, title, journal, year, and URL/DOI where available)' : 'Suggests creating a workflow to accomplish the task'}
4. ${isResearchIntent ? 'Focus on scientific accuracy — only cite papers from the provided list, never fabricate citations' : 'DO NOT compute or calculate any results yourself - always recommend using BioMate tools'}
${isDrugDevelopmentQuery && !isResearchIntent ? `
5. If drug-development related:
   - Include at least 2 concrete workflow phases (e.g., target prep, docking, ADMET, hERG, PK/NCA).
   - Include at least 1 decision gate/criterion (e.g., ranking/cutoff/risk flag) or explicitly state why criterion cannot be provided.
   - If generation fails, provide at least 2 blocker categories plus at least 2 follow-up questions.` : ''}`;

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
        apiOptions.temperature = 0.7;
      }

      let rawResponse = '';
      let lastStopReason: string | null = null;
      if (onResponseDelta) {
        const stream = await this.claude.messages.create({
          ...apiOptions,
          stream: true,
        } as any);
        for await (const event of stream as any) {
          if (event?.type === 'content_block_delta' && event?.delta?.type === 'text_delta') {
            const text = String(event.delta.text || '');
            if (text) {
              rawResponse += text;
              onResponseDelta(text);
            }
          } else if (event?.type === 'message_stop') {
            lastStopReason = String(event?.message?.stop_reason || '');
          }
        }
        console.log('[GalaxyAssistant] Response stream complete:', {
          model: this.modelConfig.responseModel,
          time_ms: Date.now() - apiStartTime,
          stop_reason: lastStopReason,
          streamed_chars: rawResponse.length,
        });
      } else {
        const completion = await this.claude.messages.create(apiOptions);

        console.log('[GalaxyAssistant] Response API response:', {
          model: this.modelConfig.responseModel,
          time_ms: Date.now() - apiStartTime,
          usage: completion.usage,
          stop_reason: completion.stop_reason,
          content_blocks: completion.content.length
        });

        // Find the text content block (thinking mode returns [thinking, text])
        const textContent = completion.content.find(c => c.type === 'text');
        rawResponse = textContent && textContent.type === 'text' ? textContent.text : 'I can help you with that!';
      }

      // Detect and parse thinking content
      const thinkingResult = thinkingDetector.detectThinking(rawResponse);

      console.log('[GalaxyAssistant] Response generated with thinking:', {
        hasThinking: thinkingResult.hasThinking,
        thinkingLevel: thinkingResult.thinkingLevel,
        thinkingWords: thinkingResult.thinkingWordCount
      });

      const qualityEnforcedMessage = this.enforceDrugDevelopmentResponseQuality({
        userMessage: message,
        assistantMessage: thinkingResult.answerContent,
        runnableWorkflow,
        workflowGenerationFailed,
        workflowFailureSignals,
      });

      const wasTruncated = lastStopReason === 'max_tokens';
      return {
        message: qualityEnforcedMessage,
        thinking: thinkingResult.hasThinking ? thinkingResult : undefined,
        truncated: wasTruncated,
      };
    } catch (error) {
      console.error('[GalaxyAssistant] Response generation failed:', error);
      return {
        message: 'I found some relevant tools and datasets for your analysis. How would you like to proceed?'
      };
    }
  }

  private enforceDrugDevelopmentResponseQuality(params: {
    userMessage: string;
    assistantMessage: string;
    runnableWorkflow: boolean;
    workflowGenerationFailed: boolean;
    workflowFailureSignals: any;
  }): string {
    const { userMessage, assistantMessage, runnableWorkflow, workflowGenerationFailed, workflowFailureSignals } = params;
    const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
      userMessage || ''
    );
    if (!isDrugDevelopmentQuery) {
      return assistantMessage;
    }

    const text = assistantMessage || '';
    const lower = text.toLowerCase();
    const additions: string[] = [];

    const hasWorkflowPhases = /(workflow phases|phase|target prep|docking|admet|herg|pk\/nca|nca)/i.test(lower);
    const hasDecisionGates = /(decision gate|gating|cutoff|threshold|risk flag|go\/no-go|go-no-go)/i.test(lower);
    const hasRequiredInputs = /(required inputs|input files|you provide|input data)/i.test(lower);
    const hasNextStep = /(next step|next steps|confirm or edit|please confirm|follow-up)/i.test(lower);

    if (!hasWorkflowPhases) {
      additions.push(
        '### Workflow phases\n- Target/assay context and data intake\n- Core analysis phase (e.g., docking, ADMET, or PK/NCA)\n- QC/safety review and report handoff'
      );
    }
    if (!hasDecisionGates) {
      additions.push(
        '### Decision gates\n- Define explicit cutoffs/thresholds for risk ranking (for example: toxicity risk flag, hERG gate, or PK acceptability criteria)\n- Use these gates as go/no-go checkpoints before advancing candidates'
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
      .slice(0, 4000); // Keep prompt compact for Haiku

    const summaryResp = await this.claude.messages.create({
      model: 'claude-haiku-4-5',
      max_tokens: 256,
      messages: [
        {
          role: 'user',
          content:
            `Summarize the following conversation in 2-3 sentences, focusing on what the user was trying to accomplish and any decisions made:\n\n${historyText}`,
        },
      ],
    });

    const summary =
      summaryResp.content[0]?.type === 'text' ? summaryResp.content[0].text.trim() : '';

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
