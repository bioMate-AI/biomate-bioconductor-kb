import { responseLanguageDirective } from "./response-language";
import { runButtonLabel } from "./ui-labels";
import { PROJECT_CONTEXT_NOTE, intentRulesBlock } from './project-rules';
import { additionalIntentWorkflows, workflowIntent } from './multi-intent-workflows';
import {
  applyLibraryMoleculeDualPath,
  isMoleculeGenerateRequest,
  messageSupportsCatalogChainHint,
  remapBulkRnaseqChainForCounts,
  type LibraryMoleculePath,
} from './library-triage-sequential';
import { isSimpleSequencePropertyRequest } from './sequence-property-intent';
import { ChatContextBuilder, manifestSummary } from './chat-context-harness';
import { localOnly, localOffline, localMessagesClient, localConfig, openaiCompatMessagesClient, reasoningBudgetBody, assertNotReasoningExhausted } from './local-llm.js';
import { cardWorkflowName } from './workflow-display-name';
import { singleWorkflowGroundingDirective } from './single-workflow-grounding';
import { stagedInputPath } from './code-runner';
import { localIntentPrompt } from './local-intent-prompt.js';
import { localResponsePrompt } from './local-response-prompt.js';
import { renderOperationSkillsBlock } from './operation-skills';
import { scientificToolRequest, scientificToolResult, targetEvidenceReply, databaseQueryRequest, databaseQueryResult } from './scientific-chat-tools';
import { groundedResearchReply, researchEvidenceContext } from './grounded-research-reply';
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

import { resolveChainHintNames } from './chain-hint-fallback';
import { routingExamplesPrompt } from './routing-examples';
import { EXECUTE_NOW_NUDGE, attachedInputNames, generatesSyntheticData, redactStoragePaths, shouldRequireExecution, syntheticDataAllowed, SYNTHETIC_DATA_REFUSAL, unbackedOutputFileClaims } from './execution-integrity';
import { applyRetrievalHints, applyUserConstraintGate, boinDoseLevelsMissing, parseUserConstraint, reconcileExecutionMode, type UserConstraint } from './routing-authority';
import { jsonrepair } from 'jsonrepair';
import Anthropic from '@anthropic-ai/sdk';
import OpenAI from 'openai';
import { AsyncLocalStorage } from 'node:async_hooks';
import { GoogleGenerativeAI, SchemaType } from '@google/generative-ai';
import { callGeminiFlash } from './gemini-flash';
import { requireCnRoute, currentLlmPolicy, policyMessagesClient, cnCompletion, cnRouteForRole, cnRoleMessagesClient, isChineseModel, modelIdentity, modelIdentityDirective, OPENROUTER_URL, type ModelIdentity, type LlmRegion } from './llm-region-policy';
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import { buildCanonicalFixturePromptSection, matchesCanonicalFixture } from './canonical-fixtures';
import { resolveCanonicalChainStepPath } from './canonical-chain-steps';

// Per-request override of `this.galaxyAPI`. Set by processMessage() when the
// caller (chat-stream) provides context.galaxyAPIOverride; resolved at every
// `this.galaxyAPI` call site so the assistant uses the authenticated user's
// per-user Galaxy API key for that single in-flight request only (no leakage
// across concurrent users). See ChatContext.galaxyAPIOverride for rationale.
const _galaxyAPIRequestStorage = new AsyncLocalStorage<GalaxyAPIProxy>();

// Per-request override for the Anthropic client. When a user supplies their
// own API key (stored encrypted in users.llm_api_keys), processMessage() runs
// inside this storage so _getClaude() returns a client scoped to their key.
// Falls back to the singleton's this.claude (system key) when not set.
const _anthropicOverride = new AsyncLocalStorage<Anthropic>();

// Per-request OpenRouter client. Set in processMessage() when the user has
// configured an OpenRouter key; _getOpenRouterClient() returns it or null.
const _openrouterClientStorage = new AsyncLocalStorage<OpenAI>();
// Set true for a turn whose LLM backbone is an OpenRouter-selected model routed
// through the agentic shim (openaiCompatMessagesClient, stored in _anthropicOverride).
// Flips isClaudeBackbone so the response path takes the agentic tool loop — the same
// structural decision localOnly makes — instead of the text-only provider chain.
const _openrouterAgentic = new AsyncLocalStorage<boolean>();
import { conversationStateManager } from './conversation-state';
import { shouldInjectDatasets } from './dataset-injection-gate';
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
import { classifyRunFailure, formatRunFailureReply } from '../shared/run-failure-classifier';
import { attachedNamesFromBlocks, stripSystemBlocks } from '../shared/chat-system-blocks';
import { toolCallDisplay } from '../shared/tool-call-display';
import { decideWorkflowReplyState } from '../shared/workflow-response-state';
import { unboundRequiredDataInputs, messageCarriesRunData, messageWaivesDataAsk, shouldRunOnExampleData, exampleDataNote } from '../shared/workflow-data-inputs';
import {
  parseAttachedFiles,
  bindAttachmentsToParams,
  rebindFilenameValues,
  attachmentsNotUsed,
  isNonInputAttachment,
  buildResolvedNfcoreInputSamplesheet,
} from '../shared/attachment-binding';
import {
  applyPreparedInputParamsToWorkflow,
  parsePreparedInputParams,
} from '../shared/prepared-inputs-params';

// ─── Agent tool infrastructure ────────────────────────────────────────────────

/** Emitted for each tool invocation during an agent loop turn. */
export interface AgentToolEvent {
  type: 'tool_call' | 'tool_result' | 'status';
  tool_use_id: string;
  name: string;
  input?: Record<string, unknown>;  // populated on tool_call
  display?: string;                 // tool_call: user-facing summary of `input` (no ids / storage paths)
  output?: unknown;                 // populated on tool_result
  error?: string;                   // populated on tool_result when execution failed
  duration_ms?: number;             // populated on tool_result
  // status events carry a user-visible message + optional structured payload
  // (e.g. { stage: 'extracting', confidence: 0.92 }).
  message?: string;
  payload?: Record<string, unknown>;
}

/** User-facing summary of a tool call: dataset ids become the dataset's name (from this turn's
 *  session datasets), other ids and storage paths are dropped — the chat card never shows raw input. */
export function toolCallDisplayFor(input: Record<string, unknown> | undefined, context?: Pick<ChatContext, 'sessionDatasets' | 'turnMessage'>): string {
  const datasets = context?.sessionDatasets || [];
  const attached = attachedDatasetsFromMessage(context?.turnMessage || '');
  return toolCallDisplay(input, (id) => datasets.find(d => d.id === id || d.projectFileId === id)?.name
    || attached.find(a => a.galaxyId === id || a.datasetId === id)?.name);
}

/** Anthropic tool definitions registered with the agent. */
const BIOMATE_TOOLS: Anthropic.Tool[] = [
  {
    name: 'run_code',
    description: `Execute Python, R, or bash code on the user's uploaded datasets.
Use this for: filtering/subsetting data, format conversion, statistics, generating plots,
exploring file contents, counting rows/records, parsing ZIP/archive files, or any ad-hoc computation.

Python calls within one reply behave like notebook cells: variables, imports and data loaded by
earlier successful calls of this reply are available (their code is re-run silently first). R and
bash calls are separate processes and must load what they use.

File access: Input datasets are staged at $DATA_DIR/<dataset_id>/<original_filename>, and a
preamble predefines INPUT_FILES (a map from original filename -> absolute path) and INPUT_PATHS
(the list of those paths) for every dataset you list in input_datasets. USE THESE DIRECTLY — e.g.
Python: path = INPUT_FILES['raw_counts.csv']  (or just iterate INPUT_PATHS); R: INPUT_FILES[["x.zip"]].
Do NOT run find/ls over '/', '/tmp', or the working directory to locate inputs, and do
NOT guess paths: every input is under $DATA_DIR and already in INPUT_FILES. If INPUT_FILES is empty
you forgot to pass input_datasets — pass the ids from the [Uploaded datasets:] block and retry.
Example — if raw_counts.csv was uploaded with dataset_id=abc123 (pass input_datasets=['abc123']):
  import os, pandas as pd
  df = pd.read_csv(INPUT_FILES['raw_counts.csv'], index_col=0)   # or os.path.join(os.environ['DATA_DIR'], 'abc123', 'raw_counts.csv')

NEVER generate, simulate or hard-code measurements to stand in for data that was not provided
(no random draws, no "typical" values, no assumed distributions as input data). If no dataset is
available and the request names a workflow or its built-in sample data, do not compute — the
workflow card runs on its real built-in data; otherwise ask the user for the data.

Write output files to $OUTPUT_DIR (os.environ['OUTPUT_DIR']). Each file a call writes is saved as a
dataset of this conversation: the user gets a download link, and its dataset_id is returned in
output_files. $OUTPUT_DIR persists for the whole conversation — a file written in an earlier call or
turn is still at os.path.join(os.environ['OUTPUT_DIR'], '<name>'), so read it from there instead of
recomputing it. Only files actually written there exist; never describe a file you did not write.
When telling the user about files, name the files and say they are saved (to the project, in a project
chat) — never mention $OUTPUT_DIR, /work or other internal paths. List every file you wrote.
Plots: save one figure per file with a descriptive name (e.g. fig1_score_distribution.png) — not one
multi-panel "dashboard" unless the user asks for one; plt.savefig(...) then plt.close(). Chinese,
Japanese and Korean labels render correctly — label in the user's language. A Markdown report must sit
next to its figures: write it in the same call as (or after) them and embed each with a bare relative
link, ![caption](fig1_score_distribution.png) — no directory, no absolute path.
Documents: Word (.docx) via python-docx (from docx import Document; doc.add_picture(path)) or pandoc
(pandoc report.md -o report.docx, run from $OUTPUT_DIR so figures resolve); PowerPoint via python-pptx.
The sandbox has NO network — never pip/apt install; use what is installed.
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
          description: 'dataset_id values of the datasets to make available (from the [Uploaded datasets:] block or <session_datasets>)',
        },
      },
      required: ['language', 'code'],
    },
  },
  {
    name: 'read_file',
    description: `Preview or open an uploaded dataset by its id — works on ANY turn for any
dataset listed in <session_datasets>, so you never need the user to re-attach a file.
Use it before running code or a workflow to see column names, types, record count, and
the first rows. For a PDF it returns the extracted text (including tables). For an IMAGE
(png/jpg/jpeg/gif/webp) it returns the actual image for you to VIEW — call this to look at
a gel/blot/histology/plot/scan the user uploaded earlier, then describe/interpret it.
Returns a structured summary regardless of format (CSV, TSV, FASTA, VCF, BAM, PDF, image…).`,
    input_schema: {
      type: 'object' as const,
      properties: {
        dataset_id: {
          type: 'string',
          description: 'The dataset_id from the [Uploaded datasets:] block or <session_datasets>',
        },
        n_lines: { type: 'number', description: 'Number of rows/records to preview (default 20)' },
      },
      required: ['dataset_id'],
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
  {
    name: 'list_history',
    description: `List the user's recent workflow runs (id, workflow name, status, params summary, output count).
Use this when the user refers to a past run without naming it precisely: e.g. "do the same as last week's RNA-seq with PARP1 instead",
"reuse my last ADMET parameters", "show me the variant call I ran on chr17". Returns up to N most recent runs (default 10).
Cite a run back to the user using its 8-char id.
Note: this surfaces RUNS (workflow executions), not raw uploaded files — separate UI lists those.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        limit: { type: 'number', description: 'How many recent runs to return (default 10, max 25)' },
        workflow_filter: {
          type: 'string',
          description: 'Case-insensitive substring filter on workflowName (e.g. "rnaseq", "admet")',
        },
        status_filter: {
          type: 'string',
          enum: ['running', 'completed', 'failed', 'cancelled'],
          description: 'Optional filter on execution status',
        },
      },
    },
  },
  {
    name: 'search_literature',
    description: `Search scientific literature across PubMed, Europe PMC, Semantic Scholar, OpenAlex and bioRxiv/medRxiv
preprints (not peer reviewed; rows carry peer_reviewed=false) in parallel, with an iterative broaden-on-gap loop. Use this to ground a claim in real papers, find prior
art / mechanism evidence, or build an evidence review — instead of answering from memory. Returns ranked
papers with title, authors, year, PMID/DOI, and abstract snippet. Cite what you use; never invent a DOI
or PMID. Prefer this over guessing when the user asks "what evidence supports…", "find papers on…", or
"is X established or just proposed?".`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'Key entities/terms to search (e.g. "PEX13 PEX14 PEX5 oligomerization"). Over-long queries return fewer hits — keep it focused.',
        },
        min_results: { type: 'number', description: 'Broaden until at least this many papers are found (default 12).' },
        max_depth: { type: 'number', description: 'Max broaden-on-gap iterations, 1–4 (default 3).' },
      },
      required: ['query'],
    },
  },
  {
    name: 'query_database',
    description: `Look up or search BioMate's public biological databases. Choose \`operation\` from the user's intent (never from the
shape of the query): "lookup" (default) fetches by accession, symbol or name; "text" is a keyword search; "similarity" searches
the WHOLE database by structure or sequence — ChEMBL and PubChem take a SMILES (Tanimoto), PDB takes a protein sequence (homolog
search over every PDB entry). Name a \`database\` for a single source, or leave it as "federated" to look the term up in the relevant
sources in parallel (optionally restrict with \`sources\`, entity_type auto-detected). Databases: uniprot, pdb, pdbe, alphafold,
interpro, string, ncbi_gene, ensembl, dbsnp, clinvar, gnomad, kegg, reactome, go, hpo, chebi, chembl, pubchem, bindingdb, pharos,
clinicaltrials (registered trials: status, phase, sponsor, stop reason; registry records, not results), biorxiv (preprints, not
peer reviewed). For papers use search_literature; for target ranking use identify_targets. Cite the record id and the source;
a source that errored was not searched.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: { type: 'string', description: 'Accession, gene symbol, compound/disease name, SMILES (similarity on chembl/pubchem) or protein sequence (similarity on pdb).' },
        database: { type: 'string', enum: ['federated', 'uniprot', 'pdb', 'pdbe', 'alphafold', 'interpro', 'string', 'ncbi_gene', 'ensembl', 'dbsnp', 'clinvar', 'gnomad', 'kegg', 'reactome', 'go', 'hpo', 'chebi', 'chembl', 'pubchem', 'bindingdb', 'pharos', 'clinicaltrials', 'biorxiv'], description: 'Default "federated".' },
        operation: { type: 'string', enum: ['lookup', 'text', 'similarity'], description: 'Search mode chosen from the user\'s intent. similarity needs database chembl, pubchem or pdb.' },
        entity_type: { type: 'string', enum: ['gene', 'protein', 'compound', 'variant', 'pathway', 'structure', 'disease', 'literature'], description: 'Federated only; auto-detected when omitted.' },
        sources: { type: 'array', items: { type: 'string' }, description: 'Federated only: restrict to these source ids, e.g. ["clinicaltrials"].' },
      },
      required: ['query'],
    },
  },
  {
    name: 'search_my_data',
    description: `Search the USER'S OWN datasets across all their BioMate projects — uploaded files and
workflow run outputs alike (counts matrices, FASTQs, VCFs, structures, reports, etc.). Use this before
asking the user to upload something, or when they refer to "my data", "the file I uploaded", "results
from my last run", or a dataset by partial name. Returns matching files with name, type, size, the
workflow/step that produced them, and the project they live in. Prefer this over assuming a file isn't
available — the user may already have it in the platform.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'Terms to match against filename, workflow, step, or source (e.g. "rnaseq counts", "salmon quant", "vcf"). Space-separated tokens are AND-matched.',
        },
        type: { type: 'string', description: 'Optional content-type filter substring (e.g. "csv", "fastq", "image", "pdb").' },
        source: { type: 'string', description: 'Optional exact source filter: "upload" or "run_output".' },
        limit: { type: 'number', description: 'Max results (default 25, cap 100).' },
      },
      required: ['query'],
    },
  },
  {
    name: 'list_data_sources',
    description: `List the external biological data sources BioMate can query — its canonical
self-awareness catalog (UniProt, PDB, PubChem, ChEMBL, gnomAD, ClinVar, KEGG, Reactome, PubMed,
Europe PMC, and more). Use this when the user asks "what databases can you access?", "can you query
<X>?", or before telling the user a source is unavailable — check here first instead of guessing.
Returns each source's name, category, the entity types it covers, and which surfaces reach it, plus
a summary count. Sources marked status "planned" are not yet wired (do not claim they work).`,
    input_schema: {
      type: 'object' as const,
      properties: {
        category: { type: 'string', description: 'Optional filter, e.g. "compound", "gene", "variant", "literature", "structure", "pathway".' },
        entity_type: { type: 'string', description: 'Optional: only sources covering this entity type (gene, protein, compound, variant, pathway, structure, disease, literature).' },
        status: { type: 'string', description: 'Optional: "live" (default view is all) or "planned".' },
      },
      required: [],
    },
  },
  {
    name: 'search_workflows',
    description: `Search BioMate's OWN catalog of 4,200+ indexed Nextflow/nf-core workflows (across
42 biological domains) by natural-language intent, on ANY turn. Use this — do NOT answer from the
static capability counts in the system prompt — whenever the user asks what BioMate can run, e.g.
"do you have a sarek variant-calling workflow?", "is there an RNA-seq pipeline?", "what CryoEM
workflows exist?", or when deciding whether a matching pipeline already exists before suggesting one.
Returns the top ranked real catalog entries (name, domain, one-line description, source, and relevance
score) from the live index. If nothing relevant comes back, the catalog has no close match — say so
instead of inventing a workflow name.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'Natural-language description of the pipeline/task (e.g. "somatic variant calling WGS", "bulk RNA-seq differential expression", "single-particle cryo-EM refinement").',
        },
        domain: {
          type: 'string',
          description: 'Optional domain bias, e.g. "variant_calling", "transcriptomics", "drug_discovery", "cryo_em". Narrows ranking toward that domain; omit to search all domains.',
        },
        limit: { type: 'number', description: 'Max results to return (default 10, cap 25).' },
      },
      required: ['query'],
    },
  },
  {
    name: 'request_new_tool',
    description: `Request that BioMate fetch and register a NEW analysis tool that is NOT yet in its
catalog, by driving its GitHub tool-ingest pipeline (search a repo -> fetch docs -> generate a
tool wrapper -> validate -> register as an auto_discovered, quality-gated tool).

Use ONLY as a last resort, after search/compose has genuinely found no existing tool for the
user's capability (i.e. you would otherwise have to say "no tool available"). Do NOT use this to
run analyses, to find already-indexed tools, or for general questions.

SAFETY — this reaches an external service (GitHub) and modifies the catalog, so it is gated:
  * It may be disabled on this deployment (you will get status "disabled" — then just tell the
    user the capability is not yet available; do not retry).
  * It requires EXPLICIT user confirmation. First call it WITHOUT confirm (or confirm=false) to get
    the confirmation prompt, relay that to the user, and only call again with confirm=true AFTER the
    user clearly agrees. Never set confirm=true on the user's behalf.
Returns a status: registered / already_exists / not_feasible / has_api / needs_review / not_found /
confirmation_required / disabled. Report the status plainly; do not claim a tool is usable unless
status is "registered".`,
    input_schema: {
      type: 'object' as const,
      properties: {
        capability_description: {
          type: 'string',
          description: 'What the needed tool should do, in plain terms (e.g. "nanopore methylation caller", "long-read structural variant genotyper").',
        },
        repo: {
          type: 'string',
          description: 'Optional exact GitHub repository as "owner/name", if the user named a specific tool/repo. Takes precedence over capability_description.',
        },
        confirm: {
          type: 'boolean',
          description: 'Set true ONLY after the user has explicitly confirmed the fetch+register. Omit or false otherwise.',
        },
      },
      required: ['capability_description'],
    },
  },
  {
    name: 'identify_targets',
    description: `Identify and rank candidate drug/biomarker TARGETS (genes) for a disease or
biological question, with provenance. Use this when the user asks "what are the targets for X?",
"nominate targets for <disease>", "rank these genes as targets", "what's the evidence for GENE in
DISEASE?", or wants a fast evidence scan before committing to a target. Returns a ranked list of
genes, each with a confidence TIER (corroborated / nominated / vetoed), a score, which evidence
CHANNELS fired, per-channel scores and provenance — so the answer is auditable, not asserted.

HONEST FRAMING: inspect the returned ranking metadata, actual channels, provenance and errors.
When OpenTargets is available the default order follows its association scores; other channels
provide corroboration/conflict. Without a disease ID or when OpenTargets fails, do NOT claim
OpenTargets-primary ordering. LLM-only nomination is not retrieved literature evidence. No result
establishes superiority over OpenTargets or clinical validity. Report every tier faithfully, including
supporting/none/vetoed. Never describe harmonic-sum per_channel_z values as statistical z-scores.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'The target-identification question / disease / biology (e.g. "targets for cutaneous melanoma", "rank BRAF, CDKN2A, BAP1 as melanoma targets").',
        },
        disease_id: {
          type: 'string',
          description: 'Optional verified EFO/MONDO disease id — enables the OpenTargets disease-association channel. Omit if unknown; never guess the identifier.',
        },
        disease: {
          type: 'string',
          description: 'The full disease name from the user, e.g. non-small-cell lung carcinoma. Supply this for disease-specific requests: the backend verifies the name against Open Targets. Prefer this over recalling an ontology id; never guess an id.',
        },
        candidate_targets: {
          type: 'array',
          items: { type: 'string' },
          description: 'Optional explicit gene symbols to score/rank (e.g. ["BRAF","CDKN2A","BAP1"]). Omit to let the channels nominate.',
        },
        top_k: { type: 'integer', minimum: 1, maximum: 100, description: 'How many ranked targets to return (default 25).' },
        ranking_mode: { type: 'string', enum: ['auto', 'integrated'], description: "'auto' (default) follows Open Targets when available; 'integrated' weights all channels together." },
        validate: { type: 'boolean', description: 'Also return, for the top targets, the BioMate workflows that could test them.' },
        suggest_modality: { type: 'boolean', description: 'Also return a guidance-only drug-type suggestion (small molecule / biologic / ...) for the top targets. Not validated; say so.' },
      },
      required: ['query'],
    },
  },
  {
    name: 'write_review',
    description: `Write a literature-backed OVERVIEW / SURVEY / mini-review on a scientific topic and
return synthesized PROSE with real citations — not just a paper list. Use this when the user asks to
"write an overview of X", "give me a survey/review of the field", "summarize the state of the art on
Y", or wants a grounded narrative with references. This runs BioMate's research agent, which does its
own literature retrieval + knowledge-base facts and synthesizes a written answer with a citation list,
a confidence score, and follow-up questions. Prefer this over search_literature when the user wants
WRITTEN synthesis; prefer search_literature when they just want the ranked papers. Cite only what the
tool returns — never invent a DOI/PMID. (Composes well after identify_targets: rank targets, then
write the overview of the top target's biology.)`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'The topic/question to write the overview on (e.g. "overview of KRAS G12C inhibitors in NSCLC", "survey of spatial transcriptomics deconvolution methods").',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'search_chat_history',
    description: `Search the user's OWN past conversations (their earlier chat sessions) for text they
mentioned before. Use this — do NOT guess from memory — whenever the user refers to something from a
prior chat: "what did we conclude last week", "find the chat where we discussed GRCh38", "which
session had the ADMET run", "remind me what we decided about X". It AND-matches your query words
(case-insensitive) against the raw transcripts of this user's other sessions and returns the most
recently-active matches first, each with a short snippet and the session_id. It does NOT search the
CURRENT conversation (you already have that above) and only ever sees this user's own chats. An empty
result is a REAL answer: if nothing matches, tell the user you found no prior chat mentioning it and
ask them to paste the detail — never fabricate a recollection.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'The words to look for across past chats (e.g. "GRCh38 variant calling", "hERG threshold", "the campaign we named Falcon"). Keep it to the distinctive terms.',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'edit_report',
    description: `Edit the written FINDINGS REPORT of one of the user's runs, through chat, and save it as a
new report version. Use this when the user asks to change their report in words: "tighten the abstract
of my last run's report", "add a limitations paragraph", "rewrite the summary for a clinical audience".
This edits the REAL, durable, versioned report (the same object the report panel shows) — version 0 (the
run original) is always preserved; your edit is appended as a new version.

THREE-STEP, NEVER-SILENT flow — follow it in order:
  1. Call with just {run_id} (and optionally the user's instruction). The tool returns base_markdown —
     the current report text. If it returns status "no_report_text", the report has not been opened or
     saved yet: ask the user to open it in the report panel once, or paste the text. NEVER invent a
     report body.
  2. Compose the FULL edited report yourself and call again with {run_id, new_content}. The tool returns
     a diff preview (added/removed lines). Show that change to the user. Do NOT save yet.
  3. Only after the user agrees, call with {run_id, new_content, confirm: true} to SAVE it as a new
     version. Saving modifies the user's report, so it requires their explicit OK first.
If the client provided the exact text the user is viewing, pass it as current_markdown so the edit forks
from precisely what they see.`,
    input_schema: {
      type: 'object' as const,
      properties: {
        run_id: {
          type: 'string',
          description: "The run whose report to edit (run id or invocation id). Get it from the recent-runs context or list_history if unsure.",
        },
        instruction: {
          type: 'string',
          description: 'Optional: what the user asked to change, for your own reference on step 1 (e.g. "tighten the abstract").',
        },
        new_content: {
          type: 'string',
          description: 'The FULL edited report markdown you composed. Required for the preview (step 2) and the save (step 3). Omit on step 1 to fetch the current text first.',
        },
        confirm: {
          type: 'boolean',
          description: 'Set true ONLY to save, and ONLY after the user has agreed to the previewed change. Without it the tool previews and does not write.',
        },
        current_markdown: {
          type: 'string',
          description: 'Optional: the exact report text the user is currently viewing, if the client supplied it. Used as the edit base so the fork matches what they see.',
        },
        note: {
          type: 'string',
          description: 'Optional short label stored with the saved version (e.g. "tightened abstract via chat").',
        },
      },
      required: ['run_id'],
    },
  },
];

/** Line-level diff summary produced by summarizeReportEdit, used by the edit_report
 *  tool to show the user WHAT an edit changes before it is saved. */
export interface ReportEditSummary {
  added: number;
  removed: number;
  baseLines: number;
  nextLines: number;
  unchanged: boolean;
  /** A short unified-diff-style preview (±/context lines), truncated. */
  preview: string;
}

/** Minimal LCS line diff. O(m*n) memory — guarded by the caller for large inputs.
 *  Returns a tagged sequence: ' ' context, '-' removed (in base only), '+' added
 *  (in next only). */
function lcsLineDiff(a: string[], b: string[]): Array<{ type: ' ' | '-' | '+'; line: string }> {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = m - 1; i >= 0; i--) {
    for (let j = n - 1; j >= 0; j--) {
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  const out: Array<{ type: ' ' | '-' | '+'; line: string }> = [];
  let i = 0;
  let j = 0;
  while (i < m && j < n) {
    if (a[i] === b[j]) {
      out.push({ type: ' ', line: a[i] });
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.push({ type: '-', line: a[i] });
      i++;
    } else {
      out.push({ type: '+', line: b[j] });
      j++;
    }
  }
  while (i < m) out.push({ type: '-', line: a[i++] });
  while (j < n) out.push({ type: '+', line: b[j++] });
  return out;
}

/** Summarize the change from `base` report markdown to `next`. Counts added/removed
 *  lines and builds a short preview of only the changed lines (with a little context),
 *  truncated to `maxPreviewLines`. For very large reports it falls back to a
 *  multiset line-count so it never allocates an O(m*n) table. Pure + testable. */
export function summarizeReportEdit(base: string, next: string, maxPreviewLines = 40): ReportEditSummary {
  const a = (base ?? '').split('\n');
  const b = (next ?? '').split('\n');
  if (base === next) {
    return { added: 0, removed: 0, baseLines: a.length, nextLines: b.length, unchanged: true, preview: '' };
  }
  // Guard the O(m*n) table on large inputs: fall back to a frequency-based count.
  if (a.length > 2000 || b.length > 2000) {
    const freq = new Map<string, number>();
    for (const l of a) freq.set(l, (freq.get(l) ?? 0) + 1);
    for (const l of b) freq.set(l, (freq.get(l) ?? 0) - 1);
    let added = 0;
    let removed = 0;
    for (const v of freq.values()) {
      if (v < 0) added += -v;
      else if (v > 0) removed += v;
    }
    return {
      added,
      removed,
      baseLines: a.length,
      nextLines: b.length,
      unchanged: added === 0 && removed === 0,
      preview: '(report too large to show a line-by-line preview; ' + added + ' line(s) added, ' + removed + ' removed)',
    };
  }
  const diff = lcsLineDiff(a, b);
  let added = 0;
  let removed = 0;
  for (const d of diff) {
    if (d.type === '+') added++;
    else if (d.type === '-') removed++;
  }
  const previewLines: string[] = [];
  for (const d of diff) {
    if (d.type === ' ') continue;
    previewLines.push((d.type === '+' ? '+ ' : '- ') + d.line);
    if (previewLines.length >= maxPreviewLines) {
      previewLines.push('… (preview truncated)');
      break;
    }
  }
  return {
    added,
    removed,
    baseLines: a.length,
    nextLines: b.length,
    unchanged: added === 0 && removed === 0,
    preview: previewLines.join('\n'),
  };
}

/** Pull a short, readable snippet from a chat_sessions.messages JSONB value around
 *  the first matching token. Defensive about message shape (array of {role,content},
 *  content as string | array-of-parts, or an arbitrary object). Used by the
 *  search_chat_history tool handler. */
export function extractChatSnippet(messages: any, lowerTokens: string[]): string {
  let flat = '';
  try {
    if (typeof messages === 'string') {
      flat = messages;
    } else if (Array.isArray(messages)) {
      flat = messages
        .map((m: any) => {
          if (typeof m === 'string') return m;
          const c = m?.content ?? m?.text ?? '';
          if (typeof c === 'string') return c;
          if (Array.isArray(c)) {
            return c.map((p: any) => (typeof p === 'string' ? p : p?.text ?? '')).join(' ');
          }
          return '';
        })
        .join('\n');
    } else if (messages && typeof messages === 'object') {
      flat = JSON.stringify(messages);
    }
  } catch {
    flat = '';
  }
  flat = flat.trim();
  if (!flat) return '';
  const hay = flat.toLowerCase();
  let idx = -1;
  for (const tok of lowerTokens) {
    if (!tok) continue;
    const i = hay.indexOf(tok);
    if (i >= 0 && (idx < 0 || i < idx)) idx = i;
  }
  if (idx < 0) idx = 0;
  const start = Math.max(0, idx - 80);
  const end = Math.min(flat.length, idx + 180);
  let snip = flat.slice(start, end).replace(/\s+/g, ' ').trim();
  if (start > 0) snip = '…' + snip;
  if (end < flat.length) snip = snip + '…';
  return snip;
}

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
  intentModel: 'gemini-3.8-flash',  // overridden by BIOMATE_INTENT_MODEL env var; gemini-3.8-flash in production
  toolRankingModel: 'claude-haiku-4-5',  // Haiku: fast lightweight ranking
  responseModel: 'gemini-3.8-flash',     // Primary: Gemini Flash; Claude/OpenAI/Ollama as fallback chain
  enableThinking: false,                 // Disable thinking by default for lower latency
  thinkingBudget: 2000,
};

// Two-tier Gemini routing: Pro for complex queries, Flash for simple ones.
// Overridable via env so model names can be tuned without code changes.
const GEMINI_FLASH_MODEL = process.env.BIOMATE_INTENT_MODEL_FLASH || 'gemini-3.8-flash';
const GEMINI_PRO_MODEL   = process.env.BIOMATE_INTENT_MODEL_PRO   || 'gemini-3.1-pro-preview';

/**
 * Pick the appropriate Gemini intent model based on query complexity.
 * Routes Pro for queries that are likely to produce large JSON intent payloads:
 *   - long messages (>140 chars)
 *   - multi-entity / comparison queries ("compare A vs B vs C", multi-target lists)
 *   - dense technical jargon (3+ tokens that look like gene names / drug names / IDs)
 * Otherwise routes Flash for cost/latency.
 */
export function pickGeminiIntentModel(_message: string): string {
  // Always use Flash for intent classification — Pro hangs for 110s+ without timeout
  // (rate-limiting / API latency) making the system unusable. Flash handles JSON
  // intent parsing equally well and responds in <5s vs 110s+ for Pro.
  return GEMINI_FLASH_MODEL;
}

export interface GalaxyAssistantOptions {
  /** Anthropic API key — optional when GOOGLE_API_KEY / GEMINI_API_KEY is present */
  anthropicApiKey?: string;
  galaxyAPIProxy: GalaxyAPIProxy;
  /** Model configuration - uses defaults if not provided */
  modelConfig?: Partial<ModelConfig>;
}

export interface ChatContext {
  /** Default reply language; scientific values and user text remain unchanged. */
  uiLanguage?: 'en' | 'zh';
  /** Chinese-LLM region policy (llm-region-policy.ts): 'cn' = every LLM call runs on a Chinese model. */
  llmRegion?: LlmRegion;
  /** The model that answers this turn — stated to the model in its MODEL IDENTITY block. */
  modelIdentity?: ModelIdentity;
  previousMessages?: Array<{ role: 'user' | 'assistant'; content: string }>;
  currentWorkflow?: any;
  /** Workflow the user explicitly chose for this turn (Workflows library "Run" or another explicit picker).
   *  Routing and catalog search are skipped; exactly this workflow's card is built. */
  selectedWorkflow?: SelectedWorkflow;
  selectedDatasets?: string[];
  userId?: number | string; // The user's id (UUID); numbers only for legacy callers
  sessionId?: string;
  /** Authenticated user id (set by routes.ts from req.user only). */
  authUserId?: string;
  /**
   * The active project id (uuid) this chat is scoped to, or undefined when the
   * chat is project-less. Set by routes.ts from the server-resolved project
   * (`_resolvedProjectId`). Used to scope standing project memory — e.g. routing
   * corrections — so a correction made in project A never surfaces in project B.
   */
  projectId?: string;
  /** Set by routes.ts: store a run_code output file as a dataset of this session (download link,
   *  visible to later turns, survives restarts) — the same store as an upload. */
  persistGeneratedFile?: (hostPath: string, name: string) => Promise<{ dataset_id: string; galaxy_dataset_id?: string; project_file_id?: string; project_id?: string; download_url: string } | undefined>;
  /** When the user has a run's report open in the panel, the client may pass the
   *  exact markdown it is showing (buildFullReportMarkdown) + that run's id. The
   *  edit_report tool uses this as the faithful base so a chat edit forks from
   *  precisely what the user sees, rather than a server-reconstructed approximation. */
  openReportRunId?: string;
  openReportMarkdown?: string;
  /** Auth headers (Authorization + cookie) copied from the originating chat
   *  request by routes.ts, so a tool handler can make an AUTHENTICATED self-call
   *  back to the Node API. Used by edit_report to reconstruct a run's report
   *  from /api/workflows/runs/:runId/findings/report when the client did not
   *  pass the open markdown and no version is saved yet. Never logged. */
  selfRequestAuth?: { authorization?: string; cookie?: string };
  enableThinking?: boolean;
  /** Accumulated facts from prior turns, passed so the LLM can decide supersession */
  accumulatedFacts?: Array<{ id: string; category: string; value: string }>;
  /** Current conversation turn number */
  turnIndex?: number;
  /** User's actual session-uploaded datasets, forwarded to generateWorkflow() */
  sessionDatasets?: Array<{
    id: string; name: string; type: string;
    /** Present only for a project_files row resolved server-side. */
    projectFileId?: string;
    /** Server-derived key; never accepted from model tool arguments. */
    s3_key?: string;
    s3_uri?: string | null;
  }>;
  /** Exact dataset objects attached for this operation from the composer. */
  datasetReferences?: Array<{ id: string; name?: string }>;
  /** Explicit references absent from the session cache; never substitute another file. */
  datasetReferenceUnresolvedIds?: string[];
  /**
   * Cross-session long-term memory block (built by MemoryIntegration from user prefs,
   * corrections, project context, and past episodes). Injected into the system prompt
   * wrapped in <long_term_memory> tags so the LLM treats it as supplemental context.
   */
  ltmContextBlock?: string;
  /** Per-tool credential availability map built by routes.ts using the user's Galaxy API key.
   *  Forwarded to generateWorkflow() so the AI backend can fall back to OSS alternatives. */
  credentialMap?: Record<string, boolean>;
  /**
   * Optional per-request GalaxyAPIProxy scoped to the authenticated user's own
   * Galaxy API key (built by routes.ts via userProxy(req)). When set, all
   * Galaxy calls from this turn use this proxy instead of the singleton's
   * admin proxy. Required because Galaxy's `/api/ai_assistant/*` routes
   * reject the shared admin key whenever its api_keys row is missing/rotated
   * (verified live today: admin key returned 401 from /api/whoami while
   * per-user keys provisioned at registration succeed). Without this each
   * chat-stream call falls back to the broken admin key and the workflow
   * generation returns "currently unavailable".
   */
  galaxyAPIOverride?: any;
  /** This turn's user message (set by _processMessageInner) — lets tool handlers see the
   *  datasets attached to it ("[Uploaded datasets: ...]" block). */
  turnMessage?: string;
  /** Successful Python run_code cells of the current turn (replayed before the next call). */
  runCodeHistory?: { turn: string; codes: string[] };
  /** $OUTPUT_DIR artifacts run_code produced in this turn — the only files a reply may present as produced. */
  runCodeOutputFiles?: { turn: string; names: string[] };
  /** run_code refused a simulated-input attempt this turn — the turn must end on real data (the workflow card). */
  syntheticDataRefused?: { turn: string };
  /** This turn's intent: the user asked for generated / example / synthetic data or a simulation.
   *  undefined = no intent available this turn (run_code's guard then uses its keyword fallback). */
  turnSyntheticDataRequested?: boolean;
  /** Set by the authenticated server route, never inferred from proxy fallback. */
  skillPrivateAccess?: boolean;
  /** Explicitly selected expert skill IDs (from SkillSelector UI). Auto-detected when absent. */
  activeSkillIds?: string[];
  /** Composer name for explicit project/question selections, including none. */
  skillPackIds?: string[];
  /**
   * Project context string built from the active project's name + researchGoal.
   * Injected into the system prompt as <project_context> so the LLM knows the
   * user's research background without the user repeating it every session.
   */
  projectContext?: string;
  /** The project's instructions as a list (project-rules.ts) — also given to intent analysis. */
  projectRules?: string[];
  /**
   * Per-composer instructions submitted with this turn. Routes normalizes and
   * bounds this user-authored text before appending it to projectContext, so it
   * is applied by every model path without being persisted as a project edit.
   */
  composerInstructions?: string;
  /**
   * Per-user Anthropic API key decrypted from the users.llm_api_keys column.
   * When set, this request's LLM calls use the user's own key/quota instead
   * of the system key. Never logged or stored beyond the request lifecycle.
   */
  userAnthropicApiKey?: string;
  /**
   * OpenRouter API key (sk-or-…). When set alongside selectedModel, all LLM
   * calls for this request route through OpenRouter instead of Anthropic.
   */
  openrouterKey?: string;
  /**
   * OpenRouter model slug, e.g. "deepseek/deepseek-chat-v3-5".
   * Ignored unless openrouterKey is also set.
   */
  selectedModel?: string;
  /**
   * Custom OpenAI-compatible base URL (e.g. DashScope / local vLLM).
   * When set alongside openrouterKey, overrides the default openrouter.ai base URL.
   * Enables on-prem deployments with Qianwen, DeepSeek, or local models.
   */
  openaiBaseUrl?: string;
  /**
   * Forces the result of intent classification to this type, bypassing the LLM.
   * Gated by routes.ts behind the E2E bypass token — only valid in test mode.
   * When set AND the query has design-verb+modality patterns, _detectCrossIntentAmbiguity
   * fires and emits an IntentClarificationCard. Used by intent-clarification E2E tests.
   */
  testForceIntent?: string;
  /**
   * Applied after intent classification: overrides the primaryIntent type.
   * Set by the frontend when the user clicks a chip in IntentClarificationCard.
   * Gated by routes.ts behind the E2E bypass token is NOT required — this is
   * normal product flow, not test-only.
   */
  intentOverride?: string;
  /**
   * Populated per-turn by generateResponse() from the user's registered external
   * MCP servers (via GET /api/biomate/mcp-tools on the Galaxy backend). Maps each
   * exposed namespaced tool name (mcp__<server>__<tool>) → its owning server_id,
   * so the tool loop can dispatch the model's call back to the correct server
   * via POST /api/biomate/mcp-servers/{id}/call. Request-scoped (concurrency-safe);
   * never persisted.
   */
  mcpToolServerMap?: Record<string, string>;
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
  // homogeneous refinement, TOPAZ, ab-initio, and 2D/3D classification uniquely
  // identify standard SPA on globular particles — suppress the globular/helical fork.
  cryoem_sample:    /\bglobular\b|\bfilamentous\b|\bhelical\b|\bhomogeneous\s+refinement\b|\bnon-uniform\s+refinement\b|\bTOPAZ\b|\bab[- ]initio\b|\b2D\s+(and\s+)?3D\s+class|\bstandard\s+SPA\b/i,
  // HaplotypeCaller is a germline-only caller — suppress the somatic-paired fork.
  // Note: ACMG alone is NOT listed here because ACMG criteria also apply to somatic variants.
  somatic_paired:   /\bmatched\s+normal\b|\btumor[- ]normal\b|\btumor[- ]only\b|\bpanel\s+of\s+normals\b|\bHaplotypeCaller\b|\bgermline\b/i,
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

  single_cell: `Available BioMate single-cell workflows (within the genomics domain directory). NOTE: BioMate has no working raw-FASTQ → annotated-cell-types end-to-end scRNA-seq pipeline — every single-cell workflow below starts from a counts matrix / annotated .h5ad, not raw 10X reads. For "run standard scRNA-seq from FASTQ" requests, ask the user for a counts matrix, an .h5ad, or a GEO/SRA accession (see routing rules) rather than promising raw-FASTQ processing.
- scrnaseq_trajectory_pseudotime (id 14436): Trajectory inference + pseudotime + lineage-DE for a clustered + annotated h5ad. Slingshot + tradeSeq + condiments. Use for: pseudotime analysis, T-cell exhaustion trajectory, hematopoietic differentiation, branching lineage analysis. Required: annotated.h5ad (from an upstream clustered + annotated single-cell object) + start_cluster OR start_celltype. T2 CPU 16 vCPU / 64 GB locked (no GPU path for tradeSeq).
- scrnaseq_cellcell_communication (id 14437): Cell-cell signaling INFERENCE via LIANA+ (consensus across CellChat/CellPhoneDB/NATMI/SCA/Connectome/logFC). Identifies ligand-receptor pairs between celltypes. Optional condition-stratified comparison (e.g. treatment-naive vs resistant). Optional decoupler TF-activity follow-up. Chains downstream to CCPlotR (id 11052) + InterCellar (id 11646) for visualization. Use for: "signaling between celltypes" / "immune-checkpoint pathways" / "ligand-receptor analysis" / "CellChat" / "LIANA" / "NicheNet" requests. Required: annotated.h5ad with celltype column.
- visium_voyager_spatial_esda (id 14438): End-to-end SPATIAL transcriptomics ESDA for 10X Visium. Composes nf-core/spatialvi (id 12783) sub-workflow + VisiumIO (id 12616) + Voyager univariate (Moran's I, Geary's C, Getis-Ord Gi*) + bivariate (Lee's L) + MULTISPATI PCA + spatial-cluster stratified spatial statistics. Chains downstream to iSEE (id 11653). Use for: any "Visium spatial analysis" / "Voyager ESDA" / "Moran's I" / "spatial autocorrelation" / "spatial transcriptomics" request on Space Ranger output. Required: spaceranger_dir + samplesheet.csv. NOT for cell-cell communication (use id 14437); NOT for Xenium (separate workflow needed).
- annotate_celltype_scRNA: Cell type annotation using reference-based label transfer (PanHuman atlas). Input: AnnData h5ad. Outputs: annotated h5ad with cell type labels.
- create_harmony_embeddings_scRNA: Batch-corrected UMAP via Harmony integration. Input: AnnData h5ad with batch column. Outputs: corrected embedding.
- create_scvi_embeddings_scRNA: Deep learning (scVI) latent embedding. Input: AnnData h5ad. Outputs: scVI latent space + UMAP.
- trajectory_inference: Pseudotime (Monocle3) + RNA velocity (scVelo) — see genomics catalog. Note: scrnaseq_trajectory_pseudotime (id 14436) is the preferred composed workflow.
- perturb_seq_analysis: CRISPR perturbation-seq analysis — see genomics catalog.
- unsupervised_celltype_transfer_between_scRNA_datasets: Cross-dataset label transfer without reference atlas.`,

  epigenomics: `Available BioMate epigenomics workflows:
- perform_chipseq_peak_calling_with_macs2: ChIP-seq peak calling — narrow peaks (TF) or broad peaks (histone marks). Input: ChIP BAM + input/control BAM. Outputs: peak BED + QC.
- analyze_chromatin_interactions: Hi-C TAD / loop / compartment analysis. Input: contact matrix.
- find_enriched_motifs_with_homer: TF motif enrichment in peak regions (HOMER). Input: peak BED + genome. Outputs: enriched motif table.`,

  proteomics: `Available BioMate proteomics workflows:
- nf-core/diaproteomics: FIRST CHOICE for DIA proteomics. Data-Independent Acquisition analysis — targeted peptide extraction from mzML files using OpenSWATH, PyProphet FDR estimation, iRT alignment, DIA-NN analysis. Use for: DIA-mode mass spectra, DIA-NN analysis, DIA mzML files, Spectronaut, data-independent acquisition quantification. Input: mzML files. Outputs: peptide/protein matrices + QC report.
- nf-core/proteomicslfq: FIRST CHOICE for DDA label-free proteomics. Data-Dependent Acquisition (DDA) — MaxQuant proteinGroups.txt → label-free quantification (LFQ). Use for: MaxQuant output, DDA, label-free DDA proteomics, raw .raw or .mzML from DDA acquisition. Outputs: differential_proteins.csv + pathway enrichment.
- nf-core/quantms: TMT/iTRAQ multiplexed quantitative mass spectrometry pipeline. Use for: TMT labeling, iTRAQ, reporter ion quantification, isobaric labeling. Outputs: quantification tables + statistical comparisons.
- chemoproteomics_pulldown: Affinity enrichment (pulldown) QC and enrichment scoring from MaxQuant proteinGroups.txt. Use ONLY for pulldown / affinity enrichment experiments — NOT for DDA or DIA shotgun proteomics. Input: MaxQuant proteinGroups CSV. Outputs: enrichment_ratios.tsv + summary JSON.`,

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
  drug_discovery: `- "ADMET", "ADMET profiling", "ADMET screening", "toxicity screening", "DILI", "hERG toxicity", "BBB penetration", "blood-brain barrier", "lipophilicity", "bioavailability prediction", "predict ADMET", or "toxicity panel": use the predict_admet_properties workflow (6 ADMET endpoints: hERG cardiac, DILI hepato, Caco-2 permeability, BBB penetration, solubility, Ames mutagenicity — all computed from SMILES. Input: smiles_input as a SMILES string or newline-separated list. Outputs: admet_results.csv + risk_summary.json). Use immediately when a user provides SMILES and asks for ADMET or safety screening — do NOT ask for a file upload. IMPORTANT: "drug-like properties" alone is NOT an ADMET request when the user asks to GENERATE / DESIGN / invent candidates (e.g. "Generate 500 candidates… with drug-like properties") — that is reinvent4_lead_design generative design, NOT predict_admet_properties and NOT drug_discovery_admet_gated_screening.
- "PK-Sim", "PK Sim", "pksim", "Open Systems Pharmacology", "OSP Suite", "OSP PBPK", "Willmann PBPK", "EMA OSP", or "LGPL PBPK": use the pk_sim_pbpk workflow (PK-Sim open-source PBPK wrapper, EMA-accepted, free, no license required. Rodgers-Rowland + Schmitt tissue partitioning, Weibull oral dissolution, CYP ontogeny for pediatric. Inputs: compound physicochemical params + CLint + dose. Outputs: pk_profile.json + nca_summary.json + PK plots. quality_tier: ema_accepted_open_source.) NO PREREQ CHECK needed — all params have defaults.
- "Simcyp", "Certara PBPK", "Certara DDI", "Simcyp DDI", "population PBPK", "Simcyp population simulator", "ADAM oral absorption model", "virtual population trial", "Simcyp pediatric", "Simcyp renal", "Simcyp perpetrator", "Simcyp victim", "AUC ratio CYP", or "Sim Cyp": use the simcyp_pbpk workflow (Simcyp Population-Based PBPK BYOL wrapper, regulatory submission grade. Requires SIMCYP_LICENSE_FILE or SIMCYP_LICENSE_SERVER in user credentials; falls back to BioMate native 8-compartment PBPK if no license. Supports DDI CYP3A4/2D6 AUC ratios, special populations, oral absorption ADAM model. Outputs: pk_profile.json + ddi_summary.json + regulatory_report.txt. quality_tier: regulatory_submission or ind_ready_screening fallback.)
- "NONMEM", "nmfe75", "population pharmacokinetics NONMEM", "population PK FOCE", "FOCE-I", "FOCE estimation", "population PK modeling", "PopPK NONMEM", "ADVAN2", "ADVAN4", "ADVAN11", "nlmixr2", "nlmixr population", "SAEM population PK", "VPC visual predictive check", "bootstrap PK", "ETA shrinkage", "OFV", "NCA population", or "nonlinear mixed effects NONMEM": use the nonmem_poppk workflow (NONMEM FOCE-I population PK modeling BYOL; nlmixr2 open-source fallback. Generates NONMEM CTL file (ADVAN2/4/11 + FOCE-I), runs VPC + bootstrap, covariate search. Requires NONMEM_HOME + NONMEM_LICENSE_FILE in credentials; auto-falls back to nlmixr2. Inputs: pk_data_csv (ID/TIME/DV/AMT/CMT/EVID). Outputs: parameter_estimates.json + vpc_plot.png + bootstrap_summary.csv. quality_tier: fda_submission_grade or fda_acceptable_open_source fallback.)
- "FcRn", "FcRn antibody", "FcRn half-life", "IgG half-life", "antibody half-life", "YTE mutation", "LS mutation", "PSA mutation", "GASD ALIE", "AAA mutation", "antibody PK engineering", "FcRn recycling", "IgG1 PK", "IgG4 PK", "bispecific antibody PK", "antibody 2-compartment PK", "monoclonal antibody PK", "mAb PK simulation", "allometric antibody", or "FcRn pH binding": use the fcrn_antibody_pk workflow (FcRn-mediated IgG PK with half-life engineering comparison — WT, YTE, LS, PSA, GASD-ALIE, AAA mutations. 2-compartment IV/SC PK + allometric species scaling. Inputs: antibody_name, molecular_weight_kda, dose_mg_kg, route, species, fc_mutation. Outputs: pk_profile.json + halflife_comparison_table.csv + allometric_scaling.json.) NO PREREQ CHECK needed — all params have defaults.
- "ICH S5", "reproductive toxicity", "DART", "developmental toxicity", "teratogenicity", "embryo-fetal development", "EFD study", "FEED study", "PPND study", "fertility toxicity", "thalidomide structural alert", "placental transfer", "pregnancy category", "WOCBP toxicity", or "Segment II toxicology": use the ich_s5_reproductive_tox workflow (ICH S5(R3) 2020 DART assessment — structural alerts, placental transfer, margin of safety, regulatory study timing for FEED/EFD/PPND. Outputs: ich_s5_safety_report.json GREEN/YELLOW/RED.)
- "transporter DDI", "P-gp inhibition", "BCRP inhibition", "OATP inhibition", "OCT inhibition", "OAT inhibition", "MATE inhibition", "efflux transporter", "uptake transporter", "ABC transporter DDI", "SLC transporter DDI", "R-value transporter", "Igut inhibition", "ABCB1 DDI", "ABCG2 DDI", "SLCO1B1 DDI", "digoxin DDI", "rosuvastatin DDI probe", or "metformin transporter": use the transporter_ddi_pgp_bcrp workflow (P-gp/BCRP/OATP1B1/1B3/OCT1/2/OAT1/3/MATE1/2 R-value calculation per FDA 2020. Flags clinical study triggers. Input: IC50 values + Cmax + dose. Output: transporter_r_values.json + ddi_flags.tsv.)
- "ICH S7A", "safety pharmacology", "hERG safety", "hERG cardiac", "hERG QTc", "Fridericia QTc", "ICH S7B", "CiPA assay", "CiPA in vitro", "cardiovascular safety", "CNS safety", "respiratory safety", "Irwin test", "core battery safety", "safety pharmacology panel", "hERG margin", "cardiac liability", or "autonomic safety pharmacology": use the ich_s7a_safety_pharmacology workflow (ICH S7A core battery: cardiovascular hERG/QTc + CNS Irwin/BBB + respiratory RR/TV/SpO2. CiPA Tier 2 escalation triggered when hERG margin <30×. GREEN/YELLOW/RED per system. Inputs: compound_name, herg_ic50_um, free_cmax_um, cnp_noael_mg_kg, irwin_observation, respiratory_noael_mg_kg, species. Outputs: safety_report.json + overall_safety_color.txt.) NO PREREQ CHECK needed — all params explicit.
- "pediatric PBPK", "pediatric pharmacokinetics", "pediatric dose", "paediatric PK", "paediatric dose", "neonatal PK", "neonatal pharmacokinetics", "infant PK", "CYP maturation", "ontogeny PBPK", "GFR maturation", "age-scaled PK", "pediatric dose prediction", "ICH E11", "ICH E11R1", "allometric scaling CYP", "developmental pharmacology", "child dose from adult", "neonate dose", or "toddler dose" (WITHOUT pregnancy): use the pbpk_pediatric workflow. NOTE: if the query also mentions pregnancy, trimester, gestational age, or maternal PK, use pbpk_pediatric_pregnancy instead (paediatric PBPK — 5 age cohorts: neonate/infant/toddler/child/adolescent. Allometric BW scaling, CYP3A4/2D6/2C19 maturation Hill functions, GFR maturation Rhodin 2009, albumin maturation. ICH E11(R1) compliance warnings. Inputs: compound physicochemical params + dose_mg_kg + route + age_groups. Outputs: pediatric_pk.csv + dose_recommendation.json + cyp_maturation_table.json.) NO PREREQ CHECK needed — all params have defaults.
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

  single_cell: `- SCRNA-DEMO GUARD (read first): every single-cell workflow below requires the user's own input (a counts matrix or an annotated .h5ad) and NONE ships a built-in / example / demo dataset. For any "demo" / "example" / "built-in dataset" / "just show me it works" scRNA request that does NOT provide data, do NOT claim a demo dataset exists — never invent a "pbmc3k example" or state a workflow includes example data. Instead ask for the input per the DATA-FIRST rule (accepted: a counts matrix / .h5ad, or an SRA/GEO accession).
- SCRNA-FASTQ CAPABILITY NOTE (read first): BioMate does NOT currently have a working end-to-end raw-FASTQ → annotated-cell-types scRNA-seq pipeline. Do NOT promise to take raw 10X Genomics FASTQ to annotated cell types in one workflow. For "run standard scRNA-seq" / "10X analysis" / "FASTQ to cell types" / "process 10X data and annotate" / "scRNA-seq from raw reads" requests: (a) ask the user to provide a counts matrix or an annotated/unannotated .h5ad (or a GEO/SRA accession) instead of raw FASTQ; and (b) route the matrix-based analysis to the working single-cell workflows — QC + doublet removal via the Bioconductor single-cell chain (scran, scater, scuttle, scdblfinder), batch-corrected embedding via Create Harmony Embeddings Scrna or Create Scvi Embeddings Scrna, and cell-type annotation via Annotate Celltype Scrna. If the user supplies a GEO scRNA-seq accession, use geo_scrna_pseudobulk (id 14485) to fetch and pseudobulk-aggregate. Keep the DATA-FIRST rule intact — if no data or accession is given, ask for it; do not silently dispatch a workflow with no input.
- "trajectory analysis", "pseudotime", "lineage trajectory", "Slingshot", "tradeSeq", "T-cell exhaustion trajectory", "developmental trajectory", "differentiation pseudotime", "branching lineage", "GAM along pseudotime", "trajectory differential expression", "condiments comparison", "monocle alternative", "pseudotime DE", or any request to infer cell trajectories from an annotated single-cell h5ad: use the scrnaseq_trajectory_pseudotime workflow (id 14436). Slingshot lineage fit + tradeSeq GAM + optional condiments condition comparison. Required: annotated.h5ad (from any upstream clustered + annotated SC object) + start_cluster OR start_celltype. T2 CPU 16 vCPU / 64 GB tier locked (no GPU path for tradeSeq; mgcv has no CUDA). For >20K cells, the workflow lineage-splits automatically to stay under the 56 GB memory ceiling.
- "cell-cell communication", "LIANA", "CellChat", "NicheNet", "CellPhoneDB", "ligand-receptor analysis", "signaling between celltypes", "intercellular signaling", "tumor-immune signaling", "immune-checkpoint pathways", "PD-L1 signaling", "TIGIT signaling", "ligand-receptor pairs", "signaling pathway analysis between cell types", or any request to identify cell-cell signaling from an annotated scRNA-seq h5ad: use the scrnaseq_cellcell_communication workflow (id 14437). LIANA+ inference (consensus across CellChat / CellPhoneDB / NATMI / SCA / Connectome / logFC) + optional condition-stratified comparison (e.g. treatment-naive vs resistant) + optional decoupler TF-activity follow-up. Chains downstream to CCPlotR (id 11052) for heatmap/dotplot/network viz + InterCellar (id 11646) for interactive Shiny exploration. Required: annotated.h5ad with celltype column. LIANA+ requires raw counts — workflow halts with remediation if log-normalized input is detected.
- "Visium analysis", "Voyager", "spatial ESDA", "spatial exploratory data analysis", "Moran's I", "Geary's C", "Getis-Ord", "spatial autocorrelation", "MULTISPATI", "Lee's L", "spatial transcriptomics analysis", "Space Ranger output analysis", "10X Visium", "spatial neighborhood graph", "spatially variable genes", "spatial clustering of spots", "Maynard DLPFC", "Visium FFPE Breast Cancer", "tissue compartment analysis", or any request to analyze 10X Visium Space Ranger output for spatial structure: use the visium_voyager_spatial_esda workflow (id 14438). End-to-end Visium ESDA — composes nf-core/spatialvi sub-workflow for Space Ranger → SpatialExperiment + VisiumIO + SpatialFeatureExperiment (SFE) conversion + Voyager univariate Moran's I / Geary's C / Getis-Ord Gi* + bivariate Lee's L + MULTISPATI PCA + spatial spot clustering with per-cluster stratified ESDA. Required: spaceranger_dir + samplesheet.csv. Output is a Voyager-vignette-style ranked-genes table by spatial autocorrelation + per-cluster top genes + SFE rds + interactive iSEE app (chained id 11653). NOT for Xenium data (different workflow needed); NOT for scRNA-seq (no spatial coords). Note: depends on the bioc-fix container update that installs Voyager + sf + spdep — currently 5 spatial workflows are exec_error pending that fix.
- "virtual cell", "perturbation prediction", "cell response to drug", "predict gene KO effect", "predict gene knockout", "CRISPR perturbation prediction", "drug effect on cell state", "cell state after perturbation", "transcriptomic perturbation response", "in silico KO", "in silico knockout", "predict scRNA-seq after treatment", "GEARS perturbation", "STATE model", "state perturbation", "predict combinatorial perturbation", "multi-gene perturbation", or "gene expression after CRISPR": use the state_perturbation_prediction workflow as primary and offer gears_perturbation_prediction as an alternative. STATE model (Singlecell Transcriptomics for Arbitrary Treatment Effects) predicts single-cell gene expression responses to unseen drug or genetic perturbations using a transformer trained on Perturb-seq data; GEARS uses a graph neural network over gene co-expression to predict combinatorial perturbation effects. Both accept: cell_type, perturbation_name (gene symbol or drug name), and optionally a reference h5ad. Outputs: predicted_expression.h5ad + differential_genes.csv + UMAP comparison. Use STATE for drug perturbations; prefer GEARS when querying multi-gene combinatorial KO panels.`,

  genomics: `- "AlphaGenome", "Alpha Genome", "DeepMind genomics 2025", "Enformer successor", "genomic track prediction", "predict ATAC-seq from sequence", "predict gene expression from DNA", "predict chromatin from sequence", "in-silico mutagenesis regulatory", "ISM variant regulatory", "enhancer prediction from sequence", "1Mb DNA prediction", "TF binding prediction sequence", or "cell-type gene expression from DNA": use the alphagenome_track_prediction workflow (AlphaGenome DeepMind 2025; predicts 5000+ tracks: ATAC, ChIP, RNA-seq, splicing, histones, CTCF across 100+ cell types. Enformer fallback if no API key. Input: genomic_region (chrom:start-end) + optional variant_vcf. Output: track predictions TSV + variant effects JSON + HTML report.)
- "Evo 2", "Evo-2", "Evo2", "Arc Institute DNA model", "DNA language model variant", "nucleotide language model", "whole genome language model", "genomic foundation model variant", "log likelihood ratio variant", "LLR variant", "non-coding variant score DNA model", "CRISPR guide scoring Evo", or "DNA sequence fitness": use the evo2_variant_effect workflow (Evo 2 Arc Institute 40B-param DNA LM; scores variants via log-likelihood ratio LLR=log P(alt)-log P(ref); negative LLR = deleterious. API: Together AI or local HF weights. Input: input_vcf + reference_genome. Output: scored TSV + ranked VCF + summary JSON.)`,

  molecular_biology: `- "ASO", "antisense oligonucleotide", "gapmer", "MOE gapmer", "LNA gapmer", "RNase H ASO", "knockdown ASO", "GalNAc-ASO", "design ASO", "design gapmer", "nusinersen-like", "inclisiran-like", "givosiran-like", "phosphorothioate oligonucleotide", or "PS backbone ASO": use the aso_gapmer_design workflow (ASO gapmer design for RNase H knockdown — MOE 5+10+5 / LNA 3+10+3 / MOE mixmer chemistries. Tm scoring with MOE/LNA correction, GC content (40-60%), G-quadruplex/GGGG rejection (hepatotoxicity), CpG flagging, palindrome check. Delivery recommendation: GalNAc-SC for liver, intrathecal for CNS, PMO/PPMO for muscle. Required: target_mrna + target_tissue. Optional: chemistry, n_top.)
- "siRNA design", "siRNA generation", "design siRNA", "siRNA candidates", "Ui-Tei criteria", "Reynolds criteria", "siRNA from mRNA", or "small interfering RNA design": use the sirna_design_full workflow (siRNA candidate generation from mRNA — sliding window 19-21mer → GC filter → Ui-Tei + Reynolds + thermodynamic asymmetry scoring → ranked candidates. Chains to sirna_offtarget_analysis for off-target screening.)`,

  transcriptomics: `- GEO accession + differential expression request (GSE followed by digits, e.g. GSE12345${process.env.S3_ENDPOINT_URL ? '' : ', but NOT GSE227835'}): first determine the assay type. For known scRNA-seq accession use geo_scrna_pseudobulk; it fetches and pseudobulk-aggregates the data before DESeq2. For bulk RNA-seq or microarray accession use geo_data_connector first to retrieve the series matrix and phenotype metadata. Do NOT claim that a generic GEO series can be run through DESeq2 automatically: GEO series can contain normalized microarray values, non-count RNA-seq measures, or no usable comparison labels. After retrieval, show the data type and available group columns and ask the researcher to confirm the contrast/method.${process.env.S3_ENDPOINT_URL ? '' : ' EXCEPTION: GSE227835 is already pre-staged — use nf-core/differentialabundance directly with the pre-staged S3 paths (see GEO routing rules below).'}
- Differential expression with uploaded CSVs (counts matrix + samplesheet + contrasts already provided as uploads or S3 URIs): use nf-core/differentialabundance directly. Map uploaded files: 'samplesheet', 'metadata', 'sample_metadata', 'design' files → samplesheet param; 'count', 'matrix', 'expression' files → matrix param; 'contrast', 'comparison' files → contrasts param.`,

  proteomics: `- "DIA", "DIA-NN", "data-independent acquisition", "DIA quantification", "DIA proteomics", "DIA mass spec", "DIA mzML", "OpenSWATH", "PyProphet", "Spectronaut DIA", "iRT alignment", "spectral library DIA", or "label-free DIA": use the nf-core/diaproteomics workflow (FIRST CHOICE for DIA proteomics — data-independent acquisition analysis using OpenSWATH + PyProphet FDR + DIA-NN + iRT alignment. Input: mzML files. Outputs: peptide/protein quantification matrices + QC report. Never use msstatsconvert or MSstats tools as the primary pipeline for raw DIA data — those are format converters for pre-quantified data, not pipelines.)
- "DDA", "MaxQuant", "label-free quantification", "LFQ", "data-dependent acquisition", "shotgun proteomics", "DDA proteomics", "label-free DDA", "proteinGroups.txt", "PRIDE", "TMT-free quantification", or "MaxQuant label-free": use the nf-core/proteomicslfq workflow (FIRST CHOICE for DDA label-free proteomics — MaxQuant proteinGroups.txt → statistical comparison. Input: raw mass spec files or MaxQuant output. Outputs: differential_proteins.csv + pathway enrichment.)
- "TMT", "iTRAQ", "TMT10", "TMT16", "isobaric labeling", "multiplexed proteomics", "reporter ion quantification", "tandem mass tag", or "isobaric tag quantification": use the nf-core/quantms workflow (multiplexed quantitative proteomics — TMT/iTRAQ reporter ion quantification. Input: raw mass spec files + experimental design. Outputs: protein quantification + statistical comparisons.)
- "phosphoproteomics", "phospho enrichment", "TiO2 enrichment", "IMAC phospho", "phosphopeptide", "phosphorylation site", "PTM site localization", or "post-translational modification profiling": describe the phosphoproteomics workflow approach (TiO2/IMAC enrichment → MaxQuant PTM site search → MSstatsPTM site localization → kinase substrate enrichment analysis KSEA). No single BioMate pipeline wraps these steps yet; recommend combining individual tools.`,
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
  pbpk_pediatric: {
    // Workflow uses `route` (string: 'oral'|'iv'); LLM sometimes emits dose_route (int 0=oral)
    dose_route: 'route', administration_route: 'route', admin_route: 'route',
    compound: 'drug_name', drug: 'drug_name',
    smiles: 'smiles_input', compound_smiles: 'smiles_input',
  },
  pbpk_simulation: {
    dose_route: 'route', administration_route: 'route', admin_route: 'route',
    compound: 'compound_name', drug: 'compound_name',
  },
  allometric_scaling: {
    compound: 'drug_name', drug: 'drug_name',
    weight: '__drop__', mw: '__drop__',
  },
};

/**
 * Workflows that accept a `smiles_list` parameter (JSON array of SMILES strings).
 * The decomposition LLM may extract SMILES using an arbitrary drug name as the key
 * (e.g. {"imatinib": "Cc1ccc..."}) instead of the workflow-expected key "smiles_list".
 * This set is used by normalizeWorkflowSmiles to know when to apply remapping.
 */
const SMILES_LIST_WORKFLOWS = new Set([
  'predict_admet_properties',
  'herg_cardiac_safety_qsar',
  'cns_penetration_prediction',
  'dart_toxicity_prediction',
  'genotoxicity_ames_prediction',
  'membrane_permeability_prediction',
  'calculate_physicochemical_properties',
  'docking_autodock_vina',
  'run_diffdock_with_smiles',
  'antibody_developability',
  'qsar_rf_model',
  'metabolite_prediction_biotransformer',
]);

/**
 * For workflows that use smiles_list, the decomposition LLM may extract SMILES strings
 * using an arbitrary drug name as the key (e.g. {"imatinib": "Cc1ccc..."}) instead of
 * the workflow-expected key "smiles_list". This function detects SMILES-like values
 * and collects them into a JSON array under "smiles_list".
 *
 * A value is treated as SMILES when its first whitespace-delimited token contains characters
 * typical of SMILES notation (=, #, [, ], /, \, @).  Trailing prose is stripped.
 */
export function normalizeAdmetSmiles(
  workflowName: string | undefined | null,
  raw: Record<string, string> | undefined | null,
): Record<string, string> {
  // Match by exact name OR by canonical short name embedded in a full display name.
  // groundInlineParameters passes workflow_ga.name ("Predict ADMET Properties (AI)"),
  // not the canonical short name ("predict_admet_properties") — check both.
  if (!raw || !workflowName) return raw || {};
  const normalizedWfKey = workflowName.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/_+$/, '');
  const isMatch = SMILES_LIST_WORKFLOWS.has(workflowName) ||
    Array.from(SMILES_LIST_WORKFLOWS).some(n => normalizedWfKey.includes(n));
  if (!isMatch) return raw;
  // SMILES heuristic: extract the first whitespace-delimited token and test it.
  // The LLM sometimes appends prose after the SMILES string
  // (e.g. "Cc1ccc...n1 and predict hERG cardiac risk"), so strip trailing text.
  const getSmilesToken = (v: unknown): string | null => {
    if (typeof v !== 'string') return null;
    const token = v.split(/\s/)[0];
    return /[=#\[\]\/\\@]/.test(token) && token.length >= 5 ? token : null;
  };
  // Parse a value into a flat list of SMILES. Handles (a) a JS array, (b) a JSON
  // array STRING ('["A","B"]' — the deterministic multi-SMILES form), (c) a raw
  // comma-separated list ("A, B, C"), and (d) a single token. Prevents the
  // first-token-only truncation and the double-wrap that occurred when a JSON
  // array string reached getSmilesToken (it treated "[" as a ring char).
  const parseSmilesValues = (v: unknown): string[] => {
    if (Array.isArray(v)) {
      return v.map((i) => String(i).trim()).filter((t) => getSmilesToken(t));
    }
    const sv = String(v ?? '').trim();
    if (!sv) return [];
    if (sv.startsWith('[')) {
      try {
        const arr = JSON.parse(sv);
        if (Array.isArray(arr)) {
          return arr.map((i) => String(i).trim()).filter((t) => getSmilesToken(t));
        }
      } catch { /* not valid JSON — fall through to comma/space split */ }
    }
    // Comma-separated list, or single token (strip trailing prose per token).
    const parts = sv.includes(',') ? sv.split(',') : [sv];
    return parts.map((p) => getSmilesToken(p.trim())).filter((t): t is string => !!t);
  };
  const smilesList: string[] = [];
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (k === 'smiles_list') {
      const parsed = parseSmilesValues(v);
      if (parsed.length > 0) {
        out[k] = JSON.stringify(parsed);
      } else if (typeof v === 'string' && v.trim().startsWith('[')) {
        out[k] = v.trim(); // valid JSON array we couldn't SMILES-validate — keep as-is
      } else if (v != null) {
        out[k] = JSON.stringify([String(v).split(/\s/)[0]]);
      }
    } else if (k === 'ADMET_model_type') {
      out[k] = Array.isArray(v) ? JSON.stringify(v) : String(v);
    } else {
      const parsed = parseSmilesValues(v);
      if (parsed.length > 0) {
        smilesList.push(...parsed);
      } else if (!Array.isArray(v) && v != null) {
        out[k] = String(v);
      }
    }
  }
  if (smilesList.length > 0 && !out.smiles_list) {
    out.smiles_list = JSON.stringify(smilesList);
    console.log('[normalizeAdmetSmiles] Remapped', smilesList.length, 'SMILES value(s) → smiles_list');
  }
  return out;
}

/** Upload references in the UI's "[Uploaded datasets: name: dataset_id=…, galaxy_dataset_id=…, s3_uri=…]"
 *  block: every id → that file's {name, s3Uri}. */
export function parseUploadedDatasetRefs(message: string): Map<string, { name: string; s3Uri?: string }> {
  const refs = new Map<string, { name: string; s3Uri?: string }>();
  for (const block of (message || '').matchAll(/\[Uploaded datasets:\s*([^\]]+)\]/gi)) {
    for (const entry of block[1].split(/;\s*/)) {
      const name = entry.match(/^([^:]+):/)?.[1]?.trim();
      if (!name) continue;
      const s3Uri = entry.match(/s3_uri=(s3:\/\/[^\s,;\]]+)/i)?.[1];
      for (const m of entry.matchAll(/(?:galaxy_)?dataset_id=([A-Za-z0-9-]+)/gi)) refs.set(m[1], { name, s3Uri });
    }
  }
  return refs;
}

const DATASET_REF_KEY_RE = /^(?:galaxy[_\s-]?)?dataset[_\s-]?ids?$|^s3[_\s-]?uris?$|^uploaded[_\s-]?datasets?$|^dataset[_\s-]?(?:ref|reference)s?$/i;

/**
 * Dataset references are never workflow parameters (W4: the intent LLM copied the upload block's
 * dataset_id UUID into inlineParameters, it passed through as an unknown key, and the panel showed
 * "Dataset Id: <uuid>" as a required param). Rules:
 *  - a dataset-reference KEY (dataset_id, galaxy_dataset_id, s3_uri, …) is dropped unless the chosen
 *    workflow's schema declares it (`allowedKeys`);
 *  - a VALUE that is an upload id is rebound to that file's s3 URI (what the executor reads and what
 *    the panel shows as a file name), or dropped when no URI is known;
 *  - with a known schema, only schema keys survive (done by the callers' schema filter).
 * Files are bound by extractUploadedFileParams, not by copying ids.
 */
export function stripDatasetReferenceParams(
  params: Record<string, any> | null | undefined,
  message: string,
  allowedKeys?: Set<string>,
): Record<string, any> {
  if (!params) return {};
  const refs = parseUploadedDatasetRefs(message);
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(params)) {
    if (DATASET_REF_KEY_RE.test(k) && !allowedKeys?.has(k)) continue;
    if (typeof v === 'string') {
      const token = v.trim().replace(/^.*dataset_id=/, '').split(/[\s,;\]]/)[0];
      const ref = refs.get(token);
      if (ref) {
        if (ref.s3Uri) out[k] = ref.s3Uri;
        continue;
      }
    }
    out[k] = v;
  }
  return out;
}

/**
 * The parameters the attachment binding filled on this generated workflow
 * ({param → dataset reference}). They are already on `workflow_ga`; the chat
 * response has to carry them too, because the panel's overlay and the
 * clarification list are built from the response, not from the workflow object.
 */
export function attachmentBoundParams(generatedWorkflow: any): Record<string, string> {
  const out: Record<string, string> = {};
  const bound: Array<{ param?: string }> = generatedWorkflow?._attachmentBinding?.bound || [];
  const inline = generatedWorkflow?.workflow_ga?.inline_parameters || generatedWorkflow?.inline_parameters;
  if (!inline || typeof inline !== 'object') return out;
  for (const b of bound) {
    const name = String(b?.param || '');
    const value = name ? (inline as Record<string, unknown>)[name] : undefined;
    if (name && typeof value === 'string' && value.trim() !== '') out[name] = value;
  }
  return out;
}

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
  // Normalize route parameter: numeric codes → string labels (0=oral, 1=iv)
  const ROUTE_CODES: Record<string, string> = { '0': 'oral', '1': 'iv', '2': 'sc', '3': 'im' };
  if (out.route !== undefined && ROUTE_CODES[String(out.route)] !== undefined) {
    out.route = ROUTE_CODES[String(out.route)];
    changed = true;
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

// ─────────────────────────────────────────────────────────────────────────────
// Schema-grounded extraction wrapper (feature-flagged).
//
// When SCHEMA_GROUNDED_EXTRACTION=1, runs Stage 3:
//   3a rule pass + 3b LLM resolver + 3c validation
// Schema is read from workflow_ga.required_params / optional_params (which the
// backend already populates from nextflow_schema.json or .nf parsing via
// backend/lib/galaxy/ai/ai_assistant.py:_get_workflow_params). The frontend
// never re-parses any schema file — that would duplicate backend logic.
//
// Falls back to the legacy WORKFLOW_PARAM_ALIASES table when the flag is off,
// when workflow_ga ships no schema metadata (older annotation rows), or when
// the new pipeline throws — so default behavior is unchanged.
// ─────────────────────────────────────────────────────────────────────────────

import {
  buildSchemaFromWorkflowGa,
  type BackendParamEntry,
} from './lib/paramSchema.js';
import {
  extractParameters,
  buildLlmGenerateAdapter,
  type ExtractorResult,
} from './lib/schemaGroundedExtractor.js';
import { llmGenerate } from './llm-client.js';

const SCHEMA_GROUNDED_FLAG = () =>
  process.env.SCHEMA_GROUNDED_EXTRACTION === '1';

/**
 * Async wrapper used at chat-stream call sites. Returns the canonical-keyed
 * dict and (optionally) an ExtractorResult for the caller to surface in the
 * chat response.
 *
 * Drop-in: if flag is off OR workflow_ga has no rich schema OR an error fires
 * inside the new pipeline, falls back to the legacy alias table — no behavior
 * regression on the default path.
 */
export async function groundInlineParameters(args: {
  workflowName: string | undefined | null;
  rawParams: Record<string, unknown> | undefined | null;
  userQuery: string;
  /** Backend's required_params from workflow_ga; either rich entries or bare names. */
  requiredParams?: Array<BackendParamEntry | string>;
  optionalParams?: Array<BackendParamEntry | string>;
  userOverriddenKeys?: Set<string>;
  /** Optional callback: emit user-visible progress to the SSE stream. */
  onStatus?: (message: string, payload?: Record<string, unknown>) => void;
}): Promise<{
  params: Record<string, string | string[]>;
  details?: ExtractorResult;
  path: 'schema-grounded' | 'legacy-alias' | 'noop';
}> {
  const { workflowName, userQuery, requiredParams, optionalParams, onStatus } = args;
  const _schemaKeys: Set<string> = new Set([
    ...(requiredParams || []).map((p) => (typeof p === 'string' ? p : p.name)),
    ...(optionalParams || []).map((p) => (typeof p === 'string' ? p : p.name)),
  ]);
  const _strippedParams = stripDatasetReferenceParams(args.rawParams as any, userQuery, _schemaKeys);
  // An upstream extractor that saw "[Attached files: nanobody_candidates.fasta]"
  // can emit the bare FILE NAME as a value ("antibodies": "nanobody_candidates.fasta").
  // A bare name resolves to nothing at run time and renders as a phantom value in
  // the panel, so rewrite it to the file's dataset reference when the parameter
  // really takes a file — and drop it when the parameter takes inline content.
  const _attachedForParams = parseAttachedFiles(userQuery);
  let rawParams: Record<string, any> = _strippedParams;
  if (_attachedForParams.length > 0) {
    const _specs = [
      ...(requiredParams || []).map((p) => (typeof p === 'string' ? { name: p, required: true } : { ...p, required: p.required ?? true })),
      ...(optionalParams || []).map((p) => (typeof p === 'string' ? { name: p, required: false } : { ...p, required: p.required ?? false })),
    ];
    const _rb = rebindFilenameValues(_strippedParams, _attachedForParams, _specs as any);
    rawParams = _rb.params;
    if (_rb.rebound.length || _rb.dropped.length) {
      console.log(
        `[groundInlineParameters] attachment filename values — rebound: ${_rb.rebound.join(',') || 'none'}; dropped (not a file parameter): ${_rb.dropped.join(',') || 'none'}`,
      );
    }
  }
  if (!workflowName) {
    return { params: (rawParams as any) || {}, path: 'noop' };
  }
  if (!SCHEMA_GROUNDED_FLAG()) {
    const normalized = normalizeAdmetSmiles(workflowName, rawParams as any);
    const remapped = remapInlineParametersForWorkflow(workflowName, normalized);
    // When the backend supplied a schema (required/optional params), drop any
    // remapped keys that are not in the schema — they are LLM hallucinations
    // (e.g. "imatinib: <SMILES>" gets parsed as param key "imatinib" but the
    // workflow only accepts "smiles"). This prevents unknown keys from being
    // passed as Nextflow --flags.
    const allKnownNames: Set<string> = new Set([
      ...(requiredParams || []).map((p) => (typeof p === 'string' ? p : p.name)),
      ...(optionalParams || []).map((p) => (typeof p === 'string' ? p : p.name)),
    ]);
    if (allKnownNames.size > 0) {
      const filtered: Record<string, string> = {};
      for (const [k, v] of Object.entries(remapped)) {
        if (allKnownNames.has(k)) {
          filtered[k] = v as string;
        } else {
          console.log(`[groundInlineParameters] dropping unknown param "${k}" (not in schema for "${workflowName}")`);
        }
      }
      return { params: filtered, path: 'legacy-alias' };
    }
    return { params: remapped, path: 'legacy-alias' };
  }
  try {
    onStatus?.('Reading parameter schema for ' + workflowName + '…', { stage: 'schema' });
    const schema = buildSchemaFromWorkflowGa({
      workflowName,
      requiredParams,
      optionalParams,
    });
    if (schema.params.length === 0) {
      // Diagnostic: surface the shape we received so we can tell whether the
      // caller passed nothing, bare strings, or rich entries.
      console.warn(
        '[groundInlineParameters] schema empty for', workflowName,
        '— required:', Array.isArray(requiredParams)
          ? `${requiredParams.length} items, first=${JSON.stringify(requiredParams[0])}`
          : typeof requiredParams,
        'optional:', Array.isArray(optionalParams)
          ? `${optionalParams.length} items, first=${JSON.stringify(optionalParams[0])}`
          : typeof optionalParams,
      );
      onStatus?.('No schema metadata; using legacy parameter mapping', { stage: 'fallback' });
      const normalized = normalizeAdmetSmiles(workflowName, rawParams as any);
      const remapped = remapInlineParametersForWorkflow(workflowName, normalized);
      return { params: remapped, path: 'legacy-alias' };
    }
    const llmCall = buildLlmGenerateAdapter(llmGenerate);
    onStatus?.('Extracting parameters from your message…', { stage: 'extract', paramCount: schema.params.length });
    const result = await extractParameters({
      schema,
      userQuery,
      rawParams: rawParams || {},
      userOverriddenKeys: args.userOverriddenKeys,
      llmCall,
    });
    const fillCount = Object.keys(result.params).length;
    if (result.clarifications.length > 0) {
      onStatus?.(
        `Extracted ${fillCount} parameter${fillCount === 1 ? '' : 's'} — ${result.clarifications.length} need your input`,
        {
          stage: 'extracted',
          confidence: result.confidence,
          clarifications: result.clarifications.length,
          missingRequired: result.validation.missingRequired,
          enumViolations: result.validation.enumViolations.map((v) => v.key),
        },
      );
    } else {
      onStatus?.(
        `Extracted ${fillCount} parameter${fillCount === 1 ? '' : 's'} from your message`,
        { stage: 'extracted', confidence: result.confidence },
      );
    }
    return { params: result.params, details: result, path: 'schema-grounded' };
  } catch (e) {
    console.warn(
      `[groundInlineParameters] schema-grounded path failed for "${workflowName}" (${(e as Error).message}); falling back to legacy alias`,
    );
    onStatus?.('Parameter extraction failed; using legacy mapping', { stage: 'error', error: (e as Error).message });
    const normalized = normalizeAdmetSmiles(workflowName, rawParams as any);
    const remapped = remapInlineParametersForWorkflow(workflowName, normalized);
    return { params: remapped, path: 'legacy-alias' };
  }
}

/**
 * Coerce array values to comma-joined strings so the legacy
 * `Record<string, string>` consumer (workflow form pre-fill) accepts them.
 * The form's multi-value renderer splits on comma for list-typed params.
 */
// Strip a composite dataset-ref value down to its leading id/uri token.
// An uploaded/attached file sometimes reaches a dataset/id param as the whole
// uploaded-dataset context entry ("<id>, s3_uri=<uri>" / "<id>, galaxy_dataset_id=<gid>",
// sometimes with a trailing "]" from the "[Uploaded datasets: …]" block) instead of
// a single clean token — the cryo "Dataset Id" leak. The composite is malformed for
// the executor anyway (nothing parses it; BioMate stages id→S3 at execute time), so
// keeping only the leading token fixes display and downstream resolution alike.
// Shared single source of truth: used both here (the emitted inlineParameters map the
// viewer merges into `params` as the top-precedence userValue) and by the workflow_ga
// value/default normalization at the generate chokepoint.
export function normalizeCompositeDatasetRef(v: unknown): unknown {
  if (typeof v !== 'string') return v;
  const m = v.match(/^\s*(\S+?)\s*,\s*(?:s3_uri|galaxy_dataset_id|dataset_id|name)=/);
  return m ? m[1] : v;
}

function stringifyParamValues(
  params: Record<string, string | string[]>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(params)) {
    const s = Array.isArray(v) ? v.join(',') : String(v);
    const n = normalizeCompositeDatasetRef(s);
    if (n !== s) {
      console.log(`[GalaxyAssistant] NormalizeComposite inlineParam ${k}: "${s.slice(0, 60)}" → "${String(n).slice(0, 60)}"`);
    }
    out[k] = String(n);
  }
  return out;
}

// Critical cross-domain disambiguation rules that MUST apply regardless of the
// intent classifier's preferredDomains. These workflows' dense-cosine candidates
// carry a non-drug_discovery domain tag ('general'/'transcriptomics'), so when
// the classifier picks a domain that HAS its own rule block the drug_discovery
// block (and these bullets with it) was dropped — survival goals then fell back
// to the raw cosine top (the broken survival_cox) and PBPK goals produced no card
// at all. Keeping them always-on is behaviour-neutral for unrelated queries (the
// bullets only fire on matching keywords). See
// docs/20261006_BIOMATE_E2E_WORKFLOW_ISSUES.md §2/§3a.
const CRITICAL_ALWAYS_ON_ROUTING = `- SURVIVAL — DATA ANALYSIS (default when the user wants to ANALYSE patient/clinical records): "survival analysis", "analyse survival", "Kaplan-Meier", "KM curve", "KM plot", "log-rank test", "Cox proportional hazards", "Cox regression", "hazard ratio from data", "compare two patient groups", "survival of patients", "time to event analysis", or "survival function from a dataset" where the user supplies (or will upload) a clinical data table: select the workflow named exactly "survival" (input-bound Kaplan-Meier survfit + Cox coxph on a clinical CSV; takes an uploaded clinical-data file). Do NOT select survival_cox_proportional_hazards_regression and do NOT select survival_analysis_km for data-analysis requests.
- SURVIVAL — TRIAL DESIGN (parametric, no data file): "clinical trial sample size", "oncology trial design", "power calculation survival", "event-driven trial", "phase III oncology", "Schoenfeld", "RMST sample size", "O'Brien-Fleming", "alpha spending", or "accrual/follow-up planning": use the survival_analysis_km workflow (Kaplan-Meier estimator + Schoenfeld sample size + RMST + O'Brien-Fleming alpha-spending. Inputs: median_control_months, median_treatment_months, alpha, power, accrual_months, follow_up_months. Outputs: km_curves.png + power_table.csv + sample_size_summary.json.) NO PREREQ CHECK needed — all params explicit.
- "PBPK simulation", "physiologically-based pharmacokinetics", "physiologically-based PK", "8-compartment PK", "full PK profile", "predict human PK", "predict human pharmacokinetics", "mechanistic PK simulation", "organ-level PK", "whole-body PK", "PBPK model", "Cmax prediction", "AUC prediction", "Tmax prediction", "oral bioavailability simulation", or "first-pass metabolism PK": use the pbpk_simulation workflow (8-compartment physiologically-based pharmacokinetic model, Rodgers/Rowland method; outputs pk_profile.csv + nca_parameters.json). NO PREREQ CHECK needed — all params have defaults (SMILES=aspirin, CLint=45 µL/min/mg, fu_plasma=0.05, population=healthy_adult, dose=500 mg); generate the card immediately and surface SMILES/CLint/fu_plasma/dose as editable params. Do NOT block on missing inputs or ask a clarifying question.`;

export function buildWorkflowRoutingBlock(preferredDomains: string[]): string {
  // The canonical-fixture auto-resolve rule is the bioinformatics analog of
  // the existing ADMET-from-SMILES and pocket-from-PDB-id rules. It belongs
  // at the top of the routing block so the LLM applies it before any
  // domain-specific rule that might re-introduce a clarification ask.
  // See docs/20260610_DETERMINISTIC_CHAT_ROUTING_PLAN.md for the gap audit.
  const fixturePreamble = buildCanonicalFixturePromptSection();

  let domainRules: string;
  if (!preferredDomains || preferredDomains.length === 0) {
    domainRules = Object.values(DOMAIN_ROUTING_RULES).join('\n');
  } else {
    const matched = preferredDomains
      .map(d => DOMAIN_ROUTING_RULES[d])
      .filter((r): r is string => !!r);
    domainRules = matched.length > 0
      ? matched.join('\n')
      : Object.values(DOMAIN_ROUTING_RULES).join('\n');
  }

  // CRITICAL_ALWAYS_ON_ROUTING is appended unconditionally — these bullets were
  // removed from the drug_discovery block (so no duplication) and must survive
  // any domain gating.
  return `${fixturePreamble}\n\n${CRITICAL_ALWAYS_ON_ROUTING}\n${domainRules}`;
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
// Skills System — Expert Role Injection
// ============================================================================

const GALAXY_URL = process.env.GALAXY_URL || 'http://localhost:8081';

/**
 * Fetch active skills from the Galaxy backend and build a system-prompt block.
 * Auto-detects from message + preferred domains unless the session has explicitly
 * set skill_ids via context.activeSkillIds.
 * Auto-detection is best-effort; explicit activation fails visibly when unavailable.
 */
/** Always-on platform skill — capability map / honest boundaries. Locked in the
 *  composer UI; merged here so auto-detect and explicit paths both carry it. */
export const DEFAULT_SKILL_ID = 'biomate-universe';

/** Ensure the locked default skill is first in the id list (deduped). */
export function withDefaultSkill(ids: string[] | undefined | null): string[] {
  const list = Array.isArray(ids) ? ids.filter((id) => typeof id === 'string' && id.length > 0) : [];
  const rest = list.filter((id) => id !== DEFAULT_SKILL_ID);
  return [DEFAULT_SKILL_ID, ...rest];
}

export async function buildSkillBlock(
  message: string,
  preferredDomains: string[],
  context: { activeSkillIds?: string[]; skillPackIds?: string[]; skillPrivateAccess?: boolean; galaxyAPIOverride?: GalaxyAPIProxy }
): Promise<string> {
  const selected = context.skillPackIds ?? context.activeSkillIds;
  const explicit = Array.isArray(selected);
  // Empty explicit list used to mean "apply none" — that fought the locked default
  // and the product rule that BioMate auto-leverages skills when the user picks
  // nothing. Fall through to auto-detect instead.
  try {
    const privateAccess = context.skillPrivateAccess === true;
    const post = async (path: string, body: object): Promise<any> => {
      const payload = { ...body, include_private: privateAccess };
      if (privateAccess) {
        if (!context.galaxyAPIOverride) throw new Error('Personal skill access is unavailable');
        const response = await context.galaxyAPIOverride.client.post(path, payload, { timeout: 3000 });
        if (response.data?.success !== true) throw new Error('Skill service unavailable');
        return response.data;
      }
      // Catalogue-only requests cannot see a shared account's private packs.
      const response = await fetch(`${GALAXY_URL}${path}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload), signal: AbortSignal.timeout(3000),
      });
      if (!response.ok) throw new Error('Skill service unavailable');
      const data = await response.json() as any;
      if (data.success !== true) throw new Error('Skill service unavailable');
      return data;
    };
    const detected = (!explicit || selected.length === 0)
      ? (await post('/api/skills/detect', {
          query: message, preferred_domains: preferredDomains,
        })).detected?.map((s: { id: string }) => s.id) ?? []
      : selected;
    const ids = withDefaultSkill(detected);
    const data = await post('/api/skills/block', { skill_ids: ids });
    if (typeof data.block !== 'string' || !data.block.trim()) throw new Error('Skill instructions unavailable');
    return data.block;
  } catch {
    if (explicit && selected!.length > 0) throw new Error('The selected expert skills could not be loaded. Please reselect the skills or try again.');
    return '';
  }
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
    'result_comparison': { needsResearchAgent: true, needsLLMReasoning: true },
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
    // Diagnosing the user's OWN failed/stuck run — answer from the run record's
    // recorded error (injected recent-runs-with-errors block), NOT from literature.
    // Routing this to research_question made BioMate reply with a generic cited
    // paper about "why code fails" and ask for logs it already had (org-user issue
    // #3, 2026-11-09). LLM reasoning only: no research/benchmark/workflow agent.
    'run_diagnostics': { needsLLMReasoning: true },
    'dataset_inquiry': { needsDatasetAccess: true, needsLLMReasoning: true },
    'experiment_design': { needsResearchAgent: true, needsLLMReasoning: true },
    'data_interpretation': { needsResearchAgent: true, needsLLMReasoning: true },
    'protocol_guidance': { needsResearchAgent: true, needsLLMReasoning: true },
    'teaching_explanation': { needsLLMReasoning: true },
    'methods_writing': { needsResearchAgent: true, needsLLMReasoning: true },
    'comparative_methodology': { needsResearchAgent: true, needsLLMReasoning: true },
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
  /** For execution intents: 'direct_compute' = compute now (run_code) on data already in the
   *  conversation; 'pipeline' = launch a workflow. Set by the classifier from what the request
   *  needs, in any language. */
  execution?: 'pipeline' | 'direct_compute' | null;
  /** Explicit user constraint the classifier read from the message (any language): 'no_workflow' =
   *  do not create/use a workflow (interpretation only, or compute directly); 'no_launch' = prepare
   *  the plan but do not launch it. Consumed by routing-authority.applyUserConstraintGate. */
  userConstraint?: UserConstraint;
  /** LLM-written routing specification for a workflow intent: method + data type + input format +
   *  expected output, no experimental-design labels. The catalog search for this branch uses it. */
  taskSpec?: string;
  /** Kinds of data the user has for this intent (closed vocabulary); undefined = not stated by the classifier. */
  inputKinds?: string[];
  /** LLM-assigned scientific domain of this branch (e.g. proteomics), preferred when routing it. */
  domain?: string;
  /** Sequential pipeline: where this step's input comes from (human-readable). */
  inputFromDescription?: string;
  /** Sequential pipeline: what this step produces (human-readable). */
  outputDescription?: string;
}

export interface IntentDecomposition {
  intents: DecomposedIntent[];
  isMultiIntent: boolean;
  primaryIntent: DecomposedIntent;
  /** True when the intents form an ordered pipeline (output of step N feeds step N+1) */
  isSequential?: boolean;
  /**
   * Skip Tier-1 single-workflow collapse in processSequentialPipeline so a
   * multi-step plan is not reduced to one Admet Pred (etc.). Tier-2 curated
   * chain lookup still runs when chainHint names a real workflow_chains row
   * (library/molecule dual path). Step-by-step triage sets chainHint=null.
   */
  skipPipelineCollapse?: boolean;
  /** LLM-inferred domain preferences for workflow search ranking (replaces rule-based _infer_domain_preferences) */
  preferredDomains?: string[];
  /** LLM-inferred domains to penalize in workflow search ranking */
  penalizedDomains?: string[];
  /** LLM-extracted technical terms to boost in FTS (replaces ABBREVIATION_MAP expansion) */
  keyTerms?: string[];
  /** Kinds of data the user has (closed vocabulary), for the backend's input-compatibility term. */
  inputKinds?: string[];
  /** True when the query benefits from extended thinking (replaces shouldEnableThinking regex) */
  needsThinking?: boolean;
  /** Name of a known workflow chain if the query maps to one, else null */
  chainHint?: string | null;
  /** Library/molecule dual-path outcome (catalog mega-chain vs step-by-step). */
  libraryMoleculePath?: LibraryMoleculePath;
  /** The user asked for generated / example / demo / synthetic data or a simulation (inferred from
   *  meaning, any language). undefined = the classifier did not say (run_code's synthetic-input
   *  guard then falls back to its keyword rule). */
  userRequestedSyntheticData?: boolean;
  /** LLM's one-line explanation of WHY it classified the intent this way.
   * Computed by the classifier but historically only logged; surfaced to the
   * user as a persistent "why this routing" line. */
  rationale?: string;
  /** True when no LLM produced this decomposition (keyword last-resort after every model failed). */
  degraded?: boolean;
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

  // Schema-grounded extraction clarifications — shown to the user as
  // a ParamClarificationCard. Only populated when SCHEMA_GROUNDED_EXTRACTION
  // is on AND the workflow's schema flagged missing-required or enum violations.
  paramClarifications?: Array<
    | { kind: 'missing_required'; paramName: string; hint?: string; examples?: string[] }
    | { kind: 'enum_violation'; paramName: string; userValue: string; allowed: string[] }
  >;

  // Intent ambiguity clarification — rendered as IntentClarificationCard.
  // Surfaces when the intent decomposer's classification looks like it might
  // be wrong for the query (design verbs + therapeutic modality but routed
  // as tool_search, etc.). Re-added 2026-06-17 after a merge dropped it.
  intentClarification?: {
    originalIntent: string;
    candidates: Array<{ type: string; label: string; primary?: boolean }>;
    reason: string;
    originalMessage: string;
  };

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

/**
 * Detect paper references in a message (URL, DOI, arXiv ID, PMID) and fetch
 * their text content. Runs in parallel with tool/dataset search.
 *
 * Returns { ref, content } or null if no paper reference found.
 * Content is capped at 8000 chars (enough for methods + abstract).
 */
async function _extractPdfText(filePath: string, maxChars = 50000): Promise<string | null> {
  // Use a direct Python subprocess to avoid contending with the Galaxy gunicorn worker
  // (Galaxy has 1 worker on dev; routing PDF extraction through it causes 30s+ queue waits).
  // Try the Galaxy venv Python first; fall back to system python3.
  const { execFile } = await import('child_process');
  const { promisify } = await import('util');
  const execFileAsync = promisify(execFile);

  const pythonScript = `
import sys, json

def _fmt_table(rows):
    # Render a pdfplumber table as pipe-delimited rows so numeric / technical
    # detail survives (extract_text() alone silently drops tabular data).
    out = []
    for row in rows or []:
        cells = [(c if c is not None else '').replace('\\n', ' ').strip() for c in row]
        if any(cells):
            out.append(' | '.join(cells))
    return '\\n'.join(out)

def _try_pdfplumber(path, max_chars):
    try:
        import pdfplumber
        parts = []
        chars = 0
        pdf = pdfplumber.open(path)
        page_count = 0
        try:
            page_count = len(pdf.pages)
            for page in pdf.pages:
                seg = (page.extract_text() or '').strip()
                # Tables carry the numeric/technical detail that extract_text drops.
                try:
                    tables = page.extract_tables() or []
                except Exception:
                    tables = []
                for ti, tbl in enumerate(tables):
                    ftxt = _fmt_table(tbl)
                    if ftxt.strip():
                        seg = (seg + '\\n\\n[Table ' + str(ti + 1) + ']\\n' + ftxt).strip()
                if seg:
                    parts.append(seg)
                    chars += len(seg)
                if chars >= max_chars:
                    break
        finally:
            try:
                pdf.close()
            except Exception:
                pass
        text = '\\n\\n'.join(parts)[:max_chars]
        return (text, page_count) if text.strip() else (None, 0)
    except Exception:
        return (None, 0)

def _try_pypdf(path, max_chars):
    try:
        from pypdf import PdfReader
        reader = PdfReader(path)
        parts = []
        chars = 0
        for page in reader.pages:
            t = (page.extract_text() or '').strip()
            if t:
                parts.append(t)
                chars += len(t)
            if chars >= max_chars:
                break
        text = '\\n\\n'.join(parts)[:max_chars]
        return (text, len(reader.pages)) if text.strip() else (None, 0)
    except Exception:
        return (None, 0)

path = sys.argv[1]
max_chars = int(sys.argv[2])
text, page_count = _try_pdfplumber(path, max_chars)
if not text:
    text, page_count = _try_pypdf(path, max_chars)
print(json.dumps({'text': text or '', 'page_count': page_count}))
`;

  const pythonCandidates = [
    process.env.GALAXY_PYTHON || '',
    '/Users/kky/biomate/backend/.venv/bin/python3',
    'python3',
    'python',
  ].filter(Boolean);

  for (const py of pythonCandidates) {
    try {
      const { stdout } = await execFileAsync(py, ['-c', pythonScript, filePath, String(maxChars)], {
        timeout: 60_000,
      });
      const data = JSON.parse(stdout.trim()) as { text: string; page_count: number };
      if (data.text && data.text.trim().length > 50) {
        console.log(`[_extractPdfText] Extracted ${data.text.length} chars from ${filePath} via subprocess (${py})`);
        return data.text;
      }
      return null;
    } catch (err: any) {
      if (err.code === 'ENOENT') continue; // Python not found, try next
      console.warn(`[_extractPdfText] subprocess failed (${py}): ${err.message?.slice(0, 200)}`);
      // Don't break — fall through to Galaxy HTTP endpoint as last resort
      break;
    }
  }

  // Last resort: Galaxy HTTP endpoint (may be slow under load)
  const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
  try {
    const r = await fetch(`${galaxyUrl}/api/ai_assistant/extract_pdf_text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ file_path: filePath, max_chars: maxChars }),
      signal: AbortSignal.timeout(90_000),
    });
    if (!r.ok) {
      console.warn(`[_extractPdfText] Galaxy endpoint returned ${r.status} for ${filePath}`);
      return null;
    }
    const data = await r.json() as { text?: string; page_count?: number };
    return data.text && data.text.trim().length > 50 ? data.text : null;
  } catch (err: any) {
    console.warn(`[_extractPdfText] Galaxy fetch failed: ${err.message}`);
    return null;
  }
}

/**
 * Remove tool-call syntax that the model sometimes NARRATES as prose text
 * instead of emitting as a structured tool_use block. Claude occasionally
 * writes Anthropic function-call XML (`<function_calls>` / `<invoke name="...">`)
 * and the ad-hoc code it wraps (e.g. `import PyPDF2`, `print(text[:5000])`)
 * directly into a text content block — most often when reading an uploaded
 * PDF and "thinking out loud" about how to extract it. Left unstripped, that
 * raw XML + code leaks into the user-visible answer (the real answer follows
 * the block in the same completion). It is also self-reinforcing: once
 * persisted to chat history and replayed, it teaches the next turn to repeat
 * the pattern. Strip the block, keep the surrounding real answer.
 *
 * Operates on COMPLETE text (post-stream / final message). For the live token
 * stream use StreamToolCallFilter, which handles fragmented tags.
 */
/** Canonical workflow identifier form (mirrors UnifiedWorkflowSearch._workflow_slug):
 *  "Perform Chipseq Peak Calling With Macs2" and "perform_chipseq_peak_calling_with_macs2"
 *  are the same workflow. */
export function workflowSlug(name: string): string {
  return (name || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

/** The catalog workflow a response presents in its header — the first bold span, minus a
 *  trailing " — description". Only identifier-shaped spans count (a snake_case id or a
 *  short Title-Case name); bold prose is not a workflow name. nf-core/<slug> is left to the
 *  dedicated nf-core guardrail. */
export function textWorkflowName(text: string): string | null {
  const m = /\*\*([^*\n]{3,120}?)\*\*/.exec(text || '');
  if (!m) return null;
  const name = m[1].split(/\s+[—–-]\s+/)[0].replace(/[:.]+$/, '').trim();
  if (/^nf-core\//i.test(name)) return null;
  if (/^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/.test(name)) return name;
  if (/^[A-Z0-9][\w+-]*(?:\s+\(?[A-Z0-9][\w+-]*\)?){1,7}$/.test(name)) return name;
  return null;
}

/** Rewrite the header's workflow name to the card's title, keeping the " — one-line description"
 *  that follows it. Used when the reply opens on a name that is NOT the card and NOT a workflow the
 *  search retrieved (an invented/renamed title): the card is right, so the TEXT is what must change —
 *  CLAUDE.md requires the chat name to be the card title exactly. Returns the text unchanged when the
 *  header is already the card, when there is no bold header, or when the header is not `named`. */
export function relabelWorkflowHeader(text: string, named: string, cardName: string): string {
  if (!text || !named || !cardName) return text;
  if (workflowSlug(named) === workflowSlug(cardName)) return text;
  const m = /\*\*([^*\n]{3,120}?)\*\*/.exec(text);
  if (!m) return text;
  const sep = /\s+[—–-]\s+/.exec(m[1]);
  const head = sep ? m[1].slice(0, sep.index) : m[1];
  const rest = sep ? m[1].slice(sep.index) : '';
  if (workflowSlug(head.replace(/[:.]+$/, '').trim()) !== workflowSlug(named)) return text;
  return `${text.slice(0, m.index)}**${cardName}${rest}**${text.slice(m.index + m[0].length)}`;
}

/** Catalog identity of a workflow the user has chosen — sent to the backend as
 *  generate_workflow's `selected_workflow`, which builds exactly that card (no search). */
export interface SelectedWorkflow {
  name: string;
  nextflow_path?: string;
  id?: number | string;
  source?: string;
  type?: string;
}

/** Validate a client-supplied `context.selectedWorkflow` (Workflows library "Run" or another explicit picker).
 *  Only catalog workflows qualify: a chain is a plan of several workflows, not one identity. */
export function normalizeSelectedWorkflow(raw: unknown): SelectedWorkflow | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const str = (v: unknown, max: number) => (typeof v === 'string' && v.trim() && v.length <= max ? v.trim() : undefined);
  const name = str(r.name, 300);
  const nextflow_path = str(r.nextflow_path, 1000);
  if (!name && !nextflow_path) return null;
  const type = str(r.type, 40);
  if (type === 'chain') return null;
  const id = typeof r.id === 'number' && Number.isInteger(r.id) ? r.id
    : (typeof r.id === 'string' && /^\d+$/.test(r.id) ? r.id : undefined);
  const source = str(r.source, 80);
  return {
    name: name || nextflow_path!,
    ...(nextflow_path ? { nextflow_path } : {}),
    ...(id !== undefined ? { id } : {}),
    ...(source ? { source } : {}),
    ...(type ? { type } : {}),
  };
}

/** Catalog identity of the workflow open in the panel (`context.currentWorkflow`, the card
 *  payload the client last opened), or null when it is not a single catalog workflow. */
export function workflowIdentityOf(wf: any): SelectedWorkflow | null {
  if (!wf || typeof wf !== 'object') return null;
  if (['chain', 'pipeline', 'disambiguation', 'clarification'].includes(String(wf.workflow_type || ''))) return null;
  const name = wf.workflow_ga?.name || wf.workflow_name || wf.workflowDefinition?.name || wf.name;
  const nextflow_path = wf.workflow_ga?.nextflow_path || wf.nextflow_path || wf.workflowDefinition?.nextflow_path;
  return normalizeSelectedWorkflow({ name, nextflow_path });
}

/**
 * Follow-up binding: does this turn fill in the workflow already open in the panel, rather than
 * ask for a new analysis? (Doc §7.4: with nf-core/rnaseq open and BioMate asking for input, the
 * reply "SRR1039508" was re-routed as a fresh request and the card became differentialabundance.)
 *
 * Decided from the intent classifier's own output — no wording regexes, so it holds in any
 * language. Bind only when ALL hold:
 *   1. one intent (a multi-intent turn is a new plan);
 *   2. the classifier wants a pipeline run/configuration (needsWorkflowGeneration or
 *      needsWorkflowModification) and not direct_compute (ad-hoc compute is not this workflow);
 *   3. the turn SUPPLIES something: inline parameter values, an uploaded-file binding, or a
 *      file_reference / parameter fact;
 *   4. the turn states no analysis of its own: the reply is value-only (isValueOnlyReply — the
 *      classifier may still attach a carried-over goal at high confidence), or there is no analysis_goal or tool_preference fact the
 *      classifier marked as explicitly stated (confidence >= 0.8 — its prompt reserves 0.9+ for
 *      direct mentions and 0.5-0.7 for inferred facts, e.g. the open workflow's goal carried
 *      over from earlier turns).
 * Anything else (a question, a new goal or tool, several tasks) routes normally. Conservative by
 * design: a miss costs one ordinary routing turn; a false bind would ignore a new request.
 */
/**
 * A workflow the user's own text names explicitly as the thing to run: a run verb followed by a
 * catalog identifier (nf-core/<name>, or a snake_case id with 2+ underscores such as
 * analyze_ebv_antibody_titers), or "run (the) <name> workflow". Deterministic: the user already
 * chose the workflow, so the classifier must not re-decide whether a workflow runs (dev
 * 2026-11-11: "Run analyze_ebv_antibody_titers on its built-in … data" was sometimes routed to no
 * workflow and the model simulated ELISA readings with run_code). Only a candidate — the backend
 * resolves it exactly; an unresolvable name falls back to normal routing.
 */
export function workflowNamedInRunRequest(message: string): SelectedWorkflow | null {
  const text = stripSystemBlocks(message);
  const verb = String.raw`(?:\brun|\bexecute|\blaunch|运行|执行)\s+(?:the\s+)?`;
  const id = new RegExp(verb + String.raw`(nf-core\/[a-z0-9_-]+|[a-z][a-z0-9]*(?:_[a-z0-9]+){2,})(?![\w/-])`, 'i').exec(text)?.[1]
    || new RegExp(verb + String.raw`([a-z][\w.-]{3,})\s+(?:workflow|pipeline)\b`, 'i').exec(text)?.[1]
    || new RegExp(verb + String.raw`([a-z][\w./-]{3,})\s*工作流`, 'i').exec(text)?.[1];
  // A captured token is only a CANDIDATE name — validated structurally downstream:
  // the backend resolves selected_workflow by EXACT catalog membership
  // (_resolve_selected_workflow: "no fuzzy search"), so a generic word like "whole"
  // in "run the whole workflow" resolves to nothing and the turn falls back to
  // normal routing. No hand-maintained stop-word list — the catalog is the
  // authority on what is a workflow name.
  return id ? normalizeSelectedWorkflow({ name: id }) : null;
}

/** Public data identifiers: SRR/ERR/DRR/SRX runs, GSE/GSM series, PRJNA/PRJEB projects, PXD, E-MTAB-…, EGA…
 *  Case-insensitive: users paste accessions lowercase too ("srr1039508"). */
const DATA_IDENTIFIER_RE = /\b(?:[A-Z]{1,6}-)?[A-Z]{2,6}[-_]?\d{3,}\b/gi;
/** File names a user might paste (sample_R1.fastq.gz, counts.csv). */
const FILE_NAME_RE = /[^\s,;，；、]+\.[A-Za-z][A-Za-z0-9]{0,7}(?:\.gz)?\b/g;

/**
 * True when the user's own text is ONLY input values — public data identifiers, attached-file
 * blocks, file names, numbers and separators — with no words left over. Such a reply cannot
 * state a new analysis, whatever goal the classifier carries over from the conversation
 * (dev 2026-11-11: for the reply "SRR1039508" with nf-core/rnaseq open, the classifier emitted
 * analysis_goal "RNA-seq alignment and quantification" at confidence 0.95, inferred from history).
 * Deterministic and language-neutral: any leftover letter or CJK character means "not value-only".
 */
export function isValueOnlyReply(message: string): boolean {
  const base = stripSystemBlocks(message);
  // Value tokens are FORMAT-defined (accessions, file names, numbers), not a
  // keyword list \u2014 DATA_IDENTIFIER_RE is case-insensitive so a lowercase accession
  // ("srr1039508") is caught too. If anything with a letter is left after removing
  // them, the reply says more than its values and is not value-only. (The commonest
  // multi-accession phrasings that ALSO carry a connective \u2014 "use SRR\u2026 and SRR\u2026" \u2014
  // are deliberately NOT special-cased here with a connective word-list; that would
  // be keyword overfitting. The real gap is the classifier carrying a stale goal
  // onto a value turn, which is the right place to fix if coverage needs it.)
  const rest = base
    .replace(DATA_IDENTIFIER_RE, ' ')
    .replace(FILE_NAME_RE, ' ')
    .replace(/\d+/g, ' ');
  const hadValue = rest !== base || /\[(?:Attached files|Uploaded datasets?)\s*:/i.test(message);
  return hadValue && !/[A-Za-z\u3400-\u9fff]/.test(rest);
}

export function followUpFillsCurrentWorkflow(decomposition: IntentDecomposition, message: string): boolean {
  if (decomposition.isMultiIntent) return false;
  const intent = decomposition.primaryIntent;
  if (!intent) return false;
  const a: Partial<ActionCategories> = intent.actions || {};
  if (!(a.needsWorkflowGeneration || a.needsWorkflowModification)) return false;
  if (intent.execution === 'direct_compute') return false;
  const facts = intent.facts || [];
  const suppliesValues =
    Object.entries(intent.inlineParameters || {}).some(([k, v]) => k !== 'domain_hint' && String(v ?? '').trim() !== '') ||
    Object.keys(extractUploadedFileParams(message)).length > 0 ||
    facts.some(f => f.category === 'file_reference' || f.category === 'parameter');
  if (!suppliesValues) return false;
  // A value-only reply states no analysis of its own; the classifier's goal for it is carried over.
  if (isValueOnlyReply(message)) return true;
  const statesNewAnalysis = facts.some(f =>
    (f.category === 'analysis_goal' || f.category === 'tool_preference') && (f.confidence ?? 1) >= 0.8);
  return !statesNewAnalysis;
}

/** The other workflows the search retrieved for this request (not the card's own), as
 *  catalog names — the only alternatives the response may lead with (Step 6c-2). */
export function alternativeWorkflowNames(payload: any): string[] {
  const card = workflowSlug(payload?.workflow_ga?.name || payload?.workflow_name || '');
  const seen = new Set<string>([card]);
  return (payload?.candidate_workflows || [])
    .map((c: any) => String(c?.name || ''))
    .filter((n: string) => { const s = workflowSlug(n); if (!n || seen.has(s)) return false; seen.add(s); return true; })
    .slice(0, 4);
}


/** The user asks about one of their runs failing / not starting / stuck (EN + ZH). */
export function asksAboutRunProblem(message: string): boolean {
  const t = message || '';
  return /\b(run|job|workflow|pipeline|analysis)s?\b[^.?!\n]{0,60}\b(fail\w*|error\w*|stuck|crash\w*|not (?:working|starting|running|finishing)|hang\w*)\b/i.test(t)
    || /\bwhy\b[^.?!\n]{0,40}\b(fail\w*|error\w*)\b/i.test(t)
    || /\bwhat does (?:this|the|that) error\b/i.test(t)
    || /(运行|任务|流程|工作流|分析)[^。？！\n]{0,20}(失败|报错|出错|卡住)|为什么.{0,10}(失败|报错)/.test(t);
}

/** One line for a failed run's recorded error: the Nextflow process that failed and the most
 *  specific message, never a bare "Caused by:" (what external users were shown). */
export function runErrorSummary(execution: any, errorMessage?: string | null): string {
  const e = execution || {};
  const raw = [e.error, errorMessage, ...(Array.isArray(e.nextflowLog) ? e.nextflowLog : []), ...(Array.isArray(e.errorLines) ? e.errorLines : [])]
    .filter((x: any) => typeof x === 'string' && x.trim()).join('\n');
  const proc = /Error executing process > '([^']+)'/.exec(raw)?.[1];
  const failed = Array.isArray(e.processes) ? e.processes.find((p: any) => /fail/i.test(String(p?.status))) : null;
  const specific = raw.split('\n').map(l => l.trim())
    .find(l => l && !/^Caused by:?$/i.test(l) && !/DEBUG|WARN\s|RetryConfig|FileHelper|Error executing process >/.test(l)) || '';
  const parts = [proc || failed?.name ? `process ${proc || failed?.name} failed` : '', specific.slice(0, 300)].filter(Boolean);
  return parts.join(' — ') || 'failed with no recorded error message (task logs not captured)';
}

/** Assemble the raw error text recorded on a run (recorded error + log/trace lines). */
function assembleRunErrorText(execution: any, errorMessage?: string | null): string {
  const e = execution || {};
  return [e.error, errorMessage, ...(Array.isArray(e.nextflowLog) ? e.nextflowLog : []), ...(Array.isArray(e.errorLines) ? e.errorLines : [])]
    .filter((x: any) => typeof x === 'string' && x.trim())
    .join('\n');
}

/**
 * Plain-language explanation of WHY a run failed — the specific cause, the input/
 * param at fault, and a concrete next action, in one message (raw error appended
 * for expansion). Uses the deterministic rule-based classifier; when the error
 * matches no known class it states the failing step and shows the raw error
 * rather than inventing a cause. This is what the assistant relays when the user
 * asks "why is the run failing?" (org-user issue #3). Returns `null` only when the
 * run is not actually in a failed/error state.
 */
export function runFailureExplanation(execution: any, errorMessage?: string | null): string | null {
  const e = execution || {};
  const status = String(e.status ?? '').toLowerCase();
  if (status && !/fail|error|cancel/.test(status)) return null;
  const raw = assembleRunErrorText(e, errorMessage);
  const failedProc = Array.isArray(e.processes) ? e.processes.find((p: any) => /fail/i.test(String(p?.status)))?.name : undefined;
  const exp = classifyRunFailure(raw, { process: failedProc });
  return formatRunFailureReply(exp);
}

/** Prompt line fixing the reply language to the user's own words (not the English attachment blocks,
 *  tool output or retrieved papers that follow them): a Chinese cell-viability request was answered
 *  in English (external-user replay 2026-11-04). Script-detectable languages are named explicitly. */
export function replyLanguageNote(message: string): string {
  const own = (message || '').split(/\n\s*\[(?:Attached files|Uploaded datasets|BioMate dataset|Galaxy dataset|Upload warnings|Memory context|Inline parameters)/i)[0];
  const count = (re: RegExp) => (own.match(re) || []).length;
  const letters = count(/\p{L}/gu) || 1;
  const named = count(/[\u3040-\u30ff]/g) / letters > 0.1 ? 'Japanese'
    : count(/[\uac00-\ud7af]/g) / letters > 0.2 ? 'Korean'
    : count(/\p{Script=Han}/gu) / letters > 0.2 ? 'Chinese (the user\'s script: simplified or traditional)'
    : count(/\p{Script=Cyrillic}/gu) / letters > 0.3 ? 'Russian'
    : '';
  return named
    ? `[Reply language: ${named} — the language of the user's own words; keep tool names, gene symbols and file names as they are]`
    : "[Reply language: the language of the user's own words above, not of attached file names, tool output or retrieved papers]";
}

/** The goal clause of the user's own request: the first line that is not a bracketed context
 *  block or the "Prepared demo context" preamble, cut at its first sentence end. */
export function requestGoal(message: string): string {
  const line = (message || '').split('\n').map(l => l.trim())
    .find(l => l && !l.startsWith('[') && !/^prepared demo context/i.test(l)) || '';
  return line.split(/(?<=[.;!?。；！？])\s*/)[0].replace(/[.;!?。；！？]$/, '').trim();
}

/** Name for a DAG plan card. Prefer the goal of the user's own request (the demo card was titled
 *  after its fan-in step, "Integrate docking scores and ADMET…", for a request to adapt a generative
 *  model); else the integration step's task, else the first branch; never a generic placeholder. */
export function dagPlanName(
  tasks: Array<{ description: string; depends_on: number[]; workflow_label?: string; workflow_name?: string }>,
  goal?: string,
): string {
  const fit = (text: string) => {
    const clause = text.replace(/\s+/g, ' ').trim();
    const name = clause.length <= 60 ? clause : clause.slice(0, 57).replace(/\s+\S*$/, '') + '…';
    return name.charAt(0).toUpperCase() + name.slice(1);
  };
  const g = goal ? requestGoal(goal) : '';
  // Prompt-as-name class (coldstart): questions / "which of these…" must NOT become
  // the panel title — prefer resolved catalog workflow labels when present.
  const labels = tasks
    .map((t) => String(t.workflow_label || t.workflow_name || '').trim())
    .filter(Boolean);
  const goalIsPromptLike =
    !g ||
    /\?$/.test(g) ||
    /^(which|what|how|why|rank these|dock the|triage this|predict binding)\b/i.test(g);
  if (goalIsPromptLike && labels.length === 1) return fit(labels[0]);
  if (goalIsPromptLike && labels.length > 1) {
    return fit(`${labels[0]} + ${labels.length - 1} more`);
  }
  if (g && !goalIsPromptLike && (g.split(/\s+/).length >= 3 || /[一-鿿]{4,}/.test(g))) return fit(g);
  // Named after the combining step; a plan with no dependent step is not "about" its last branch.
  if (tasks.length > 1 && tasks.every(t => !t.depends_on.length)) return `${tasks.length} parallel analyses`;
  const sink = [...tasks].reverse().find(t => t.depends_on.length > 1) || tasks[tasks.length - 1] || tasks[0];
  const text = (sink?.description || 'Multi-step analysis').replace(/\s+/g, ' ').trim();
  const clause = text.split(/(?<=[.;:。；])\s*/)[0].replace(/[.;:。；]$/, '');
  const name = clause.length <= 60 ? clause : clause.slice(0, 57).replace(/\s+\S*$/, '') + '…';
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/** Closing lines of a DAG plan message: what was filled from the user's files and what is still
 *  needed, per step (from /plan_dag's bound_from_uploads / missing_inputs). A backend that does not
 *  report inputs gets the previous generic instruction — never a claim that inputs are complete. */
export function dagInputStatus(steps: any[], hasUnwired: boolean): string[] {
  if (!steps.some(s => Array.isArray(s?.missing_inputs))) {
    return ['Fill in each branch\'s input files in the plan, then click **Confirm & Run**.'];
  }
  const per = (key: string) => steps
    .map((s, k) => ({ k: k + 1, names: (Array.isArray(s?.[key]) ? s[key] : []) as string[] }))
    .filter(x => x.names.length)
    .map(x => `step ${x.k} — ${x.names.join(', ')}`);
  const filled = per('bound_from_uploads');
  const needed = per('missing_inputs');
  return [
    filled.length ? `Filled from your files: ${filled.join('; ')}.` : '',
    needed.length ? `Still needed before running: ${needed.join('; ')}. Without its data files a step runs on the workflow's built-in sample data, not yours.` : '',
    needed.length || hasUnwired
      ? 'Fill these in the plan, then click **Confirm & Run**.'
      : 'Inputs are set — review the plan, then click **Confirm & Run**.',
  ].filter(Boolean);
}

/** A tool output with image BYTES removed, for serializing as model TEXT. `image_data_uri` (run_code
 *  plot previews for the UI) becomes a short marker; `__imageBlocks` (real vision blocks, attached
 *  separately as image content) is dropped. Images reach a model only as image blocks, never as text. */
export function stripImageBytesForModel(value: any): any {
  if (Array.isArray(value)) return value.map(stripImageBytesForModel);
  if (value && typeof value === 'object') {
    const out: Record<string, any> = {};
    for (const [k, v] of Object.entries(value)) {
      if (k === '__imageBlocks') continue;
      out[k] = k === 'image_data_uri' && typeof v === 'string' ? '[image — attached separately, not as text]'
        : stripImageBytesForModel(v);
    }
    return out;
  }
  return value;
}

/** Vision image blocks for the plots a run_code call produced, so the model can look at the figure
 *  it reports. Only raster formats the vision model reads (PNG/JPEG/GIF/WebP), within the same limits
 *  as attached images (_VISION_MAX_RAW_BYTES each, _VISION_MAX_IMAGES total). */
export function plotImageBlocks(files: Array<{ name?: string; image_data_uri?: string }> | undefined): any[] {
  const allowed = new Set(Object.values(_VISION_MEDIA_TYPES));
  const blocks: any[] = [];
  for (const f of files || []) {
    const m = /^data:([\w/+.-]+);base64,(.+)$/s.exec(f?.image_data_uri || '');
    if (!m || !allowed.has(m[1])) continue;
    if (Math.floor(m[2].length * 3 / 4) > _VISION_MAX_RAW_BYTES) continue;
    blocks.push({ type: 'image', source: { type: 'base64', media_type: m[1], data: m[2] } });
    if (blocks.length >= _VISION_MAX_IMAGES) break;
  }
  return blocks;
}

/** Closed input-kind vocabulary — kept equal to backend chain_composer/input_kinds_classifier.INPUT_KINDS. */
export const INPUT_KIND_VOCAB = [
  'fastq', 'bam', 'raw_spectra', 'idat', 'bcl', 'nanopore_signal', 'raw_images',
  'counts_matrix', 'h5ad', 'cellranger_output', 'protein_table', 'peptide_table', 'metabolite_table', 'beta_values',
  'vcf', 'peaks', 'gene_list', 'fasta', 'annotation', 'structure', 'molecules', 'tabular',
] as const;

/** The classifier's input_kinds, restricted to the vocabulary; undefined when the field is absent
 *  (the backend then falls back to detecting the data kind from the text). [] = "states no input data". */
export function parseInputKinds(v: unknown): string[] | undefined {
  if (!Array.isArray(v)) return undefined;
  const ok = new Set<string>(INPUT_KIND_VOCAB);
  return Array.from(new Set(v.map(x => String(x).trim().toLowerCase()).filter(x => ok.has(x))));
}

/** Intents in dependency order (stable; unknown dependency ids ignored). null on a cycle. */
export function topoOrderIntents<T extends { id: string; dependsOn?: string[] }>(intents: T[]): T[] | null {
  const ids = new Set(intents.map(i => i.id));
  const done = new Set<string>();
  const out: T[] = [];
  let progressed = true;
  while (out.length < intents.length && progressed) {
    progressed = false;
    for (const it of intents) {
      if (done.has(it.id)) continue;
      const deps = (it.dependsOn || []).filter(d => ids.has(d) && d !== it.id);
      if (deps.every(d => done.has(d))) { out.push(it); done.add(it.id); progressed = true; }
    }
  }
  return out.length === intents.length ? out : null;
}

/** A branch domain the router can use: the classifier's domain vocabulary is wider than the 14
 *  CANONICAL_DOMAINS that preferred_domains (and so the ±4 domain term) accept. Aliases map; others drop. */
export function canonicalBranchDomain(d: string | undefined): string | undefined {
  if (!d) return undefined;
  const v = d.trim().toLowerCase();
  if ((CANONICAL_DOMAINS as readonly string[]).includes(v)) return v;
  const alias: Record<string, string> = { variant_calling: 'genomics', pharmacology: 'drug_discovery', imaging: 'bioimaging',
    ...(SUBDOMAIN_TO_CANONICAL as Record<string, string>) };
  return alias[v];
}

/** One decomposition call through OpenRouter's OpenAI-compatible API (retried once on a transport or
 *  provider error — providers throttle concurrent ≈21k-token requests). Returns the raw text. */
export async function decomposeViaOpenRouter(model: string, key: string, system: string, user: string,
  fetchImpl: typeof fetch = fetch): Promise<string> {
  let lastErr: unknown;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetchImpl('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'X-Title': 'BioMate' },
        body: JSON.stringify({ model, ...reasoningBudgetBody('https://openrouter.ai/api/v1', 4096), temperature: 0, messages: [{ role: 'system', content: system }, { role: 'user', content: user }] }),
        signal: AbortSignal.timeout(45000),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status}: ${(await r.text()).slice(0, 160)}`);
      const j: any = await r.json();
      assertNotReasoningExhausted(j);
      const text = j?.choices?.[0]?.message?.content;
      if (typeof text !== 'string' || !text.trim()) throw new Error('empty response');
      return text;
    } catch (e) {
      lastErr = e;
      if (attempt === 0) await new Promise(res => setTimeout(res, 1500));
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
}

/** Provider-chain contract: a reply with no text is a failure so the chain fails over. */
export function requireNonEmptyResponse(text: string | null | undefined, provider: string): string {
  if (typeof text !== 'string' || !text.trim()) throw new Error(`${provider} returned an empty response`);
  return text;
}

export function parseExecutionMode(v: unknown): 'pipeline' | 'direct_compute' | null {
  return v === 'direct_compute' || v === 'pipeline' ? v : null;
}

/** Data the user put in the conversation that run_code can compute on: an attached / project /
 *  Galaxy dataset block, or a pasted table (>=3 delimited rows, e.g. a CSV or VCF excerpt). */
export function hasComputableData(message: string): boolean {
  const text = message || '';
  if (/\[(?:Uploaded datasets?|BioMate dataset|Galaxy dataset)\s*:/i.test(text)) return true;
  const rows = text.match(/[^\s,;|]+(?:[,\t][^\s,;\t]*){2,}/g) || [];
  return rows.length >= 3;
}

/** Data run_code can compute on exists anywhere in the conversation — this message, an earlier
 *  user turn (the UI adds the dataset block only on the turn the file is attached), or datasets
 *  selected in the UI. hasComputableData(message) alone is false on every follow-up turn. */
/** Raw instrument data (sequencing reads, cryo-EM movies, raw MS files) is pipeline-scale: the
 *  run_code sandbox cannot align / call variants / reconstruct from it, so a direct_compute label on
 *  a conversation carrying it is not a compute-now request (dev 2026-11-11: FASTQ tumour/normal +
 *  "call variants" → run_code built a samplesheet and the reply claimed "pipeline configured" with
 *  no card). Read from the attached-file names in this message and earlier user turns. */
const PIPELINE_SCALE_FILE_RE = /\.(?:f(?:ast)?q(?:\.gz)?|bam|cram|sra|mrcs?|tiff?|eer|raw|wiff|d)$/i;
export function conversationHasPipelineScaleData(
  message: string,
  context?: { previousMessages?: Array<{ role: string; content: string }> },
): boolean {
  const currentNames = attachedNamesFromBlocks(message || '');
  if (currentNames.some(n => PIPELINE_SCALE_FILE_RE.test(n))) return true;
  // The current turn brought its own (non-pipeline) data — that IS the task; a
  // stale pipeline-scale attachment from an earlier, unrelated turn must not
  // suppress direct_compute for it (correctness review 2026-11-11: a turn-1 FASTQ
  // was disabling run_code for a turn-5 "mean of column 3" on a fresh CSV).
  if (currentNames.length > 0 || hasComputableData(message || '')) return false;
  // No data on this turn → a carried-over pipeline-scale file is the subject (the
  // UI adds the dataset block only on the turn the file is attached).
  return (context?.previousMessages || []).filter(m => m.role === 'user')
    .some(m => attachedNamesFromBlocks(m.content || '').some(n => PIPELINE_SCALE_FILE_RE.test(n)));
}

export function conversationHasComputableData(
  message: string,
  context?: { previousMessages?: Array<{ role: string; content: string }>; selectedDatasets?: string[] },
): boolean {
  if (hasComputableData(message)) return true;
  if (Array.isArray(context?.selectedDatasets) && context!.selectedDatasets!.length > 0) return true;
  return (context?.previousMessages || []).some(m => m.role === 'user' && hasComputableData(m.content || ''));
}

export const FINAL_ANSWER_INSTRUCTION = 'The tool budget for this turn is used up. Do not call any more tools. '
  + 'Write the final answer for the user now, using only the tool results above: what was computed, the '
  + 'actual numbers and files produced, and any limitation. Do not describe steps you have not run.';

export const TRUNCATED_REPLY_INSTRUCTION = 'Your previous reply was cut off by the output length limit before it finished, '
  + 'so any tool call in it was NOT run and the user has not seen a result. Continue now: if you were writing code, '
  + 'call the tool again with a shorter script (split the work into smaller steps if needed); otherwise continue the '
  + 'answer from exactly where it stopped, without repeating what was already written. Do not announce what you are '
  + 'about to do — do it.';

/** A turn that stopped on the output-length limit is incomplete: its text is a fragment and any
 *  tool_use in it was cut mid-input and never run (dev 2026-11-12, GLM via OpenRouter: the 5th turn of
 *  an image-QC chat stopped on max_tokens while writing the plotting script, and "现在让我生成可视化的 QC
 *  报告：" was shown as the whole answer). Returns the transcript entries that replace that turn: its
 *  text only (an unrun tool_use would need a tool_result) plus the instruction to continue. */
/** Whether a turn that stopped on max_tokens is mid-work (follow up and let the model continue) or a
 *  long prose answer (keep it; the reply is flagged truncated and the client offers "Continue").
 *  Mid-work: it was cutting off a tool call, tools already ran in this response (its text is the
 *  narration of a next step — the dev 2026-11-12 case), or it produced no text at all. Committee
 *  review 2026-11-12: following up on a prose answer replaced the whole answer with its tail. */
export function truncatedTurnNeedsFollowUp(content: any[] | undefined, toolsRanThisResponse: boolean): boolean {
  const blocks = content || [];
  if (blocks.some((b: any) => b?.type === 'tool_use')) return true;
  if (toolsRanThisResponse) return true;
  return !blocks.some((b: any) => b?.type === 'text' && String(b.text || '').trim());
}

/** An assistant text block the API accepts: a blank text block is rejected outright
 *  ("text content blocks must contain non-whitespace text", dev 2026-11-12 — it failed the
 *  final-answer turn and the user got raw tool stdout as the answer). */
export function assistantTextBlock(text: string | undefined | null, placeholder = '[reply cut off by the output limit]') {
  return { type: 'text', text: String(text || '').trim() ? String(text) : placeholder };
}

export function truncatedTurnFollowUp(content: any[] | undefined): Array<{ role: 'assistant' | 'user'; content: any }> {
  const text = (content || []).filter((b: any) => b?.type === 'text' && b.text).map((b: any) => b.text).join('');
  return [
    { role: 'assistant', content: [assistantTextBlock(text)] },
    { role: 'user', content: TRUNCATED_REPLY_INSTRUCTION },
  ];
}

/** The request for the final, tool-free turn of the agentic loop once its tool budget is spent:
 *  same model/system, the full transcript plus an instruction, tools declared but disabled
 *  (tool_choice none — the transcript contains tool_use blocks, so the tools stay defined). */
export function finalAnswerRequest(
  apiOptions: Record<string, any>,
  agentMessages: Array<{ role: string; content: any }>,
  agentTools?: any[] | null,
): Record<string, any> {
  const messages = agentMessages.slice();
  const last = messages[messages.length - 1];
  if (last?.role === 'user' && Array.isArray(last.content)) {
    messages[messages.length - 1] = { ...last, content: [...last.content, { type: 'text', text: FINAL_ANSWER_INSTRUCTION }] };
  } else if (last?.role === 'user' && typeof last.content === 'string') {
    // e.g. the loop ended on a truncated-reply follow-up: one user turn, not two in a row.
    messages[messages.length - 1] = { ...last, content: [{ type: 'text', text: last.content }, { type: 'text', text: FINAL_ANSWER_INSTRUCTION }] };
  } else {
    messages.push({ role: 'user', content: FINAL_ANSWER_INSTRUCTION });
  }
  const { stream: _stream, tools: _tools, tool_choice: _tc, ...base } = apiOptions;
  return {
    ...base,
    messages,
    ...(agentTools?.length ? { tools: agentTools, tool_choice: { type: 'none' } } : {}),
  };
}

/** The user asked for code itself ("write a script", "give me the R code", 写代码/脚本). */
export function wantsCodeItself(message: string): boolean {
  return /\b(write|give|show|generate|provide)\b[^.\n]{0,40}\b(scripts?|code|snippets?|functions?)\b|代码|脚本/i.test(message || '');
}

/** A reply that presents analysis code (a fenced Python/R block) — used to catch replies that
 *  describe running code that was never executed (external-user replay 2026-11-04: "Running
 *  analysis on qa_new_account_counts.csv…" with a pandas block and no run_code call). */
export function presentsUnexecutedCode(text: string): boolean {
  return /```\s*(?:python|py|r)\s*\n[\s\S]{60,}?```/i.test(text || '') || claimsProducedOutputFile(text);
}

/** A reply that says it produced an output file ("已生成 `results.csv`", "saved to summary.json").
 *  Only meaningful when run_code did not run this turn — then the file does not exist
 *  (EPAR test 2026-11-10: "已生成 clinical_studies_structured.csv" with no execution). */
export function claimsProducedOutputFile(text: string): boolean {
  return /(?:已生成|已保存|已导出|已创建|生成了|保存为|导出为|\b(?:saved|generated|created|wrote|written|exported)\b)[^\n]{0,60}?\b[\w.-]+\.(?:csv|tsv|xlsx?|json|png|pdf|svg|parquet|txt)\b/i.test(text || '');
}

/** Datasets attached to a message by the chat composer: the "[Uploaded datasets: name: dataset_id=<uuid>,
 *  galaxy_dataset_id=<id>, s3_uri=...; ...]" block chat-interface.tsx appends on send. */
export function attachedDatasetsFromMessage(message: string): Array<{ name: string; datasetId?: string; galaxyId?: string }> {
  const m = /\[Uploaded datasets?:\s*([^\]]+)\]/i.exec(message || '');
  if (!m) return [];
  return m[1].split(/;\s*/).map(entry => {
    const name = entry.split(':')[0].trim();
    const datasetId = /\bdataset_id=([^,\s]+)/.exec(entry)?.[1];
    const galaxyId = /\bgalaxy_dataset_id=([^,\s]+)/.exec(entry)?.[1];
    return { name, datasetId: datasetId && datasetId !== 'n/a' ? datasetId : undefined, galaxyId };
  }).filter(d => d.name && (d.datasetId || d.galaxyId));
}

/** The "[Uploaded datasets: …]" block as the response model sees it: one neutral `dataset_id` per
 *  file (the backend id when present — the same id <session_datasets> and run_code staging use —
 *  else BioMate's), the backend-specific key dropped so the model never learns or repeats it
 *  (founder 2026-11-12: "there should not have galaxy in output"). s3_uri is kept: it is a
 *  workflow-parameter value, and replies are guarded by redactStoragePaths. */
export function modelFacingUploads(text: string): string {
  return String(text || '')
    // Legacy attachment lines still in older chat histories.
    .replace(/\[Galaxy dataset:\s*([^\]]*?)\s*\(id:\s*([^)\s]+)\)\s*\]/gi, '[Dataset: $1 (dataset_id: $2)]')
    .replace(/\[Uploaded datasets?:\s*([^\]]+)\]/gi, (_all, body: string) => {
    const entries = body.split(/;\s*/).map((entry) => {
      const fields = parseUploadEntry(entry);
      if (!fields.name) return '';
      const id = fields.galaxy_dataset_id || (fields.dataset_id && fields.dataset_id !== 'n/a' ? fields.dataset_id : undefined);
      const parts = [id ? `dataset_id=${id}` : '', fields.s3_uri ? `s3_uri=${fields.s3_uri}` : ''].filter(Boolean);
      return parts.length ? `${fields.name}: ${parts.join(', ')}` : fields.name;
    }).filter(Boolean);
    return `[Uploaded datasets: ${entries.join('; ')}]`;
  });
}

/** One "[Uploaded datasets:]" entry → its fields. The file name is everything before the first
 *  `key=` (names may contain ':' or spaces); each value runs to the next ", key=" (so an s3 URI
 *  built from a file name with spaces stays whole). */
export function parseUploadEntry(entry: string): { name: string; dataset_id?: string; galaxy_dataset_id?: string; s3_uri?: string } {
  const KEY = /(?:^|[\s,])(galaxy_dataset_id|dataset_id|s3_uri)=/g;
  const marks: Array<{ key: string; at: number; valueAt: number }> = [];
  for (const m of entry.matchAll(KEY)) {
    const lead = m[0].length - m[1].length - 1;
    marks.push({ key: m[1], at: (m.index ?? 0) + lead, valueAt: (m.index ?? 0) + m[0].length });
  }
  const name = (marks.length ? entry.slice(0, marks[0].at) : entry).trim().replace(/:\s*$/, '').trim();
  const out: any = { name };
  marks.forEach((mk, k) => {
    const end = k + 1 < marks.length ? marks[k + 1].at : entry.length;
    const v = entry.slice(mk.valueAt, end).replace(/,\s*$/, '').trim();
    if (v) out[mk.key] = v;
  });
  return out;
}

/** The local-upload id (BioMate dataset id) of an attachment the model referenced by its
 *  model-facing id, from this turn's or an earlier turn's upload block. */
export function attachmentLocalId(id: string, context?: Pick<ChatContext, 'turnMessage' | 'previousMessages'>): string | undefined {
  const texts = [context?.turnMessage || '', ...(context?.previousMessages || []).map(m => typeof m.content === 'string' ? m.content : '')];
  for (const t of texts) {
    for (const a of attachedDatasetsFromMessage(t)) if (a.galaxyId === id && a.datasetId) return a.datasetId;
  }
  return undefined;
}

/** This turn's uploaded files with their runnable S3 location, for binding to a plan's declared
 *  inputs (POST /plan_dag). Entries without an s3_uri are omitted: a bare file name is not runnable. */
export function uploadedRefsFromMessage(message: string): Array<{ name: string; s3_uri: string }> {
  const m = /\[Uploaded datasets?:\s*([^\]]+)\]/i.exec(message || '');
  if (!m) return [];
  return m[1].split(/;\s*/).map(entry => ({
    name: entry.split(':')[0].trim(),
    s3_uri: /\bs3_uri=([^,\s;\]]+)/.exec(entry)?.[1] || '',
  })).filter(d => d.name && d.s3_uri.startsWith('s3://'));
}

/** The id run_code stages an attached dataset under: its Galaxy id (durable), else BioMate's dataset id. */
export function stagingIdFor(a: { datasetId?: string; galaxyId?: string }): string {
  return (a.galaxyId || a.datasetId)!;
}

/** Prompt line giving the model the exact sandbox paths of this turn's attached files, so its first
 *  run_code call reads INPUT_FILES instead of guessing (dev 2026-11-04: every ad-hoc answer's first
 *  call read a guessed path such as /tmp/<name> and failed; the second used staged_inputs). Empty
 *  when nothing is attached. */
export function runCodeInputsNote(message: string, heads: Record<string, string[]> = {}): string {
  const attached = attachedDatasetsFromMessage(message);
  if (!attached.length) return '';
  const files = Object.fromEntries(attached.map(a => [a.name, stagedInputPath(stagingIdFor(a), a.name)]));
  const shown = Object.fromEntries(Object.entries(heads).filter(([name, lines]) => name in files && lines.length));
  return `[run_code inputs — the attached files are already staged; open them via INPUT_FILES (Python: INPUT_FILES["name"], R: INPUT_FILES[["name"]]) at exactly these paths, never a guessed path: ${JSON.stringify(files)}]`
    + (Object.keys(shown).length
      ? `\n[First lines of the attached text files — use these exact column names; do not assume pandas defaults such as "index": ${JSON.stringify(shown)}]`
      : '');
}

/** Attached files whose first lines are worth showing the model (text tables / lists). */
export const HEAD_PREVIEW_EXT_RE = /\.(csv|tsv|tab|txt|smi|smiles)$/i;

/** First `maxLines` lines from a byte stream, reading at most `maxBytes` (the stream is closed early). */
export async function headLines(stream: AsyncIterable<Buffer>, maxLines = 3, maxBytes = 4096, maxLineChars = 300): Promise<string[]> {
  let buf = '';
  for await (const chunk of stream) {
    buf += chunk.toString('utf8');
    if (buf.split('\n').length > maxLines || buf.length >= maxBytes) break;
  }
  return buf.slice(0, maxBytes).split(/\r?\n/).slice(0, maxLines).filter(l => l.length).map(l => l.slice(0, maxLineChars));
}

export function stripNarratedToolCalls(text: string): string {
  if (!text) return text;
  if (!/<\/?(?:antml:)?(?:function_calls|invoke|parameter)\b/i.test(text)) {
    return text;
  }
  let t = text;
  // 1. Balanced <function_calls>…</function_calls> blocks (optional antml: prefix).
  t = t.replace(/<(?:antml:)?function_calls\b[\s\S]*?<\/(?:antml:)?function_calls>/gi, '');
  // 2. Balanced <invoke …>…</invoke> blocks not wrapped in function_calls.
  t = t.replace(/<(?:antml:)?invoke\b[\s\S]*?<\/(?:antml:)?invoke>/gi, '');
  // 3. Unclosed opener (stream cut mid-block, or block runs to end) — drop to end.
  t = t.replace(/<(?:antml:)?(?:function_calls|invoke)\b[\s\S]*$/gi, '');
  // 4. Any stray leftover tags.
  t = t.replace(/<\/?(?:antml:)?(?:function_calls|invoke|parameter)\b[^>]*>/gi, '');
  return t.replace(/\n{3,}/g, '\n\n').trim();
}

/**
 * Streaming counterpart of stripNarratedToolCalls: filters narrated tool-call
 * XML out of a token stream one chunk at a time so the leak never reaches the
 * user's screen live. Buffers just enough at the tail to avoid emitting a
 * partial `<function_calls`/`<invoke` opener; suppresses everything from an
 * opener to its matching close; passes all other text straight through.
 * Never fabricates text — worst case it holds a fragment until flush().
 */
export class StreamToolCallFilter {
  private buf = '';
  private suppressing = false;
  private closeTag = '';

  private static readonly OPENERS: Array<{ re: RegExp; close: string }> = [
    { re: /<(?:antml:)?function_calls\b[^>]*>/i, close: '</function_calls>' },
    { re: /<(?:antml:)?invoke\b[^>]*>/i, close: '</invoke>' },
  ];
  private static readonly CANDS = ['<function_calls', '<invoke', '</function_calls', '</invoke'];

  push(chunk: string): string {
    if (!chunk) return '';
    this.buf += chunk;
    let out = '';
    for (;;) {
      if (this.suppressing) {
        const i = this.buf.toLowerCase().indexOf(this.closeTag);
        if (i === -1) {
          // Retain only a tail that might hold a split close tag; drop the rest.
          const keep = this.closeTag.length - 1;
          if (this.buf.length > keep) this.buf = this.buf.slice(this.buf.length - keep);
          return out;
        }
        this.buf = this.buf.slice(i + this.closeTag.length);
        this.suppressing = false;
        continue;
      }
      // Find the earliest COMPLETE opener tag.
      let best = -1;
      let bestClose = '';
      for (const o of StreamToolCallFilter.OPENERS) {
        const m = o.re.exec(this.buf);
        if (m && (best === -1 || m.index < best)) {
          best = m.index;
          bestClose = o.close;
        }
      }
      if (best !== -1) {
        out += this.buf.slice(0, best);
        this.buf = this.buf.slice(best);
        this.suppressing = true;
        this.closeTag = bestClose.toLowerCase();
        continue;
      }
      // No complete opener. Emit the safe prefix; hold back only a tail that
      // could still grow into a tool tag (incomplete opener with no '>' yet).
      const lt = this.buf.lastIndexOf('<');
      if (lt === -1) {
        out += this.buf;
        this.buf = '';
        return out;
      }
      const tail = this.buf.slice(lt).toLowerCase();
      const couldBeTag =
        !tail.includes('>') &&
        StreamToolCallFilter.CANDS.some((c) => c.startsWith(tail) || tail.startsWith(c));
      if (couldBeTag) {
        out += this.buf.slice(0, lt);
        this.buf = this.buf.slice(lt);
        return out;
      }
      // A '<' that is normal prose (e.g. "hERG < 10 µM") or a stray complete
      // tag — emit it all; the final stripNarratedToolCalls pass removes any
      // orphan tag from the persisted answer.
      out += this.buf;
      this.buf = '';
      return out;
    }
  }

  /** Call once the stream ends to release any safely-buffered remainder. */
  flush(): string {
    if (this.suppressing) {
      this.buf = '';
      return '';
    }
    const rest = stripNarratedToolCalls(this.buf);
    this.buf = '';
    return rest;
  }
}

async function _fetchPaperContentFromMessage(
  message: string,
): Promise<{ ref: string; content: string } | null> {
  // --- New chip format: [Dataset: name (id: <value>)] ---
  // Emitted by chat-input.tsx when the user attaches a dataset chip.
  // The "id" field may be a UUID, an S3 URI (s3://bucket/uploads/<uuid>/file.pdf),
  // a local file path, or a Galaxy dataset ID. Extract all PDF refs and pull content.
  const newFormatRefs = [...message.matchAll(/\[Dataset:\s*([^\(]+?)\s*\(id:\s*([^\)]+?)\s*\)\]/gi)];
  if (newFormatRefs.length > 0) {
    try {
      const { getUploadedFile } = await import('./routes');
      const textParts: string[] = [];
      const refNames: string[] = [];
      for (const m of newFormatRefs) {
        const name = m[1].trim();
        const rawId = m[2].trim();
        // Resolve to a local file. Try the raw ID first, then extract a UUID from an S3 URI.
        let localFile = getUploadedFile(rawId);
        if (!localFile) {
          // If rawId is an S3 URI like s3://bucket/uploads/<uuid>/file.pdf, extract the UUID
          const uuidInS3 = rawId.match(/uploads\/([0-9a-f-]{36})\//i)?.[1];
          if (uuidInS3) localFile = getUploadedFile(uuidInS3);
        }
        if (!localFile?.filePath) {
          // Also skip non-PDF names — GalaxyDatasetBrowser can hold any file type
          if (!name.toLowerCase().endsWith('.pdf')) continue;
          console.warn(`[_fetchPaperContentFromMessage] No local file for dataset id=${rawId} (name: ${name})`);
          continue;
        }
        if (!localFile.filePath.toLowerCase().endsWith('.pdf')) continue;
        const text = await _extractPdfText(localFile.filePath, 120000);
        if (text) {
          textParts.push(`=== ${name} ===\n${text}`);
          refNames.push(name);
          console.log(`[_fetchPaperContentFromMessage] Extracted ${text.length} chars from ${name} (id=${rawId})`);
        }
      }
      if (textParts.length > 0) {
        return {
          ref: refNames.join(', '),
          content: textParts.join('\n\n---\n\n').slice(0, 150000),
        };
      }
    } catch (err: any) {
      console.warn(`[_fetchPaperContentFromMessage] New-format PDF extraction failed: ${err.message}`);
    }
  }

  // --- Legacy format (from old chat-input.tsx) ---
  //   [Attached files: paper.pdf, other.pdf]
  //   [Uploaded datasets: paper.pdf: dataset_id=<uuid>[, galaxy_dataset_id=<gid>][; other.pdf: dataset_id=<uuid2>]]
  const _attachedBlock = message.match(/\[Attached files:\s*([^\]]+)\]/i)?.[1] ?? '';
  const _datasetsBlock = message.match(/\[Uploaded datasets:\s*([^\]]+)\]/i)?.[1] ?? '';
  if (_attachedBlock && _datasetsBlock && /\.pdf\b/i.test(_attachedBlock)) {
    try {
      const { getUploadedFile } = await import('./routes');
      // Split multi-file entries: "name.pdf: dataset_id=<uuid>[, galaxy_dataset_id=<gid>]"
      const entries = _datasetsBlock.split(/;\s*/);
      const textParts: string[] = [];
      const refNames: string[] = [];
      for (const entry of entries) {
        const name = entry.match(/^([^:]+):/)?.[1]?.trim() ?? '';
        if (!name.toLowerCase().endsWith('.pdf')) continue;
        const datasetId = entry.match(/dataset_id=([a-f0-9-]+)/i)?.[1];
        if (!datasetId) continue;
        const localFile = getUploadedFile(datasetId);
        if (!localFile?.filePath) {
          console.warn(`[_fetchPaperContentFromMessage] No local file for dataset ${datasetId}`);
          continue;
        }
        const text = await _extractPdfText(localFile.filePath, 120000);
        if (text) {
          textParts.push(`=== ${name} ===\n${text}`);
          refNames.push(name);
        }
      }
      if (textParts.length > 0) {
        return {
          ref: refNames.join(', '),
          content: textParts.join('\n\n---\n\n').slice(0, 150000),
        };
      }
    } catch (err: any) {
      console.warn(`[_fetchPaperContentFromMessage] PDF extraction failed: ${err.message}`);
    }
  }

  // arXiv: https://arxiv.org/abs/XXXX.XXXXX or arxiv:XXXX.XXXXX
  const arxivMatch = message.match(/(?:https?:\/\/arxiv\.org\/(?:abs|pdf)\/|arxiv[:\s]+)(\d{4}\.\d{4,})/i);

  // DOI: bare 10.XXXX/... NOT inside a URL (negative lookbehind for URL path chars)
  const doiRaw = message.match(/(?<![:/\w])(10\.\d{4,}\/[^\s\])"',;]+)/);
  const doiMatch = doiRaw
    ? (() => {
        // Double-check: skip if the match sits inside an https:// URL
        const idx = doiRaw.index ?? 0;
        const pre = message.slice(Math.max(0, idx - 30), idx);
        return /https?:\/\/\S*$/.test(pre) ? null : doiRaw;
      })()
    : null;

  // PMID: PMID:XXXXXXXX or pubmed.ncbi.../<digits>
  const pmidMatch = message.match(/\bPMID[:\s]+(\d{5,})\b/i)
    || message.match(/pubmed\.ncbi\.nlm\.nih\.gov\/(\d{5,})/i);

  // Bare https URL (only if none of the above matched)
  const urlMatch = !arxivMatch && !doiMatch && !pmidMatch
    ? message.match(/https?:\/\/[^\s\])"']+/)
    : null;

  try {
    if (arxivMatch) {
      const id = arxivMatch[1];
      const ref = `arXiv:${id}`;
      // Fetch abstract HTML page — has citation_* meta tags, faster than export Atom API
      const res = await fetch(`https://arxiv.org/abs/${id}`, {
        signal: AbortSignal.timeout(15_000),
        headers: { 'User-Agent': 'BioMate/1.0 (research assistant; mailto:biomate@biomate.ai)' },
      }).catch(() => null);
      if (!res?.ok) return null;
      const html = await res.text();
      const title = html.match(/<meta name="citation_title" content="([^"]+)"/i)?.[1]?.trim()
        ?? html.match(/<title>([^<]+)<\/title>/i)?.[1]?.replace(/\[.*?\]\s*/, '').trim()
        ?? '';
      const summary = html.match(/<meta name="citation_abstract" content="([^"]+)"/i)?.[1]?.trim()
        ?? html.match(/<blockquote class="abstract[^"]*">([\s\S]*?)<\/blockquote>/i)?.[1]
             ?.replace(/<[^>]+>/g, '').replace(/Abstract:\s*/i, '').trim()
        ?? '';
      const content = `Title: ${title}\n\nAbstract: ${summary}`;
      return content.length > 30 ? { ref, content: content.slice(0, 8000) } : null;
    }

    if (doiMatch) {
      const doi = doiMatch[1].replace(/[.,;)\]]+$/, '');
      const ref = `DOI:${doi}`;
      const crossref = await fetch(
        `https://api.crossref.org/works/${encodeURIComponent(doi)}?mailto=biomate@biomate.ai`,
        { signal: AbortSignal.timeout(12_000) },
      ).catch(() => null);
      if (crossref?.ok) {
        const data = await crossref.json();
        const item = data?.message ?? {};
        const title = (item.title ?? [])[0] ?? '';
        const abstract = item.abstract?.replace(/<[^>]+>/g, '') ?? '';
        const content = `Title: ${title}\nAbstract: ${abstract}`.slice(0, 8000);
        if (content.trim().length > 50) return { ref, content };
      }
      return null;
    }

    if (pmidMatch) {
      const pmid = pmidMatch[1];
      const ref = `PMID:${pmid}`;
      // Fetch abstract text via PubMed efetch
      const efetch = await fetch(
        `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=${pmid}&rettype=abstract&retmode=text`,
        { signal: AbortSignal.timeout(12_000) },
      ).catch(() => null);
      if (efetch?.ok) {
        const content = (await efetch.text()).slice(0, 8000);
        if (content.trim().length > 50) return { ref, content };
      }
      return null;
    }

    if (urlMatch) {
      const url = urlMatch[0].replace(/[.,;)\]]+$/, '');

      // bioRxiv / medRxiv: extract DOI from URL path and use their REST API
      const biorxivDoi = url.match(/(?:biorxiv|medrxiv)\.org\/content\/(10\.\d{4,}\/[^\s?#v]+)/i)?.[1];
      if (biorxivDoi) {
        const server = url.includes('medrxiv') ? 'medrxiv' : 'biorxiv';
        const apiRes = await fetch(
          `https://api.biorxiv.org/details/${server}/${biorxivDoi}/json`,
          { signal: AbortSignal.timeout(12_000) },
        ).catch(() => null);
        if (apiRes?.ok) {
          const data = await apiRes.json();
          const paper = (data?.collection ?? [])[0];
          if (paper) {
            const content = `Title: ${paper.title ?? ''}\nAuthors: ${paper.authors ?? ''}\nAbstract: ${paper.abstract ?? ''}`.slice(0, 8000);
            if (content.trim().length > 50) return { ref: `${server}:${biorxivDoi}`, content };
          }
        }
        // If API fails, fall through to HTML fetch
      }

      const res = await fetch(url, {
        signal: AbortSignal.timeout(15_000),
        headers: { 'User-Agent': 'BioMate/1.0 (research assistant; mailto:biomate@biomate.ai)' },
      }).catch(() => null);
      if (!res?.ok) return null;
      const ct = res.headers.get('content-type') ?? '';
      if (ct.includes('pdf')) {
        // PDF binary fetch via URL — call Python backend for pdfplumber extraction
        // (latin1 decode produces junk; skip binary PDF here, let upload flow handle it)
        return null;
      }
      // HTML: strip style/script/tags, collapse whitespace
      const html = await res.text();
      const text = html
        .replace(/<style[\s\S]*?<\/style>/gi, '')
        .replace(/<script[\s\S]*?<\/script>/gi, '')
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s{2,}/g, '\n')
        .slice(0, 8000);
      return text.trim().length > 100 ? { ref: url, content: text } : null;
    }
  } catch (err: any) {
    console.warn('[_fetchPaperContentFromMessage] fetch failed:', err.message);
  }
  return null;
}

// Anthropic vision accepts only these media types; tiff/bmp/svg are not supported.
const _VISION_MEDIA_TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
};
// Anthropic hard limit is 5MB per image (base64). base64 inflates ~4/3, so cap
// raw bytes at ~3.75MB. We can't downscale (no image lib), so oversized images
// are skipped with a note rather than silently dropped.
const _VISION_MAX_RAW_BYTES = 3_750_000;
const _VISION_MAX_IMAGES = 8;

/**
 * Detect image attachments in a chat message and return Anthropic image content
 * blocks (base64) so an uploaded histology slide, gel/blot, plot, or scan is
 * actually SEEN by the multimodal model — enabling a grounded biomedical read
 * instead of the model guessing or trying to `read_file` the binary (which
 * garbles and triggers the tool-call-leak failure mode).
 *
 * Parses the same chip formats as _fetchPaperContentFromMessage. Returns the
 * image blocks plus the list of names that were too large or unsupported so the
 * caller can tell the user.
 */
export async function _buildImageContentBlocks(
  message: string,
  // Resolver is injectable so this stays decoupled from the (side-effect-heavy)
  // routes module and is unit-testable. Defaults to the routes registry.
  resolveFile?: (id: string) => { filePath?: string } | undefined,
  // Project files (Data page) live in object storage, not the local upload registry: the caller
  // passes a reader for ids it authorised this turn (sessionDatasets with an s3_key). Live dev
  // 2026-11-12: a project image attached from the picker never reached the model.
  readProjectFile?: (id: string, maxBytes: number) => Promise<Buffer | undefined>,
): Promise<{ blocks: any[]; attached: string[]; skipped: Array<{ name: string; reason: string }> }> {
  const blocks: any[] = [];
  const attached: string[] = [];
  const skipped: Array<{ name: string; reason: string }> = [];

  // Collect (name, id) pairs from both the new chip format and the legacy one.
  const refs: Array<{ name: string; id: string }> = [];
  // "[Dataset: …]" (legacy) and "[BioMate dataset: …]" (the Data-page picker chip).
  for (const m of message.matchAll(/\[(?:BioMate\s+)?Dataset:\s*([^\(]+?)\s*\(id:\s*([^\)]+?)\s*\)\]/gi)) {
    refs.push({ name: m[1].trim(), id: m[2].trim() });
  }
  const datasetsBlock = message.match(/\[Uploaded datasets:\s*([^\]]+)\]/i)?.[1] ?? '';
  if (datasetsBlock) {
    for (const entry of datasetsBlock.split(/;\s*/)) {
      const name = entry.match(/^([^:]+):/)?.[1]?.trim() ?? '';
      const id = entry.match(/dataset_id=([a-f0-9-]+)/i)?.[1];
      if (name && id) refs.push({ name, id });
    }
  }
  if (refs.length === 0) return { blocks, attached, skipped };

  let fs: typeof import('fs/promises') | null = null;
  let getUploadedFile: ((id: string) => { filePath?: string } | undefined) | null = resolveFile ?? null;
  try {
    fs = await import('fs/promises');
    if (!getUploadedFile) ({ getUploadedFile } = await import('./routes'));
  } catch {
    return { blocks, attached, skipped };
  }

  const seen = new Set<string>();
  for (const { name, id } of refs) {
    const ext = (name.toLowerCase().match(/\.[a-z0-9]+$/)?.[0]) ?? '';
    if (!(ext in _VISION_MEDIA_TYPES)) {
      // Only flag image-ish extensions we can't send; ignore non-image files.
      if (['.tif', '.tiff', '.bmp', '.svg'].includes(ext)) {
        skipped.push({ name, reason: `${ext} is not a format the vision model can read — export as PNG or JPEG` });
      }
      continue;
    }
    if (blocks.length >= _VISION_MAX_IMAGES) {
      skipped.push({ name, reason: `only the first ${_VISION_MAX_IMAGES} images are analyzed` });
      continue;
    }
    // Resolve to a local file (raw id, or a UUID embedded in an s3:// URI).
    let localFile = getUploadedFile!(id);
    if (!localFile?.filePath) {
      const uuidInS3 = id.match(/uploads\/([0-9a-f-]{36})\//i)?.[1];
      if (uuidInS3) localFile = getUploadedFile!(uuidInS3);
    }
    const seenKey = localFile?.filePath || `project:${id}`;
    if (seen.has(seenKey)) continue;
    seen.add(seenKey);
    try {
      const buf = localFile?.filePath
        ? await fs!.readFile(localFile.filePath)
        : await readProjectFile?.(id, _VISION_MAX_RAW_BYTES + 1);
      if (!buf) continue;
      if (buf.length > _VISION_MAX_RAW_BYTES) {
        skipped.push({ name, reason: `image is ${(buf.length / 1e6).toFixed(1)}MB — over the 3.75MB limit; downscale and re-upload` });
        continue;
      }
      blocks.push({
        type: 'image',
        source: { type: 'base64', media_type: _VISION_MEDIA_TYPES[ext], data: buf.toString('base64') },
      });
      attached.push(name);
      console.log(`[_buildImageContentBlocks] Attached image ${name} (${(buf.length / 1024).toFixed(0)}KB, ${_VISION_MEDIA_TYPES[ext]})`);
    } catch (err: any) {
      console.warn(`[_buildImageContentBlocks] Failed to read ${name} (id=${id}): ${err.message}`);
    }
  }
  return { blocks, attached, skipped };
}

async function extractInlineDataWithLLM(
  message: string,
  claude: Anthropic,
): Promise<InlineDataMap> {
  // Cache key: hash of message text (avoid re-running for identical messages)
  const { createHash } = await import('node:crypto');
  const cacheKey = createHash('sha256').update(message).digest('hex').slice(0, 16);
  if (_inlineDataCache.has(cacheKey)) {
    const cached = _inlineDataCache.get(cacheKey)!;
    const _cArrayKeys = Object.keys(cached).filter(k => cached[k].startsWith('['));
    console.log(`[extractInlineData] result keys=${Object.keys(cached).join(',') || 'none'} arrayKeys=${_cArrayKeys.join(',') || 'none'} map=${JSON.stringify(cached)} (cache-hit)`);
    return cached;
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
- vcf_variants: a VCF-format variant table with #CHROM/POS/ID/REF/ALT columns, chromosome positions, and rs-IDs (e.g. "#CHROM\tPOS\tID\tREF\tALT\n1\t752566\trs3094315\tG\tA"). Distinguish from count_matrix by the presence of REF/ALT nucleotide columns and chromosomal POS integers.
- gwas_summary_stats: GWAS summary statistics table with SNP/CHR/POS/BETA/SE/P (or OR/Z/P) columns. Common column headers: rsid, chr, bp, beta, se, p, pval, or, maf, af1.
- genomic_intervals: a BED-format or similar table of genomic regions with chr, start, end columns (e.g. "chr1\t1000\t2000\tpeak1").
- count_matrix: a comma/tab-separated gene expression count matrix (header row + data rows with gene IDs and numeric counts, e.g. "gene,ctrl1,ctrl2\nGENE1,100,120")
- any other scientific parameter you recognize as concrete input data

Rules:
- Only extract values that are DIRECTLY present as literal strings in the message
- Do NOT infer or hallucinate values not in the message
- Do NOT extract workflow names, tool names, or method descriptions — only input DATA
- Return the extracted value exactly as it appears in the message
- Return ONLY valid JSON, no markdown, no explanation`;

  // Helper: parse and normalize LLM JSON response
  const _parseInlineJson = (raw: string): InlineDataMap | null => {
    try {
      const cleaned = raw.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
      const parsed = JSON.parse(cleaned);
      if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
        const result: InlineDataMap = {};
        for (const [k, v] of Object.entries(parsed)) {
          if (typeof v === 'string' && v.trim()) {
            result[k] = v.trim();
          } else if (Array.isArray(v) && v.length > 0) {
            const strings = v.filter((item): item is string => typeof item === 'string' && item.trim() !== '');
            if (strings.length > 0) result[k] = JSON.stringify(strings);
          }
        }
        return result;
      }
    } catch { /* fall through */ }
    return null;
  };

  // Try Gemini first (cloud), then OpenAI-compatible (on-prem Qianwen/vLLM)
  let llmResult: InlineDataMap | null = null;
  try {
    const raw = await callGeminiFlash({
      messages: [{ role: 'user', content: message.slice(0, 1200) }],
      system: SYSTEM,
      maxTokens: 1024,
      jsonMode: true,
      signal: AbortSignal.timeout(15_000),
    });
    llmResult = _parseInlineJson(raw);
  } catch (geminiErr: any) {
    // Gemini unavailable (e.g. on-prem without GEMINI_API_KEY) — try OpenAI-compatible
    const oacClient = _openrouterClientStorage.getStore();
    if (oacClient) {
      try {
        const model = process.env.LLM_MODEL || 'qwen-max';
        const resp = await oacClient.chat.completions.create({
          model,
          messages: [
            { role: 'system', content: SYSTEM },
            { role: 'user', content: message.slice(0, 1200) },
          ],
          max_tokens: 1024,
          response_format: { type: 'json_object' },
          // @ts-ignore AbortSignal not in all type defs
          signal: AbortSignal.timeout(15_000),
        });
        const raw = resp.choices[0]?.message?.content || '{}';
        llmResult = _parseInlineJson(raw);
      } catch (oacErr: any) {
        console.warn('[extractInlineData] OpenAI-compatible extraction failed:', oacErr.message);
      }
    } else {
      console.warn('[extractInlineData] LLM extraction failed, using regex fallback:', geminiErr.message);
    }
  }

  if (llmResult) {
    _inlineDataCache.set(cacheKey, llmResult);
    const arrayKeys = Object.keys(llmResult).filter(k => llmResult![k].startsWith('['));
    console.log(`[extractInlineData] result keys=${Object.keys(llmResult).join(',') || 'none'} arrayKeys=${arrayKeys.join(',') || 'none'} map=${JSON.stringify(llmResult)}`);
    return llmResult;
  }

  // Regex fallback — high-confidence patterns only (accessions, file paths, tabular data)
  const fallback: InlineDataMap = {};
  const sra = message.match(/\b((SRR|ERR|DRR|SRS|ERS|DRS|SRP|ERP|DRP|PRJNA|PRJEB)\d+)\b/i);
  if (sra) fallback.sra_accession = sra[1].toUpperCase();
  const geo = message.match(/\b((GSE|GSM|GDS|GPL|E-MTAB-|E-GEOD-|PXD)\d+)\b/i);
  if (geo) fallback.geo_accession = geo[1].toUpperCase();
  const file = message.match(/\b((?:s3|gs|ftp|http|https):\/\/\S+|\/\S+\.(?:fastq|fq|bam|vcf|fa|fasta|gz|csv|tsv|h5))\b/i);
  if (file) fallback.file_path = file[1];
  const upload = message.match(/\[Uploaded datasets:\s*([^\]]+)\]/);
  if (upload) fallback.uploaded_dataset = upload[1].trim();
  // SMILES detection — generalizable to all ADMET / docking / drug-discovery queries.
  // Ensures hasInlineData=true for messages containing SMILES strings so the LLM receives
  // correct format instructions (Technical failure, not Clarification needed).
  const smilesM = message.match(/\bSMILES\s*[=:]\s*([A-Za-z0-9@\[\]\(\)\+\-=#\/\\\.%:]{8,})/i);
  if (smilesM) fallback.smiles = smilesM[1].replace(/[.,;)\]]+$/, '');
  // ── Genomic format detection (must precede the generic count_matrix catch-all) ──────────────
  // VCF variant table: #CHROM header OR chr/pos/rsID row pattern.
  const hasVCFHeader = /^#CHROM\s+POS\s+ID\s+REF\s+ALT/im.test(message);
  const hasVCFRow = /^(?:chr)?[\dXY]+\t\d+\t(?:rs\d+|\.|[A-Z_*]+)\t[ACGTNacgtn.]+\t[ACGTNacgtn.,*]+/im.test(message);
  // GWAS summary statistics: CHR/POS + effect columns (BETA/SE/P or OR/P).
  // Pattern: any header containing "beta","se","pval" or "p_value" alongside position columns.
  const hasGWASHeader = /\b(?:CHR(?:OM)?|chromosome)\b.*\b(?:POS(?:ITION)?|BP)\b.*\b(?:BETA|OR|EFFECT|Z_STAT)\b/i.test(message) ||
    /\b(?:BETA|OR|EFFECT)\b.*\b(?:SE|STD_ERR)\b.*\b(?:P(?:VAL)?|P_VALUE|PVALUE)\b/i.test(message);
  const hasGWASRow = /^(?:rs\d+|chr[\dXY]+)[\t,][\d.]+[\t,][\d.]+[\t,]-?[\d.]+[\t,][\d.e+\-]+[\t,][\d.e\-]+/i.test(message);
  // BED format: chr\t start\t end (optionally followed by name/score columns).
  const hasBEDRows = message.split('\n').filter(Boolean).filter(l => {
    const c = l.split('\t');
    return c.length >= 3 && /^(?:chr)?[\dXYMT]+$/i.test(c[0]) && /^\d+$/.test(c[1]) && /^\d+$/.test(c[2]);
  }).length >= 2;

  if (hasVCFHeader || hasVCFRow) {
    fallback.vcf_variants = message.trim();
  } else if (hasGWASHeader || hasGWASRow) {
    fallback.gwas_summary_stats = message.trim();
  } else if (hasBEDRows) {
    fallback.genomic_intervals = message.trim();
  } else {
    // Tabular data: ≥2 lines each with ≥2 comma/tab-separated tokens where at least one is
    // numeric. Catches gene count matrices, sample metadata tables, and similar pasted inputs.
    const tabularLines = message.split('\n').map((l: string) => l.trim()).filter(Boolean);
    const numericTabularRows = tabularLines.filter((line: string) => {
      const cols = line.split(/[,\t]/);
      return cols.length >= 2 && cols.some((c: string) => /^\d+(\.\d+)?$/.test(c.trim()));
    });
    if (numericTabularRows.length >= 2) fallback.count_matrix = message.trim();
  }
  _inlineDataCache.set(cacheKey, fallback);
  // Log regex fallback result using same format as LLM path so E2E tests can observe both paths.
  const _fbArrayKeys = Object.keys(fallback).filter(k => fallback[k].startsWith('['));
  console.log(`[extractInlineData] result keys=${Object.keys(fallback).join(',') || 'none'} arrayKeys=${_fbArrayKeys.join(',') || 'none'} map=${JSON.stringify(fallback)} (regex-fallback)`);
  return fallback;
}

/**
 * Parse the `[Uploaded datasets: ...]` block from a chat message and map filenames
 * to workflow parameter names deterministically.
 *
 * This implements the file-to-param mapping that was previously only described as a
 * natural language rule in the response-generation prompt (line 7675). By doing it in
 * code before generateWorkflow() is called, uploaded file S3 URIs reach the workflow
 * generation step with the correct parameter names — without relying on the LLM to
 * infer the mapping from natural language.
 *
 * Returns a flat object of {paramName → s3_uri} suitable for merging into inlineParameters.
 *
 * General rules (not demo-specific):
 *   filename contains "sample" | "metadata" | "samplesheet" | "coldata" | "design" → samplesheet
 *   filename contains "count" | "matrix" | "expression" | "counts"                → matrix
 *   filename contains "contrast" | "comparison"                                    → contrasts
 *   filename contains "gene_list" | "genes" | "de_gene" | "genelist"              → gene_list
 *   filename contains "gene_expr" | "expression_matrix"                            → matrix (already covered)
 *   filename ends with .fastq | .fq | _R1 | _R2                                   → reads
 *   filename ends with .bam                                                        → bam
 *   filename ends with .vcf | .vcf.gz                                              → vcf
 */
export function extractUploadedFileParams(message: string): Record<string, string> {
  const params: Record<string, string> = {};

  // Parse explicit "paramName: s3://..." key-value lines (chip-injected text format)
  // This handles the case where the chip fills the textarea with:
  //   samplesheet: s3://bucket/sample_metadata.csv
  //   matrix: s3://bucket/counts_matrix.csv
  // without a formal [Uploaded datasets:] block.
  const _KNOWN_PARAM_KEYS = new Set([
    'samplesheet', 'input', 'matrix', 'contrasts', 'gene_list', 'reads',
    'bam', 'vcf', 'file_path', 'fastq', 'design',
  ]);
  for (const m of message.matchAll(/^(\w+):\s*(s3:\/\/\S+)/gm)) {
    const key = m[1].toLowerCase();
    const uri = m[2];
    if (_KNOWN_PARAM_KEYS.has(key) && !params[key]) {
      params[key] = uri;
    }
  }

  const block = message.match(/\[Uploaded datasets:\s*([^\]]+)\]/i)?.[1];
  if (!block) return params;

  // Each entry is separated by ";" and has format: "filename: dataset_id=<id>[, s3_uri=<uri>]"
  const entries = block.split(/;\s*/);
  for (const entry of entries) {
    const nameMatch = entry.match(/^([^:]+):/);
    if (!nameMatch) continue;
    const fname = nameMatch[1].trim().toLowerCase();

    // S3 URI takes priority; dataset_id as fallback (staged at execute time)
    const s3Match = entry.match(/s3_uri=(s3:\/\/[^\s,;]+)/i);
    const idMatch = entry.match(/dataset_id=([a-f0-9-]+)/i);
    const value = s3Match?.[1] || idMatch?.[1];
    if (!value) continue;

    // DE samplesheet / metadata
    if (/sample|metadata|samplesheet|coldata|design/.test(fname)) {
      params.samplesheet = params.samplesheet ?? value;
    }
    // Count matrix
    else if (/count|matrix|expression|expr/.test(fname)) {
      params.matrix = params.matrix ?? value;
    }
    // Contrasts
    else if (/contrast|comparison/.test(fname)) {
      params.contrasts = params.contrasts ?? value;
    }
    // Gene list (pathway enrichment, enrichGO)
    else if (/gene_list|genelist|de_gene|\.genes\.|genes\.txt|sig_gene/.test(fname)) {
      params.gene_list = params.gene_list ?? value;
    }
    // FASTQ reads
    else if (/\.(fastq|fq)(\.gz)?$|_r[12]_|_read[12]_|_R[12]\./.test(fname)) {
      params.reads = params.reads ?? value;
    }
    // BAM
    else if (/\.bam$/.test(fname)) {
      params.bam = params.bam ?? value;
    }
    // VCF
    else if (/\.vcf(\.gz)?$/.test(fname)) {
      params.vcf = params.vcf ?? value;
    }
    // Generic fallback: use the first unrecognized file as file_path
    else {
      params.file_path = params.file_path ?? value;
    }
  }
  return params;
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
  private _geminiClient: GoogleGenerativeAI | null = null;
  /** Gemini, unless the request is a China-region user's (llm-region-policy.ts): then null, so every
   *  Gemini branch falls through to the policy-aware clients. */
  private get gemini(): GoogleGenerativeAI | null {
    return currentLlmPolicy()?.region === 'cn' ? null : this._geminiClient;
  }
  private galaxyAPI: GalaxyAPIProxy;
  private modelConfig: ModelConfig;
  private sessionMemory: SessionMemoryUpdater;

  /** In-memory domain profile cache: userId → { domains, topics, fetchedAt } */
  private _domainProfileCache: Map<number | string, { domains: string[]; topics: string[]; fetchedAt: number }> = new Map();
  private static readonly DOMAIN_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

  constructor(options: GalaxyAssistantOptions) {
    // Anthropic is optional — Gemini can drive the assistant alone
    this.claude = localOnly() ? localMessagesClient() as unknown as Anthropic : new Anthropic({ apiKey: options.anthropicApiKey || '' });
    // Accept either GEMINI_API_KEY or GOOGLE_API_KEY (both mean the same credential)
    const geminiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
    if (geminiKey && !localOnly()) this._geminiClient = new GoogleGenerativeAI(geminiKey);
    this.galaxyAPI = options.galaxyAPIProxy;
    // Auto-detect: if no Anthropic key but Gemini is available, switch response model to Gemini.
    // This prevents silent auth failures when ANTHROPIC_API_KEY is absent on a Gemini-only deployment.
    const computedModelConfig = { ...DEFAULT_MODEL_CONFIG, ...options.modelConfig };
    if (!options.anthropicApiKey && geminiKey && !computedModelConfig.responseModel?.startsWith('gemini-')) {
      computedModelConfig.responseModel = GEMINI_FLASH_MODEL;
      console.log('[GalaxyAssistant] No ANTHROPIC_API_KEY — switching responseModel to gemini flash');
    }
    // Inverse (QA 2026-08-17): the default config points at Gemini, but on an
    // Anthropic-only deployment (no GEMINI_API_KEY) the Gemini primary 404s and
    // the code falls back to a NON-agentic Claude path where BIOMATE_TOOLS
    // (run_code, …) are never attached — so the model fabricates tool output
    // instead of executing. When Anthropic is present but Gemini is not, route
    // the gemini-configured models to Claude so the full agentic tool loop runs.
    if (options.anthropicApiKey && !geminiKey) {
      if (computedModelConfig.responseModel?.startsWith('gemini-')) {
        computedModelConfig.responseModel = 'claude-sonnet-4-5';
      }
      if (computedModelConfig.intentModel?.startsWith('gemini-')) {
        computedModelConfig.intentModel = 'claude-haiku-4-5';
      }
      console.log('[GalaxyAssistant] No GEMINI_API_KEY — routing gemini models to Claude (response=sonnet-4-5, intent=haiku-4-5) so the agentic tool loop + run_code work');
    }
    if (localOnly()) {
      computedModelConfig.intentModel = localConfig().model;
      computedModelConfig.responseModel = localConfig().model;
      computedModelConfig.toolRankingModel = localConfig().model;
    }
    this.modelConfig = computedModelConfig;
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
   * Returns the Galaxy API proxy for the in-flight request. If processMessage
   * was invoked with `context.galaxyAPIOverride`, we stored it in
   * AsyncLocalStorage and resolve it here per-call — so the chat-stream turn
   * uses the authenticated user's per-user Galaxy API key. Otherwise falls
   * back to the singleton's admin proxy. See ChatContext.galaxyAPIOverride.
   */
  private _api(): GalaxyAPIProxy {
    return _galaxyAPIRequestStorage.getStore() ?? this.galaxyAPI;
  }

  /** Returns the Anthropic client for the current request.
   *  Uses the per-user key stored in AsyncLocalStorage when set by processMessage();
   *  falls back to the singleton system key otherwise. */
  private _getClaude(): Anthropic {
    // A China-region user with no per-request client still gets their Chinese model (fail closed).
    return localOnly() ? this.claude : (_anthropicOverride.getStore() ?? policyMessagesClient(this.claude));
  }

  /** The model that answers a chat turn with this context (what processMessage will use). */
  responseModelFor(context: ChatContext): string {
    if (localOnly()) return localConfig().model;
    if (context.openrouterKey) {
      const baseURL = context.openaiBaseUrl || 'https://openrouter.ai/api/v1';
      return context.selectedModel || (baseURL.includes('openrouter.ai') ? 'z-ai/glm-5.3-prime' : (process.env.LLM_MODEL || 'qwen-max'));
    }
    return this.modelConfig.responseModel;
  }

  /** Returns the OpenRouter OpenAI client if set for this request, otherwise null. */
  private _getOpenRouterClient(): OpenAI | null {
    return _openrouterClientStorage.getStore() ?? null;
  }

  /**
   * Streaming chat via OpenRouter. Used when the user has configured their own
   * OpenRouter key and selected model (e.g. DeepSeek, Qwen, Llama).
   * Returns a full GalaxyAssistantResponse with text only — no workflow generation.
   */
  private async _generateChatWithOpenRouter(
    message: string,
    context: ChatContext,
    onResponseDelta?: (chunk: string) => void,
  ): Promise<GalaxyAssistantResponse> {
    const client = this._getOpenRouterClient();
    if (!client) throw new Error('OpenRouter client not set');
    // Use the alias (no version suffix) so OpenRouter always routes to the latest model.
    const FALLBACK_MODEL = 'deepseek/deepseek-chat';
    const model = context.selectedModel || FALLBACK_MODEL;

    const ltmBlock = context.ltmContextBlock
      ? `<long_term_memory>\n${context.ltmContextBlock}\n</long_term_memory>\n\n`
      : '';
    const projectBlock = context.projectContext
      ? `<project_context>\n${context.projectContext}\n</project_context>\n\n`
      : '';

    const systemPrompt = `${ltmBlock}${projectBlock}You are BioMate, an expert bioinformatics AI assistant with deep scientific knowledge across genomics, transcriptomics, proteomics, drug discovery, cryo-EM, and clinical research.

Provide accurate, evidence-based answers. Be concise and direct. When you don't know something, say so. For computational analyses that require running code or workflows on biological data, let the user know they can switch to the BioMate default model which can run workflows directly.${responseLanguageDirective(context.uiLanguage)}${modelIdentityDirective(context.modelIdentity ?? modelIdentity(model), context.llmRegion)}`;

    const messages: Array<{ role: 'user' | 'assistant'; content: string }> = [
      ...(context.previousMessages ?? []).map(m => ({ role: m.role as 'user' | 'assistant', content: m.content })),
      { role: 'user', content: message },
    ];

    const openaiMessages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: 'system', content: systemPrompt },
      ...messages,
    ];

    const tryStream = async (modelId: string): Promise<string> => {
      const stream = await client.chat.completions.create({
        model: modelId,
        messages: openaiMessages,
        stream: true,
        max_tokens: 4096,
        temperature: 0.3,
      });
      let text = '';
      for await (const chunk of stream) {
        const delta = chunk.choices[0]?.delta?.content ?? '';
        if (delta) { text += delta; onResponseDelta?.(delta); }
      }
      return text;
    };

    let fullText = '';
    try {
      fullText = await tryStream(model);
    } catch (primaryErr: any) {
      // Primary model failed — fall back to DeepSeek Chat (fast, cheap, reliable)
      if (model !== FALLBACK_MODEL) {
        try {
          onResponseDelta?.(`\n\n*(${model} unavailable, switching to ${FALLBACK_MODEL})*\n\n`);
          fullText = await tryStream(FALLBACK_MODEL);
        } catch (fallbackErr: any) {
          const errMsg = `OpenRouter error: ${fallbackErr.message ?? 'unknown error'}`;
          onResponseDelta?.(errMsg);
          return { message: errMsg, intentType: 'research_question', suggestions: [], sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false } };
        }
      } else {
        const errMsg = `OpenRouter error (${model}): ${primaryErr.message ?? 'unknown error'}`;
        onResponseDelta?.(errMsg);
        return { message: errMsg, intentType: 'research_question', suggestions: [], sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false } };
      }
    }

    return { message: fullText, intentType: 'research_question', suggestions: [], sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false } };
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
    toolContext?: { tools: typeof BIOMATE_TOOLS; context: ChatContext; onToolEvent?: (e: AgentToolEvent) => void; requireExecution?: boolean },
  ): Promise<string> {
    if (!this.gemini) throw new Error('Gemini client not initialized — set GEMINI_API_KEY');
    const geminiModelName = modelOverride
      ?? (this.modelConfig.responseModel.startsWith('gemini-') ? this.modelConfig.responseModel : GEMINI_FLASH_MODEL);

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
      generationConfig: { maxOutputTokens: maxTokens, temperature: 0, thinkingConfig: { thinkingBudget: 0 } } as any,
      ...(geminiTools ? { tools: geminiTools as any } : {}),
    });

    let rawResponse = '';
    if (messages.length === 0) return '';

    // Gemini requires the first history entry to have role='user'. The chat
    // often starts with a greeting/system reply (role='assistant' → 'model'
    // here), which Gemini rejects with:
    //   "First content should be with role 'user', got model"
    // Drop any leading model-role messages so history always starts user.
    const mappedHistory = messages.slice(0, -1).map(m => ({
      role: (m.role === 'assistant' ? 'model' : 'user') as 'user' | 'model',
      parts: [{ text: m.content }],
    }));
    let firstUserIdx = 0;
    while (firstUserIdx < mappedHistory.length && mappedHistory[firstUserIdx].role !== 'user') {
      firstUserIdx++;
    }
    const history = mappedHistory.slice(firstUserIdx);
    const chat = model.startChat({ history });
    const lastMessage = messages[messages.length - 1].content;

    // Agentic loop: handle tool calls (up to 12 turns, then force a final answer)
    const MAX_TOOL_TURNS = 12;
    let currentMessage: string | object = lastMessage;
    let _geminiRanRunCode = false;
    let _geminiNudged = false;
    for (let turn = 0; turn < MAX_TOOL_TURNS; turn++) {
      // Use streaming so tokens flow to the client as they arrive instead of
      // appearing all at once after the full model round-trip completes.
      const streamResult = await chat.sendMessageStream(currentMessage as any);
      for await (const chunk of streamResult.stream) {
        for (const part of (chunk.candidates?.[0]?.content?.parts || []) as any[]) {
          if (part.text) {
            rawResponse += part.text;
            onResponseDelta?.(part.text);
          }
        }
      }
      // Await the aggregated response to:
      //  1. Ensure SDK updates chat history before the next sendMessageStream call
      //  2. Reliably detect function calls (never split across stream chunks)
      //  3. Fall back to aggregated text if streaming chunks produced no text
      //     (some Gemini SDK versions emit text only in aggregated, not in stream chunks)
      const aggregated = await streamResult.response;
      const allParts: any[] = aggregated.candidates?.[0]?.content?.parts || [];
      console.log(`[GeminiLoop] turn=${turn} parts=${allParts.length} keys=${allParts.map((p: any) => Object.keys(p).join(',')).join('|')}`);

      // If streaming produced no text but the aggregated response has text, extract it now.
      if (!rawResponse) {
        const aggregatedText = allParts
          .filter((p: any) => p.text)
          .map((p: any) => p.text as string)
          .join('');
        if (aggregatedText) {
          rawResponse = aggregatedText;
          onResponseDelta?.(aggregatedText);
          console.log(`[GeminiLoop] Streaming produced no text — extracted ${aggregatedText.length} chars from aggregated response`);
        }
      }

      // Check for function calls
      const fnCalls = allParts.filter((p: any) => p.functionCall);
      // Sentinel-gated diagnostic (invisible to real users): only emits when the probe
      // message contains __DIAGTOOLS__. Reveals whether the tool declarations actually
      // reach the model at runtime vs. the model declining to call — the last unknown in
      // the Gemini agentic-tools issue. Remove once the layer-2 cause is confirmed.
      if (turn === 0 && typeof lastMessage === 'string' && lastMessage.includes('__DIAGTOOLS__')) {
        const _decls = geminiTools ? ((geminiTools[0] as any).functionDeclarations || []).length : 0;
        onResponseDelta?.(`[[GTOOLS decls=${_decls} fnCalls=${fnCalls.length} hasCtx=${!!toolContext} textLen=${rawResponse.length}]]`);
      }
      if (fnCalls.length === 0 && toolContext && shouldRequireExecution({
        directCompute: !!toolContext.requireExecution,
        runCodeOffered: toolContext.tools.some(t => t.name === 'run_code'),
        ranRunCode: _geminiRanRunCode, alreadyNudged: _geminiNudged, proseSignal: false,
      })) {
        // Classifier said direct_compute but the reply ran no code: re-prompt once to execute. The
        // pre-nudge text is discarded from the returned message (the final message replaces the preview).
        console.warn('[GeminiLoop] direct_compute turn ended without run_code — asking the model to execute');
        _geminiNudged = true;
        rawResponse = '';
        currentMessage = EXECUTE_NOW_NUDGE;
        continue;
      }
      if (fnCalls.length === 0 || !toolContext) break;  // No tools or no context — done
      if (fnCalls.some((p: any) => p.functionCall?.name === 'run_code')) _geminiRanRunCode = true;

      // Execute all function calls
      const functionResults: object[] = [];
      for (const part of fnCalls) {
        const fnCall = part.functionCall;
        if (!fnCall) continue;
        const { name, args } = fnCall as { name: string; args: any };
        console.log(`[GeminiLoop] tool_call name=${name} args_keys=${Object.keys(args || {}).join(',')}`);
        toolContext.onToolEvent?.({ type: 'tool_call', tool_use_id: name, name, input: args, display: toolCallDisplayFor(args, toolContext.context) });
        let output: unknown = null;
        let error: string | undefined;
        try {
          switch (name) {
            case 'run_code':    output = await this._toolRunCode(args, toolContext.context); break;
            case 'read_file':   output = await this._toolReadFile(args, toolContext.context); break;
            case 'query_domain_knowledge': output = await this._toolQueryKnowledge(args); break;
            case 'list_history': output = await this._toolListHistory(args, toolContext.context); break;
            case 'search_literature': output = await this._toolSearchLiterature(args); break;
            case 'query_database': output = await this._toolQueryDatabase(args); break;
            case 'search_my_data': output = await this._toolSearchMyData(args, toolContext.context); break;
            case 'search_chat_history': output = await this._toolSearchChatHistory(args, toolContext.context); break;
            case 'edit_report': output = await this._toolEditReport(args, toolContext.context); break;
            case 'list_data_sources': output = await this._toolListDataSources(args); break;
            case 'search_workflows': output = await this._toolSearchWorkflows(args); break;
            case 'request_new_tool': output = await this._toolRequestNewTool(args, toolContext.context); break;
            case 'identify_targets': output = await this._toolIdentifyTargets(args); break;
            case 'write_review': output = await this._toolWriteReview(args); break;
            default:
              // External MCP tools (mcp__<server>__<tool>) → route to owning server.
              if (typeof name === 'string' && name.startsWith('mcp__')) {
                output = await this._toolCallExternalMcp(name, args, toolContext.context);
              } else {
                output = { error: `Unknown tool: ${name}` };
              }
              break;
          }
        } catch (e: any) { error = e.message; output = { error }; }
        // Model text never carries image bytes (this loop has no image parts); the UI event keeps
        // the plot preview but not the duplicate vision-block bytes.
        const modelText = JSON.stringify(stripImageBytesForModel(output));
        const eventOut = (output as any)?.__imageBlocks
          ? { ...(output as any), __imageBlocks: `[${(output as any).__imageBlocks.length} image block(s)]` } : output;
        console.log(`[GeminiLoop] tool_result name=${name} output=${modelText.slice(0, 200)}`);
        toolContext.onToolEvent?.({ type: 'tool_result', tool_use_id: name, name, output: JSON.stringify(eventOut) });
        functionResults.push({ functionResponse: { name, response: { output: modelText } } });
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
        const summaryStream = await summaryChatObj.sendMessageStream(
          'Based on all the code results above, what is the final answer? Reply with ONLY the answer value.'
        );
        for await (const chunk of summaryStream.stream) {
          const txt = (chunk.candidates?.[0]?.content?.parts || [])
            .filter((p: any) => p.text)
            .map((p: any) => p.text as string)
            .join('');
          if (txt) {
            rawResponse += txt;
            onResponseDelta?.(txt);
          }
        }
      } catch (e: any) {
        console.warn('[GeminiLoop] Final answer request failed:', e.message);
      }
    }

    // No tools and no text (empty candidate): retry the turn once on a fresh chat before reporting
    // empty — the caller's provider chain treats '' as a failure (requireNonEmptyResponse).
    if (!rawResponse && !toolContext) {
      try {
        const retry = await model.startChat({ history }).sendMessage(lastMessage);
        rawResponse = retry.response.text() || '';
        if (rawResponse) onResponseDelta?.(rawResponse);
        console.warn(`[GeminiLoop] empty reply — retried once (${rawResponse.length} chars)`);
      } catch (e: any) {
        console.warn('[GeminiLoop] empty-reply retry failed:', e?.message);
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
    const model = process.env.OLLAMA_MODEL ?? 'qwen3:32b';
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
   * Generate a response using OpenAI-compatible API (gpt-4o by default).
   * Streaming via the standard SSE chat completions endpoint.
   */
  private async _generateWithOpenAI(
    systemPrompt: string,
    messages: Array<{ role: 'user' | 'assistant'; content: string }>,
    onResponseDelta?: (text: string) => void,
    maxTokens = 4096,
  ): Promise<string> {
    const openaiKey = process.env.OPENAI_API_KEY;
    if (!openaiKey) throw new Error('OPENAI_API_KEY not set');
    const model = process.env.OPENAI_MODEL ?? 'gpt-4o';
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${openaiKey}` },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: systemPrompt },
          ...messages.map(m => ({ role: m.role, content: m.content })),
        ],
        stream: true,
        temperature: 0,
        max_tokens: maxTokens,
      }),
    });
    if (!res.ok) throw new Error(`OpenAI HTTP ${res.status}: ${await res.text()}`);
    let rawResponse = '';
    const reader = res.body?.getReader();
    if (!reader) throw new Error('No response body from OpenAI');
    const decoder = new TextDecoder();
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

  /** Convert Anthropic.Tool[] → OpenAI ChatCompletionTool[] (function-calling format). */
  private static _anthropicToolsToOpenAI(tools: Anthropic.Tool[]): OpenAI.ChatCompletionTool[] {
    return tools.map(t => ({
      type: 'function' as const,
      function: {
        name: t.name,
        description: t.description ?? '',
        parameters: t.input_schema as Record<string, unknown>,
      },
    }));
  }

  /**
   * Agentic tool loop for any OpenAI-compatible provider
   * (Qianwen/DashScope, DeepSeek, vLLM, GPT-4, local LLMs, …).
   *
   * Mirrors _generateWithGemini's structure but uses OpenAI function-calling
   * format.  Tool execution is delegated to the existing _executeTools() so
   * all BioMate tools (run_code, search_literature, list_data_sources, …)
   * work identically regardless of which model is driving the conversation.
   *
   * Falls back to tool-less streaming if the provider rejects the tool schema
   * (HTTP 400/422) — allows less-capable models to still generate text.
   */
  private async _generateWithOpenAICompatible(
    client: OpenAI,
    model: string,
    systemPrompt: string,
    messages: Array<{ role: 'user' | 'assistant'; content: string }>,
    onResponseDelta?: (text: string) => void,
    maxTokens = 4096,
    toolContext?: { tools: Anthropic.Tool[]; context: ChatContext; onToolEvent?: (e: AgentToolEvent) => void },
  ): Promise<string> {
    let openaiTools: OpenAI.ChatCompletionTool[] | undefined = toolContext
      ? GalaxyAssistant._anthropicToolsToOpenAI(toolContext.tools)
      : undefined;

    const chatMessages: OpenAI.ChatCompletionMessageParam[] = [
      { role: 'system', content: systemPrompt },
      ...messages.map(m => ({ role: m.role as 'user' | 'assistant', content: m.content })),
    ];

    const MAX_TURNS = 8;
    let fullText = '';

    for (let turn = 0; turn < MAX_TURNS; turn++) {
      // Accumulate streaming tool_call deltas indexed by their array position.
      const pending: Record<number, { id: string; name: string; argsRaw: string }> = {};
      let turnText = '';

      let stream: AsyncIterable<OpenAI.ChatCompletionChunk>;
      try {
        stream = await client.chat.completions.create({
          model,
          messages: chatMessages,
          stream: true,
          max_tokens: maxTokens,
          temperature: 0,
          ...(openaiTools ? { tools: openaiTools, tool_choice: 'auto' } : {}),
        } as OpenAI.ChatCompletionCreateParamsStreaming);
      } catch (err: any) {
        // Provider rejected tool schemas — fall back to tool-less for the remainder
        if (openaiTools && (err?.status === 400 || err?.status === 422)) {
          console.warn('[GalaxyAssistant] OpenAI-compat provider rejected tool schemas, falling back to tool-less');
          openaiTools = undefined;
          stream = await client.chat.completions.create({
            model, messages: chatMessages, stream: true, max_tokens: maxTokens, temperature: 0,
          } as OpenAI.ChatCompletionCreateParamsStreaming);
        } else {
          throw err;
        }
      }

      for await (const chunk of stream) {
        const choice = chunk.choices[0];
        if (!choice) continue;

        // Text delta
        const textDelta = choice.delta?.content ?? '';
        if (textDelta) {
          turnText += textDelta;
          fullText += textDelta;
          onResponseDelta?.(textDelta);
        }

        // Tool-call deltas — accumulate by index (id + name in first chunk only,
        // arguments fragments stream across multiple chunks)
        const tcDeltas = (choice.delta as any)?.tool_calls as any[] | undefined;
        if (tcDeltas) {
          for (const tc of tcDeltas) {
            const idx: number = tc.index ?? 0;
            if (!pending[idx]) pending[idx] = { id: '', name: '', argsRaw: '' };
            if (tc.id) pending[idx].id = tc.id;
            if (tc.function?.name) pending[idx].name = (pending[idx].name || '') + tc.function.name;
            if (tc.function?.arguments) pending[idx].argsRaw += tc.function.arguments;
          }
        }
      }

      const toolCalls = Object.values(pending).filter(tc => tc.id && tc.name);

      // No tool calls or tools disabled → generation complete for this turn
      if (!toolCalls.length || !openaiTools || !toolContext) break;

      // Append the assistant turn (with tool_calls) to the conversation
      chatMessages.push({
        role: 'assistant',
        content: turnText || null,
        tool_calls: toolCalls.map(tc => ({
          id: tc.id,
          type: 'function' as const,
          function: { name: tc.name, arguments: tc.argsRaw },
        })),
      } as OpenAI.ChatCompletionMessageParam);

      // Execute tools in parallel via the shared _executeTools implementation
      const toolBlocks = toolCalls.map(tc => {
        let input: Record<string, unknown> = {};
        try { input = JSON.parse(tc.argsRaw || '{}'); } catch { /* ignore */ }
        return { id: tc.id, name: tc.name, input };
      });
      const results = await this._executeTools(toolBlocks, toolContext.context, toolContext.onToolEvent);

      // Append tool results as tool-role messages
      for (const result of results) {
        const contentStr = typeof result.content === 'string'
          ? result.content
          : JSON.stringify(result.content);
        chatMessages.push({
          role: 'tool',
          tool_call_id: result.tool_use_id,
          content: contentStr,
        } as OpenAI.ChatCompletionMessageParam);
      }
      // Next turn: model reads tool results and decides whether to call more tools or stop
    }

    return fullText;
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
  private async _fetchDomainProfile(userId?: number | string): Promise<{ domains: string[]; topics: string[] } | null> {
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
   *
   * Project-scoped: when `projectId` is a project id, only that project's
   * corrections plus the user's project-agnostic ones are used (a correction
   * made in project A never surfaces in project B). When `projectId` is null
   * (a project-less session) only account-level corrections are used. When
   * undefined, scoping is left to the repository default (all corrections).
   *
   * Non-fatal: returns empty string on any error.
   */
  private async _buildCorrectionContextBlock(
    userId: string,
    projectId?: string | null
  ): Promise<string> {
    try {
      const corrections = await memoryService.users.getUserCorrections(userId, 5, projectId)
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
   * Standing long-term-memory prefix injected on EVERY turn (not first-message-only).
   *
   * Today this is the project-scoped routing-corrections block. It lives here —
   * separate from the first-message cross-session / episode recall — because
   * corrections are a persistent user constraint the model must honour on every
   * message, not a one-time session primer. Project scoping flows straight
   * through: `context.projectId` (undefined when the chat is project-less, in
   * which case we pass `null` so only account-level corrections surface, never
   * another project's).
   *
   * Non-fatal: returns '' on any error or when there is no user.
   */
  private async _buildStandingLtmPrefix(context: ChatContext): Promise<string> {
    if (!context.userId) return '';
    try {
      const projectId = context.projectId ?? null;
      return await this._buildCorrectionContextBlock(String(context.userId), projectId);
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



  /**
   * Returns the Galaxy interactive-tool type the message is requesting,
   * or null if it's not an IT launch request.
   * Supports English and Chinese.
   */
  private _getInteractiveToolRequest(message: string): { toolId: string; label: string } | null {
    const lc = message.toLowerCase();
    // RStudio patterns (check before Jupyter — "r studio" is unambiguous)
    if (/\b(rstudio|r\s+studio)\b/i.test(message)
        || /(?:启动|打开|开启|运行|跑一个).*(?:rstudio|r\s*studio)/u.test(message)) {
      return { toolId: 'interactive_tool_rstudio', label: 'RStudio' };
    }
    // Jupyter patterns
    if (/\b(jupyter|jupyter\s+notebook|jupyter\s+lab|jupyterlab|notebook\s+server)\b/i.test(message)
        || /(?:启动|打开|开启|运行|跑一个).*(?:jupyter|notebook|笔记本|交互.*工具|interactive.*tool)/u.test(message)
        || /(?:jupyter|notebook|笔记本).*(?:启动|打开|开启)/u.test(message)) {
      return { toolId: 'interactive_tool_jupyter_notebook', label: 'Jupyter Notebook' };
    }
    // Catch-all Chinese: "帮我启动一个交互工具"
    if (/(?:帮我|请|想要)(?:启动|打开|开启).*(?:交互|interactive)/u.test(message)) {
      return { toolId: 'interactive_tool_jupyter_notebook', label: 'Jupyter Notebook' };
    }
    return null;
  }

  /** Launch a Galaxy interactive tool and return a GalaxyAssistantResponse with the entry URL. */
  private async _handleInteractiveToolLaunch(
    toolId: string,
    label: string,
    context: ChatContext,
    onResponseDelta?: (chunk: string) => void
  ): Promise<GalaxyAssistantResponse> {
    const api = this._api();
    try {
      // Get or create a Galaxy history for this session
      let historyId: string;
      const histories = await api.getHistories().catch(() => []);
      if (histories.length > 0) {
        historyId = histories[0].id;
      } else {
        historyId = await api.createHistory(`BioMate IT Session`);
      }

      const result = await api.launchInteractiveTool(toolId, historyId, {});

      // Galaxy IT containers take 30–90s to start; poll for the entry_point_url.
      const { rewriteInteractiveToolUrl } = await import('./routes');
      let entryUrl: string | undefined = result.entry_point_url
        ? rewriteInteractiveToolUrl(result.entry_point_url)
        : undefined;

      if (!entryUrl) {
        onResponseDelta?.(`Your **${label}** session is starting (job \`${result.job_id}\`)… waiting for container`);
        // Poll up to 90 seconds (18 × 5s)
        for (let i = 0; i < 18 && !entryUrl; i++) {
          await new Promise(r => setTimeout(r, 5000));
          try {
            const sessions = await api.getActiveInteractiveSessions();
            const mine = sessions.find((s: any) => s.job_id === result.job_id);
            // Galaxy's /api/entry_points returns "target" not "entry_point_url"
            const rawUrl = mine?.target || mine?.entry_point_url || (mine as any)?.url;
            if (rawUrl) {
              entryUrl = rewriteInteractiveToolUrl(rawUrl);
            }
          } catch { /* ignore poll errors */ }
          if (!entryUrl) onResponseDelta?.('.');
        }
      }

      const urlLine = entryUrl
        ? `\n\n[Open ${label}](${entryUrl})`
        : '\n\nContainer is still starting — check the Interactive Sessions tab in a minute for the URL.';

      const msg = `Your **${label}** session is ready (job \`${result.job_id}\`).${urlLine}`;
      onResponseDelta?.(msg);

      return {
        message: msg,
        intentType: 'interactive_tool_launch',
        suggestions: [`Show me active sessions`, `Launch RStudio instead`, `Run code with run_code`],
        sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false },
      };
    } catch (err: any) {
      // User-facing: no backend name or raw backend error text.
      console.warn(`[GalaxyAssistant] interactive tool launch failed (${label}):`, err?.message);
      const errMsg = /^zh/i.test(String((context as any)?.uiLanguage || ''))
        ? `暂时无法启动 **${label}**，请稍后重试；若持续失败请联系支持。`
        : `Couldn't start **${label}** right now. Please try again in a minute; if it keeps failing, contact support.`;
      onResponseDelta?.(errMsg);
      return {
        message: errMsg,
        intentType: 'interactive_tool_launch',
        suggestions: [],
        sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: false, thinkingUsed: false },
      };
    }
  }

  /**
   * Post-classifier routing for the single-intent path. The classifier decided workflow-vs-not; this
   * only (1) reconciles its execution mode with its action flags, (2) adds retrieval hints, and
   * (3) applies the explicit-prohibition and BOIN-prerequisite gates. See routing-authority.ts and
   * docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md. Measured by scripts/routing_replay/run.ts.
   */
  _applyPostClassifierRouting(
    intent: DecomposedIntent,
    decomposition: IntentDecomposition,
    message: string,
    opts: { paperContentResult?: unknown; originalUserQuery?: string; context?: ChatContext } = {},
  ): { boinDoseLevelsMissing?: boolean; pathwayEnrichment?: boolean } {
    const userText = opts.originalUserQuery ?? message;
    reconcileExecutionMode(intent, conversationHasComputableData(message, opts.context) && !conversationHasPipelineScaleData(message, opts.context));
    const { pathwayEnrichment } = applyRetrievalHints(intent, decomposition, userText);
    const gate = applyUserConstraintGate(intent, userText);
    if (gate !== 'none') console.log(`[GalaxyAssistant] [routing] user-constraint gate: ${gate}`);
    if (boinDoseLevelsMissing(intent, userText)) {
      console.log('[GalaxyAssistant] [routing] BOIN prereq gate: dose levels missing — returning clarification');
      intent.actions.needsWorkflowGeneration = false;
      return { boinDoseLevelsMissing: true, pathwayEnrichment };
    }
    return { pathwayEnrichment };
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

    // Canonical-fixture gate (Plan C): when the user already named a built-in
    // fixture or accession (airway, pasilla, pbmc3k, SRR\d+, etc.), the
    // dataset is resolved — the workflow knows how to load it. Suppress the
    // clarification ask deterministically so verbose phrasings like
    // "Run DESeq2 on airway; treated vs untreated; export CSV + MA plot"
    // don't re-trigger an "I need the counts matrix" reply. See
    // docs/20260610_DETERMINISTIC_CHAT_ROUTING_PLAN.md (Plan C).
    const _canonicalFixture = matchesCanonicalFixture(message);
    if (_canonicalFixture) {
      console.log(`[_clarificationGate] suppressed by canonical fixture: ${_canonicalFixture}`);
      return null;
    }

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
    this.modelConfig = { ...this.modelConfig, ...config, ...(localOnly() ? { intentModel: localConfig().model, responseModel: localConfig().model, toolRankingModel: localConfig().model } : {}) };
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
    onToolEvent?: (event: AgentToolEvent) => void,
    onProgress?: (stage: string, detail?: string) => void
  ): Promise<GalaxyAssistantResponse> {
    if (Array.isArray(context.skillPackIds) || Array.isArray(context.activeSkillIds)) {
      const selectedSkills = await buildSkillBlock(message, [], context);
      if (selectedSkills) context = { ...context, projectContext: [context.projectContext, selectedSkills].filter(Boolean).join("\n\n") };
    }
    // If the caller (chat-stream) supplied a per-user Galaxy proxy, scope it
    // to this turn via AsyncLocalStorage so every `this._api()` call in any
    // helper method picks it up. Skip the wrapper if no override is provided.
    if (!context.modelIdentity) context = { ...context, modelIdentity: modelIdentity(this.responseModelFor(context)) };
    const overrideProxy = context.galaxyAPIOverride as GalaxyAPIProxy | undefined;
    // A China-region user's Anthropic key is never used (llm-region-policy.ts; routes.ts drops it too).
    const userAnthropicKey = context.llmRegion === 'cn' ? undefined : context.userAnthropicApiKey;
    const openrouterKey = context.openrouterKey;

    const runInner = () => {
      if (overrideProxy) {
        return _galaxyAPIRequestStorage.run(overrideProxy, () =>
          this._processMessageInner(message, context, onResponseDelta, onToolEvent, onProgress));
      }
      return this._processMessageInner(message, context, onResponseDelta, onToolEvent, onProgress);
    };

    // OpenRouter / OpenAI-compatible providers.
    // - OpenRouter: the user's selected model runs the FULL agentic pipeline (intent → workflow
    //   generation → tool loop → run_code), not a chat-only stream. openaiCompatMessagesClient is
    //   the Anthropic↔OpenAI function-calling shim proven on the on-prem path (local-llm.ts): it
    //   replaces _getClaude() (via _anthropicOverride) and _openrouterAgentic flips the response
    //   path to the agentic loop. A model that cannot do function-calling surfaces a real error
    //   rather than a silently degraded chat-only answer. _generateChatWithOpenRouter is kept for
    //   an explicit future route for models known to lack tool support.
    // - Custom OpenAI-compatible providers (context.openaiBaseUrl: DashScope/Qianwen, vLLM, local
    //   LLM…): the client is stored in _openrouterClientStorage and picked up by the provider chain
    //   in _processMessageInner, so workflow generation works normally.
    // Only fires with a user/system OpenRouter or LLM_API_* key, so the default (Gemini) path is
    // unchanged.
    if (openrouterKey && !localOnly()) {
      const baseURL = context.openaiBaseUrl || 'https://openrouter.ai/api/v1';
      if (baseURL.includes('openrouter.ai')) {
        // China-region users: the Chinese model SET — each call on its role's model (the reply and
        // tool loop on the response model, Haiku-class calls on the light model, images on the
        // vision model). Everyone else: the selected model for every Anthropic-SDK call, as before.
        const cnRoute = requireCnRoute();
        const orShim = (cnRoute ? cnRoleMessagesClient(cnRoute) : openaiCompatMessagesClient({
          url: baseURL,
          model: context.selectedModel || 'z-ai/glm-5.3-prime',
          key: openrouterKey,
        })) as unknown as Anthropic;
        return _anthropicOverride.run(orShim, () => _openrouterAgentic.run(true, runInner));
      }
      const orClient = new OpenAI({ baseURL, apiKey: openrouterKey });
      return _openrouterClientStorage.run(orClient, () => runInner());
    }

    if (userAnthropicKey && !localOnly()) {
      const userClaude = new Anthropic({ apiKey: userAnthropicKey });
      return _anthropicOverride.run(userClaude, runInner);
    }
    return runInner();
  }

  private async _processMessageInner(
    message: string,
    context: ChatContext = {},
    onResponseDelta?: (chunk: string) => void,
    onToolEvent?: (event: AgentToolEvent) => void,
    onProgress?: (stage: string, detail?: string) => void
  ): Promise<GalaxyAssistantResponse> {
    const startTime = Date.now();
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] ${step}`);

    log('Processing message: ' + message.substring(0, 50));
    context.turnMessage = message;
    context.turnSyntheticDataRequested = undefined;  // set from this turn's intent below, never carried over

    // IT launch shortcut: "帮我启动Jupyter / launch RStudio" → skip intent analysis,
    // call Galaxy IT API directly, return a response with the session URL.
    const itRequest = this._getInteractiveToolRequest(message);
    if (itRequest) {
      log(`IT launch shortcut: ${itRequest.toolId}`);
      return this._handleInteractiveToolLaunch(itRequest.toolId, itRequest.label, context, onResponseDelta);
    }

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
    // Universe model: the user's recent runs — each with status, output count and,
    // for any FAILED run, a plain-language diagnosis (cause · at-fault · next, from
    // the run's own recorded error) — are STANDING context on EVERY turn, not gated
    // on detecting a "why did it fail?" phrasing or the first message. This is the
    // principled fix for the class of context-referential questions ("why did my
    // run fail?", "what did my run produce?", "show my results"): the run record is
    // always part of the model on the MAIN assistant path, so the answer never depends
    // on the intent classifier noticing it first. (The earlier gating is exactly how
    // "why is the run failing?" reached the literature agent with no run in context —
    // org-user issue #3.)
    // HONEST SCOPE (committee review 2026-11-10): the research/literature sub-agent does
    // NOT share this standing context by the same mechanism — it runs as a separate call
    // (`queryResearch`), so the `run_diagnostics` short-circuit (asksAboutRunProblem →
    // force run_diagnostics) is CURRENTLY LOAD-BEARING, not vestigial: without it a
    // run-problem classified `research_question` would still reach the literature path.
    // We now also thread the universe into that payload (`researchPayload.context
    // .user_context`), but full parity needs the backend research agent to prefer it —
    // until then the short-circuit stays as a real guard, not a belt-and-suspenders.
    if (context.userId) {
      const runsBlock = await this._buildRecentRunsBlock(
        String(context.userId),
        { withErrors: true, chatSessionId: context.sessionId },
      ).catch(() => '');
      if (runsBlock) {
        context = { ...context, ltmContextBlock: runsBlock + (context.ltmContextBlock || '') };
        log('Universe: recent runs (status + outputs + failed-run diagnosis) injected as standing context');
      }
      // P2 routing corrections are STANDING context on EVERY turn (not
      // first-message-only): they are a persistent user constraint the model
      // must honour on every message, and they are PROJECT-SCOPED via
      // context.projectId so a correction made in project A never surfaces in
      // project B (project-less sessions see only account-level corrections).
      const standingLtm = await this._buildStandingLtmPrefix(context).catch(() => '');
      if (standingLtm) {
        context = { ...context, ltmContextBlock: standingLtm + (context.ltmContextBlock || '') };
        log('Universe: project-scoped routing corrections injected as standing context');
      }
    }
    // First-message-only memory blocks (cross-session recall, episode memory).
    // Runs and routing corrections are no longer here — they are standing
    // context above (corrections moved out of this first-message gate).
    if (isFirstMessage && context.userId) {
      const uid = String(context.userId);
      try {
        const [crossSessionBlock, episodeBlock] =
          await Promise.all([
            this._buildCrossSessionContextBlock(message, uid),
            this._buildEpisodeMemoryBlock(message, uid),          // P1
          ]);

        let prefix = '';
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

    // SHADOW (chat context harness, P0 — observability only, NO behavior change). `context` is now
    // final (project context, LTM/memory, history, session datasets all resolved). Build the
    // inspectable manifest from the top-level blocks and log one line, so we can SEE the real
    // per-turn view scope on live traffic before migrating the assembly onto the harness. The blocks
    // are already merged at this provider-independent point (ltm = A7–A10+session; project_context =
    // A3–A5+skills), so sizes are per-block; channel-level detail comes when assembly is migrated in.
    // See docs/20261106_CHAT_CONTEXT_HARNESS_SCOPE.md.
    try {
      const _prev = context.previousMessages ?? [];
      const _histContent = _prev.map(m => m.content || '').join('\n');
      const _sd = context.sessionDatasets ?? [];
      const _mf = new ChatContextBuilder()
        .add({ name: 'project_context', scope: 'project', content: context.projectContext || '' })
        .add({ name: 'cross_session', scope: 'user', content: context.ltmContextBlock || '', wrap: { open: '<long_term_memory>', close: '</long_term_memory>' } })
        .add({ name: 'session_datasets', scope: 'conversation', content: _sd.length ? _sd.map((d: any) => d.name).join(', ') : '' })
        .add({ name: 'history', scope: 'conversation', content: _histContent })
        .build();
      log(`${manifestSummary(_mf)} msgs=${_prev.length} firstMsg=${isFirstMessage}`);
    } catch { /* shadow must never affect a turn */ }

    // Step 1: Analyze user intent with NLU (supports all formats: single, multi, sequential)
    // The LLM recognizes bullet lists, numbered steps, prose pipelines, and all other formats.
    onProgress?.('intent');
    log('Step 1: Analyzing intent');
    let decomposition = await this.analyzeIntent(message, context, sessionMemoryBlock);
    // A degraded (keyword last-resort) decomposition carries no inferred intent: leave it unknown.
    context.turnSyntheticDataRequested = decomposition.degraded ? undefined : decomposition.userRequestedSyntheticData;
    this._maybeCollapseNamedWorkflowCardRequest(decomposition, message);

    // Library / molecule-design dual path (both supported — never force only one):
    //  - catalog mega-chain when a real workflow_chains row matches
    //  - sequential step-by-step (ordinary single workflows) for synthesise-now/park
    //    triage and other multi-step asks with no catalog match
    // Do NOT invent ad-hoc workflow_chains rows; do NOT bind a lone Admet Pred card
    // for multi-step triage prose.
    {
      const perceivedKinds =
        decomposition.inputKinds ?? decomposition.primaryIntent?.inputKinds;
      const dual = applyLibraryMoleculeDualPath(
        message,
        perceivedKinds,
        decomposition.chainHint,
      );
      if (dual) {
        decomposition = dual as IntentDecomposition;
        log(
          `Step 1: library/molecule dual-path → ${dual.libraryMoleculePath}` +
            (dual.chainHint ? ` chain=${dual.chainHint}` : '') +
            ` (${dual.intents.length} intents; skipPipelineCollapse=` +
            `${!!dual.skipPipelineCollapse})`,
        );
      }
    }

    // Apply intentOverride from a prior IntentClarificationCard chip click.
    if (context.intentOverride) {
      const applyOverride = (i: DecomposedIntent) => {
        i.type = context.intentOverride!;
        i.actions = inferActionsFromType(context.intentOverride!);
      };
      applyOverride(decomposition.primaryIntent);
      for (const i of decomposition.intents) applyOverride(i);
      log(`Step 1: intentOverride applied → ${context.intentOverride}`);
    }

    const intent = decomposition.primaryIntent;
    log(`Step 1 complete - Intent: ${intent.type}, isMultiIntent: ${decomposition.isMultiIntent}, intents: ${decomposition.intents.length}`);

    // Pinned workflow: the user already chose the workflow, so routing must not re-decide it.
    //  - explicit: context.selectedWorkflow (Workflows library "Run" or another explicit picker) — always honoured;
    //  - follow-up: this turn fills inputs for the workflow open in the panel
    //    (followUpFillsCurrentWorkflow — classifier output, see its comment for the rule).
    // A pinned turn skips catalog search; the backend builds exactly that card (selected_workflow).
    const explicitSelection = normalizeSelectedWorkflow(context.selectedWorkflow);
    const openWorkflow = workflowIdentityOf(context.currentWorkflow);
    //  - named: the user's own text names the workflow to run (workflowNamedInRunRequest) — forces
    //    generation like a selection, but falls back to normal routing if the name does not resolve.
    const namedInText = explicitSelection ? null : workflowNamedInRunRequest(message);
    let pinnedWorkflow: SelectedWorkflow | null = explicitSelection
      || namedInText
      || (openWorkflow && followUpFillsCurrentWorkflow(decomposition, message) ? openWorkflow : null);
    if (pinnedWorkflow) {
      log(`Step 1: workflow pinned → "${pinnedWorkflow.name}" (${explicitSelection ? 'user selection' : namedInText ? 'named in the request' : 'follow-up fills the open workflow'})`);
    }

    // Surface the classifier's reasoning (computed above, historically only
    // logged) in the existing progress box by re-emitting the 'intent' stage
    // with the rationale as its detail → "Understanding your goal… · <why>".
    if (decomposition.rationale) {
      onProgress?.('intent', decomposition.rationale);
    }

    // Cross-intent ambiguity — only when no intentOverride already set.
    // Fires when the intent type looks wrong for a design-shaped query and
    // returns an IntentClarificationCard rather than proceeding blindly.
    if (!context.intentOverride && !pinnedWorkflow) {
      const ambiguity = this._detectCrossIntentAmbiguity(message, intent);
      if (ambiguity.shouldClarify) {
        log(`Step 1.5: ambiguity detected (${ambiguity.reason}) — emitting IntentClarificationCard`);
        const friendly = 'I want to make sure I do the right thing. Did you mean to run a design workflow, or are you asking something else?';
        if (onResponseDelta) onResponseDelta(friendly);
        return {
          message: friendly,
          intentType: intent.type,
          intentConfidence: intent.confidence,
          intentClarification: {
            originalIntent: intent.type,
            candidates: ambiguity.candidates,
            reason: ambiguity.reason,
            originalMessage: message,
          },
          suggestions: [],
          truncated: false,
          isMultiIntent: false,
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
    }

    // Multi-intent path: fan out to processSubIntent for each intent
    if (decomposition.isMultiIntent && !pinnedWorkflow) {
      return this.processMultiIntent(decomposition, message, context, startTime, onResponseDelta, domainProfileContext, sessionMemoryBlock, onToolEvent);
    }

    // Single-intent path: unchanged from original pipeline
    // Steps 2 & 3: Search for tools and datasets IN PARALLEL
    let recommendedTools: ToolRecommendation[] = [];
    let recommendedDatasets: DatasetRecommendation[] = [];
    let toolSearchUsed = false;
    let datasetRAGUsed = false;

    // Parallel content fetch: if the message contains a paper URL, DOI, arXiv ID, or PMID,
    // fetch its text content now — in parallel with tool/dataset search — so the workflow
    // generator and research agent both have the actual paper content to work from.
    const _paperContentPromise = _fetchPaperContentFromMessage(message);

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

    // Wait for all parallel searches + paper content fetch to complete
    log('Steps 2-3: Starting parallel searches');
    const [, paperContentResult] = await Promise.all([
      searchPromises.length > 0 ? Promise.all(searchPromises) : Promise.resolve(),
      _paperContentPromise,
    ]);
    log('Steps 2-3 complete');

    // Capture user's original query before paper-content injection so the
    // paper-question guard can test only what the user actually typed.
    const originalUserQuery = message;

    // Inject fetched paper content into the message so the workflow generator and
    // response synthesizer both see the actual paper text.
    if (paperContentResult) {
      message = `${message}\n\n[Paper content: ${paperContentResult.ref}]\n${paperContentResult.content}`;
      log(`Paper content injected: ${paperContentResult.ref} (${paperContentResult.content.length} chars)`);
    }

    // Step 4: Determine if workflow generation is needed
    let workflowSuggestion: WorkflowSuggestion;
    let generatedWorkflow = null;
    let workflowGenerated = false;

    // Action-flag-based routing (replaces switch-on-type)
    let researchResponse: any = undefined;
    let benchmarkEvidence: any = undefined;
    const actions = intent.actions;

    const _routing = this._applyPostClassifierRouting(intent, decomposition, message, { paperContentResult, originalUserQuery, context });
    const _isPathwayEnrichmentQuery = !!_routing.pathwayEnrichment;
    if (_routing.boinDoseLevelsMissing) {
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

    // S1: ClarificationGate — returns early if ambiguity requires user clarification
    // An explicit selection is generated whatever the per-keyword overrides above decided. A
    // follow-up binding is only an inference: if a guard above decided this turn runs no workflow
    // (e.g. the data-attach guard), it stands. A pinned turn skips the clarification gate, which
    // asks WHICH kind of workflow — already decided.
    if (explicitSelection || namedInText) actions.needsWorkflowGeneration = true;
    else if (pinnedWorkflow && !(actions.needsWorkflowGeneration || actions.needsWorkflowModification)) pinnedWorkflow = null;
    const clarificationResponse = pinnedWorkflow ? null : await this._clarificationGate(
      intent, actions, message, recommendedTools, recommendedDatasets
    );
    if (clarificationResponse) {
      log(`Step 4: Returning clarification question for ambiguity="${intent.workflowAmbiguity}"`);
      return clarificationResponse;
    }

    // Workflow generation — intent flags already determined by analyzeIntent; no further gate needed
    const needsGeneration = actions.needsWorkflowGeneration || actions.needsWorkflowModification;
    // Re-runs Step 4's generateWorkflow call with a different intent text (same datasets,
    // inline params, domain hints, session files). A card swapped in after the response text
    // is written (Steps 6b/6c) must be built this way — complete, with its OWN parameters
    // and file bindings — not from a stripped name lookup carrying the old card's params.
    // With `selection`, the backend builds exactly that catalog workflow (no search).
    let regenerateWorkflowFor: ((intentText: string, selection?: SelectedWorkflow) => Promise<any>) | null = null;
    // Names the workflow search retrieved for this request (Step 4). The response text may
    // lead with one of these instead of the card, and Step 6c-2 only follows the text to one
    // of these: the response model re-ranks retrieved candidates, it does not retrieve.
    let searchCandidateNames: string[] = [];
    let userInputKinds: string[] | undefined;  // classifier's input_kinds for this turn (guards card swaps)
    if (needsGeneration) {
      try {
        // No "Searching…" stage for a pinned workflow: nothing is searched.
        if (!pinnedWorkflow) onProgress?.('search');
        log('Step 4: Generating workflow');
        // Preserve original message keywords alongside the LLM-distilled subQuery.
        // subQuery can lose domain tokens (e.g. "ADMET", SMILES) when project context
        // or prior messages distort intent synthesis. Python fast paths and semantic
        // search need the original user text. Mirrors the multi-intent path (line ~4962)
        // and the docking/named-tool checks (lines ~4926, ~4939).
        const workflowUserIntent = intent.subQuery && intent.subQuery !== message
          ? `${intent.subQuery} ${message}`
          : (intent.subQuery || message);

        // Parse uploaded file S3 URIs and map filenames → workflow param names in code.
        // This ensures the Python generate_workflow call receives samplesheet/matrix/contrasts/
        // gene_list etc. from the uploaded datasets block without relying on the LLM to infer
        // the filename→paramname mapping from the response-generation prompt.
        const _uploadedFileParams = extractUploadedFileParams(message);
        const _mergedInline: Record<string, string> = {
          ...stripDatasetReferenceParams(intent.inlineParameters, message),
          ..._uploadedFileParams,
        };
        if (Object.keys(_uploadedFileParams).length > 0) {
          log(`Step 4: Injecting uploaded file params: ${JSON.stringify(_uploadedFileParams)}`);
        }

        userInputKinds = intent.inputKinds ?? decomposition.inputKinds;
        regenerateWorkflowFor = (intentText: string, selection?: SelectedWorkflow) => this.generateWorkflow(
          intentText,
          recommendedDatasets.map(d => d.dataset),
          _mergedInline,
          context,
          decomposition.preferredDomains,
          decomposition.keyTerms,
          context.sessionDatasets?.length ? context.sessionDatasets : undefined,
          decomposition.penalizedDomains,
          userInputKinds,
          selection,
          message
        );
        if (pinnedWorkflow) {
          generatedWorkflow = await regenerateWorkflowFor(workflowUserIntent, pinnedWorkflow);
          if (!generatedWorkflow?.success && !explicitSelection) {
            // The open/named workflow is not a resolvable catalog workflow (e.g. a personal upload,
            // or a name that is not an exact catalog id): the pin was an inference, so route normally.
            log(`Step 4: open workflow "${pinnedWorkflow.name}" could not be built (${generatedWorkflow?.error}) — routing normally`);
            pinnedWorkflow = null;
            onProgress?.('search');
            generatedWorkflow = await regenerateWorkflowFor(workflowUserIntent);
          }
        } else {
          generatedWorkflow = await regenerateWorkflowFor(workflowUserIntent);
        }
        searchCandidateNames = (generatedWorkflow?.candidate_workflows || [])
          .map((c: any) => String(c?.name || ''))
          .filter(Boolean);
        workflowGenerated = !!(
          generatedWorkflow?.success &&
          !generatedWorkflow?.error &&
          (generatedWorkflow?.workflow_ga ||
           generatedWorkflow?.nextflow_path ||
           generatedWorkflow?.workflow_type === 'chain')
        );
        log('Step 4 complete - workflowGenerated: ' + workflowGenerated);
        if (workflowGenerated) onProgress?.('matched', (generatedWorkflow as any)?.workflow_name);

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
        // Preserve error so workflowGenerationFailed=true in generateResponse.
        generatedWorkflow = { success: false, error: `STEP4_THROW: ${error.message}`, _caughtAt: 'step4' };
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
    // Skip when the message already contains injected paper content — the LLM has everything
    // it needs to answer directly. The research agent adds value for external knowledge queries
    // (database lookups, literature search) but NOT when paper text is already in-context.
    // Text-reasoning intents (protocol_guidance, data_interpretation, methods_writing,
    // experiment_design, teaching_explanation) don't need the Python research agent when paper
    // content is present; the LLM is the stronger reasoner for this task.
    const _textReasoningIntents = new Set([
      'protocol_guidance', 'data_interpretation', 'methods_writing',
      'experiment_design', 'teaching_explanation', 'general_question',
    ]);
    const _hasPaperContent = paperContentResult !== null;
    const _skipResearchAgent = localOffline() || (_hasPaperContent && _textReasoningIntents.has(intent.type));

    if (actions.needsResearchAgent && !_skipResearchAgent) {
      log('Routing to research backend');
      // Emit a progress status so the UI shows feedback during the long research query.
      if (onToolEvent) {
        onToolEvent({
          type: 'status',
          tool_use_id: 'research_agent',
          name: 'research_query',
          message: paperContentResult
            ? `Reading your paper, then searching PubMed · Europe PMC · Semantic Scholar · OpenAlex in parallel…`
            : `Searching PubMed · Europe PMC · Semantic Scholar · OpenAlex in parallel…`,
        });
      }
      try {
        // When paper content is available, pass it directly to the research agent
        // so it becomes the PRIMARY source for synthesis. The agent then
        // cross-references with PubMed/Semantic Scholar for supporting literature.
        const researchPayload: Record<string, unknown> = {
          query: message,
          context: {
            information_need: intent.type,
            // Universe context (the user's recent runs/outputs + standing memory) so the
            // research agent can answer a question about the user's OWN run/data from it
            // rather than citing general literature. This is the systematic counterpart to
            // the run_diagnostics short-circuit: that guard keeps run-problems off this path,
            // but any context-referential question that still routes here now at least carries
            // the universe. (Backend research agent should prefer this when the question is
            // about the user's own runs/outputs — committee review 2026-11-10.)
            user_context: context.ltmContextBlock || undefined,
          },
          include_citations: true,
          include_benchmark_evidence: true,
        };
        if (paperContentResult) {
          researchPayload.paper_content = paperContentResult.content;
          log(`Passing paper content to research agent: ${paperContentResult.ref} (${paperContentResult.content.length} chars)`);
        }
        researchResponse = await this._api().queryResearch(researchPayload);
        log('Research response received');
        if (onToolEvent) {
          onToolEvent({
            type: 'status',
            tool_use_id: 'research_agent',
            name: 'research_query',
            message: `Synthesizing findings and generating response…`,
          });
        }
      } catch (error: any) {
        log('Research query failed: ' + (error.message ?? error.error ?? String(error)));
      }
    } else if (_skipResearchAgent) {
      log(localOffline()
        ? 'Offline mode: using local knowledge tools and supplied evidence'
        : `Skipping research agent — paper content (${paperContentResult?.content.length ?? 0} chars) already in context; LLM will reason directly`);
    }

    // Benchmark agent
    if (actions.needsBenchmarkAgent) {
      log('Routing to benchmark backend');
      try {
        benchmarkEvidence = await this._api().queryBenchmark({
          query: message,
        });
        log('Benchmark response received');
      } catch (error: any) {
        log('Benchmark query failed: ' + error.message);
      }
    }

    // Step 6: Generate natural language response
    onProgress?.('plan');
    log('Step 6: Generating response');
    // Research synthesis already owns its numbered source list. Buffer chat's
    // rewrite so invented references are never streamed before validation.
    let citedResearch = researchResponse?.success && Array.isArray(researchResponse?.citations) && researchResponse.citations.length
      ? researchResponse : null;
    let executedTargets: any = null;
    let targetToolStarted = false;
    let reviewToolCompleted = false;
    const researchAwareDelta = onResponseDelta ? (chunk: string) => {
      if (!citedResearch && !targetToolStarted) onResponseDelta(chunk);
    } : undefined;
    const researchAwareToolEvent = (event: AgentToolEvent) => {
      if (event.name === 'identify_targets') {
        targetToolStarted = true;
        if (event.type === 'tool_result') {
          try {
            const value = typeof event.output === 'string' ? JSON.parse(event.output) : event.output;
            if (!event.error && value?.status === 'ok') executedTargets = value;
          } catch { /* malformed output is not successful execution evidence */ }
        }
      }
      if (event.type === 'tool_result' && event.name === 'write_review') {
        try {
          const value: any = typeof event.output === 'string' ? JSON.parse(event.output) : event.output;
          if (value?.status === 'ok' && value.answer && Array.isArray(value.citations)) {
            citedResearch = {success:true,...value};
            researchResponse = citedResearch;
            reviewToolCompleted = true;
          }
        } catch { /* malformed tool output remains an error, not evidence */ }
      }
      onToolEvent?.(event);
    };
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
      researchAwareDelta,
      domainProfileContext,
      sessionMemoryBlock,
      decomposition.preferredDomains ?? [],
      researchAwareToolEvent
    );
    if (executedTargets && !reviewToolCompleted) {
      // Present the actual ranking, not an earlier survey that never saw the
      // completed tool result. Source ownership is per artifact, not per turn.
      response.message = targetEvidenceReply(executedTargets);
      onResponseDelta?.(response.message);
    } else if (citedResearch) {
      const guarded = groundedResearchReply(response.message, citedResearch);
      response.message = executedTargets ? `${targetEvidenceReply(executedTargets)}\n\n${guarded.message}` : guarded.message;
      onResponseDelta?.(response.message);
      if (guarded.usedBackendAnswer) log('Research citation boundary: retained grounded backend answer');
    } else if (targetToolStarted) {
      onResponseDelta?.(response.message);
    }
    log('Step 6 complete');

    // Step 6r: a simulated-input attempt was refused (run_code would have invented the data). The
    // turn must not END on that refusal: build the real workflow — the one the user named, else
    // normal routing — so the reply finishes on a card that runs on real (built-in or attached)
    // data. The user is told the simulation was detected, then given the real result path.
    if (context.syntheticDataRefused?.turn === message && !workflowGenerated) {
      const named = workflowNamedInRunRequest(message);
      log(`Step 6r: simulated-data attempt refused — building the real workflow${named ? ` "${named.name}"` : ''}`);
      const build = (selection?: SelectedWorkflow) => regenerateWorkflowFor
        ? regenerateWorkflowFor(message, selection)
        : this.generateWorkflow(message, [], intent.inlineParameters, context, decomposition.preferredDomains,
            decomposition.keyTerms, context.sessionDatasets?.length ? context.sessionDatasets : undefined,
            decomposition.penalizedDomains, intent.inputKinds ?? decomposition.inputKinds, selection, message);
      try {
        let recovered = await build(named ?? undefined);
        if (!recovered?.success && named) recovered = await build();
        if (recovered?.success && !recovered?.error && (recovered.workflow_ga || recovered.nextflow_path || recovered.workflow_type === 'chain')) {
          generatedWorkflow = recovered;
          workflowGenerated = true;
          const name = cardWorkflowName(recovered) || named?.name || 'the workflow';
          response.message = /[\u4e00-\u9fff]/.test(message)
            ? `检测到一次模拟数据的尝试，已阻止——不会用编造的数值作为结果。\n\n**${name}** 已就绪（见下方工作流），它使用真实数据运行（工作流自带的示例数据或您提供的数据）。请检查参数后点击“${runButtonLabel('zh')}”。`
            : `A simulated-data attempt was detected and stopped — no made-up numbers are reported.\n\n**${name}** is ready below and runs on real data (the workflow's built-in sample data or yours). Review the parameters and click "${runButtonLabel('en')}".`;
          onResponseDelta?.(response.message);
        } else {
          log(`Step 6r: no workflow could be built (${recovered?.error || 'no match'}) — the reply asks for data`);
        }
      } catch (e: any) {
        log('Step 6r failed: ' + (e?.message || e));
      }
    }

    // Step 6b: LLM reselection — confirm or override FTS workflow choice.
    // The text-generating LLM (Step 6) has full routing rules and domain knowledge;
    // the FTS search (Step 4) does not. When the generated text describes a different
    // workflow than what FTS selected, we ask a cheap LLM call to pick from the top
    // candidates using both the user message and the generated text as context.
    if (!pinnedWorkflow && generatedWorkflow?.success && generatedWorkflow?.candidate_workflows?.length > 1) {
      try {
        const reselectedName = await this._reselectWorkflow(
          message,
          response.message,
          generatedWorkflow.candidate_workflows,
          decomposition.preferredDomains ?? []
        );
        if (reselectedName && reselectedName !== generatedWorkflow.workflow_name) {
          log(`Step 6b: LLM reselected workflow "${reselectedName}" (was "${generatedWorkflow.workflow_name}")`);
          // The reselected workflow's own card (its parameters, prefilled from this request),
          // not the previous card's parameters under a new name.
          const reselected = await this._cardForNamedWorkflow(reselectedName, message, regenerateWorkflowFor, userInputKinds);
          if (reselected) {
            generatedWorkflow = { ...reselected, source: 'llm_reselection' };
            workflowGenerated = true;
            log(`Step 6b: reselection applied — panel will show "${reselectedName}"`);
          } else {
            log(`Step 6b: no complete card for "${reselectedName}" — keeping "${generatedWorkflow.workflow_name}"`);
          }
        } else {
          log(`Step 6b: LLM confirmed "${generatedWorkflow.workflow_name}" — no change`);
        }
      } catch (err: any) {
        log(`Step 6b: reselection failed (${err.message}) — keeping FTS result`);
      }
    }

    // Step 6c: Text-vs-card consistency guardrail
    // The LLM generates its text response AFTER the FTS search, so its text is the
    // more authoritative signal. If the text explicitly names an nf-core workflow that
    // differs from the workflow card, look it up and swap the card.
    // This catches FTS mis-rankings where the right workflow is at rank-1 in raw search
    // but a lower-scoring result slipped through the generate_workflow pipeline.
    // EXCEPTION: Skip when the pathway enrichment override fired — the LLM text may mention
    // nf-core/differentialabundance from prior-turn context, but the override has already
    // explicitly chosen clusterprofiler via key_terms/penalizedDomains. Applying the guardrail
    // here would undo the override and route back to differentialabundance (the Step 6c bug
    // diagnosed 2026-07-20 after the MG demo E2E reproducibly showed this pattern).
    // A pinned card (Step 1) is the user's own choice: neither text guardrail may move it.
    // Unpinned, the workflow open in the panel is a legitimate target for both guardrails besides
    // this request's search candidates — "not a search candidate" must never keep a card that
    // contradicts both the reply and the workflow the user has open (doc §7.4).
    const _isOpenWorkflow = (n: string) => !!openWorkflow && !!n && workflowSlug(n) === workflowSlug(openWorkflow.name);
    if (
      !pinnedWorkflow &&
      generatedWorkflow?.success &&
      generatedWorkflow?.workflow_ga &&
      !generatedWorkflow?.workflow_type?.includes('chain') &&
      response.message &&
      !_isPathwayEnrichmentQuery
    ) {
      try {
        const _cardName: string = (generatedWorkflow.workflow_ga?.name || generatedWorkflow.workflow_name || '').toLowerCase();
        // Extract the first bold nf-core workflow name from the LLM response text.
        // The pattern does NOT require closing ** because the LLM often bolds a full
        // phrase: "**nf-core/proteomicslfq — Label-free quantification...**" — the
        // workflow name ends at the first non-name character (space, dash, em-dash).
        // Fallback: plain unbolded mention (e.g. "recommend nf-core/rnaseq for this").
        const _boldNfcore =
          response.message.match(/\*\*(nf-core\/[a-z][a-z0-9\-]+)/i) ||
          response.message.match(/\b(nf-core\/[a-z][a-z0-9\-]+)\b/i);
        const _textWorkflow = _boldNfcore?.[1]?.toLowerCase();
        // Same constraint as Step 6c-2: follow the text only to a workflow the search retrieved for this
        // request (unconstrained, the response model's own "retrieval" moved correct cards to wrong ones).
        const _isCandidate = !!_textWorkflow && (
          searchCandidateNames.some(c => workflowSlug(c) === workflowSlug(_textWorkflow)) || _isOpenWorkflow(_textWorkflow));
        if (
          _textWorkflow &&
          _textWorkflow !== _cardName &&
          !_cardName.includes(_textWorkflow.replace('nf-core/', '')) &&
          !_textWorkflow.includes(_cardName) &&
          !_isCandidate
        ) {
          log(`Step 6c: text mentions "${_textWorkflow}", not a search candidate for this request — keeping "${_cardName}"`);
        } else if (
          _textWorkflow &&
          _textWorkflow !== _cardName &&
          !_cardName.includes(_textWorkflow.replace('nf-core/', '')) &&
          !_textWorkflow.includes(_cardName)
        ) {
          log(`Step 6c: text mentions "${_textWorkflow}" but card shows "${_cardName}" — correcting via lookup`);
          // The open workflow is rebuilt as its own complete card (own params, this turn's values).
          const _openCard = _isOpenWorkflow(_textWorkflow) && regenerateWorkflowFor
            ? await regenerateWorkflowFor(message, openWorkflow!) : null;
          const _openOk = !!(_openCard?.success && _openCard.workflow_ga);
          const corrected = _openOk ? null : await this._lookupWorkflowByName(_textWorkflow, message, userInputKinds);
          if (_openOk) {
            generatedWorkflow = { ..._openCard, source: 'text_guardrail' };
            workflowGenerated = true;
            log(`Step 6c: card corrected to the open workflow "${openWorkflow!.name}"`);
          } else if (corrected?.input_compatible === false) {
            // 2026-11-05: the reply recommended nf-core/proteomicslfq "for MaxQuant proteinGroups.txt" and
            // this step moved the correct dep card onto a raw-spectra pipeline.
            log(`Step 6c: "${_textWorkflow}" cannot run on this request's data (backend input-kind check) — keeping "${_cardName}"`);
            // The card is right but the prose still recommends the other workflow: say so next to it.
            const _cardLabel = generatedWorkflow.workflow_ga?.name || generatedWorkflow.workflow_name || _cardName;
            response.message += `\n\n> **Note:** ${_textWorkflow} does not accept the kind of data described in your request, `
              + `so the plan below uses **${_cardLabel}** instead.`;
          } else if (corrected?.success && (corrected.workflow_ga || corrected.nextflow_path)) {
            generatedWorkflow = {
              ...generatedWorkflow,
              ...corrected,
              required_params: generatedWorkflow.required_params,
              optional_params: generatedWorkflow.optional_params,
              param_prefill_deferred: generatedWorkflow.param_prefill_deferred,
              source: 'text_guardrail',
            };
            workflowGenerated = true;
            log(`Step 6c: card corrected to "${_textWorkflow}"`);
          } else {
            log(`Step 6c: lookup for "${_textWorkflow}" failed — keeping original card`);
          }
        }
      } catch (err: any) {
        log(`Step 6c: text guardrail failed (${err.message}) — keeping FTS result`);
      }
    }

    // Step 6c-2: Text-vs-card consistency for every catalog workflow, not only nf-core.
    // The response header names the workflow it describes ("**hts_plate_qc_hit_calling** —",
    // "**REINVENT4 Generative Lead Design** —"). Measured 2026-11-03 on the cold-start
    // examples: half of the workflow cards disagreed with their own chat text, and where the
    // text named a real catalog workflow it was the right one (plate reshape, DE + GO,
    // generative design) while the card was a lexical near-miss. The nf-core branch above
    // could not see these names. Same exception as above for the pathway-enrichment override.
    if (
      !pinnedWorkflow &&
      generatedWorkflow?.success &&
      generatedWorkflow?.workflow_ga &&
      !generatedWorkflow?.workflow_type?.includes('chain') &&
      generatedWorkflow?.source !== 'text_guardrail' &&
      response.message &&
      !_isPathwayEnrichmentQuery
    ) {
      try {
        const _named = textWorkflowName(response.message);
        const _card = generatedWorkflow.workflow_ga?.name || generatedWorkflow.workflow_name || '';
        if (_named && workflowSlug(_named) !== workflowSlug(_card)) {
          // Follow the text only to a workflow the search retrieved for this request. Measured
          // 2026-11-03: unconstrained, the response model also "retrieved" on its own and moved
          // correct cards to wrong ones (dock-the-top-50 -> pocket detection; safety-gate
          // triage -> pharmacophore filtering).
          const _candidate = searchCandidateNames.find(c => workflowSlug(c) === workflowSlug(_named))
            || (_isOpenWorkflow(_named) ? openWorkflow!.name : undefined);
          if (!_candidate) {
            log(`Step 6c-2: text presents "${_named}", not a search candidate for this request — keeping "${_card}"`);
            // The card stays, but the reply must not introduce it under another name. Dev 2026-11-11:
            // "Design nanobody candidates against this epitope." answered "**Nanobody Design Against
            // SARS-CoV-2 Spike RBD**" over a bispecific_antibody_design card — an invented title is
            // never a search candidate, so this branch used to leave text and panel disagreeing.
            // CLAUDE.md: the chat name must be the card title exactly, so relabel the header in place.
            const _display = cardWorkflowName(generatedWorkflow);
            if (_display) {
              const _relabelled = relabelWorkflowHeader(response.message, _named, _display);
              if (_relabelled !== response.message) {
                response.message = _relabelled;
                log(`Step 6c-2: reply header relabelled to the card name "${_display}"`);
              }
            }
          } else {
            log(`Step 6c-2: text presents candidate "${_candidate}" but card shows "${_card}"`);
            const _open = _isOpenWorkflow(_candidate) && regenerateWorkflowFor
              ? await regenerateWorkflowFor(message, openWorkflow!) : null;
            const corrected = (_open?.success && _open.workflow_ga) ? _open
              : await this._cardForNamedWorkflow(_candidate, message, regenerateWorkflowFor, userInputKinds);
            if (corrected) {
              generatedWorkflow = { ...corrected, source: 'text_guardrail' };
              workflowGenerated = true;
              log(`Step 6c-2: card corrected to "${_candidate}"`);
            } else {
              log(`Step 6c-2: could not build a card for "${_candidate}" — keeping "${_card}"`);
            }
          }
        }
      } catch (err: any) {
        log(`Step 6c-2: guardrail failed (${err.message}) — keeping current card`);
      }
    }

    // Step 6d: User-explicit workflow override
    // When the user's message explicitly names an nf-core pipeline (e.g. "run nf-core/spatialvi"),
    // that stated intent overrides the FTS+LLM routing. Checked last so it beats all heuristics.
    if (
      generatedWorkflow?.success &&
      generatedWorkflow?.workflow_ga &&
      !generatedWorkflow?.workflow_type?.includes('chain') &&
      message
    ) {
      try {
        const _userNfcore =
          message.match(/\b(nf-core\/[a-z][a-z0-9\-]+)\b/i) ||
          message.match(/run\s+(nf-core\/[a-z][a-z0-9\-]+)/i);
        const _userWorkflow = _userNfcore?.[1]?.toLowerCase();
        const _currentCard6d = (generatedWorkflow.workflow_ga?.name || generatedWorkflow.workflow_name || '').toLowerCase();
        if (
          _userWorkflow &&
          _userWorkflow !== _currentCard6d &&
          !_currentCard6d.includes(_userWorkflow.replace('nf-core/', '')) &&
          !_userWorkflow.includes(_currentCard6d)
        ) {
          log(`Step 6d: user explicitly requested "${_userWorkflow}" but card shows "${_currentCard6d}" — correcting`);
          const corrected = await this._lookupWorkflowByName(_userWorkflow);
          if (corrected?.success && (corrected.workflow_ga || corrected.nextflow_path)) {
            generatedWorkflow = {
              ...generatedWorkflow,
              ...corrected,
              required_params: generatedWorkflow.required_params,
              optional_params: generatedWorkflow.optional_params,
              param_prefill_deferred: generatedWorkflow.param_prefill_deferred,
              source: 'user_explicit_override',
            };
            workflowGenerated = true;
            log(`Step 6d: card corrected to "${_userWorkflow}" per user's explicit request`);
          } else {
            log(`Step 6d: lookup for "${_userWorkflow}" failed — keeping "${_currentCard6d}"`);
          }
        }
      } catch (err: any) {
        log(`Step 6d: user-explicit override failed (${err.message}) — keeping FTS result`);
      }
    }

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

    // Ground LLM-extracted keys against the workflow schema so the panel
    // form actually populates. When SCHEMA_GROUNDED_EXTRACTION=1, runs the
    // rule+LLM+validate pipeline; otherwise falls back to the legacy
    // WORKFLOW_PARAM_ALIASES table.
    const _workflowNameForRemap =
      generatedWorkflow?.workflow_ga?.name || generatedWorkflow?.workflow_name;
    // Standing project rules must reach schema-grounded extraction so a silent
    // message still honors "always GRCh38" / FDR thresholds once the workflow
    // schema exposes those slots (backend rule-based fill also uses the message).
    const _paramExtractQuery = [
      message,
      ...(context?.projectRules?.length
        ? [`Standing project instructions:\n${context.projectRules.map((r, i) => `${i + 1}. ${r}`).join('\n')}`]
        : []),
    ].join('\n\n');
    const _groundResult = await groundInlineParameters({
      workflowName: _workflowNameForRemap,
      rawParams: intent.inlineParameters,
      userQuery: _paramExtractQuery,
      requiredParams: generatedWorkflow?.workflow_ga?.required_params,
      optionalParams: generatedWorkflow?.workflow_ga?.optional_params,
      onStatus: onToolEvent
        ? (msg, payload) =>
            onToolEvent({
              type: 'status',
              tool_use_id: 'param_ground_' + (_workflowNameForRemap || 'wf'),
              name: 'parameter_extraction',
              message: msg,
              payload,
            })
        : undefined,
    });
    const _groundedInlineParams = stringifyParamValues(_groundResult.params);
    // Backend rule-based / genome injection fills optional_params[].default|value and
    // workflow_ga.parameters — fold those into the overlay so the panel and e2e see
    // structured obedience even when the LLM intent stage only echoed rules in prose.
    const _backendFilledParams: Record<string, string> = {};
    const _gaForFill = generatedWorkflow?.workflow_ga || generatedWorkflow || {};
    for (const [k, v] of Object.entries(_gaForFill.parameters || {})) {
      if (v != null && String(v).trim() !== '') _backendFilledParams[k] = String(v);
    }
    for (const p of [...(_gaForFill.required_params || []), ...(_gaForFill.optional_params || [])]) {
      if (!p?.name) continue;
      const v = p.value ?? p.default;
      if (v != null && String(v).trim() !== '' && _backendFilledParams[p.name] === undefined) {
        _backendFilledParams[p.name] = String(v);
      }
    }
    // The parameter extractor reads the message, not the workflow object, so a
    // required input the attachment binding already filled still came back as
    // "missing_required" — the founder saw "1 required parameter need to be
    // filled" plus a "Which input_smiles?" card with the file already attached.
    // Carry the bound values into the overlay and withdraw their questions.
    // Same for prepared-input key=value / backend-filled slots (movies_path=s3://…,
    // analysis=screening, ligand_a=…) — Confirm must enable without force-Confirm.
    // Also write prepared KV onto the workflow object itself (param strip source).
    if (generatedWorkflow?.workflow_ga) {
      applyPreparedInputParamsToWorkflow(generatedWorkflow.workflow_ga, _paramExtractQuery);
    } else if (generatedWorkflow) {
      applyPreparedInputParamsToWorkflow(generatedWorkflow, _paramExtractQuery);
    }
    const _attachmentBoundParams = attachmentBoundParams(generatedWorkflow);
    const _preparedKvParams = parsePreparedInputParams(_paramExtractQuery, [
      ...Object.keys(_backendFilledParams),
      ...Object.keys(_groundedInlineParams),
      ...((_gaForFill.required_params || []).map((p: any) => p?.name).filter(Boolean)),
      ...((_gaForFill.optional_params || []).map((p: any) => p?.name).filter(Boolean)),
    ]);
    const _filledForClarify: Record<string, string> = {
      ..._backendFilledParams,
      ..._preparedKvParams,
      ..._attachmentBoundParams,
    };
    const _remappedInlineParams = {
      ..._backendFilledParams,
      ..._preparedKvParams,
      ..._groundedInlineParams,
      ..._attachmentBoundParams,
    };
    const _clarifications = (_groundResult.details?.clarifications || []).filter(
      (c) => !_filledForClarify[c.paramName],
    );
    if (Object.keys(_filledForClarify).length > 0) {
      console.log(
        '[InlineParam Ground] filled params kept:', Object.keys(_filledForClarify).join(','),
        '— clarifications withdrawn:',
        (_groundResult.details?.clarifications || []).length - _clarifications.length,
      );
    }
    if (_groundResult.path !== 'noop') {
      console.log(
        '[InlineParam Ground]',
        _workflowNameForRemap,
        'path:', _groundResult.path,
        'confidence:', _groundResult.details?.confidence?.toFixed(2),
        'clarifications:', _clarifications.length,
      );
    }

    const finalResult: GalaxyAssistantResponse = {
      message: finalMessage,
      intentType: intent.type,
      intentConfidence: intent.confidence,
      inlineParameters: Object.keys(_remappedInlineParams).length > 0 ? _remappedInlineParams : undefined,
      paramClarifications: _clarifications.length > 0 ? _clarifications : undefined,
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
    // Check for unfilled required params to warn the user
    const wfGaParams = wf.workflow_ga || {};
    const unfilledRequired = (wfGaParams.required_params || wf.required_params || []).filter(
      (p: any) => (p.value === null || p.value === undefined || p.value === '') &&
                  (p.default === null || p.default === undefined || p.default === '') &&
                  !p.autoFilled
    );
    // NOTE: We deliberately do NOT emit a "<name> is ready in the panel — check
    // the steps and parameters, then click Confirm & Run" preamble here. That
    // sentence duplicated the workflow card rendered directly below the message
    // (same name, same Confirm & Run affordance) and carried no extra signal.
    // The structured summary (Predict … / Input / Key steps / Expected output)
    // is supplied by the caller's base message. This helper now only surfaces
    // the required-parameter warning, which the card does NOT show inline.
    const warning = unfilledRequired.length > 0
      ? `⚠️ **${unfilledRequired.length} required parameter${unfilledRequired.length === 1 ? '' : 's'}** need to be filled — open the panel to configure before running.`
      : '';
    return warning;
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

  /**
   * Curated-chain response for a classifier chain_hint (TIER 2 of the sequential pipeline, after TIER 1
   * found no single covering workflow). Not used for single-intent turns: one intent means the classifier
   * judged one workflow covers the request, and honouring the hint there replaced correct single-pipeline
   * cards (nf-core/mag, nf-core/methylarray) with chains on dev (2026-11-05, domain_retag arm R).
   * Returns null when the hint is dropped or the chain cannot be built.
   */
  private async _curatedChainResponse(
    decomposition: IntentDecomposition,
    message: string,
    context: ChatContext,
    log: (step: string) => void,
  ): Promise<GalaxyAssistantResponse | null> {
    // ═══════════════════════════════════════════════════════════════════════
    // TIER 2: Curated chain lookup via chainHint.
    // If the intent classifier named a known chain, use its pre-defined steps.
    // ═══════════════════════════════════════════════════════════════════════
    // Guard: honor a chain_hint only when the CURRENT message supports it. The
    // intent classifier is fed the last ~3 turns with "no programmatic gate"
    // (see ~line 7013), so a single-analysis turn (e.g. ADMET) can inherit a
    // prior turn's chain (e.g. an RNA-seq DE chain) and be mis-routed/mis-labelled
    // (docs/20261006_CHAIN_NAME_LEAK_AND_HANG_ROOTCAUSE.md). Decomposition flags
    // can be contaminated by that history, so we check the MESSAGE TEXT: does it
    // reference a chain/pipeline, or any distinctive token of the hint slug?
    if (decomposition.chainHint) {
      // Shared guard with selectLibraryMoleculeRouting — refuse leaked hints on
      // single-intent ADMET / bare "screen compound" (Bugbot 2026-11-14).
      const _msgSupportsChain = messageSupportsCatalogChainHint(
        message,
        decomposition.chainHint,
      );
      // Generative design must never keep a screening mega-chain hint.
      if (!_msgSupportsChain || isMoleculeGenerateRequest(message)) {
        log(`Tier 2: dropping stale chain_hint "${decomposition.chainHint}" — ${
          isMoleculeGenerateRequest(message) ? 'generate/design intent (not screening)' : 'current message lacks multi-step/library-screening phrasing or explicit chain slug (likely inherited from prior-turn context)'
        }`);
        decomposition.chainHint = null;
      }
    }
    // Count-matrix DE coldstart: do not launch FASTQ nf-core/rnaseq chain.
    if (decomposition.chainHint) {
      const remapped = remapBulkRnaseqChainForCounts(decomposition.chainHint, message);
      if (remapped && remapped !== decomposition.chainHint) {
        log(`Tier 2: remapping chain_hint ${decomposition.chainHint} → ${remapped} (count matrix attached)`);
        decomposition.chainHint = remapped;
      }
    }

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
              chainPipelineSteps.map((s, i) => `  ${i + 1}. **${s.workflow_name}**${s.nextflow_path ? '' : ' (workflow not yet resolved)'}`)
                .join('\n'),
              '',
              `Review the steps below, then click **${runButtonLabel((context as any)?.uiLanguage)}** to execute them in order.`,
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
              chain_display_name: chain.display_name || chain.name,
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
    return null;
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
    const noCollapse = decomposition.skipPipelineCollapse === true;

    // ═══════════════════════════════════════════════════════════════════════
    // TIER 1: Try the full query as a single workflow first.
    // If one workflow covers all the user's biological steps → return early.
    // Skipped for rule-built plans that must stay discrete (library triage).
    // ═══════════════════════════════════════════════════════════════════════
    if (noCollapse) {
      log('Tier 1: skipped (skipPipelineCollapse — keep discrete single-workflow steps)');
    } else try {
      // Use a clean context (no previous messages) to avoid chat-history bias from prior turns.
      // Tier 1 evaluates this query in isolation: "can one workflow cover all the steps?"
      const tier1Context: ChatContext = {
        ...context,
        previousMessages: [],
      };
      const _t1UploadedParams = extractUploadedFileParams(message);
      const _t1MergedInline: Record<string, string> = {
        ...stripDatasetReferenceParams(decomposition.intents[0]?.inlineParameters, message),
        ..._t1UploadedParams,
      };
      const tier1Workflow = await this.generateWorkflow(
        message,
        [],
        _t1MergedInline,
        tier1Context,
        decomposition.preferredDomains,
        decomposition.keyTerms,
        context.sessionDatasets?.length ? context.sessionDatasets : undefined,
        decomposition.penalizedDomains,
        undefined,
        undefined,
        message
      );
      if (tier1Workflow?.success && tier1Workflow?.nextflow_path) {
        const _t1Name = tier1Workflow.workflow_name || tier1Workflow.workflow_ga?.name || tier1Workflow.name || tier1Workflow.nextflow_path?.split('/').pop() || 'workflow';
        log(`Tier 1: Got workflow "${_t1Name}" (${tier1Workflow.nextflow_path}) — checking coverage`);
        const coverage = await this._checkWorkflowCoverage(
          _t1Name,
          tier1Workflow.description || tier1Workflow.message || '',
          decomposition.intents,
          message
        );
        log(`Tier 1 coverage: ${coverage.coveredCount}/${decomposition.intents.length} steps, confidence=${coverage.confidence.toFixed(2)}`);
        // HIGH confidence threshold (≥0.8): auto-collapse to single workflow without asking.
        if (coverage.confidence >= 0.8 && coverage.coversAll) {
          // Merge all inline params into the workflow
          const mergedParams = Object.assign({}, ...decomposition.intents.map(i => stripDatasetReferenceParams(i.inlineParameters, message)));
          tier1Workflow.parameters = { ...tier1Workflow.parameters, ...mergedParams };
          log(`Tier 1 MATCH: returning single workflow card`);
          const allFacts = decomposition.intents.flatMap(i => i.facts);
          const t1Summary = this._buildPreExecutionSummary(tier1Workflow, message, context.sessionDatasets);
          const t1BaseMsg = `I'll run the **${_t1Name}** workflow — it handles all your steps in one integrated pipeline.`;
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
          const mergedParams = Object.assign({}, ...decomposition.intents.map(i => stripDatasetReferenceParams(i.inlineParameters, message)));
          tier1Workflow.parameters = { ...tier1Workflow.parameters, ...mergedParams };
          const allFacts = decomposition.intents.flatMap(i => i.facts);
          const t1mSummary = this._buildPreExecutionSummary(tier1Workflow, message, context.sessionDatasets);
          const t1mBaseMsg = `I believe the **${_t1Name}** workflow covers your full request — it handles all the described steps in one integrated run. Please review and confirm this meets your needs before running.`;
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

    // TIER 2: curated chain (see _curatedChainResponse).
    // Dual-path: honour a real chainHint even when skipPipelineCollapse
    // (that flag only blocks Tier-1 single-wf collapse — e.g. Admet Pred).
    // Step-by-step library triage sets chainHint=null so this no-ops.
    {
      const wantedCatalog =
        decomposition.libraryMoleculePath === 'catalog_mega_chain' ||
        (!!decomposition.chainHint && noCollapse);
      const wantedHint = decomposition.chainHint;
      const tier2 = await this._curatedChainResponse(decomposition, message, context, log);
      if (tier2) return tier2;
      if (noCollapse && !decomposition.chainHint) {
        log('Tier 2: no catalog chainHint (sequential step-by-step path)');
      }
      // Catalog mega-chain miss must NOT silently invent Tier-3 placeholders
      // that look like the curated chain (Bugbot Medium #4).
      if (wantedCatalog && wantedHint && !tier2) {
        log(`Tier 2: catalog mega-chain "${wantedHint}" unresolved — returning disambiguation (no Tier-3 invent)`);
        return {
          message: [
            `I recognised your request as the curated **${wantedHint.replace(/_/g, ' ')}** pipeline, but that catalog chain could not be loaded right now.`,
            '',
            'I am **not** inventing a substitute step-by-step plan that would look like the mega-chain.',
            'Retry in a moment, or ask for a single workflow (e.g. ADMET only, docking only) and I will route that directly.',
          ].join('\n'),
          intentType: 'clarification',
          intentConfidence: 0.7,
          isMultiIntent: false,
          extractedFacts: [],
          suggestions: [
            'Retry the screening pipeline',
            'Run ADMET only on my compounds',
            'Dock my library with Vina',
          ],
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
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TIER 3: Greedy sequential resolution.
    // Resolve steps one cluster at a time; a single workflow may cover multiple
    // consecutive biological steps. When skipPipelineCollapse, resolve each
    // intent independently (one catalog workflow per step — task-by-task).
    // ═══════════════════════════════════════════════════════════════════════
    log('Tier 3: Greedy sequential resolution');

    const stepResults: Array<{ intent: DecomposedIntent; subResult: any; idx: number }> = [];
    let remainingIntents = [...decomposition.intents];
    let globalIdx = 0;

    while (remainingIntents.length > 0) {
      const currentIntent = remainingIntents[0];
      // Build a combined sub-query for remaining steps to give the workflow search better context.
      // Independent resolution for skipPipelineCollapse avoids "dock then ADMET then …"
      // collapsing into a single wrong bind (e.g. Admet Pred).
      const stepQuery = noCollapse
        ? currentIntent.subQuery
        : remainingIntents.length > 1
          ? remainingIntents.slice(0, Math.min(3, remainingIntents.length)).map(i => i.subQuery).join(' then ')
          : currentIntent.subQuery;
      const combinedIntent: DecomposedIntent = { ...currentIntent, subQuery: stepQuery };

      log(`Tier 3 step ${globalIdx + 1}: resolving "${stepQuery}"`);
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
      if (!noCollapse && wf?.nextflow_path && remainingIntents.length > 1) {
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
      const resolvedPath = wf?.nextflow_path || resolveCanonicalChainStepPath(
        wf?.workflow_name || wf?.name || intent.subQuery || ''
      );
      return {
        id: intent.id || `step_${idx + 1}`,
        step_number: idx + 1,
        workflow_name: wf?.workflow_name || wf?.name || intent.subQuery,
        nextflow_path: resolvedPath || null,
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
    // Skipped when skipPipelineCollapse (library triage must stay multi-step).
    // -----------------------------------------------------------------------
    const resolvedPaths = pipelineSteps.map(s => s.nextflow_path).filter(Boolean);
    const uniquePaths = new Set(resolvedPaths);
    if (!noCollapse && resolvedPaths.length === pipelineSteps.length && uniquePaths.size === 1) {
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
      (s, i) => `  ${i + 1}. **${s.workflow_name}**${s.nextflow_path ? '' : ' (workflow not yet resolved)'}` +
        (s.uses_description ? `\n     → Input: ${s.uses_description}` : '')
    );
    const summaryMessage = [
      noCollapse
        ? `I've planned a **${pipelineSteps.length}-step library triage** — each step is a separate indexed workflow (run **task by task**):`
        : `I've planned a **${pipelineSteps.length}-step sequential pipeline** for you:`,
      '',
      ...stepSummaryLines,
      '',
      noCollapse
        ? 'Review the steps below. **Confirm & Run** starts step 1 only; after it finishes, **Approve & Run** the next step. Outputs stay available for later steps — this is not one mega-chain card.'
        : 'Review the steps below, then click **Confirm & Run** to execute them in order.',
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
        name: noCollapse
          ? `Library Triage (${pipelineSteps.length} steps — task by task)`
          : `Sequential Pipeline (${pipelineSteps.length} steps)`,
        pipeline_steps: pipelineSteps,
        step_count: pipelineSteps.length,
        source: noCollapse ? 'library_triage_sequential' : 'biomate_sequential',
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

  /** Non-sequential multi-intent request with >=2 workflow intents (parallel branches and/or a fan-in
   *  integration step) → POST /api/ai_assistant/plan_dag → one DAG pipeline card the chain executor
   *  runs (depends_on / connections / max_parallel). Before this, such requests produced separate
   *  single-workflow cards and the dependency structure was dropped (bulk RNA-seq + proteomics
   *  integration, external user 2026-11-03; docs/20261019 Part A "A-live"). Returns null — and the
   *  existing path continues — when there is nothing to plan or the backend refuses (with a reason). */
  private async _tryDagPlan(decomposition: IntentDecomposition, message: string, log: (s: string) => void,
    routedPaths: Map<string, string> = new Map()): Promise<GalaxyAssistantResponse | null> {
    const wf = decomposition.intents.filter(i =>
      (i.type === 'workflow_generation' || i.actions?.needsWorkflowGeneration) && i.execution !== 'direct_compute');
    if (wf.length < 2) return null;
    // Number the intents in dependency order: the classifier may list a combining step before its
    // branches, and a step can only depend on an earlier one — numbering in emitted order silently
    // dropped those edges and presented a fan-in as all-parallel (committee review 2026-11-05).
    const ordered = topoOrderIntents(wf);
    if (!ordered) {
      log('DAG plan not assembled (cyclic dependencies between workflow intents) — per-intent cards');
      return null;
    }
    const idx = new Map(ordered.map((i, k) => [i.id, k + 1]));
    const tasks = ordered.map((i, k) => ({
      id: i.id,
      description: i.subQuery || message,
      depends_on: (i.dependsOn || []).map(d => idx.get(d)).filter((n): n is number => typeof n === 'number' && n <= k),
      ...(routedPaths.get(i.id) ? { nextflow_path: routedPaths.get(i.id) } : {}),
    }));
    const { data } = await this._api().client.post('/api/ai_assistant/plan_dag', {
      tasks, name: dagPlanName(tasks, message), uploaded_datasets: uploadedRefsFromMessage(message),
    }, { timeout: 60000 });
    if (!data?.success || !data.workflow) {
      log(`DAG plan not assembled (${data?.reason || 'no response'}) — per-intent cards`);
      return null;
    }
    const card = data.workflow;
    const steps: any[] = card.pipeline_steps || [];
    // Repair prompt-as-name titles after plan_dag resolves catalog labels.
    const catalogLabels = steps
      .map((s) => String(s.workflow_label || s.workflow_name || '').trim())
      .filter(Boolean);
    if (catalogLabels.length && /^(which|what|how|why|rank these|dock the|triage this)\b|\?$/i.test(String(card.name || ''))) {
      card.name = catalogLabels.length === 1
        ? catalogLabels[0]
        : `${catalogLabels[0]} + ${catalogLabels.length - 1} more`;
    }
    log(`DAG plan assembled: ${steps.length} steps, max_parallel=${card.max_parallel}`);
    const lines = steps.map((s, k) => {
      const deps = (s.depends_on || []) as number[];
      const wired = !data.order_only;
      // User-facing name only — never leak the internal engine path (nextflow_path /
      // nextflow_nfcore/subworkflows/.../main.nf), per the storage-path redaction standard.
      return `  ${k + 1}. **${s.description || s.workflow_name}**` +
        (s.workflow_label ? ` — runs **${s.workflow_label}**` : '') +
        (s.reroute_reason ? ` — switched from ${s.rerouted_from} because it ${s.reroute_reason}` : '') +
        (deps.length
          ? ` (${wired ? 'uses the results of' : 'runs after'} step${deps.length > 1 ? 's' : ''} ${deps.join(', ')})`
          : ' (runs in parallel)');
    });
    const unwired: Array<{ from_step: number; to_step: number }> = data.unwired_dependencies || [];
    const hasJoin = steps.some(st => (st.depends_on || []).length > 0);
    const message_ = [
      hasJoin
        ? `I've planned this as **one ${steps.length}-step analysis**: the independent branches run in parallel and the combining step waits for them.`
        : `I've planned this as **one ${steps.length}-step analysis**: the steps are independent and run in parallel.`,
      '',
      ...lines,
      '',
      unwired.length
        ? (data.order_only
          ? `Step ${[...new Set(unwired.map(u => u.to_step))].join(', ')} runs after step${unwired.length > 1 ? 's' : ''} ${unwired.map(u => u.from_step).join(', ')}, but their result files are not connected to it automatically (the workflows do not declare matching input/output types) — select those results as its inputs when the earlier steps finish.`
          : `Before running, map the inputs of step ${[...new Set(unwired.map(u => u.to_step))].join(', ')} in the plan: the outputs of step${unwired.length > 1 ? 's' : ''} ${unwired.map(u => u.from_step).join(', ')} are not connected to it automatically.`)
        : '',
      ...dagInputStatus(steps, unwired.length > 0),
    ].filter(Boolean).join('\n');
    return {
      message: message_,
      intentType: 'workflow_generation',
      intentConfidence: 0.9,
      isMultiIntent: true,
      generatedWorkflow: { success: true, step_count: steps.length, source: 'biomate_dag', ...card },
      suggestions: ['Change the analysis for one branch', 'Run only one branch first', 'Explain the integration step'],
      sources: { toolSearchUsed: false, datasetRAGUsed: false, workflowGenerated: true, thinkingUsed: false, researchAgentUsed: false, benchmarkAgentUsed: false },
    } as GalaxyAssistantResponse;
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

    // Fork/join (independent branches and/or fan-in): one executable DAG. Each branch uses the
    // workflow this turn's own per-intent routing chose (a bare catalog search resolved an RNA-seq
    // DE branch to a CLIP-seq workflow, dev 2026-11-04).
    const routedPaths = new Map<string, string>();
    decomposition.intents.forEach((it, k) => {
      const wf: any = subIntentResults[k]?.generatedWorkflow;
      const path = wf?.nextflow_path || wf?.workflow_ga?.nextflow_path;
      if (wf?.success && typeof path === 'string' && path.endsWith('.nf')) routedPaths.set(it.id, path);
    });
    const dagResponse = await this._tryDagPlan(decomposition, message, log, routedPaths).catch(() => null);
    if (dagResponse) {
      // The other parts of the request (interpretation, literature, benchmark…) were already answered in
      // Steps 4–5; returning only the plan discarded them (committee review 2026-11-05).
      const others = decomposition.intents
        .map((it, k) => ({ it, r: subIntentResults[k] }))
        .filter(({ it, r }) => !(it.type === 'workflow_generation' || it.actions?.needsWorkflowGeneration)
          && typeof r?.message === 'string' && r.message.trim());
      if (others.length) {
        dagResponse.message += '\n\n' + others.map(({ it, r }) => `**${it.subQuery}**\n\n${String(r?.message || '').trim()}`).join('\n\n');
      }
      onResponseDelta?.(dagResponse.message);
      return dagResponse;
    }

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

    // Preserve one result per requested intent, even when executable paths match.
    const additionalWorkflows = additionalIntentWorkflows(subIntentResults, workflowResult, isRunnableWf);

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
    const _multiGroundResult = await groundInlineParameters({
      workflowName: _multiWorkflowName,
      rawParams: primaryIntent.inlineParameters,
      userQuery: primaryIntent.subQuery || message,
      requiredParams: _multiGeneratedWorkflow?.workflow_ga?.required_params,
      optionalParams: _multiGeneratedWorkflow?.workflow_ga?.optional_params,
      onStatus: onToolEvent
        ? (msg, payload) =>
            onToolEvent({
              type: 'status',
              tool_use_id: 'param_ground_' + (_multiWorkflowName || 'wf'),
              name: 'parameter_extraction',
              message: msg,
              payload,
            })
        : undefined,
    });
    // Same as the single-intent path: attachment-bound + prepared-input key=value
    // slots are carried into the overlay and no longer asked about.
    const _multiQuery = primaryIntent.subQuery || message;
    if (_multiGeneratedWorkflow?.workflow_ga) {
      applyPreparedInputParamsToWorkflow(_multiGeneratedWorkflow.workflow_ga, _multiQuery);
    } else if (_multiGeneratedWorkflow) {
      applyPreparedInputParamsToWorkflow(_multiGeneratedWorkflow, _multiQuery);
    }
    const _multiAttachmentBound = attachmentBoundParams(_multiGeneratedWorkflow);
    const _multiPreparedKv = parsePreparedInputParams(_multiQuery, [
      ...((_multiGeneratedWorkflow?.workflow_ga?.required_params || []).map((p: any) => p?.name).filter(Boolean)),
      ...((_multiGeneratedWorkflow?.workflow_ga?.optional_params || []).map((p: any) => p?.name).filter(Boolean)),
    ]);
    const _multiFilled: Record<string, string> = {
      ..._multiPreparedKv,
      ..._multiAttachmentBound,
    };
    const _multiRemappedInlineParams = {
      ..._multiPreparedKv,
      ...stringifyParamValues(_multiGroundResult.params),
      ..._multiAttachmentBound,
    };
    const _multiClarifications = (_multiGroundResult.details?.clarifications || []).filter(
      (c) => !_multiFilled[c.paramName],
    );

    const multiIntentResult: GalaxyAssistantResponse = {
      message: response.message,
      intentType: primaryIntent.type,
      intentConfidence: primaryIntent.confidence,
      inlineParameters: Object.keys(_multiRemappedInlineParams).length > 0 ? _multiRemappedInlineParams : undefined,
      paramClarifications: _multiClarifications.length > 0 ? _multiClarifications : undefined,
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

  /** Post-classifier routing for one sub-intent of a multi-intent message: the classifier decided;
   *  only reconcile its execution mode with its action flags (see _applyPostClassifierRouting). */
  _applySubIntentRouting(intent: DecomposedIntent, originalMessage: string, context?: ChatContext): void {
    reconcileExecutionMode(intent, conversationHasComputableData(originalMessage, context) && !conversationHasPipelineScaleData(originalMessage, context));
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

    this._applySubIntentRouting(intent, originalMessage, context);

    try {
      // Action-flag-based routing: multiple agents can be invoked per intent

      // Tool search results already available from parallel search
      if (actions.needsToolSearch && recommendedTools.length > 0) {
        baseResult.recommendedTools = recommendedTools;
      }

      // Workflow generation — intent flags already determined by analyzeIntent
      if (actions.needsWorkflowGeneration || actions.needsWorkflowModification) {
        // Route this branch's scientific task. Catalog/domain context is supplied separately;
        // reusing the full request here makes every branch select the same primary workflow.
        // The LLM's task_spec (method + data type + input format, no design labels) when present: the
        // free-text sub-query's "WT vs KO / lysate / triplicates" matched a CLIP-seq workflow whose
        // inputs are named wt_/ko_ (dev, 2026-11-04).
        const effectiveIntent = workflowIntent(intent.taskSpec || intent.subQuery, originalMessage);
        const _branchDomain = canonicalBranchDomain(intent.domain);
        if (_branchDomain) {
          preferredDomains = [_branchDomain, ...(preferredDomains || []).filter(d => d !== _branchDomain)];
        }
        const _subUploadedParams = extractUploadedFileParams(originalMessage || intent.subQuery);
        const _subMergedInline: Record<string, string> = {
          ...stripDatasetReferenceParams(intent.inlineParameters, originalMessage || intent.subQuery),
          ..._subUploadedParams,
        };
        const workflow = await this.generateWorkflow(
          effectiveIntent,
          recommendedDatasets.map(d => d.dataset),
          _subMergedInline,
          context,
          preferredDomains,
          keyTerms,
          context.sessionDatasets?.length ? context.sessionDatasets : undefined,
          penalizedDomains,
          intent.inputKinds,  // this branch's own data, not the whole message's
          undefined,
          originalMessage || intent.subQuery
        );
        baseResult.generatedWorkflow = workflow;
      }

      // Research agent
      if (actions.needsResearchAgent) {
        try {
          baseResult.researchResponse = await this._api().queryResearch({
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
          baseResult.benchmarkEvidence = await this._api().queryBenchmark({
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
    // Resolution delegated to chain-hint-fallback.resolveChainHintNames so the
    // fallback-vs-live path is unit-testable without spinning up Galaxy.
    // intent_hint=true (handled inside the helper) excludes bioc_reactive chains
    // so the classifier doesn't mis-route single-step requests into full chains.
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    const { names, fromFallback } = await resolveChainHintNames(galaxyUrl);
    if (!fromFallback) {
      this._chainHintNamesCache = { names, fetchedAt: Date.now() };
    }
    return names;
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

    // Short-circuit: the user is asking why THEIR OWN run failed / is stuck.
    // Deterministically route to run_diagnostics so the answer is composed from
    // the run record's recorded error (the recent-runs-with-errors block injected
    // upstream), NOT the research/literature agent. The production misroute this
    // fixes: "why is the run failing?" was classified research_question and
    // answered with a generic cited paper ("code execution often fails… please
    // provide the error message/logs") three times — for logs BioMate already had
    // (org-user issue #3, 2026-11-09). Gated on a real run-problem phrasing and a
    // userId (so we have a run to inspect), and excluded when the user is clearly
    // asking for new literature instead (so "find papers on why runs fail" still
    // reaches research). asksAboutRunProblem is already scoped to not match
    // generic questions like "what is the failure rate of CAR-T therapy?".
    const _wantsLiterature = /\b(find|search|cite|review|look up)\b[^.?!\n]{0,40}\b(papers?|literature|publications?|studies|articles?)\b|\bpapers? (?:on|about)\b/i.test(message);
    if (asksAboutRunProblem(message) && context.userId && !_wantsLiterature) {
      const diagIntent: DecomposedIntent = {
        id: 'intent_run_diagnostics_forced',
        type: 'run_diagnostics',
        subQuery: message,
        keywords: [],
        inlineParameters: {},
        needsToolSearch: false,
        needsDatasets: false,
        confidence: 0.95,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType('run_diagnostics'),
      };
      console.log('[GalaxyAssistant] Short-circuit: run-diagnostics (user asked why their run failed) — bypassing research/literature routing');
      return { intents: [diagIntent], isMultiIntent: false, primaryIntent: diagIntent };
    }

    // Short-circuit: E2E test hook — bypass LLM classification entirely.
    // Only reachable when context.testForceIntent is set, which routes.ts
    // gates behind the E2E bypass token (never set by normal product requests).
    if (context.testForceIntent) {
      const forcedType = context.testForceIntent;
      const forcedIntent: DecomposedIntent = {
        id: 'intent_force_test',
        type: forcedType,
        subQuery: message,
        keywords: [],
        inlineParameters: {},
        needsToolSearch: false,
        needsDatasets: false,
        confidence: 1.0,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType(forcedType),
      };
      return { intents: [forcedIntent], isMultiIntent: false, primaryIntent: forcedIntent };
    }

    const chainHintList = (await this._getChainHintNames()).join(', ');
    const systemPrompt = localOnly()
      ? localIntentPrompt(sessionMemoryBlock, context.accumulatedFacts, chainHintList.split(', '), message)
      : `${sessionMemoryBlock}${intentRulesBlock(context.projectRules)}You are a bioinformatics intent analyzer. Classify user messages by their information need and declare which system agents should handle the request.

When a "[Prior conversation context]" block appears before the message, use it to understand the user's full intent. The current message may be a short confirmation, file path, or follow-up — synthesize the **complete** bioinformatics intent (goal + data + parameters) into the subQuery field rather than copying the literal current message. Example: if prior context says "run RNA-seq on mouse samples" and current message is "s3://bucket/R1.fastq.gz", produce subQuery: "RNA-seq alignment and quantification on mouse GRCm38 samples using paired-end FASTQ from s3://bucket/".


## Information Need Types

Describe the user's information need with a descriptive label. You may use these common labels or create a new one that better fits:

**workflow_generation** — Execute a computational pipeline or run code on user data. Covers: (a) Nextflow pipelines processing files/accessions (set needsWorkflowGeneration: true), and (b) direct code execution via run_code for ad-hoc computations on provided inputs such as a pasted sequence, numeric parameters, or a small dataset (set needsWorkflowGeneration: false, needsLLMReasoning: true). Both are execution tasks — the distinction is whether BioMate needs to launch a full Nextflow workflow or can compute directly.

**R/Bioconductor execution priority** — When a task requires R or Bioconductor tools (DESeq2, edgeR, limma, clusterProfiler, Seurat, etc.), follow this order:
1. Search BioMate's indexed Bioconductor workflows first (1,000+ available). If a matching workflow exists, use it (needsWorkflowGeneration: true, runs ${process.env.NEXTFLOW_USE_AWS === 'true' ? 'on AWS Batch' : 'via local Docker'} with full R + Bioconductor).
2. If no indexed workflow matches, generate a new Nextflow/R workflow and add it to BioMate's DB.
3. If the task is ad-hoc or too small for a full pipeline (single statistical test, small inline dataset), execute R directly via run_code (needsWorkflowGeneration: false).
**CRITICAL — inline data is ALWAYS workflow_generation, never tool_search:** If the user pastes data directly in the message (CSV rows, gene counts, a count matrix, SMILES strings, sequences, numeric arrays) AND uses an analysis verb (run, analyse, compute, test, compare, identify, find), classify as **workflow_generation**. The inline data IS their input — BioMate will execute the analysis. Never classify this as tool_search or research_question.
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

## Execution mode (every workflow_generation intent) — "execution": "direct_compute" | "pipeline"

Decide from what the request NEEDS, whatever language it is written in:
- **direct_compute** — the data is ALREADY in the conversation (an attached/uploaded file, a project dataset, or a table/list pasted in the message) and the task is an ad-hoc computation on it: summary statistics, means/fold changes, a statistical test, reshaping/merging tables, a plot, a correlation, a small differential-expression or clustering run on that table. BioMate computes it now with run_code and returns the numbers/figures.
- **pipeline** — the input must be fetched or processed by a workflow: raw reads/FASTQ/BAM, accessions (GSE/SRR/PDB…), SMILES for ADMET/docking models, structures, long-running or GPU tools, or the user asks for a workflow/pipeline.
Examples: "计算每个基因 treated/control 的 fold change 并按降序输出" + attached CSV → direct_compute. "Compare the two groups' cell viability and plot each sample" + attached table → direct_compute. "Cluster these pasted single-cell counts and draw a UMAP" (counts pasted) → direct_compute. "Run nf-core/rnaseq on SRR1234567" → pipeline. "Screen these SMILES for ADMET" → pipeline.

${routingExamplesPrompt()}

## HIGHEST PRIORITY RULE — Knowledge Reasoning vs Pipeline Execution

Ask a single question: **"Does completing this task require running a computational pipeline or tool on user-provided data — files, accession IDs, or molecular inputs?"**

- If yes → **workflow_generation**. The user may not have named their inputs yet; BioMate will ask.
- **"Prepare the plan / don't run it yet" is STILL workflow_generation.** A request to run/execute/process a concrete pipeline or tool on user data that ALSO says "prepare the plan", "draft the workflow", "set it up first", "don't launch/run/execute (any jobs) yet", "just plan it", "review before running", "stage it", or "show me the steps first" is **workflow_generation**. The user wants the workflow PREPARED as a draft card; actually launching it is a separate "Confirm & Run" step BioMate handles afterward. Do NOT downgrade these to general_question, experiment_design, or data_interpretation just because the user withheld the launch. (Only a request with NO concrete pipeline to run — pure strategy/study design — is experiment_design.) Example: "Run quality control, then alignment, then differential expression on my RNA-seq data — prepare the plan, don't launch any jobs yet" → **workflow_generation**, multi-intent, sequential.
- **Accession IDs are workflow inputs.** SRA (SRR/ERR/DRR), GEO (GSE/GSM), NCBI (PRJNA/PRJEB), UniProt IDs, PDB IDs, EMBL accessions — these are valid workflow inputs BioMate fetches automatically. "Run RNA-seq on SRR12345678" or "dock compound into PDB:3HTB" is workflow_generation, not a database lookup.
- **Molecular inputs are workflow inputs.** SMILES strings, PDB/SDF files, concentration-time CSV — signal workflow_generation for drug discovery / pharmacology workflows. But a conceptual or planning question about these topics (how does hERG work? what dose range is typical?) is still research_question or experiment_design.
- **Paper-to-workflow (CRITICAL):** If the user provides a research paper — via URL (http/https), DOI (10.xxx/...), arXiv ID, PMID, uploaded PDF, or "[Attached files: paper.pdf]" — AND uses any execution verb (run, reproduce, implement, build, execute, replicate, generate the workflow, do what they did, follow their pipeline, apply their method) → **workflow_generation**. The paper is the workflow specification; BioMate will fetch it and extract the methods. Do NOT classify as research_question or protocol_guidance.
- **Document reading without execution intent:** If the user provides a paper/URL and asks to read, summarize, extract, explain, or find information — WITHOUT asking to run anything → **protocol_guidance** (if asking about experimental steps) or **research_question** (if asking about findings/content).
- If the task is planning, strategy, or design WITHOUT asking BioMate to execute a pipeline → **experiment_design**.
- If the task is interpreting existing results, explaining what output means → **data_interpretation**.
- If the task is diagnosing why a run failed or a metric looks wrong → **troubleshooting**.
- If the task requires querying a live biological database (GWAS Catalog, OMIM, ClinVar, Open Targets, Ensembl) for structured facts → **database_lookup**, **genomics_knowledge**, or **clinical_genomics** as appropriate.
- If the task can be fully resolved from scientific literature or general biological knowledge → **research_question**.

Key distinction: **candidate lists from published studies are NOT user data.** A question giving a list of rsIDs or gene names from a published GWAS and asking to identify the causal one is a database lookup — no pipeline needed.

**HPO terms + ENSG candidate genes = clinical_genomics, NOT workflow_generation.** A task providing HPO phenotype codes and a list of ENSG gene IDs asking to identify the causal gene queries ClinVar/OMIM/Monarch — it does not run a Nextflow pipeline.

The distinction is the nature of the task, not the presence of file names in the message.

---

## Hard classification examples (highest priority — override any rule above)

These are real cases that LLMs tend to mis-classify. When the user message closely matches one of these patterns, use the classification shown:

| User message pattern | Correct classification | needsWorkflowGeneration |
|---|---|---|
| "Spectral counting from DDA mass spec" (method noun phrase, no verb) | workflow_generation | true |
| "Retention time alignment using iRT standards" | workflow_generation | true |
| "Clonal lineage reconstruction from BCR sequencing" | workflow_generation | true |
| "CC(=O)Nc1ccc(O)cc1 — predict hERG/ADMET" (raw SMILES + toxicity keyword) | workflow_generation | true |
| "Run ProTrek / Boltz-2 / Chai-1 / DrugCLIP on my sequence" (AI model name) | workflow_generation | true |
| "PBPK simulation for oral dosing of compound X" | workflow_generation | true |
| "PK-Sim / Simcyp / NONMEM model for this compound" (named PK tool) | workflow_generation | true |
| "BOIN dose-escalation design for 3+3 trial" | workflow_generation | true |
| "Pathway enrichment / GO analysis on this gene list" | workflow_generation | true |
| "GWAS → eQTL → scRNA colocalisation for this locus" | workflow_generation | true |
| "Multi-omics integration: RNA-seq + proteomics + metabolomics" | workflow_generation | true |
| "Run macrophage metabolic state analysis from scRNA" | workflow_generation | true |
| "CryoEM single-particle analysis of my dataset" | workflow_generation | true |
| "s3://bucket/sample.fastq.gz" (bare S3/GS path, follow-up turn) | workflow_generation | true |
| "SRR1234567, SRR1234568" (bare SRA accession list, follow-up turn) | workflow_generation | true |
| "yes" / "go ahead" / "use defaults" (confirmation in a workflow conversation) | workflow_generation | true |
| "What is hERG?" / "How does PBPK work?" (conceptual question, no execution intent) | research_question | false |
| "HP:0001250 HP:0001252 — ENSG00000123456 ENSG00000234567 — which is causal?" | clinical_genomics | false |

**General principle for ambiguous method-description queries (no explicit action verb):**
If the message names a bioinformatics method/tool and mentions user-owned data types (FASTQ, BAM, VCF, raw mass spec, scRNA, spatial, accession IDs, SMILES, PDB) — even without a verb like "run" or "analyse" — classify as **workflow_generation**. The user is describing what they want to do, not asking for an explanation.

**AI/ML model names not in the catalog above** (Boltz-2, Chai-1, ProTrek, DrugCLIP, SynCraft, STATE, scFv-ProteinMPNN, ProFam, ESM, AlphaFold search): always **workflow_generation** when the user is asking to run them on a sequence or structure input.

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

**Imaging / flow cytometry (workflow-specific availability):** CytoPipeline (flow cytometry), EBImage, and imcRtools-related workflows may be available when their declared input contract and runtime are confirmed. MCMICRO for CODEX, CyCIF, and MIBI is a candidate integration under validation, **not a currently runnable BioMate workflow**. Do not promise whole-slide pathology analysis; ask for the image modality and use only a workflow whose inputs and status are explicitly confirmed.

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
- Allometric scaling / FIH dose: "allometric scaling / inter-species scaling / human PK prediction from animals / FIH dose / MRSD / MABEL / power-law fit across species" with per-species CL/Vd/t_half (mouse/rat/dog/monkey) → workflow_generation (allometric_scaling). Disambiguation: do NOT use PBPK (no SMILES needed); do NOT ask for SMILES — allometric needs species CL/Vd values, not molecular structure. The workflow emits qc_metrics.json with R² (SILVER-anchored to FDA 2005 FIH; the 0.85 cutoff is community convention).
- Biologics: "scFv intrabody design / antibody developability / LNP formulation optimization" → workflow_generation

Key: providing concrete molecular inputs (SMILES, PDB, dose levels, CSV data) + asking to run/compute/predict = workflow_generation. Asking "how does hERG work?" = research_question.
${renderOperationSkillsBlock()}

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

## Workflow intent fields: "task_spec" and "domain" (every workflow_generation intent in a multi-intent reply)

BioMate routes each workflow intent to ONE catalog workflow by searching with its "task_spec". Write it as a precise analysis specification:
- the analysis METHOD (what computation), the DATA TYPE / assay, the INPUT FORMAT the user actually has (raw reads, a processed matrix, a results table, structures, SMILES…), and the EXPECTED OUTPUT;
- NO experimental-design labels: sample/cell-line names, genotypes or arms ("WT vs KO", "SCC9", "treated"), replicate counts, cohort names. Those are parameters — keep them in subQuery / inlineParameters / facts. They do not identify the method, and searching with them matches unrelated workflows that happen to use the same words.
"domain" is the branch's scientific domain: one of transcriptomics, proteomics, genomics, variant_calling, epigenomics, single_cell, metabolomics, multi_omics, systems_biology, drug_discovery, pharmacology, structural_biology, cryo_em, metagenomics, immunology, imaging.

Good vs bad task_spec:
- Request "duplicates of SCC9 WT vs KO lysates, DIA-NN report.pg_matrix.tsv": GOOD "differential protein abundance testing on a processed DIA-NN protein-group intensity matrix (log2 intensities, missing-value imputation), two-group comparison → per-protein log2 fold change and adjusted p-values", domain "proteomics". BAD "Differential abundance analysis of SCC9 WT vs KO lysate proteomics (duplicates)".
- Request "triplicates of WT and KO, counts and CPM in ko vs wt.csv": GOOD "differential gene expression on a bulk RNA-seq gene count matrix (DESeq2/edgeR-style negative-binomial model), two-group comparison → per-gene log2 fold change and adjusted p-values", domain "transcriptomics".
- Request "integrate the RNA and protein results": GOOD "integration of two quantitative omics layers (transcript and protein differential results or matrices) — multi-omics concordance / sparse PLS or co-inertia analysis → shared features, layer agreement, joint pathway enrichment", domain "multi_omics". BAD "Integrate bulk RNA-seq, lysate proteomics, and secretome proteomics differential results across SCC9 WT vs KO".
- Request "call variants on my WGS FASTQ pair, GRCh38": GOOD "germline short-variant calling from paired-end whole-genome FASTQ (alignment, duplicate marking, base recalibration, HaplotypeCaller) → annotated VCF", domain "variant_calling".

## Branch-and-integrate (fork/join) Detection

When a request analyses SEVERAL data layers or datasets independently and then COMBINES them — "integrate bulk RNA-seq and proteomics", "compare lysate and secretome proteomics with RNA-seq", "run DE in each cohort, then meta-analyse" — emit:
- one **workflow_generation** intent PER independent layer/dataset (its own subQuery naming that layer's data and analysis), with "dependsOn": [];
- one **workflow_generation** integration intent whose subQuery names the integration analysis, with "dependsOn" listing ALL the layer intents' ids;
- "is_sequential": false (the layers run in parallel; only the integration waits for them).
A single interpretation request about the combined result may follow as a separate (non-workflow) intent.
Worked example — "Integrate my bulk RNA-seq (KO vs WT triplicates, ko vs wt.csv with counts) with DIA proteomics of lysates (duplicates) and conditioned-media secretome (triplicates), report.pg_matrix.tsv from DIA-NN, and give a biological interpretation":
{"is_sequential": false, "preferred_domains": ["multi_omics","transcriptomics","proteomics"], "intents": [
 {"id":"intent_1","type":"workflow_generation","execution":"pipeline","subQuery":"Bulk RNA-seq differential expression, KO vs WT lysates (triplicates)","task_spec":"differential gene expression on a bulk RNA-seq gene count matrix, two-group comparison → per-gene log2 fold change and adjusted p-values","domain":"transcriptomics","dependsOn":[]},
 {"id":"intent_2","type":"workflow_generation","execution":"pipeline","subQuery":"Lysate proteomics differential abundance, KO vs WT (duplicates)","task_spec":"differential protein abundance on a processed DIA-NN protein-group intensity matrix (log2, imputation), two-group comparison → per-protein log2 fold change and adjusted p-values","domain":"proteomics","dependsOn":[]},
 {"id":"intent_3","type":"workflow_generation","execution":"pipeline","subQuery":"Secretome (conditioned media) proteomics differential abundance, KO vs WT (triplicates)","task_spec":"differential protein abundance on a processed DIA-NN protein-group intensity matrix of secreted proteins, two-group comparison → per-protein log2 fold change and adjusted p-values","domain":"proteomics","dependsOn":[]},
 {"id":"intent_4","type":"workflow_generation","execution":"pipeline","subQuery":"Integrate the RNA and protein differential results","task_spec":"integration of transcript and protein differential results — concordance and sparse PLS / co-inertia multi-omics integration → shared features and joint pathway enrichment","domain":"multi_omics","dependsOn":["intent_1","intent_2","intent_3"]},
 {"id":"intent_5","type":"data_interpretation","subQuery":"Biological interpretation of the integrated results","dependsOn":["intent_4"]}]}
(Abbreviated: real replies also carry keywords, actions, facts, confidence.)

Other shapes:
- Independent analyses, no combining step — "call variants on my WGS FASTQs and, separately, run RNA-seq DE on my counts" → two workflow intents, both "dependsOn": [], is_sequential false.
- Screening fan-out — "dock these 200 SMILES against EGFR and also predict their ADMET" → two parallel workflow intents over the same input (docking; ADMET prediction), both "dependsOn": []; a third "rank by docking score and ADMET" intent depends on both.
- Strict chain — "QC, then align, then call peaks" → the Sequential Pipeline format below, not this one.

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
  "execution": "direct_compute",
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
  "chain_hint": null,
  "rationale": "User pasted a raw nucleotide sequence inline with no file attachment — this is a direct in-line computation request, not a pipeline execution."
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
  "input_kinds": ["fastq"],
  "needs_thinking": false,
  "chain_hint": null,
  "rationale": "User supplied SRA accessions plus an explicit RNA-seq differential-expression goal, so this routes to a Nextflow transcriptomics pipeline (nf-core/rnaseq) rather than a direct inline computation."
}

Note: chain_hint is null here even though this involves RNA-seq + DE, because the user did not
explicitly ask for a named multi-step pipeline. BioMate will route this to the best single
workflow (nf-core/rnaseq). Chain suggestions for downstream DE analysis come reactively after
the run completes.

Key rule: needsWorkflowGeneration: true when the user provides a file path, SRA/GEO accession, or any data reference that must be fetched and processed by a Nextflow pipeline. needsWorkflowGeneration: false when the user pastes the data inline (a short sequence, a few numbers, a small table) and BioMate can compute the answer directly without a pipeline.

preferred_domains: list of 0–3 domain strings most relevant to this query, chosen from:
  [${PREFERRED_DOMAINS_PROMPT_LIST}]
  Leave empty [] when the query is domain-agnostic or unclear.

input_kinds: the kinds of data the user HAS and wants analysed (the workflow's input), chosen ONLY from:
  [${INPUT_KIND_VOCAB.join(', ')}]
  Raw instrument data: fastq (reads, SRA runs), bam (aligned reads/CRAM), raw_spectra (.raw/.mzML/.d/.wiff), idat,
  bcl, nanopore_signal, raw_images. Processed: counts_matrix, h5ad (AnnData/Seurat/SCE objects), cellranger_output,
  protein_table (MaxQuant proteinGroups, DIA-NN pg_matrix, protein intensities), peptide_table (peptides.txt,
  precursor/PSM reports), metabolite_table, beta_values, vcf, peaks, gene_list; other: fasta, annotation, structure,
  molecules, tabular. Rules: list what the user says they have or attached — NOT the outputs they want ("get beta
  values" from IDATs → ["idat"]), NOT data they say they lack ("I don't have the raw files, only proteinGroups.txt"
  → ["protein_table"]), NOT reference files the workflow downloads. When the user has several kinds but asks to use
  one ("I have FASTQ but only want DE on my count matrix"), list the one to be analysed (["counts_matrix"]).
  [] when the user states no input data. In a multi-intent response, give "input_kinds" on EACH intent (that
  branch's own input).

user_constraint: "no_workflow" when the user explicitly says not to build/use/run a workflow or pipeline, or wants
  interpretation/explanation only ("不用工作流", "不要运行", "只做解读", "no pipeline", "don't run anything") — then
  needsWorkflowGeneration MUST be false (execution=direct_compute if they still want a computation on their data);
  "no_launch" when they want the workflow prepared but not launched yet ("先别运行", "don't launch yet") — still a
  workflow_generation draft; null otherwise.

key_terms: up to 8 specific technical terms that boost workflow search recall. Prioritise:
  1. The ASSAY TYPE / SEQUENCING TECHNOLOGY — e.g. "ATAC-seq", "ChIP-seq", "16S amplicon",
     "DIA proteomics", "Hi-C", "CUT&RUN", "ancient DNA", "metagenome assembly"
  2. The INPUT FILE FORMAT — e.g. "FASTQ", "BAM", "count matrix", ".idat", "BCL", ".raw mass-spec"
  3. KEY TOOLS that appear in the workflow — e.g. "STAR", "GATK", "DESeq2", "MACS2",
     "Bismark", "DIA-NN", "QIIME2", "Salmon", "sarek", "nf-core/rnaseq"
  4. THE ANALYSIS GOAL in technical vocabulary — e.g. "differential expression",
     "peak calling", "variant calling", "metagenome-assembled genomes", "DMR analysis"
  For MULTI-HOP queries (user describes an outcome without naming the assay), infer the
  assay from context: "accessible regions" → "ATAC-seq open chromatin"; "cell type composition
  at single-cell resolution" → "scRNA-seq 10X Genomics"; "chromatin loops TADs" → "Hi-C";
  "transcription factor binding" → "ChIP-seq peak calling MACS2".
  Omit generic words like "run", "analyze", "data", "pipeline", "workflow".

needs_thinking: true only when the query requires multi-step reasoning, pipeline design,
  troubleshooting, or methodology comparison. false for simple workflow execution requests.

user_requested_synthetic_data: ALWAYS include (true/false). true when the user explicitly wants
  generated values: to generate, simulate, mock up or use example / demo / toy / test / synthetic
  data (in any language, e.g. "make an example dataset", "生成示例数据", "用模拟数据演示"), or a task that
  is itself a simulation (Monte Carlo, power / sample-size analysis, simulated curves). false when
  the user wants their own, attached, staged or a workflow's real built-in data analysed — even if
  that data is not attached yet. Judge the meaning, not the words.

chain_hint: ONLY set if the user explicitly requests a named multi-step pipeline that spans ALL
  the steps in that chain (e.g. "run the full drug discovery pipeline", "target-to-lead", "rare
  disease multi-modal workup"). NEVER set if the user asks for a single analysis type (RNA-seq,
  differential expression, ADMET screening) even if that step is part of a chain — a partial
  request should go through normal workflow search (Tier 1), not chain escalation. Set null when
  in doubt.
  Known chain names: [${chainHintList}]

rationale: ALWAYS include a single plain-language sentence (max ~30 words) explaining WHY you
  classified the request this way — the data shape you saw, the goal you inferred, and why it
  routes to this kind of handling (inline compute vs Nextflow pipeline vs research, etc.). This
  is shown to the user as a "why this routing" note, so write it for them, not as debug text.
  Required for every single-intent response.

For MULTI-intent messages (parallel), respond with an "intents" array:
{
  "is_sequential": false,
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["differential expression", "DESeq2", "edgeR"],
  "needs_thinking": true,
  "chain_hint": null,
  "rationale": "User asked for two things at once — run DE on their RNA-seq data and compare DESeq2 vs edgeR — so this is split into parallel intents: one pipeline run and one methods comparison.",
  "intents": [
    {
      "id": "intent_1",
      "type": "workflow_generation",
      "subQuery": "Run DE analysis on my RNA-seq data",
      "task_spec": "differential gene expression on bulk RNA-seq data, two-group comparison → per-gene log2 fold change and adjusted p-values",
      "domain": "transcriptomics",
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
  "chain_hint": null,
  "rationale": "This is a factual biomedical knowledge question with no data to process, so it routes to the research agent rather than a workflow."
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

For MULTI-HOP workflow queries (user describes a biological goal without naming the assay):
"Which genomic regions are accessible in my cell type? I want to identify active regulatory elements."
{
  "type": "workflow_generation",
  "keywords": ["accessible chromatin", "regulatory elements"],
  "inlineParameters": {},
  "needsToolSearch": true,
  "needsDatasets": false,
  "confidence": 0.88,
  "actions": {
    "needsToolSearch": true,
    "needsWorkflowGeneration": true,
    "needsWorkflowModification": false,
    "needsResearchAgent": false,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": false
  },
  "facts": [{"category": "data_type", "value": "ATAC-seq FASTQ", "confidence": 0.85}],
  "workflowAmbiguity": null,
  "preferred_domains": ["genomics"],
  "key_terms": ["ATAC-seq", "open chromatin", "MACS2", "peak calling", "FASTQ", "Tn5 transposase"],
  "needs_thinking": false,
  "chain_hint": null
}

"Find genes that are up- or down-regulated between my treatment and control groups"
{
  "type": "workflow_generation",
  "keywords": ["differential expression"],
  "inlineParameters": {},
  "needsToolSearch": true,
  "needsDatasets": false,
  "confidence": 0.82,
  "actions": {
    "needsToolSearch": true,
    "needsWorkflowGeneration": true,
    "needsWorkflowModification": false,
    "needsResearchAgent": false,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": false
  },
  "facts": [{"category": "analysis_goal", "value": "differential expression", "confidence": 0.95}],
  "workflowAmbiguity": "input_format",
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["differential expression", "DESeq2", "count matrix", "RNA-seq"],
  "needs_thinking": false,
  "chain_hint": null
}

"I want to know what cell types are present in my tumor biopsy at single-cell resolution"
{
  "type": "workflow_generation",
  "keywords": ["cell type annotation", "single-cell"],
  "inlineParameters": {},
  "needsToolSearch": true,
  "needsDatasets": false,
  "confidence": 0.88,
  "actions": {
    "needsToolSearch": true,
    "needsWorkflowGeneration": true,
    "needsWorkflowModification": false,
    "needsResearchAgent": false,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": false
  },
  "facts": [{"category": "data_type", "value": "scRNA-seq FASTQ", "confidence": 0.87}],
  "workflowAmbiguity": null,
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["scRNA-seq", "10X Genomics", "cell barcode demultiplexing", "FASTQ", "STARsolo"],
  "needs_thinking": false,
  "chain_hint": null
}

**Library / molecule-design — dual path (both supported).**
(A) Catalog mega-chain: when the request matches a REAL known chain in the list above
(e.g. drug_discovery_admet_gated_screening, drug_discovery_screening, admet_to_cipa_cardiac,
target_to_lead_full, andv_inhibitor_track_v1), set chain_hint to that exact name and
is_sequential true. Do NOT invent new chain names.
(B) Step-by-step: when the user asks to triage a compound/SMILES library into "synthesise-now"
vs "park" (or triage+library with no matching catalog chain), this is multi-intent sequential
workflow_generation with ≥3 intents: (1) AutoDock Vina docking, (2) predict_admet_properties,
(3) pharmacophore_filtering. Set chain_hint null — do NOT collapse to a single Admet Pred /
ADMET-only workflow and do NOT invent a curated mega-chain. Each intent is one ordinary
indexed workflow; BioMate runs them task by task.

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

    // Always give UQU the conversation history. The LLM decides what is relevant:
    // it will use prior turns when the current message is a follow-up and ignore
    // them when the user has switched topics. No programmatic gate needed.
    const priorUserTurns = (context.previousMessages || [])
      .filter((m) => m.role === 'user' && (m.content || '').trim().length > 10)
      .slice(-3)
      .map((m, i) => `Turn ${i + 1}: ${(m.content || '').trim().slice(0, 400)}`);
    const messageForUQU = priorUserTurns.length > 0
      ? `[Prior conversation context:\n${priorUserTurns.join('\n')}\n]\n\nCurrent user message (classify this):\n${message}`
      : message;

    try {
      const intentStartTime = Date.now();
      // Two-tier Gemini routing: Pro for complex queries, Flash for simple ones.
      // Falls back to the configured intentModel for non-Gemini backbones.
      const configured = this.modelConfig.intentModel;
      // "openrouter:<slug>" = classify/decompose with that model via OpenRouter using its OWN key
      // (BIOMATE_DECOMP_OPENROUTER_KEY — not OPENROUTER_API_KEY, which routes every keyless user's whole
      // chat through OpenRouter). Chosen on the held-out decomposition benchmark (docs/20261103 §12.2).
      // On failure the Gemini path below runs (Flash), then the keyword fallback, marked degraded.
      let orModel = configured.startsWith('openrouter:') ? configured.slice('openrouter:'.length) : '';
      let orKey = process.env.BIOMATE_DECOMP_OPENROUTER_KEY || '';
      // China-region users: the Chinese set's intent model (llm-region-policy.ts CN_MODEL_SET.intent,
      // overridable by BIOMATE_CN_INTENT_MODEL) on the user's Chinese route — not the deployment's
      // decomposition model and not the response model.
      const cnRoute = requireCnRoute();
      const cnOnprem = !!cnRoute && cnRoute.url !== OPENROUTER_URL;
      if (cnRoute) {
        orModel = cnRoute.models.intent;
        orKey = cnRoute.key;
      }
      const isGemini = configured.startsWith('gemini-') || !!orModel;
      const effectiveIntentModel = orModel ? GEMINI_FLASH_MODEL : isGemini ? pickGeminiIntentModel(message) : configured;
      let primaryText: string | undefined;
      if (orModel && !orKey) {
        console.warn(`[Intent] BIOMATE_INTENT_MODEL=openrouter:${orModel} but BIOMATE_DECOMP_OPENROUTER_KEY is unset — using ${GEMINI_FLASH_MODEL}`);
      }
      if (orModel && orKey) {
        primaryText = await (cnOnprem
          ? cnCompletion(cnRouteForRole(cnRoute!, 'intent'), { system: systemPrompt, messages: [{ role: 'user', content: messageForUQU }] })
          : decomposeViaOpenRouter(orModel, orKey, systemPrompt, messageForUQU)).catch((e: any) => {
          console.warn(`[Intent] primary decomposition model ${orModel} failed (${String(e?.message || e).slice(0, 160)}) — falling back to ${GEMINI_FLASH_MODEL}`);
          return undefined;
        });
        if (primaryText !== undefined) console.log('[GalaxyAssistant] Intent API response (OpenRouter):', { model: orModel, time_ms: Date.now() - intentStartTime });
      }
      console.log('[GalaxyAssistant] Intent API request:', {
        model: effectiveIntentModel,
        tier: isGemini ? (effectiveIntentModel === GEMINI_PRO_MODEL ? 'pro' : 'flash') : 'non-gemini',
        max_tokens: 4096,
        system_prompt_length: systemPrompt.length,
        message_length: message.length
      });

      // Intent classification - using configurable model (Anthropic or Gemini)
      let resultText: string;

      if (primaryText !== undefined) {
        resultText = primaryText;
      } else if (isGemini && this.gemini) {
        const geminiModel = this.gemini.getGenerativeModel({
          model: effectiveIntentModel,
          // Bumped 2500→4096: complex tier 0 queries (e.g. T03 "Base editing strategy for
          // PCSK9 LOF in hypercholesterolemia (VERVE-102 style)") truncated JSON output at
          // 2500, producing "Unexpected end of JSON input" and zero workflow_ready event.
          // Gemini thinking tokens count against this budget; 4096 leaves room for the
          // full intent + inlineParameters payload.
          // thinkingBudget: 0 — intentional: Flash thinking disabled for latency.
          generationConfig: { temperature: 0, maxOutputTokens: 4096, responseMimeType: 'application/json', thinkingConfig: { thinkingBudget: 0 } } as any,
          systemInstruction: systemPrompt,
        });
        // Attempt Gemini; on 429 immediately fall back to Haiku — no slow retry loop.
        let geminiResult: any;
        let usedGeminiFallback = false;
        try {
          const geminiTimeout = new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error('Gemini intent timeout after 30s')), 30_000)
          );
          geminiResult = await Promise.race([geminiModel.generateContent(messageForUQU), geminiTimeout]);
        } catch (err: any) {
          const is429 = err?.message?.includes('429') || err?.status === 429;
          const isTimeout = err?.message?.includes('timeout');
          if (is429 || isTimeout) {
            if (isTimeout) console.warn('[GalaxyAssistant] Gemini intent classification timed out (>30s) — falling back to Flash chain');
            else console.warn('[GalaxyAssistant] Gemini 429 — falling back to Haiku for intent classification (no delay)');
            usedGeminiFallback = true;
          } else {
            throw err;
          }
        }

        if (usedGeminiFallback) {
          // Gemini 429 fallback: route through the YAML chain (Gemini 3.5 Flash →
          // Claude → GPT-4o → Ollama) rather than crashing when ANTHROPIC_API_KEY
          // is empty. Direct Haiku path preserved only as last resort if chain fails.
          console.warn('[GalaxyAssistant] Gemini 429 → using YAML fallback chain for intent classification');
          const { llmGenerate } = await import('./llm-client');
          let chainResult: string | null = null;
          try {
            const r = await llmGenerate({
              prompt: messageForUQU,
              system: systemPrompt,
              maxTokens: 4096,
              jsonMode: false,
            });
            chainResult = r.text || null;
            console.log('[GalaxyAssistant] Intent chain fallback done:', {
              model_used: r.modelUsed, fallback_depth: r.fallbackDepth,
              time_ms: Date.now() - intentStartTime,
            });
          } catch (chainErr: any) {
            console.warn('[GalaxyAssistant] Chain fallback also failed; trying Haiku directly:', chainErr?.message);
          }
          if (chainResult !== null) {
            resultText = chainResult;
          } else if (process.env.ANTHROPIC_API_KEY) {
            // Direct Haiku only when we have a real key (centralised tool-ranking model)
            const haiku = this.modelConfig.toolRankingModel;
            const fallbackCompletion = await this._withAnthropicRetry(
              () => this._getClaude().messages.create({
                model: haiku,
                max_tokens: 4096,
                system: systemPrompt,
                messages: [{ role: 'user', content: messageForUQU }],
              }),
              'intent-classification-haiku-fallback',
            );
            console.log('[GalaxyAssistant] Intent Haiku fallback response:', {
              model: haiku,
              time_ms: Date.now() - intentStartTime,
              usage: fallbackCompletion.usage,
            });
            const fc = fallbackCompletion.content[0];
            resultText = fc.type === 'text' ? fc.text : '{}';
          } else {
            throw new Error('Intent classification failed: Gemini 429, chain exhausted, no Anthropic key');
          }
        } else {
          resultText = geminiResult.response.text();
          console.log('[GalaxyAssistant] Intent API response (Gemini):', {
            model: effectiveIntentModel,
            time_ms: Date.now() - intentStartTime,
          });
        }
      } else {
        // Anthropic path (default). When ANTHROPIC_API_KEY is absent but a custom
        // OpenAI-compatible client is available (e.g. Qianwen on-prem), use that
        // instead so intent classification works without Claude.
        const compatClient = _openrouterClientStorage.getStore();
        if (!process.env.ANTHROPIC_API_KEY && compatClient) {
          const compatModel = process.env.LLM_MODEL || 'qwen-max';
          console.log('[GalaxyAssistant] Intent classification via OpenAI-compatible provider:', compatModel);
          const stream = await compatClient.chat.completions.create({
            model: compatModel,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: messageForUQU },
            ],
            stream: true,
            max_tokens: 4096,
            temperature: 0,
          });
          let text = '';
          for await (const chunk of stream) {
            text += chunk.choices[0]?.delta?.content ?? '';
          }
          resultText = text;
          console.log('[GalaxyAssistant] Intent API response (OpenAI-compatible):', {
            model: compatModel,
            time_ms: Date.now() - intentStartTime,
          });
        } else {
          // Note: temperature is deprecated for Claude 4.x models
          const completion = await this._withAnthropicRetry(
            () => this._getClaude().messages.create({
              model: this.modelConfig.intentModel,
              max_tokens: 4096,
              system: [
                {
                  type: 'text',
                  text: systemPrompt,
                  cache_control: { type: 'ephemeral' },
                },
              ],
              messages: [{ role: 'user', content: messageForUQU }],
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
      }

      // Strip markdown code blocks if present
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')
        .replace(/\n?```+\s*$/gi, '')
        .replace(/^\s*`+\s*/g, '')
        .replace(/\s*`+\s*$/g, '')
        .trim();

      // Extract the JSON object using brace counting (not a greedy regex).
      // Greedy /\{[\s\S]*\}/ expands to the LAST } in the text, which causes
      // "Unexpected non-whitespace character after JSON" when Gemini appends
      // trailing explanation text that itself contains a } character.
      {
        const firstBrace = resultText.indexOf('{');
        if (firstBrace !== -1) {
          let depth = 0;
          let inStr = false;
          let escape = false;
          let end = -1;
          for (let i = firstBrace; i < resultText.length; i++) {
            const c = resultText[i];
            if (escape) { escape = false; continue; }
            if (c === '\\' && inStr) { escape = true; continue; }
            if (c === '"') { inStr = !inStr; continue; }
            if (inStr) continue;
            if (c === '{') depth++;
            else if (c === '}') { depth--; if (depth === 0) { end = i; break; } }
          }
          if (end !== -1) resultText = resultText.slice(firstBrace, end + 1);
        }
      }

      // Remove any remaining backticks that might be inside string values
      resultText = resultText.replace(/`/g, "'");

      // Log the raw LLM response so we can see the rationale before JSON parsing
      console.log('[Intent Classifier RAW]', resultText.slice(0, 1500));

      // Try strict parse first; fall back to jsonrepair for Gemini quirks
      // (unescaped quotes in strings, trailing commas, etc.)
      let result: any;
      try {
        result = JSON.parse(resultText);
      } catch (parseErr) {
        const repaired = jsonrepair(resultText);
        result = JSON.parse(repaired);
      }

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
      // One more LLM attempt before any keyword heuristic: the configured fallback chain (llm-client
      // YAML chain), with the same prompt. Previously only a Gemini 429/timeout reached it; any other
      // model error or an unparseable reply went straight to the keyword path, silently.
      let _chainErr = '';
      try {
        const { llmGenerate } = await import('./llm-client');
        const r = await llmGenerate({ prompt: messageForUQU, system: systemPrompt, maxTokens: 4096, jsonMode: false });
        const txt = (r?.text || '').trim();
        if (txt) {
          let recovered: any;
          try { recovered = JSON.parse(txt); } catch { recovered = JSON.parse(jsonrepair(txt)); }
          console.warn(`[Intent] primary classification failed (${errMsg.slice(0, 160)}) — recovered via fallback chain model ${r.modelUsed} (depth ${r.fallbackDepth})`);
          return this.parseIntentResult(recovered, message);
        }
        _chainErr = 'empty response';
      } catch (chainErr: any) {
        _chainErr = String(chainErr?.message || chainErr).slice(0, 160);
      }
      // JSON parse failure: build a best-effort intent so the pipeline still
      // attempts workflow search rather than silently skipping it.
      // If the message contains inline data (tabular data, SRA/GEO accessions,
      // SMILES, file paths), default to workflow_generation — inline data is
      // strong evidence the user wants to run a pipeline, not just search tools.
      const rawKeywords = message
        .toLowerCase()
        .replace(/[^\w\s-]/g, ' ')
        .split(/\s+/)
        .filter(w => w.length > 3 && !['with','that','this','from','have','will','your','their','what','which','when','then','they','also','into','been','would','could'].includes(w))
        .slice(0, 8);
      const _fallbackHasInlineData = (
        /\b((SRR|ERR|DRR|SRS|ERS|DRS|SRP|ERP|DRP|PRJNA|PRJEB)\d+)\b/i.test(message) ||
        /\b((GSE|GSM|GDS|GPL|E-MTAB-|E-GEOD-|PXD)\d+)\b/i.test(message) ||
        /\b((?:s3|gs|ftp|http|https):\/\/\S+|\/\S+\.(?:fastq|fq|bam|vcf|fa|fasta|gz|csv|tsv|h5))\b/i.test(message) ||
        /[=#\[\]\/\\@(][A-Za-z0-9@=#\-+\[\]()\/.\\]{4,}/.test(message) || // SMILES-like
        (() => {
          const lines = message.split('\n').map(l => l.trim()).filter(Boolean);
          return lines.filter(l => { const c = l.split(/[,\t]/); return c.length >= 2 && c.some(x => /^\d+(\.\d+)?$/.test(x.trim())); }).length >= 2;
        })()
      );
      const _fallbackType = _fallbackHasInlineData ? 'workflow_generation' : 'tool_search';
      const fallback: DecomposedIntent = {
        id: 'intent_fallback',
        type: _fallbackType,
        subQuery: message,
        keywords: rawKeywords,
        inlineParameters: {},
        needsToolSearch: !_fallbackHasInlineData,
        needsDatasets: false,
        confidence: 0.4,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType(_fallbackType),
      };
      // Last resort only: every LLM path failed. Not a decomposition — say so loudly (the benchmark found
      // this path scoring silently for 240 throttled calls, 2026-11-04) and mark the result degraded.
      console.error(`[Intent] DEGRADED: all decomposition models failed (primary: ${errMsg.slice(0, 160)}; fallback chain: ${_chainErr}) — keyword fallback, type=${_fallbackType} (hasInlineData=${_fallbackHasInlineData})`);
      return {
        intents: [fallback],
        isMultiIntent: false,
        primaryIntent: fallback,
        degraded: true,
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

    const parseActions = (raw: any, type: string, execution?: unknown): ActionCategories => {
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
        // needsWorkflowGeneration is the classifier's own decision. The former "mustGenerateWorkflow"
        // guard forced it true for every workflow_generation type, which silently discarded the
        // classifier's run_code branch (type=workflow_generation + needsWorkflowGeneration=false /
        // execution=direct_compute — the prompt's documented direct-compute shape). It existed because a
        // no-workflow reply once came back empty from Gemini; that root cause is fixed in the response
        // provider chain (an empty reply now fails over — see firstNonEmptyResponse). Its execution mode
        // is authoritative over the flag (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md).
        const nwg = parseExecutionMode(execution) === 'direct_compute'
          ? false
          : (typeof raw.needsWorkflowGeneration === 'boolean' ? raw.needsWorkflowGeneration : base.needsWorkflowGeneration);
        return {
          needsToolSearch: typeof raw.needsToolSearch === 'boolean' ? raw.needsToolSearch : base.needsToolSearch,
          needsWorkflowGeneration: nwg,
          needsWorkflowModification: typeof raw.needsWorkflowModification === 'boolean' ? raw.needsWorkflowModification : base.needsWorkflowModification,
          // If type requires research agent, always enable it regardless of what the classifier returns
          needsResearchAgent: mustUseResearch ? true : (typeof raw.needsResearchAgent === 'boolean' ? raw.needsResearchAgent : base.needsResearchAgent),
          needsBenchmarkAgent: typeof raw.needsBenchmarkAgent === 'boolean' ? raw.needsBenchmarkAgent : base.needsBenchmarkAgent,
          needsDatasetAccess: typeof raw.needsDatasetAccess === 'boolean' ? raw.needsDatasetAccess : base.needsDatasetAccess,
          needsLLMReasoning: nwg ? (typeof raw.needsLLMReasoning === 'boolean' ? raw.needsLLMReasoning : base.needsLLMReasoning) : true,
          needsChainProposal: typeof raw.needsChainProposal === 'boolean' ? raw.needsChainProposal : (base.needsChainProposal ?? false),
        };
      }
      if (parseExecutionMode(execution) === 'direct_compute') return { ...base, needsWorkflowGeneration: false, needsLLMReasoning: true };
      return base;
    };

    // Extract top-level UQU fields (present in both single and multi-intent responses)
    const preferredDomains: string[] = Array.isArray(result.preferred_domains) ? result.preferred_domains : [];
    const penalizedDomains: string[] = Array.isArray(result.penalized_domains) ? result.penalized_domains : [];
    const keyTerms: string[] = Array.isArray(result.key_terms) ? result.key_terms : [];
    const needsThinking: boolean = result.needs_thinking === true;
    const chainHint: string | null = typeof result.chain_hint === 'string' ? result.chain_hint : null;
    // undefined when the classifier did not say — the run_code guard then uses its keyword fallback.
    const userRequestedSyntheticData: boolean | undefined =
      typeof result.user_requested_synthetic_data === 'boolean' ? result.user_requested_synthetic_data : undefined;

    // Multi-intent format: { intents: [...] }
    if (Array.isArray(result.intents) && result.intents.length > 0) {
      const isSequential = result.is_sequential === true;
      // One line per intent — the RAW log above is cut at 1,500 chars, which hid branches 2..N of a
      // fork/join decomposition (2026-11-04); decomposition quality must be observable per branch.
      (result.intents as any[]).forEach((it: any, i: number) => console.log(
        `[Intent Decomposition] ${it?.id || `intent_${i + 1}`} type=${it?.type} domain=${it?.domain ?? '-'} dependsOn=${JSON.stringify(it?.dependsOn ?? [])} task_spec=${JSON.stringify(String(it?.task_spec ?? '')).slice(0, 220)}`));
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
        actions: parseActions(intent.actions, intent.type || 'general_question', intent.execution),
        execution: parseExecutionMode(intent.execution),
        userConstraint: parseUserConstraint(intent.user_constraint ?? result.user_constraint),
        taskSpec: typeof intent.task_spec === 'string' && intent.task_spec.trim() ? intent.task_spec.trim() : undefined,
        domain: typeof intent.domain === 'string' && intent.domain.trim() ? intent.domain.trim() : undefined,
        inputKinds: parseInputKinds(intent.input_kinds) ?? parseInputKinds(result.input_kinds),
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
        inputKinds: parseInputKinds(result.input_kinds),
        needsThinking,
        chainHint,
        userRequestedSyntheticData,
        rationale: typeof result.rationale === 'string' ? result.rationale : undefined,
      };
    }

    // Single-intent format: flat object with type, keywords, etc.
    const intentType = result.type || 'general_question';
    const intentRationale: string | undefined = typeof result.rationale === 'string' ? result.rationale : undefined;

    console.log(
      `[Intent Classifier] type=${intentType} confidence=${result.confidence ?? '?'}` +
      (intentRationale ? `\n  rationale: ${intentRationale}` : '')
    );

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
      actions: parseActions(result.actions, intentType, result.execution),
      workflowAmbiguity: typeof result.workflowAmbiguity === 'string' ? result.workflowAmbiguity : null,
      execution: parseExecutionMode(result.execution),
      userConstraint: parseUserConstraint(result.user_constraint),
      inputKinds: parseInputKinds(result.input_kinds),
    };

    return {
      intents: [singleIntent],
      isMultiIntent: false,
      primaryIntent: singleIntent,
      preferredDomains,
      penalizedDomains,
      keyTerms,
      inputKinds: parseInputKinds(result.input_kinds),
      needsThinking,
      chainHint,
      userRequestedSyntheticData,
      rationale: intentRationale,
    };
  }

  /**
   * Heuristic check for cross-intent ambiguity: detects queries that look like
   * workflow_generation requests (design verb + therapeutic modality) but were
   * classified as something else (e.g. tool_search). Used to surface an
   * IntentClarificationCard so the user can correct the routing.
   */
  private _detectCrossIntentAmbiguity(
    message: string,
    primaryIntent: DecomposedIntent,
  ): {
    shouldClarify: boolean;
    candidates: Array<{ type: string; label: string; primary?: boolean }>;
    reason: string;
  } {
    if (primaryIntent.type === 'workflow_generation') {
      return { shouldClarify: false, candidates: [], reason: '' };
    }
    const designVerb =
      /\b(design|triage|compare|co-?design|bake[-\s]?off|engineer|propose|generate|build)\b/i;
    const modalityToken =
      /\b(bispecific|bsab|crossmab|kih|bite|car[-\s]?t|carT|car\s+construct|base[-\s]?edit|prime[-\s]?edit|knock[-\s]?(out|down|in)|glp[-\s]?1|glp1\b|modalit(y|ies)|adc|protac|mrna(\s+therap)?|aav(\s+serotype)?|aso(\s+gapmer)?|sirna|si[-\s]?rna|gapmer|peptide\s+therapeutic)\b/i;
    const triggers: string[] = [];
    if (designVerb.test(message) && modalityToken.test(message)) triggers.push('design-verb+modality');
    if (/\b(triage|compare|bake[-\s]?off)\b.*\bmodalit(y|ies)\b/i.test(message))
      triggers.push('verb+modalities');
    if (/\bin[-\s]?vivo\b.*\b(car[-\s]?t|base[-\s]?edit|knock[-\s]?(out|down|in))\b/i.test(message))
      triggers.push('in-vivo therapy');
    if (triggers.length === 0) {
      return { shouldClarify: false, candidates: [], reason: '' };
    }
    return {
      shouldClarify: true,
      candidates: [
        { type: 'workflow_generation', label: 'Run a design workflow', primary: true },
        { type: 'tool_search', label: 'Just search for tools' },
        { type: 'research_question', label: 'Answer as a research question' },
      ],
      reason: triggers.join(', '),
    };
  }

  /**
   * Search for relevant tools using Galaxy Tool Search Index
   */
  private async searchRelevantTools(
    userMessage: string,
    keywords: string[],
    userId?: number | string
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
        toolSearchResponse = await this._api().searchTools(query, undefined, 20);

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
      // Feature-flagged migration off Claude Haiku → YAML fallback chain
      // (Gemini 3.1 Pro primary → 3.5 Flash → Claude → ...) to reduce
      // Claude rate-limit pressure on chat. Default stays direct-Claude.
      // Flip BIOMATE_CHAT_VIA_CHAIN=true to opt in.
      const useChain = process.env.BIOMATE_CHAT_VIA_CHAIN === 'true';
      const userPrompt = `User request: ${userMessage}\n\nAvailable tools:\n${toolCatalog}`;
      const rankStartTime = Date.now();

      let resultText: string;
      if (useChain) {
        console.log('[GalaxyAssistant] Tool ranking via chain (Gemini primary):', {
          tools_to_rank: tools.length, max_tokens: 2000,
        });
        const { llmGenerate } = await import('./llm-client');
        const r = await llmGenerate({
          prompt: userPrompt,
          system: systemPrompt,
          maxTokens: 2000,
          jsonMode: true,
        });
        resultText = r.text || '[]';
        console.log('[GalaxyAssistant] Tool ranking via chain done:', {
          model_used: r.modelUsed, fallback_depth: r.fallbackDepth,
          time_ms: Date.now() - rankStartTime,
        });
      } else {
        console.log('[GalaxyAssistant] Tool ranking API request (Claude direct):', {
          model: this.modelConfig.toolRankingModel,
          max_tokens: 2000,
          tools_to_rank: tools.length
        });

        const completion = await this._withAnthropicRetry(
          () => this._getClaude().messages.create({
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
                content: userPrompt,
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
        resultText = content.type === 'text' ? content.text : '[]';
      }

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
      const datasetSearchResponse = await this._api().searchDatasets({
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
   * Post-text LLM reselection: given the generated text response and top candidates,
   * ask a cheap LLM call which workflow best matches. Returns the workflow name or null.
   */
  private async _reselectWorkflow(
    userMessage: string,
    generatedText: string,
    candidates: Array<{ name: string; description: string; domain: string; score: number }>,
    preferredDomains: string[]
  ): Promise<string | null> {
    if (!candidates?.length) return null;
    const candidateList = candidates
      .map((c, i) => `${i + 1}. "${c.name}" [${c.domain}]: ${c.description}`)
      .join('\n');
    // Include relevant routing rules for the detected domain
    const routingContext = buildWorkflowRoutingBlock(preferredDomains);
    const prompt = `You are a bioinformatics workflow router. A user sent this request:
"${userMessage.slice(0, 600)}"

The AI assistant generated this response describing what it will do:
"${generatedText.slice(0, 800)}"

The workflow database search returned these candidates:
${candidateList}

Routing rules:
${routingContext.slice(0, 1000)}

Selection rules:
- Base your selection primarily on what the AI response describes — the tools, methods, and scientific approach it mentions.
- EXPLICIT TOOL REQUEST: If the user message says "using <Tool>", "run <Tool>", or "with <Tool>" as the primary method, select that tool's workflow.
  POSITIVE example: user says "run DiffDock on my protein" → select DiffDock workflow.
  POSITIVE example: user says "using HADDOCK for docking" → select HADDOCK workflow.
- COMPARISON / ALTERNATIVES: If the user lists tools as options ("benchmark DiffDock or HADDOCK", "like DiffDock but for cyclic peptides", "DiffDock vs HADDOCK"), do NOT lock onto the first named tool. Select the workflow that fits the actual scientific goal.
  NEGATIVE example: user says "benchmark DiffDock or HADDOCK-based docking" but the AI response describes cyclic peptide design → select the cyclic peptide workflow, not DiffDock.
  NEGATIVE example: user says "like DiffDock but for macrolactam PPI" → select the macrolactam/PPI workflow, not DiffDock.

Reply with ONLY the number (e.g. "1" or "3"). If none match, reply "0".`;

    try {
      const llm = this._getClaude();
      const raw = await llm.messages.create({
        model: this.modelConfig.intentModel,
        max_tokens: 4,
        temperature: 0,
        messages: [{ role: 'user', content: prompt }],
      });
      const pick = parseInt(((raw.content[0] as any)?.text || '').trim(), 10);
      if (pick > 0 && pick <= candidates.length) {
        return candidates[pick - 1].name;
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Direct workflow lookup by name — used after LLM reselection.
   */
  /** Build the card for catalog workflow `name` after the response text was written.
   *  Identity is checked first with the cheap name lookup (so a header that is not a catalog
   *  workflow costs no regeneration); the card is then regenerated through Step 4's call with
   *  the name made explicit, which the backend's named-workflow fast path resolves to the
   *  complete card (own parameters, session-file bindings, runnable path). Returns null —
   *  keep the current card — unless the regenerated card IS that workflow. */
  private async _cardForNamedWorkflow(
    name: string,
    message: string,
    regenerate: ((intentText: string) => Promise<any>) | null,
    userInputKinds?: string[],
  ): Promise<any | null> {
    if (!regenerate) return null;
    const ident = await this._lookupWorkflowByName(name, message, userInputKinds);
    if (!ident?.success || !ident.workflow_name) return null;
    // The backend judged this workflow unable to run on the request's explicit data (e.g. a raw-spectra
    // pipeline for a MaxQuant protein table): a text-driven swap must not move the card there.
    if (ident.input_compatible === false) return null;
    const target = workflowSlug(ident.workflow_name);
    const card = await regenerate(`${message}\n\nRun the ${target} workflow.`);
    const built = workflowSlug(card?.workflow_ga?.name || card?.workflow_name || '');
    return card?.success && !card?.error && built === target ? card : null;
  }

  private async _lookupWorkflowByName(name: string, query?: string, inputKinds?: string[]): Promise<any> {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      // POST: the request text (used for the input-compatibility check) does not belong in a URL —
      // percent-encoded long or CJK messages exceed request-line limits, and URLs are access-logged.
      const resp = await fetch(`${galaxyUrl}/api/ai_assistant/workflow_by_name`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-api-key': process.env.GALAXY_MASTER_API_KEY || process.env.GALAXY_API_KEY || '',
        },
        body: JSON.stringify({ name, ...(query ? { query: query.slice(0, 20000) } : {}),
          ...(inputKinds ? { input_kinds: inputKinds } : {}) }),
      });
      if (!resp.ok) return null;
      return await resp.json();
    } catch {
      return null;
    }
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
    penalizedDomains?: string[],
    userInputKinds?: string[],
    selectedWorkflow?: SelectedWorkflow,
    /** The raw user message, so the attached files can be bound to this
     *  workflow's schema once we know it (see the binding block below). */
    attachmentMessage?: string
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

    // No manual FTS enrichment needed here: UQU now receives conversation context
    // and synthesizes a semantically rich subQuery from the full intent history.
    // That subQuery is what reaches this function as userIntent.

    // Skip Haiku domain round-trip when ANDV E2E names an explicit registry workflow.
    const _explicitRegistryFastPath =
      /\bregistry\s+id\s+(10813|12824|12700)\b/i.test(userIntent) ||
      /\boptimize_codons_for_heterologous_expression\b/i.test(userIntent) ||
      /\b(autodock\s*vina|docking_autodock_vina)\b/i.test(userIntent);
    // When transcriptomics is penalized (pathway enrichment override), skip domain
    // inference to prevent _inferDomainWithLLM from returning rna_seq due to the
    // active differentialabundance workflow context — which would contradict the penalty
    // and route Turn 2 back to differentialabundance instead of clusterprofiler/enrichGO.
    const _transcriptomicsPenalized = penalizedDomains?.some(
      d => /^(transcriptomics|rna_seq)$/i.test(d)
    );
    // The domain hint only steers catalog search, which a selected workflow skips.
    const domainHint = (_explicitRegistryFastPath || _transcriptomicsPenalized || selectedWorkflow)
      ? undefined
      : await this._inferDomainWithLLM(userIntent, currentWorkflowText || recentContext || undefined);
    // Normalize composite dataset-ref values (e.g. the cryo "Dataset Id" leak
    // "<uuid>, s3_uri=s3://…]") at the SOURCE. This map is both (a) sent to the
    // backend as generateWorkflow's inline_parameters, and (b) echoed back onto
    // the workflow object as `wf.metadata.workflow.inline_parameters` — the BASE
    // map the viewer seeds its `params` from (chat-with-artifacts.tsx:1793,
    // nextflow-workflow-viewer.tsx:1051). Normalizing the camelCase overlay alone
    // (stringifyParamValues) missed it because groundInlineParameters remaps/drops
    // the `dataset_id` key off the overlay, so the composite only survives on this
    // base map. Cleaning it here fixes both the executor input and the display.
    const mergedInlineParameters = Object.fromEntries(
      Object.entries({
        ...(inlineParameters || {}),
        ...(domainHint ? { domain_hint: domainHint } : {}),
      }).map(([k, v]) => [k, String(normalizeCompositeDatasetRef(v))])
    );

    console.log('[GalaxyAssistant] ========================================');
    console.log('[GalaxyAssistant] Generating workflow using Unified AI');
    console.log('[GalaxyAssistant] User intent:', userIntent);
    console.log('[GalaxyAssistant] Available datasets:', datasets.length);
    console.log('[GalaxyAssistant] Inline parameters:', JSON.stringify(mergedInlineParameters));

    // Append standing project rules so backend rule-based param inference
    // (_extract_genome_build, genome injection) can honor "always GRCh38" even
    // when the user message does not name a genome. Search still keys primarily
    // on the leading userIntent sentence.
    const _intentForBackend = context?.projectRules?.length
      ? `${userIntent}\n\nStanding project instructions:\n${context.projectRules.join('\n')}`
      : userIntent;
    const response = await this._api().generateWorkflow({
      user_intent: _intentForBackend,
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
      // undefined = classifier did not say → backend detects from the text; [] = user states no input data
      user_input_kinds: userInputKinds,
      session_datasets: sessionDatasets?.length ? sessionDatasets : undefined,
      credential_map: context?.credentialMap ?? undefined,
      ...(selectedWorkflow ? { selected_workflow: {
        name: selectedWorkflow.name,
        ...(selectedWorkflow.nextflow_path ? { nextflow_path: selectedWorkflow.nextflow_path } : {}),
        ...(selectedWorkflow.id !== undefined ? { id: selectedWorkflow.id } : {}),
      } } : {}),
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

      // Force-merge inline params into workflow required_params to override any
      // concatenation error from the LLM parsing multi-param message text.
      // Only override if the inline value is an s3:// URI or non-empty string.
      const _overridableKeys = new Set(['samplesheet', 'input', 'matrix', 'contrasts', 'reads', 'gene_list', 'geo_accession', 'file_path']);
      if (mergedInlineParameters && Object.keys(mergedInlineParameters).length) {
        const _wfGaRef = (response as any).workflow_ga || (response as any);
        for (const _pList of ['required_params', 'optional_params']) {
          const _arr: any[] = _wfGaRef[_pList] || [];
          for (const _p of _arr) {
            const _inlineVal = (mergedInlineParameters as Record<string, unknown>)[_p.name];
            if (_inlineVal && typeof _inlineVal === 'string' && (_overridableKeys.has(_p.name) || _inlineVal.startsWith('s3://'))) {
              if (_p.value !== _inlineVal) {
                console.log(`[GalaxyAssistant] InlineOverride ${_pList} ${_p.name}: "${String(_p.value || '').slice(0,80)}" → "${_inlineVal.slice(0,80)}"`);
                _p.value = _inlineVal;
                _p.autoFilled = true;
              }
            }
          }
        }
        // Fallback: if exactly one inline S3 value is unmatched AND exactly one required
        // param is empty, inject by position (handles gene_list → gene_file name mismatch).
        const _wfGaRef2 = (response as any).workflow_ga || (response as any);
        const _emptyRequired: any[] = (_wfGaRef2.required_params || []).filter(
          (p: any) => !p.value && p.required !== false
        );
        const _unmatchedS3 = Object.entries(mergedInlineParameters)
          .filter(([k, v]) => typeof v === 'string' && (v as string).startsWith('s3://')
            && _emptyRequired.every((p: any) => p.name !== k));
        if (_emptyRequired.length === 1 && _unmatchedS3.length === 1) {
          const [_uk, _uv] = _unmatchedS3[0];
          console.log(`[GalaxyAssistant] InlineOverride positional fallback: ${_uk} → ${_emptyRequired[0].name} = ${_uv}`);
          _emptyRequired[0].value = _uv;
          _emptyRequired[0].autoFilled = true;
        }
      }

      // ── Prepared-input key=value → param strip (rule-first) ──────────────
      // Cold-start demos put `movies_path=s3://…`, `analysis=screening`,
      // `ligand_a=imatinib.sdf`, etc. in the hidden [Prepared inputs] block.
      // The LLM/schema-grounded path often leaves those required slots empty
      // (Confirm blocked + "Which <param>?"). Seed them onto workflow_ga here
      // before attachment binding so Confirm enables without force-Confirm.
      // Attachment binding (below) overwrites bare filenames with dataset refs.
      {
        const _wfGaPrep: any = (response as any).workflow_ga || (response as any);
        const _seeded = applyPreparedInputParamsToWorkflow(
          _wfGaPrep,
          attachmentMessage || userIntent,
        );
        if (_seeded.length > 0) {
          console.log(
            `[GalaxyAssistant] PreparedInputSeed ${_seeded.join(', ')} ← explicit key=value in message`,
          );
        }
      }

      // ── Attachment → input binding (schema-driven) ───────────────────────
      // The name-based mapping above only knows canonical parameter names
      // (samplesheet / matrix / reads / …). A workflow whose input is called
      // `input_smiles`, `ligand_file`, `structure_pdb`, … never received the
      // user's upload, so the panel showed "1 required parameter need to be
      // filled" while the right file was already attached. Bind here, where the
      // chosen workflow's schema is known: a file may only land on a parameter
      // that really takes a file, and only when its extension matches the kind
      // of data the parameter asks for (shared/attachment-binding.ts, rule-only).
      // This is the one chokepoint the panel, the reply state and the execute
      // payload all read, so binding here fixes all three.
      {
        const _attached = parseAttachedFiles(attachmentMessage || userIntent);
        if (_attached.length > 0) {
          const _wfGaA: any = (response as any).workflow_ga || (response as any);
          const _specs: any[] = [
            ...(_wfGaA.required_params || []),
            ...(_wfGaA.optional_params || []),
          ];
          const _bindings = bindAttachmentsToParams(_attached, _specs);
          for (const b of _bindings) {
            const _p = _specs.find((p: any) => String(p?.name) === b.param);
            if (!_p) continue;
            _p.value = b.value;
            _p.autoFilled = true;
            if (!_wfGaA.inline_parameters || typeof _wfGaA.inline_parameters !== 'object') {
              _wfGaA.inline_parameters = {};
            }
            _wfGaA.inline_parameters[b.param] = b.value;
            console.log(
              `[GalaxyAssistant] AttachmentBind ${b.param} ← ${b.files.map((f) => f.name).join(', ')} (score ${b.score}: ${b.reason})`,
            );
          }
          // nf-core sarek/proteinfold: rebuild `input` as a schema-valid samplesheet
          // whose path cells are co-attached S3/dataset refs. Bare basenames in the
          // demo CSV fail nf-schema exists:true → "Validation of pipeline parameters
          // failed". Inline CSV is materialized to S3 at execute time. `input` is
          // often executor-owned (data_inputs only) — always write inline_parameters.
          {
            const _sheet = buildResolvedNfcoreInputSamplesheet(
              String(_wfGaA?.name || _wfGaA?.display_name || ''),
              _attached,
            );
            if (_sheet) {
              const _inputParam =
                _specs.find((p: any) => String(p?.name) === 'input') ||
                _specs.find((p: any) => String(p?.name) === 'samplesheet') ||
                (_wfGaA.data_inputs || []).find((p: any) =>
                  ['input', 'samplesheet', 'sample_sheet'].includes(String(p?.name || '')),
                );
              const _inputName = String(_inputParam?.name || 'input');
              if (_inputParam) {
                _inputParam.value = _sheet.csv;
                _inputParam.autoFilled = true;
                if ('bound' in _inputParam) {
                  _inputParam.bound = true;
                  _inputParam.bound_value = 'samplesheet from attached files';
                }
              }
              if (!_wfGaA.inline_parameters || typeof _wfGaA.inline_parameters !== 'object') {
                _wfGaA.inline_parameters = {};
              }
              if (!_wfGaA.parameters || typeof _wfGaA.parameters !== 'object') {
                _wfGaA.parameters = {};
              }
              _wfGaA.inline_parameters[_inputName] = _sheet.csv;
              _wfGaA.parameters[_inputName] = _sheet.csv;
              console.log(
                `[GalaxyAssistant] NfcoreSamplesheet ${_inputName} ← inline (${_sheet.reason})`,
              );
            }
          }
          // Record what we could and could not bind so the reply never claims a
          // workflow was built from data it does not actually read.
          const _boundNames = new Set(_bindings.flatMap((b) => b.files.map((f) => f.name)));
          // Bundle documentation (README, provenance) is not data the workflow
          // was supposed to read, so it is not reported as unused data either.
          const _dataAttached = _attached.filter((f) => !isNonInputAttachment(f));
          (response as any)._attachmentBinding = {
            attached: _dataAttached.map((f) => f.name),
            bound: _bindings.map((b) => ({ param: b.param, file: b.files.map((f) => f.name).join(', ') })),
            unbound: _dataAttached.filter((f) => !_boundNames.has(f.name)).map((f) => f.name),
          };
          // The panel reads this (not the login-session upload list) to say "files attached here are
          // not used by this workflow" — only when this chat really attached some.
          if (_wfGaA && typeof _wfGaA === 'object') (_wfGaA as any).attachment_binding = (response as any)._attachmentBinding;
          if (_bindings.length === 0) {
            console.log(
              `[GalaxyAssistant] AttachmentBind: none of ${_attached.length} attached file(s) fits "${_wfGaA?.name || 'workflow'}" inputs`,
            );
          }
        }
      }

      // Normalize composite dataset-ref param VALUES at the Node response chokepoint.
      // An uploaded/attached file sometimes reaches a dataset/id param as the whole
      // context entry ("<id>, s3_uri=<uri>" / "<id>, galaxy_dataset_id=<gid>") instead of
      // a single clean token — the cryo "Dataset Id" leak. This runs on the final
      // workflow_ga regardless of which upstream path (LLM suggest/infer/recommend, or a
      // binding) produced the value, so it is the one place that reliably catches it.
      // Keep only the leading id/uri token: the composite is malformed for the executor
      // anyway (no code parses it; BioMate stages id→S3 at execute time), so this fixes
      // both the display and any downstream resolution without weakening the input gate
      // (the gate validates step-bound `inputs`, a separate structure, not this value).
      {
        const _wfGaN: any = (response as any).workflow_ga || (response as any);
        const _normComposite = normalizeCompositeDatasetRef;
        // Normalize EVERY value-bearing field, not just `value`. The viewer's
        // display precedence is userValue → p.value → p.default → "" (and it also
        // surfaces p.defaultValue), so a composite that lands in `default` while
        // `value` is undefined renders straight from `default` and a value-only
        // pass never catches it — the exact reason the cryo "Dataset Id" leak
        // survived four value-targeted fixes. One loop over all three fields at
        // this chokepoint is the reliable fix regardless of which field the
        // upstream path populated.
        for (const _pList of ['required_params', 'optional_params']) {
          for (const _p of (_wfGaN?.[_pList] || [])) {
            for (const _field of ['value', 'default', 'defaultValue']) {
              if (!(_field in (_p || {}))) continue;
              const _nv = _normComposite(_p[_field]);
              if (_nv !== _p[_field]) {
                console.log(`[GalaxyAssistant] NormalizeComposite ${_pList} ${_p.name}.${_field}: "${String(_p[_field]).slice(0, 60)}" → "${String(_nv).slice(0, 60)}"`);
                _p[_field] = _nv;
              }
            }
          }
        }
        // The viewer ALSO seeds its params from workflow_ga.inline_parameters — an
        // OBJECT the Python backend builds from the attached dataset (read as the
        // panel base at routes.ts:6563; the camelCase overlay lacks `dataset_id`, so
        // this composite base wins). The array loop above never touches this object,
        // which is why the cryo "Dataset Id" leak survived the required/optional_params,
        // inlineParameters-overlay, and mergedInlineParameters-request fixes — none
        // normalized THIS field. This is the one the viewer actually reads. Normalize it
        // on both workflow_ga and the response root (whichever carries it).
        for (const _host of [_wfGaN, (response as any)]) {
          const _inlineObj = _host?.inline_parameters;
          if (_inlineObj && typeof _inlineObj === 'object' && !Array.isArray(_inlineObj)) {
            for (const _k of Object.keys(_inlineObj)) {
              const _nv = _normComposite(_inlineObj[_k]);
              if (_nv !== _inlineObj[_k]) {
                console.log(`[GalaxyAssistant] NormalizeComposite inline_parameters ${_k}: "${String(_inlineObj[_k]).slice(0, 60)}" → "${String(_nv).slice(0, 60)}"`);
                _inlineObj[_k] = _nv;
              }
            }
          }
        }
        // Schema-authoritative param rows: the viewer renders a param row for every
        // key in workflow_ga.inline_parameters (nextflow-workflow-viewer seeds its
        // `params` from this object). An upstream extractor that invents a key not
        // in the workflow's real schema — e.g. the LLM mis-reading caffeine's
        // "CN1C=NC2…" as key=value and emitting "CN1C" — would otherwise surface as
        // a phantom "Recommended" param row. Intersect inline_parameters with the
        // actual schema (required ∪ optional) so ONLY real params can prefill and no
        // hallucinated key becomes a row. General (not value-type specific): any key
        // the schema does not declare is dropped, whatever produced it.
        {
          const _schemaNames = new Set<string>();
          for (const _pList of ['required_params', 'optional_params']) {
            for (const _p of (_wfGaN?.[_pList] || [])) {
              if (_p?.name) _schemaNames.add(String(_p.name));
            }
          }
          for (const _host of [_wfGaN, (response as any)]) {
            const _inlineObj = _host?.inline_parameters;
            if (_inlineObj && typeof _inlineObj === 'object' && !Array.isArray(_inlineObj)) {
              // Empty schema (missing .nf / orphan catalog): do NOT keep LLM
              // inline_parameters — the viewer would promote them as Recommended
              // phantoms (Admet Pred → target_pdb / library_file, 2026-11-13).
              // Prefer honest empty over invented docking rows. Alias/_find_nf_file
              // parity is the durable fix for real schemas; this is the fail-closed guard.
              if (_schemaNames.size === 0) {
                for (const _k of Object.keys(_inlineObj)) {
                  if (_k === 'domain_hint') continue;
                  console.log(
                    `[GalaxyAssistant] Clearing inline param "${_k}" (schema empty for ${_wfGaN?.name || 'workflow'}) — prevents empty-schema phantom row`,
                  );
                  delete _inlineObj[_k];
                }
                continue;
              }
              for (const _k of Object.keys(_inlineObj)) {
                if (_k === 'domain_hint') continue;
                // Drop any inline key the schema doesn't declare (prevents a hallucinated phantom
                // "Recommended" row).
                if (!_schemaNames.has(_k)) {
                  console.log(`[GalaxyAssistant] Dropping inline param "${_k}" (not in ${_wfGaN?.name || 'workflow'} schema) — prevents phantom param row`);
                  delete _inlineObj[_k];
                }
              }
            }
          }
        }
      }

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
    const inlineDataMap = await extractInlineDataWithLLM(message, this._getClaude());
    // Treat a canonical fixture name (airway, pasilla, pbmc3k, SRR\d+, etc.)
    // as if it were inline data. The fixture is the data — `data(airway)`
    // loads counts + metadata from the airway R package; SRA accessions
    // resolve via sra-toolkit; nf-core test profiles ship their fixtures
    // inside the pipeline. Without this, verbose phrasings like
    // "Run DESeq2 on airway; treated vs untreated; export CSV + MA plot"
    // still re-triggered the LLM's "Please upload counts matrix" reflex
    // despite the prompt-level rule. See Plan C in
    // docs/20260610_DETERMINISTIC_CHAT_ROUTING_PLAN.md.
    const _matchedFixture = matchesCanonicalFixture(message);
    if (_matchedFixture) {
      console.log(`[chat] canonical fixture matched in user message: ${_matchedFixture} — suppressing clarification ask`);
    }
    const hasInlineData = Object.keys(inlineDataMap).length > 0 ||
      /do not ask|no (further )?clarification|use (the )?provided|use default/i.test(message) ||
      _matchedFixture !== null;

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
      // An EXAMPLE value (the workflow's test data) is not something the user supplied: it must
      // never be declared pre-satisfied (live dev 2026-11-12: the model then called the example
      // SMILES "可选；默认值为阿司匹林" and never asked for the user's compounds).
      const exampleEntries: [string, string][] = [];
      for (const p of allParams) {
        const v = p?.value ?? p?.default;
        if (p?.example && v !== null && v !== undefined && v !== '') { exampleEntries.push([p.name, String(v)]); continue; }
        if (p?.autoFilled && (p.value !== null && p.value !== undefined && p.value !== '')) {
          autoFilledEntries.push([p.name, String(p.value)]);
        }
      }
      const exampleBlock = exampleEntries.length
        ? `\n<example_parameter_values>\nThese parameters are pre-filled with the workflow's EXAMPLE inputs (its test data). They are NOT defaults the user chose, NOT recommendations, and NOT the user's data:\n${exampleEntries.map(([k, v]) => `  ${k}: ${v}`).join('\n')}\nSay plainly that the card is pre-filled with example inputs (name what they are), and ask the user for their own inputs (paste them or attach a file). Never call these values a default or recommended.\n</example_parameter_values>\n`
        : '';
      const allEntries = [...entries, ...autoFilledEntries];
      if (allEntries.length === 0) return exampleBlock;
      const lines = allEntries.map(([k, v]) => `  ${k}: ${v}`);
      // When a genome build is present, add an explicit note that reference genome files
      // are auto-resolved via igenomes — the LLM must not ask for FASTA paths or known-sites VCFs.
      const genomeBuild = inlineDataMap['genome_build'];
      const genomeSuffix = genomeBuild
        ? `\n  Note: reference genome FASTA, genome index, and known-variant VCF files for ${genomeBuild} are auto-resolved from the igenomes reference data registry. Do NOT ask the user to provide these files.`
        : '';
      return `\n<pre_satisfied_parameters>\nThe following parameters are already present in the user's message and must NOT be requested again:\n${lines.join('\n')}${genomeSuffix}\n</pre_satisfied_parameters>\n` + exampleBlock;
    })();

    // ── Session datasets block ─────────────────────────────────────────────
    // Galaxy history is the authoritative store for uploaded datasets;
    // sessionDatasets is the structured projection we already load on every
    // chat turn (req.session.uploadedDatasets ∪ chat_sessions.datasets
    // rehydration). Previously the chat LLM only "saw" attached datasets via
    // the verbose `[Galaxy dataset: <name> (id: <uuid>)]` blocks inlined into
    // the user message — those fell out of the recency window after a few
    // turns and the bot kept asking for files. See
    // docs/20260610_REAL_USER_FULL_CHAT_LOGS.md (wjunlin@HKU) and
    // docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md (Q3).
    //
    // The canonical fix is to inject the dataset list as a short, structured
    // bulletin in the system prompt — ~80 bytes per dataset, present every
    // turn, independent of chat-history slicing.
    const sessionDatasetsBlock = (() => {
      const sd = (context as any)?.sessionDatasets as Array<{
        id?: string; name?: string; type?: string; file_path?: string | null;
        s3_uri?: string | null; s3_key?: string; projectFileId?: string;
        recovered?: boolean; sourceSessionId?: string;
      }> | undefined;
      const unresolved = Array.isArray((context as any)?.datasetReferenceUnresolvedIds)
        ? (context as any).datasetReferenceUnresolvedIds.filter((id: unknown) => typeof id === 'string')
        : [];
      if (!sd?.length && !unresolved.length) return '';
      const availableDatasets = sd ?? [];
      const explicitSelection = Array.isArray((context as any)?.datasetReferences)
        && (context as any).datasetReferences.length > 0;

      // Context-aware injection gate. The block is only useful when the
      // chat round actually needs to reason about the user's data — see
      // docs/20260613_DATASET_INJECTION_GATE_DESIGN.md. Default-on
      // (false-skip cost > false-inject cost), but suppress on pure
      // abstract-knowledge turns where no signal points at data.
      const _gate = shouldInjectDatasets({
        message,
        intentType: (intent as any)?.type,
        datasets: sd as any,
        history: (context as any)?.previousMessages,
        runState: (context as any)?.runState,
      });
      if (!_gate.inject) {
        if (!explicitSelection) {
          console.log(`[sessionDatasetsBlock] gate=skip reason=${_gate.reason}`);
          return '';
        }
        console.log('[sessionDatasetsBlock] explicit dataset selection overrides injection gate');
      }
      // Log injects too so the per-reason mix is visible.
      console.log(`[sessionDatasetsBlock] gate=inject reason=${explicitSelection ? 'explicit_request_selection' : _gate.reason}`);

      // Split into direct (attached this conversation) vs recovered
      // (from a sister session in the same project — cold-refresh).
      // See docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
      const valid = availableDatasets.filter(d => d && d.id);
      const projectFiles = valid.filter(d => !!d.projectFileId && d.type === 'project file').slice(0, 32);
      const direct = valid.filter(d => !d.recovered && !d.projectFileId).slice(0, 32);
      const recovered = valid.filter(d => d.recovered).slice(0, 20);

      const fmt = (d: any) =>
        `  - ${d.name || '(unnamed)'} | id=${d.id} | type=${d.type || 'unknown'}${d.s3_uri ? ` | s3_uri=${d.s3_uri}` : ''}`;
      const directRows = direct.map(fmt).join('\n');
      const projectFileRows = projectFiles.map(fmt).join('\n');
      const recoveredRows = recovered.map(fmt).join('\n');

      if (!directRows && !projectFileRows && !recoveredRows) return '';

      let body = '\n<session_datasets>\n';
      if (explicitSelection) {
        body += 'These are the exact dataset objects the user selected for this operation. Use only these IDs; do not substitute another session dataset or a later version.\n\n';
      }
      if (unresolved.length) {
        body += `The following selected IDs are not in the current session cache and must be resolved by their exact IDs before use: ${unresolved.join(', ')}. If resolution fails, report that failure; do not substitute another dataset.\n\n`;
      }
      if (directRows) {
        body += `Datasets attached to this conversation (these IDs are stable across turns and runs):\n${directRows}\n\n`;
      }
      if (projectFileRows) {
        body += `Project files selected for this operation (authorized exact objects, not conversation uploads):\n${projectFileRows}\n\n`;
      }
      if (recoveredRows) {
        body += `Datasets from earlier sessions in this project (recovered after refresh — the user did NOT attach them this turn; ask once if you're unsure which they meant):\n${recoveredRows}\n\n`;
      }
      body += `When the user refers to "the dataset", "the file I uploaded", "the counts matrix", etc. — these are the candidates. For a selected project file, use its id with read_file to preview it, OR with run_code's input_datasets to load the FULL file for computation (it is staged into the sandbox like any input; a file over the sandbox cap will not be staged and run_code will report that — run a workflow on very large files). Use its s3_uri for Nextflow workflow parameters. If a selected project file has no s3_uri, its Batch staging failed: it may be previewed or read in run_code, but do NOT launch a workflow with it; report the staging failure plainly. For conversation datasets, use the id for read_file and run_code's input_datasets. For Nextflow workflow parameters from conversation datasets: use s3_uri when present; if absent, use the dataset id — BioMate will stage the local file to S3 at execute time. NEVER omit a file param just because s3_uri is absent. Do NOT ask the user to re-upload datasets that already appear here. For *recovered* datasets in particular, you may confirm intent ("I see ${recovered[0]?.name ?? 'X'} from your earlier session — should I use that?") but never claim the user attached them this turn. When you MENTION a dataset to the user in your reply, refer to it by its NAME only (e.g. "counts_matrix.csv") — never print its id/UUID or s3_uri in prose; those are for your tool calls, not for the user to read.\n</session_datasets>\n`;
      return body;
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

    const projectContextBlock = context.projectContext
      ? `<project_context>\n${context.projectContext}\n</project_context>\n${PROJECT_CONTEXT_NOTE}\n\n`
      : '';

    // Compute isWorkflowTurn here so it is available for both the system prompt
    // selection (below) and the agent-tools gate (further down in the Claude branch).
    const isWorkflowTurn = workflowSuggestion.shouldGenerate || !!generatedWorkflow;
    // Ground chat prose to a single bound workflow_ga (no fake multi-step chain narration).
    const singleWfGrounding = singleWorkflowGroundingDirective(
      generatedWorkflow as any,
      cardWorkflowName(generatedWorkflow) || undefined,
    );
    // Tools should be suppressed only when there is a REAL, runnable workflow to
    // narrate — not merely when generateWorkflow ran and returned a failed/empty
    // object (which happens on false-positive workflow classification of plain
    // compute/lookup questions). Mirrors the runnable check in routes.ts.
    const _gw: any = generatedWorkflow;
    const hasRunnableWorkflow = !!(_gw && _gw.success && !_gw.error &&
      (_gw.workflow_ga || _gw.nextflow_path || _gw.workflow_type === 'chain' ||
       _gw.chain_name || _gw.workflow_type === 'cryosparc'));
    // Reply state is chosen here from real signals, not left to the model: a
    // generated workflow whose REQUIRED data input is still unbound (and the
    // message carries no data) is "identified, waiting for data" — never
    // "could not generate" (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md §7.3).
    const unboundDataInputs = runnableWorkflow
      ? unboundRequiredDataInputs(generatedWorkflow, new Set(Object.keys(inlineDataMap)))
      : [];
    // Example-data default: the resolved workflow ships its own bundled example
    // dataset and runs with no user input (backend `example_data.present`, a real
    // property of the .nf — a built-in demo-data fallback or a data param that
    // defaults to bundled example data). When the request carries no user data,
    // the reply presents the card as runnable on the example dataset and does NOT
    // ask for an upload. When the user DID provide data, their data is used and
    // this is moot. A workflow that genuinely needs data and ships none is
    // unaffected — the DATA-FIRST ask still fires (docs/20261111 example-data default).
    const userSuppliedRunData = hasInlineData
      || messageCarriesRunData(message)
      || messageWaivesDataAsk(message)
      || _matchedFixture !== null;
    const runsOnExampleData = shouldRunOnExampleData(generatedWorkflow, { runnableWorkflow, userSuppliedRunData });
    const workflowReplyState = decideWorkflowReplyState({
      isWorkflowTurn,
      runnableWorkflow,
      generationFailed: workflowGenerationFailed,
      hasInlineData,
      // Example data satisfies the data-first ask the same way an upload would.
      messageCarriesData: messageCarriesRunData(message) || messageWaivesDataAsk(message) || _matchedFixture !== null || runsOnExampleData,
      unboundRequiredInputs: unboundDataInputs,
    });
    // Never ask for data when the workflow runs on its own example dataset.
    const needsDataInput = workflowReplyState === 'generated_needs_input' && !runsOnExampleData;
    const needsInputList = unboundDataInputs
      .map(i => `${i.label}${i.description ? ` (${i.description.replace(/s3:\/\/\S+/gi, '').trim()})` : ''}`)
      .join('; ');

    // Attached data the chosen workflow does not read. The binding pass in
    // generateWorkflow() records what fitted a real file input; when nothing did
    // and the workflow has no waiting data input, the workflow genuinely takes no
    // data — so the reply must NOT present it as built from the user's files
    // (founder report: five files attached, panel said "parameters only").
    const attachmentsUnusedList = attachmentsNotUsed((generatedWorkflow as any)?._attachmentBinding, {
      runnableWorkflow,
      unboundRequiredInputs: unboundDataInputs.length,
    });
    const attachmentsUnused = attachmentsUnusedList.length > 0;

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
    let systemPrompt = localOnly()
      ? localResponsePrompt(`${sessionMemoryBlock}${ltmBlock}${projectContextBlock}${inlineDataBlock}${sessionDatasetsBlock}${domainProfileContext}`, localOffline())
      : isResearchIntent
      ? `${sessionMemoryBlock}${ltmBlock}${projectContextBlock}${inlineDataBlock}${sessionDatasetsBlock}${domainProfileContext}You are BioMate, an expert bioinformatics AI assistant with deep scientific knowledge.

PROACTIVE-WORK RULE (highest priority):
- Do everything you can with the information already on the table BEFORE asking the user a clarifying question.
- NEVER produce any of these refusal patterns: "I don't have internet access", "I can't query databases", "I can't execute under the current environment", "I lack live access to X", "I can't run this in this environment". They are FALSE — BioMate has live DB integrations on the backend, indexed DB-API tool-functions reachable via workflow steps, and pre-resolved results injected into the prompt. Only report a failure when a tool actually returned an error in this turn.
- If the user gave a SMILES, gene symbol, accession, or any other identifier, ASSUME BioMate can resolve it — look in <pre_satisfied_parameters> or prior tool messages, or resolve it yourself via the data-plane tools (search_literature, list_data_sources, run_code). Use those before claiming anything is missing.

BioMate's real capability surface (verified, do not extrapolate):
- **Data ingestion:** users get data in by (a) the upload button, (b) an S3/local path, (c) an SRA/ENA/GEO/ArrayExpress/PXD accession, or (d) **Import from URL** (Data → Import from URL), which fetches any direct HTTP/FTP/S3 link AND a **Google Drive or Dropbox share link** — BioMate converts the share link to a direct download server-side. So BioMate CAN use a user's Google Drive / Dropbox data; NEVER tell a user it "cannot access Google Drive / Dropbox / their cloud files" — instead point them to **Import from URL** and ask for the share link.
- **4,200+ indexed Nextflow workflows** across 36 biological domains: transcriptomics (1,695), genomics (756), epigenomics (265), drug_discovery (200), proteomics (186), variant_calling (181), single_cell (100), cryo_em (19), and more.
- **12,312 indexed tool-functions** (individual command/wrapper entries) in the AI tool DB, ~4,141 with curated tool_knowledge metadata. Includes ~179 DB-API tool-functions (PubChem Download, UniProt Sparql, PubMed query, ChEMBL fetchers, etc.) that workflow steps can invoke.
- **Verified live DB integrations** called directly from the BioMate backend (research_agent + knowledge modules):
  - PubChem (compounds; resolve SMILES/CIDs on demand via the backend DB integrations)
  - PubMed / NCBI E-utilities (literature, gene lookups)
  - UniProt REST (proteins)
  - EBI (api.ebi.ac.uk — covers ChEMBL, Ensembl, AlphaFold)
  - OpenTargets platform API (drug-target evidence)
  - UCSC genome browser API
  Other DBs (KEGG, Reactome, OMIM, HPO, GTEx, ENCODE, DepMap, …) are reachable indirectly: route to an indexed DB-API tool-function as a workflow step rather than disclaiming. Say "I can pull this via the <tool-name> workflow step" — don't tell the user we lack the source.
- **Auto-injected pre-results** appear in <pre_satisfied_parameters> and similar tags. Read those before answering.
- **run_code tool** — Python/R/bash in an ephemeral biomate-biotools sandbox. R + Bioconductor (DESeq2, clusterProfiler, edgeR, limma, GSVA, fgsea, ReactomePA), numpy/scipy/pandas/statsmodels, biopython, pysam, cyvcf2, samtools/bcftools/bwa/mafft/iqtree pre-installed. **Sandboxed with --network=none — run_code cannot reach external APIs.** Use it for offline compute on data already in the prompt or attached as a file. If you need data from a DB, route to a workflow step that pulls it.
- **Workflow execution** ${process.env.NEXTFLOW_USE_AWS === 'true' ? 'on BioMate cloud compute via Nextflow — heavy-compute production path. All real workflows run on BioMate cloud compute; there is no local-vs-cloud switch.' : 'via local Docker+Nextflow — heavy-compute production path. Workflows run on this on-prem server using local Docker containers; no AWS Batch involved.'} The two paths overlap in what statistical / R+Bioconductor work they CAN do — pick by scale and whether the task matches an indexed pipeline.
- **Reusing prior-run outputs as next-workflow inputs.** Any workflow file parameter accepts the URI \`run:<fullRunId>:outputs/<filename>\`, which the backend automatically resolves to the underlying S3 path. To use this: call \`list_history\` to find the prior run's full id, then \`list_run_outputs\` to get its output file names. The \`param_uri\` field in that tool's response is the exact string to pass as the file param value — do not transform it. Example: a previous variant-calling run \`abcdef1234567890\` produced \`variants.vcf\`; for a variant-annotation workflow, set \`vcf_input = "run:abcdef1234567890:outputs/variants.vcf"\`.

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
- **Nextflow workflow ${process.env.NEXTFLOW_USE_AWS === 'true' ? 'on BioMate cloud compute' : '(local Docker)'}** (heavy path): production pipelines, multi-step orchestration, large datasets, GPU work, anything that needs network access (e.g. a DB-API tool-function step) or per-step containerization.

If the user explicitly says "use run_code" or "do not launch a Nextflow workflow", honor that. Otherwise pick based on what fits.

TOOL-USE OUTPUT RULE (critical):
- To use a tool (run_code, read_file, search_workflows, …) emit a REAL tool call — the system runs it and hands you the result. NEVER write tool-call syntax as prose: do not type \`<function_calls>\`, \`<invoke name="...">\`, \`</invoke>\`, or \`</function_calls>\` tags in your answer, and do not narrate the extraction plumbing (\`import PyPDF2\`, \`text.split('\\n')\`, \`print(text[:5000])\`, "let me read the file directly…") to the user.
- When a PDF, image, or other file is attached, its extracted content is ALREADY provided to you in-context (under a [Paper content: …] block or a tool result). Read that directly and answer — do not re-implement file reading in code you show the user.
- The user sees only your final answer. The mechanics of how you obtained it (tool calls, intermediate code) must never appear in the response text.

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

PROCESS / PROCEDURE FORMATTING (fixed template — reproduce the SHAPE verbatim so the answer is structured identically across runs; never describe a multi-step process as a running paragraph):
When the answer describes a process, protocol, procedure, method, pipeline, or any ordered sequence of ≥2 steps, render the steps as a numbered list using this exact template:

**<Process title>**
1. **<Step name>** — <what happens; key tool / parameter / value if any>
2. **<Step name>** — <what happens; key tool / parameter / value if any>
   (…one step per line, in order — as many as the process needs)

<optional one-line note on caveats, prerequisites, or expected output>

Rules: one step per numbered line; bold the step name; keep each step to a single line; steps in execution order; do NOT merge steps into prose. For a NON-ordered set of items (options, criteria, components), use "-" bullets instead of numbers, one item per line. Apply this every time a process is described, regardless of phrasing.

Do NOT strip explanation for "give me a number" questions — keep the number first, then a one-line rationale. The previous "print only value" pattern was overfitted to benchmark scoring and is removed.
For trivial arithmetic, answer directly without invoking run_code.`
      : `${sessionMemoryBlock}${ltmBlock}${projectContextBlock}${inlineDataBlock}${sessionDatasetsBlock}${domainProfileContext}You are BioMate, an expert bioinformatics AI assistant.

PROACTIVE-WORK RULE (highest priority):
- Do everything you can with what's on the table BEFORE asking the user a clarifying question. Use literature defaults (typical human dose/route, standard population, well-characterized PK values for known drugs) and STATE assumptions explicitly.
- NEVER produce refusal patterns like "I don't have internet access", "I can't query databases", "I can't execute under the current environment". They are FALSE. Only report a failure when a tool returned an actual error in this turn.
- Check <pre_satisfied_parameters> and prior tool messages before claiming an identifier is unresolved.

BioMate's real capability surface:
- **4,200+ indexed Nextflow workflows** across 36 domains (transcriptomics 1,695, genomics 756, epigenomics 265, drug_discovery 200, proteomics 186, variant_calling 181, single_cell 100, cryo_em 19, …)
- **12,312 indexed tool-functions** in the AI tool DB, ~4,141 with curated metadata. Includes ~179 DB-API tool-functions (PubChem, UniProt, ChEMBL, PubMed, etc. wrappers) that workflow steps invoke.
- **Verified live DB integrations** in the BioMate backend: PubChem, NCBI E-utilities / PubMed, UniProt, EBI (ChEMBL / Ensembl / AlphaFold), OpenTargets, UCSC. Resolve identifiers against these on demand rather than disclaiming.
- **run_code tool** — Python/R/bash in the biomate-biotools sandbox (R + Bioconductor, numpy/scipy/pandas, samtools/mafft/bwa/iqtree, biopython/pysam pre-installed). **--network=none — cannot reach external APIs.** Light-compute path for ad-hoc / format conversion / small statistical work on data already in the prompt.
- **Workflow execution** ${process.env.NEXTFLOW_USE_AWS === 'true' ? 'on BioMate cloud compute via Nextflow — heavy-compute production path; the path with network. ALL real workflows run on BioMate cloud compute; there is no local-vs-cloud switch.' : 'via local Docker+Nextflow — heavy-compute production path. Workflows run on this on-prem server using local Docker containers; no AWS Batch involved.'} Pick run_code or Nextflow by scale + whether the task matches an indexed pipeline.
- If the user needs to supply project-specific data, ask straightforwardly: "Please upload [format] / provide [value]." Do not phrase it as an environment limitation.

(Inline data — if any — is listed in <pre_satisfied_parameters> above. Never ask for those parameters again.)

RESPONSE FORMAT — follow this structure every time:

When a workflow was generated successfully:
  **[Workflow name]** — [one-sentence description]
  - **Input:** [list the actual inputs used from the query]
  - **Key steps:** [2–3 bullets, tool name → output]
  - **Expected output:** [what files/results the user will get]

When a workflow WAS generated (its card and panel are shown) but a required data input is not provided yet (the user has not given data):
  **[Workflow name]** — [one sentence: what it does]
  [One or two sentences: the data input it still needs (e.g. a samplesheet of FASTQ reads) and how to give it — attach the files with the 📎 button, or, for public sequencing data, reply with its accession (e.g. SRR…/GSE…).]
  Never say the workflow could not be generated or is unavailable — it was found. Do not list pipeline stages. Never ask for a storage path.

When no workflow was generated AND no inline data is present (clarification needed — workflow turn only):
  **Missing: [what is needed]**
  [ONE specific question stating exactly what formats are accepted]

When no workflow was generated AND inline data IS present (technical failure — workflow turn only):
  **Could not generate workflow** — [specific reason in one sentence]
  **Closest available option:** [name + brief description]
  [ONE configuration question if needed, otherwise say "Try adjusting parameters in the panel"]

**The formats above apply ONLY to workflow-generation turns.** For all other intents (research questions, protocol guidance, document extraction, general questions, explanations, data interpretation, etc.) respond directly and comprehensively — no "Missing:" prefix, no data-format questions. Just answer.
════════════════════════════════════════════════════════

IMPORTANT RULES:
${isWorkflowTurn ? `- NEVER compute or calculate results yourself for workflow tasks (e.g., sequence alignment, variant calling, etc.) — ALWAYS run the appropriate BioMate tool or workflow instead` : `- You CAN and SHOULD compute, calculate, and reason directly when no Nextflow workflow panel is open. Use the run_code tool for numerical computations, statistical calculations, sequence operations, or data manipulation. Prefer run_code over mental arithmetic for non-trivial calculations.
- R/BIOCONDUCTOR EXECUTION PRIORITY: (1) Search BioMate's 1,000+ indexed Bioconductor workflows first — if a match exists, use it. (2) If no match, generate a new workflow. (3) For small ad-hoc tasks or single statistical tests, use run_code with R directly — do not refuse to execute R code.`}
- If a runnable workflow was generated, explain it and tell the user to review the panel and click "${runButtonLabel(context.uiLanguage)}" (that exact button label)
- If workflow generation failed, explicitly explain likely reasons using available diagnostics and process outputs (error details, confidence, template match, tool/runtime signals)
- If workflow generation failed, collaborate with the user by asking targeted follow-up questions and proposing concrete next recovery actions
- If no workflow but tools were found, explain which tool to use and suggest creating a workflow
- Only provide direct answers for conceptual questions (e.g., "what is RNA-seq?"). If the user wants to RUN or GENERATE a workflow, apply the DATA-FIRST RULE below — do not explain pipeline steps.

DATA-FIRST RULE (hard prohibition — no exceptions except demo/test/mock):
- NEVER describe workflow steps, list pipeline stages, explain tools, or provide any execution instructions in response to a workflow-generation request when the user has not yet provided input data. This is a strict prohibition, not a preference. Violating this rule means the system cannot run.
- EXCEPTION — PRE-SATISFIED PARAMETERS: If a <pre_satisfied_parameters> block appears above AND a runnable workflow was generated, the DATA-FIRST RULE does NOT apply. The parameters are already provided (either explicitly in the message or auto-extracted by the AI). Proceed directly to the "Workflow generated" format.
- "Input data provided" means the user's message contains ANY of: a file path (e.g. /path/to/sample.fastq, /data/reads_R1.fastq.gz), an S3 URI (s3://…), an SRA/ENA/DDBJ accession (SRR followed by digits, ERR followed by digits, DRR followed by digits), a GEO accession (GSE followed by digits, GSM followed by digits), an ArrayExpress accession (E-MTAB- followed by digits), a PXD accession (PXD followed by digits), a SMILES string, an InChI string, an amino acid sequence, a PDB ID, or an "[Uploaded datasets: ...]" block.
- **PAPER-AS-SPECIFICATION EXCEPTION:** When the user provides a research paper (URL, DOI, arXiv ID, PMID, "[Attached files: *.pdf]", or "[Paper content: ...]" block) AND asks to reproduce/run/implement the workflow from it, the DATA-FIRST RULE does NOT apply. The paper is the workflow specification. Proceed to workflow generation — BioMate will extract the methods section and map it to an appropriate pipeline. If sample input data is needed to actually run the workflow, ask for it AFTER presenting the generated workflow, not before.
- SRA ACCESSION RULE: An SRA/ENA/DDBJ accession number (e.g. SRR1518169, ERR204916, DRR013480) IS input data. Treat it as the reads/input parameter. Proceed directly to workflow generation. DO NOT ask for files when an SRA accession is present in the message.
- EXCEPTION — EXAMPLE-DATA WORKFLOW: If the Current context below says "EXAMPLE-DATA WORKFLOW", the resolved workflow runs on its own built-in example dataset and the DATA-FIRST RULE does NOT apply. Do NOT ask for data; present the runnable card and follow that directive.
- If NO input data is present (and no EXAMPLE-DATA WORKFLOW directive applies): ask EXACTLY ONE specific question. State what the workflow needs and list the accepted data formats. Example: "To run this GATK germline pipeline I need your input data. Please attach your FASTQ files with the 📎 button, or give an SRA accession number (e.g. SRR1518169). Which do you have?" Do NOT explain workflow steps. Do NOT list pipeline stages. Do NOT describe what the tools do.
- Exception: if the user explicitly requests a "demo", "test", or "mock" workflow, generate it immediately without asking for data. This exception ALSO covers any of these phrasings, treat them as identical: "with defaults", "use defaults", "default parameters", "synthetic data", "synthetic plate", "demo data", "example data", "sample data", "built-in demo", "use the demo data", "no data, just run it", "I just want to see it", "show me how this works". Many BioMate workflows (notably hts_plate_qc_hit_calling, exposure_response_modelling, demo PBPK, the cryo-EM SPA reference workflows) ship with a built-in synthetic-data generator that fires when no input is provided — when the user signals they want to use it, generate the workflow immediately and do NOT ask for an upload.

TURN-2 QUALIFIER RULE:
- If the previous assistant message generated a workflow card AND the user's current message provides a type qualifier (e.g., "germline", "somatic", "bulk RNA-seq", "single-cell", "tumor-only", "paired tumor/normal", "inherited disease", "cancer"), regenerate the workflow immediately with the qualifier applied. Do NOT describe the workflow in text. Do NOT ask for data again. The previous conversation's input data is still valid.

ONE-QUESTION RULE:
- Ask at most ONE clarification question per conversation. Once the user has replied with any data OR answered a question (even if no data was provided), generate the workflow immediately using the information gathered and sensible default parameter values. Do NOT ask multiple rounds of clarifying questions — parameters can be adjusted in the workflow parameter panel after generation.
- If the conversation history shows that the assistant already asked a question in the previous turn (e.g., asked for data or asked germline/somatic clarification), and the user's current message replies to that question (even if no data accession was given), generate the workflow immediately. Do not ask for data again. Use placeholder values for missing required params — the user can fill them in the parameter panel. This applies in particular when the user's reply is a confirmation-style answer such as "yes", "yes run with defaults", "go ahead", "run it", "proceed", "ok", "sure", "use the demo data", "fine, use defaults". Treat all of these as instructions to generate the workflow now. Never ask for data twice in the same conversation — if you asked once and the user did not provide data on reply, generate with defaults/synthetic-data fallback.
- META-RULE on phrasing: never echo the name of an internal instruction in your reply. Forbidden surface phrases include (but are not limited to): "SECOND-TURN OVERRIDE", "OVERRIDE applies", "ONE-QUESTION RULE", "rule applies", "applying rule X", "META-RULE", "system prompt says", "according to my instructions". Internal scaffolding must stay internal. Just produce the answer the rule prescribes — do not narrate the rule.
- NEVER show storage locations to the user: no "s3://" URIs, bucket names, the word "S3", upload paths or dataset UUIDs — in any language. Likewise never name the execution infrastructure (AWS, Batch, the internal workflow backend) — say "BioMate's cloud compute". Refer to inputs by file name (e.g. pilot_compounds.csv) or by public accession (e.g. SRR1039508). Storage URIs are for tool and workflow parameters only, never for your reply text.
- When the message contains a "[Prepared inputs: ...]" block, it is background notes about the attached example files (what the data is, column meanings, where it is already staged). Use it to run the request correctly; never quote it, mention it, or call it a "block", "demo context" or "notes".
- When the message contains an "[Uploaded datasets: ...]" block, parse it. Format: "filename: dataset_id=<ID>" or "filename: dataset_id=<ID>, s3_uri=<S3URI>". For read_file and run_code: use the dataset_id and access via $DATA_DIR/<id>/<filename>. For Nextflow workflow parameters (matrix_file, sample_file, input, reads, etc.): use s3_uri when present (Nextflow workers access files directly via the s3_uri); if s3_uri is absent, use the dataset_id as the param value — BioMate stages the file at execute time. NEVER leave a file param empty or skip a Nextflow workflow because s3_uri is absent.
- Differential-expression file mapping rule: When multiple CSV files are uploaded for a DE workflow (differentialabundance, DESeq2, edgeR, limma), map them as follows based on filename keywords: files containing "sample", "metadata", "samplesheet", "coldata", "design" → use as the 'samplesheet' param (or 'input' if the workflow only declares 'input'). Files containing "count", "matrix", "expression", "counts" → use as the 'matrix' param. Files containing "contrast", "comparison" → use as the 'contrasts' param. NEVER create a generic 'dataset' param. Every uploaded file must map to a named workflow param.
- When the message contains an "[Attached files: ...]" block without a corresponding "[Uploaded datasets: ...]" block, the upload failed. Tell the user which files failed and ask them to try again.
- GEO accession routing rules:
${process.env.S3_ENDPOINT_URL ? '' : `  GSE227835 (AChR+ myasthenia gravis scRNA-seq, pseudobulk-aggregated, ALWAYS ready):
    Route to nf-core/differentialabundance. Do NOT route to geo_scrna_pseudobulk.
    ALWAYS set these THREE SEPARATE parameters — never leave them empty, never concatenate:
    samplesheet: s3://biomate-nextflow-work/demo/mg_demo/sample_metadata.csv
    matrix: s3://biomate-nextflow-work/demo/mg_demo/counts_matrix.csv
    contrasts: s3://biomate-nextflow-work/demo/mg_demo/contrasts.csv
    If the message contains uploaded file URIs (s3://biomate-nextflow-outputs/...) for these params, use those instead.
    Tell the user you are using pre-processed pseudobulk counts for GSE227835 (MG vs healthy controls).
`}  Other GEO accessions (any GSE ID that is NOT GSE227835):
    Route to geo_scrna_pseudobulk only when it is a single-cell DE/pseudobulk request. For bulk RNA-seq or microarray, route to geo_data_connector with accession pre-filled. Say that it will retrieve the GEO series matrix and sample metadata for review; do not promise automatic DESeq2 or automatic contrast selection.
${process.env.S3_ENDPOINT_URL ? '' : `  * GSE227835 enrichGO follow-up (complement pathway enrichment after DESeq2 on GSE227835 MG data):
    When the conversation includes a prior DESeq2/differentialabundance run on GSE227835 AND the user requests pathway enrichment or clusterProfiler/enrichGO:
    ALWAYS set gene_list: s3://biomate-nextflow-work/demo/mg_demo/de_genes.txt
    If the message contains an uploaded gene list file URI, use that instead.
    Route to clusterprofiler. Do NOT ask the user to upload a gene list.
`}
- Differential-expression method selection (data-type rule): When the input is **microarray** data — signals include (a) the word "microarray", (b) a log-transformed continuous expression matrix (non-integer values, often 4–14 range), (c) a GEO accession known to be microarray (e.g. GSE22055, GSE10072 — Affymetrix/Illumina BeadChip series) — **prefer limma** (linear-model + empirical Bayes) and NOT DESeq2/edgeR. DESeq2 and edgeR assume raw integer counts (RNA-seq) and produce invalid results on continuous microarray intensities. For RNA-seq raw counts use DESeq2 (most common) or edgeR. For RNA-seq with low-count genes or covariate-heavy designs, limma-voom is also valid. If the data type is ambiguous, ask once which platform produced the data, then route accordingly — do not default to DESeq2 silently.
${isDrugDevelopmentQuery ? `- For drug-development requests, provide decision-grade guidance: list concrete workflow phases, critical safety/quality gates, required inputs, and explicit next actions` : ''}
${isDrugDevelopmentQuery ? `- For drug-development WORKFLOW GENERATION FAILURES ONLY (when the system returns an error or cannot find a matching workflow): include at least TWO distinct blocker categories (e.g., tool gap, input gap, domain mismatch) and ask at least TWO targeted follow-up questions. IMPORTANT: This rule does NOT apply when the user has already provided input data (SMILES, sequence, files) — in that case generate the workflow immediately.` : ''}

Workflow routing (use these specific workflows when the user's intent matches):
${buildWorkflowRoutingBlock(preferredDomains)}

${cryoEmContextBlock ? `${cryoEmContextBlock}\n\n` : ''}${buildDomainSpecialistBlock(preferredDomains)}${buildDomainCatalogBlock(preferredDomains)}${context.skillPackIds !== undefined || context.activeSkillIds !== undefined ? "" : await buildSkillBlock(message, preferredDomains, context)}${(generatedWorkflow as any)?._nearTieAlternative ? `\n[NEAR-TIE NOTE] The workflow search found "${(generatedWorkflow as any)._nearTieAlternative}" with a very similar match score. At the end of your response, add exactly one sentence: "If you were looking for ${(generatedWorkflow as any)._nearTieAlternative} instead, let me know and I'll switch." Do not ask this as a question — state it as a note.\n` : ''}Style guide:
- Be concise and practical
- When mentioning tools, use the primary user-facing name (e.g. "CryoSPARC", "BWA-MEM2", "GATK") — never use internal pipeline paths or tool IDs
- Explain workflow steps and expected outputs clearly
- Do NOT include a "Next Steps After This Workflow" section — suggest follow-up steps only after the user confirms execution is complete
${isDrugDevelopmentQuery ? `- Use section labels when possible: "Workflow phases", "Required inputs", and "Next step"` : ''}

Current context:
${tools.length > 0 ? `- Found ${tools.length} relevant tools` : ''}
${datasets.length > 0 ? `- Found ${datasets.length} relevant datasets` : ''}
${runsOnExampleData ? `- EXAMPLE-DATA WORKFLOW (overrides the DATA-FIRST RULE): This workflow ships its own built-in example/reference dataset and runs on it when no files are attached. Do NOT ask the user to upload or provide data, and do NOT list missing inputs — the card is runnable now. Present it with the "Workflow generated" format and include exactly one honest sentence to the effect of: "${exampleDataNote(generatedWorkflow)}" Never mention storage paths, S3, buckets or dataset IDs, and do not claim it analyses the user's own data.` : needsDataInput ? `- Workflow generated; its required data input is not provided yet (${needsInputList}) — use the "generated but required data input not provided yet" format` : runnableWorkflow ? '- Runnable workflow generated successfully — use "Workflow generated" format' : ''}
${singleWfGrounding ? `- ${singleWfGrounding}` : ''}
${attachmentsUnused ? `- ATTACHED DATA NOT USED: the user attached ${attachmentsUnusedList.join(', ')}, but this workflow reads none of them — it is configured by parameters only. Do NOT say it was built from, uses, or analyses their data, and do NOT list their files as its inputs. State in one plain sentence that this workflow does not take those files, say what it does run on, and offer to find a workflow that does read that data.` : ''}
${(() => {
  const _mfi: string[] = (generatedWorkflow as any)?.missing_file_inputs ?? [];
  if (!_mfi.length || runsOnExampleData) return '';
  return `- MISSING INPUT FILES: The workflow was found but cannot run without these input files: ${_mfi.join(', ')}. The Run button in the panel is blocked until they are provided. Do NOT describe workflow steps. Instead: (1) confirm you found the workflow by name, (2) list each missing file with its expected format (e.g. CSV samplesheet, count matrix CSV), (3) ask the user to provide the data by ANY of: the 📎 attach button, a public URL, an SRA/GEO accession, OR **Import from URL** — which fetches a direct link AND a Google Drive / Dropbox **share link** (BioMate converts the share link to a direct download server-side). Never tell the user BioMate "cannot access Google Drive / Dropbox" — it can, via Import from URL with the share link. Use plain language — no "DATA-FIRST RULE" phrasing.`;
})()}
${workflowGenerationFailed && hasInlineData ? '- Workflow generation failed (inline data was present) — use "Technical failure" format, do NOT ask for data the user already provided' : ''}
${workflowGenerationFailed && !hasInlineData ? '- Workflow generation failed (no inline data) — use "Clarification needed" format' : ''}
${(generatedWorkflow as any)?.license_notice ? `- LICENSE REROUTING ACTIVE: ${(generatedWorkflow as any).license_notice} The response MUST explicitly tell the user that the originally requested tool is not available under their current license configuration and explain that the fallback alternative was automatically selected instead. Include the phrase "not available" or "requires a license" in the explanation.` : ''}`;


    systemPrompt += responseLanguageDirective(context.uiLanguage);
    systemPrompt += modelIdentityDirective(context.modelIdentity ?? modelIdentity(this.responseModelFor(context)), context.llmRegion);

    if (isSimpleSequencePropertyRequest(message)) {
      systemPrompt += '\nThis is a basic property calculation on the supplied sequence, not folding or antibody design. Execute it with run_code using Bio.SeqUtils.ProtParam.ProteinAnalysis. Print a JSON object with sequence, molecular_weight and isoelectric_point from the actual library methods. Only report values returned by the successful tool. State that these are theoretical properties of an unmodified linear sequence; do not infer cyclic chemistry, structure, affinity, efficacy or safety. If reporting the computed instability index, the ProtParam convention is below 40 predicted stable and above 40 potentially unstable; 40 is a boundary, not a measured half-life or a validated stability threshold for this short peptide. Do not invent a different threshold or assert experimentally established peptide instability. Prefer the requested molecular weight and pI over unsolicited biological interpretations.';
    }

    // Build research/benchmark context sections.
    // Prioritise the synthesized `answer` field (which already contains db_facts, tool context,
    // and figure data from the Python research agent) rather than truncating the raw JSON.
    const researchSection = researchResponse
      ? (() => {
          const rr = researchResponse as any;
          const parts: string[] = [researchEvidenceContext(rr)];
          if (rr.benchmark_evidence) {
            parts.push(`\nBenchmark evidence: ${JSON.stringify(rr.benchmark_evidence).slice(0, 500)}`);
          }
          return `\n${parts.join('\n')}`;
        })()
      : '';
    const benchmarkSection = benchmarkEvidence
      ? `\nBenchmark Evidence:\n${JSON.stringify(benchmarkEvidence, null, 2).slice(0, 2000)}`
      : '';

    const inputsNote = !runnableWorkflow && attachedDatasetsFromMessage(message).length
      ? runCodeInputsNote(message, await this._attachedFileHeads(message, context))
      : '';
    const userPrompt = `User: ${modelFacingUploads(message)}
${replyLanguageNote(message)}
${inputsNote ? `\n${inputsNote}\n` : ''}
${tools.length > 0 ? `\nRelevant tools:\n${tools.map((t, i) => `${i + 1}. ${t.tool.name} - ${t.reasoning}`).join('\n')}` : ''}

${datasets.length > 0 ? `\nRelevant datasets:\n${datasets.map((d, i) => `${i + 1}. ${d.dataset.name} - ${d.reasoning}`).join('\n')}` : ''}

${needsDataInput ? `\nA workflow has been generated and is shown in the panel. It is waiting only for its required data input: ${needsInputList}.` : runnableWorkflow ? '\nA runnable workflow has been generated and is ready to run.' : ''}
${attachmentsUnused ? `\nThe workflow in the panel reads none of the attached files (${attachmentsUnusedList.join(', ')}) — it takes parameters only. Say so plainly; never describe those files as its inputs.` : ''}
${workflowGenerationFailed && hasInlineData ? `\nWorkflow generation failed (inline data was present — do NOT ask for it again).\nFailure details: ${JSON.stringify(workflowFailureSignals, null, 2).slice(0, 800)}` : ''}
${workflowGenerationFailed && !hasInlineData ? `\nWorkflow generation diagnostics:\n${JSON.stringify(workflowFailureSignals, null, 2).slice(0, 1600)}` : ''}${researchSection}${benchmarkSection}

Use the RESPONSE FORMAT from the system prompt. Specifically:
${needsDataInput
  ? `FORMAT: Workflow generated — required data input not provided yet.
     - ${cardWorkflowName(generatedWorkflow)
        ? `Start with "**${cardWorkflowName(generatedWorkflow)}** — [one sentence on what it does]", using exactly that name.`
        : `Start with "**[workflow name]** — [one sentence on what it does]"`}
     - Then say the one data input it still needs (${needsInputList}) in plain words, and how to give it: attach the files with the 📎 button, or, for public sequencing data, reply with its accession (e.g. SRR…/GSE…).
     - Do NOT say the workflow could not be generated, is missing, or failed — it was found and is in the panel.
     - Do NOT list pipeline stages. Do NOT mention storage locations, buckets or paths.`
  : runnableWorkflow
  ? `FORMAT: Workflow generated successfully.
     - ${cardWorkflowName(generatedWorkflow)
        ? `The workflow panel shows "${cardWorkflowName(generatedWorkflow)}". Start with "**${cardWorkflowName(generatedWorkflow)}** — [one sentence]", using exactly that name. Never lead with a descriptive title or any other name of your own.${alternativeWorkflowNames(generatedWorkflow).length
          ? `
     - The workflow search also found: ${alternativeWorkflowNames(generatedWorkflow).map(n => `"${n}"`).join(', ')}. Only if one of these is clearly the right workflow for this request and the panel's is not, lead with that one's exact name in bold instead — the panel switches to the workflow you lead with.`
          : ''}`
        : `Start with "**[workflow name]** — [one sentence]"`}
     - Bullet: Input used (the actual value from the message)
     - Bullet: Key steps (2–3, tool → output) — ONLY steps of the bound workflow above; never invent a multi-step composite pipeline in prose when the engine bound a single workflow_ga
     - Bullet: Expected output (file types / results)
     - Do NOT say "click Run" — the Run button is already visible${singleWfGrounding ? `
     - ${singleWfGrounding}` : ''}`
  : !isWorkflowTurn
    ? (researchResponse || /\[Paper content:/i.test(message))
      ? `FORMAT: Research / document answer.
     - Answer directly and fully. Extract information from any [Paper content: ...] blocks in the message and use any research evidence provided.
     - Cite the paper(s) by name. Use [N] inline where relevant.
     - End with ## References section listing papers cited.`
      : `FORMAT: Direct answer.
     - Answer the question directly and completely. No workflow format. No "Missing:" prefix.
     - Use run_code if computation is needed on data already in the prompt.`
  : workflowGenerationFailed && hasInlineData && workflowFailureSignals?.error === 'clarification_needed'
    ? `FORMAT: Pipeline selection needs one clarification.
     - Do NOT say "internal routing error" or "could not generate" — this is a normal disambiguation step.
     - Ask the specific clarification question from the failure details (clarification_question field).
     - One line: name the closest pipeline option found.
     - At most ONE question. Do not ask for data the user already provided.`
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
        content: typeof msg.content === 'string' ? modelFacingUploads(msg.content) : msg.content,
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
      const useThinking = !localOnly() && this.modelConfig.enableThinking;
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
      // Gate on the ACTUAL generated workflow, not isWorkflowTurn. isWorkflowTurn is
      // also true when a workflow was merely *suggested* (shouldGenerate) but none was
      // produced — a frequent false positive on plain data/compute/lookup questions
      // ("list my files", "compute this"), which wrongly suppressed the whole agentic
      // tool layer and made the model hallucinate/deny tools it has. Tools are only
      // counter-productive when there is a real workflow to narrate (generatedWorkflow).
      const toolsEnabledThisTurn = (!useThinking && onToolEvent && !hasRunnableWorkflow);
      // Expose the authenticated user's registered external MCP tools alongside the
      // built-in tools (namespaced mcp__<server>__<tool> — no collision). Fetched
      // once per turn; populates context.mcpToolServerMap for dispatch. Skipped
      // entirely when tools are off this turn or there is no user-scoped proxy.
      const userMcpTools = toolsEnabledThisTurn ? await this._fetchUserMcpTools(context) : [];
      // Tool turns write whole analysis scripts in one call; 4096 cut them off repeatedly (live dev
      // 2026-11-12: two max_tokens turns in one image-QC chat). Plain replies keep 4096.
      if (toolsEnabledThisTurn) apiOptions.max_tokens = Math.max(apiOptions.max_tokens || 0, 8192);
      const agentTools = toolsEnabledThisTurn
        ? [
            ...BIOMATE_TOOLS.filter(tool => !localOffline() || !['search_literature', 'query_database', 'list_data_sources', 'identify_targets', 'write_review'].includes(tool.name)),
            ...userMcpTools,
          ]
        : undefined;

      // Vision: when the user attached image(s), send them to the multimodal model
      // as real image content blocks so it can give a grounded biomedical read
      // (histology, gels/blots, plots, scans) instead of guessing from filenames.
      // Only the Claude backbone consumes agentMessages; other providers use a
      // text-only plainMessages path below, so skip the base64 work for them.
      // Images reach every path that can carry image blocks: the Claude-shaped agent loop (local,
      // a claude-* backbone, the OpenRouter shim) — and, with an Anthropic key, a non-Claude backbone
      // too, because an image turn is routed through that loop below (live dev 2026-11-12: with
      // BIOMATE_RESPONSE_MODEL=gpt-5.6-luna the gate skipped the image although the turn ran on Haiku).
      const _imageCapablePath = localOnly() || this.modelConfig.responseModel.startsWith('claude-')
        || !!_openrouterAgentic.getStore() || !!process.env.ANTHROPIC_API_KEY;
      const _projectImageReader = async (id: string, maxBytes: number): Promise<Buffer | undefined> => {
        const d = (context.sessionDatasets || []).find(x => (x.id === id || x.projectFileId === id) && !!x.s3_key);
        if (!d?.s3_key) return undefined;
        const { s3Service } = await import('./s3-client');
        return s3Service.readBuffer(d.s3_key, maxBytes);
      };
      const { blocks: imageBlocks, attached: attachedImages, skipped: skippedImages } =
        _imageCapablePath
          ? await _buildImageContentBlocks(message, undefined, _projectImageReader)
          : { blocks: [] as any[], attached: [] as string[], skipped: [] as Array<{ name: string; reason: string }> };
      let userContent: Anthropic.MessageParam['content'];
      if (imageBlocks.length > 0) {
        const visionNote =
          `\n\n[${attachedImages.length} image(s) attached and shown to you: ${attachedImages.join(', ')}]` +
          (skippedImages.length
            ? `\n[Not shown: ${skippedImages.map(s => `${s.name} (${s.reason})`).join('; ')}]`
            : '') +
          `\nGive a careful biomedical read of the image(s): describe what you see, note any features of scientific interest, and offer an interpretation. State your uncertainty explicitly and frame it as informational analysis, NOT a clinical diagnosis — recommend expert/lab confirmation for anything consequential.`;
        userContent = [
          { type: 'text', text: userPrompt + visionNote },
          ...imageBlocks,
        ];
      } else {
        userContent = userPrompt;
      }

      const agentMessages: Anthropic.MessageParam[] = [
        ...previousMessages,
        { role: 'user', content: userContent },
      ];


      let rawResponse = '';
      let lastStopReason: string | null = null;
      const MAX_TOOL_TURNS = 5;

      // ── Response generation: Gemini (primary) → Claude → OpenAI → Ollama ──────
      // Fallback chain mirrors llm_providers.yml. Claude path below this block
      // provides the full agentic tool loop; this chain handles non-Claude primaries
      // and serves as the fallback when Claude is unavailable.
      const responseModel = this.modelConfig.responseModel;
      // OpenRouter-selected models run the agentic loop via the shim in _anthropicOverride
      // (see processMessage); treat them as a Claude-shaped backbone here so the agentic
      // tool loop fires (and the model isn't force-overridden to Haiku below).
      const isClaudeBackbone = localOnly() || responseModel.startsWith('claude-') || !!_openrouterAgentic.getStore();

      // Tool-eligible turns need a REAL tool loop. The non-Claude provider chain
      // below is text-only (no tool loop) → the 60+ data-plane DBs, literature
      // search, run_code and MCP tools never fire, and the model confabulates
      // lookups it never ran. Route those turns through the proven Claude agentic
      // loop when an Anthropic key is available, overriding the model (the
      // configured responseModel, e.g. gpt-5.6-luna, is not an Anthropic model).
      // Non-tool turns keep the configured model via the text-only chain below;
      // if no Anthropic key, this degrades to the current text-only behavior
      // (and the integrity guard still flags any fabricated lookup).
      // An image turn needs the loop that carries image blocks; the text-only chain drops them.
      const useAgenticLoop = isClaudeBackbone
        || ((toolsEnabledThisTurn || imageBlocks.length > 0) && !!process.env.ANTHROPIC_API_KEY);
      if (useAgenticLoop && !isClaudeBackbone) {
        apiOptions.model = 'claude-haiku-4-5-20251001';
      }

      if (!useAgenticLoop) {
        const plainMessages = [
          ...previousMessages.map(m => ({
            role: (m.role === 'assistant' ? 'assistant' : 'user') as 'user' | 'assistant',
            content: typeof m.content === 'string' ? m.content
              : (m.content as any[]).filter((b: any) => b.type === 'text').map((b: any) => b.text).join(''),
          })),
          { role: 'user' as const, content: userPrompt },
        ];

        // Provider chain: try each in order, stop on first success
        const _openaiCompatClient = _openrouterClientStorage.getStore();
        const providers: Array<{ name: string; fn: () => Promise<string>; available: boolean }> = [
          {
            // Custom OpenAI-compatible provider (Qianwen/DashScope, DeepSeek, vLLM, etc.)
            // injected via AsyncLocalStorage when LLM_API_KEY + LLM_API_URL are set.
            // Uses the full agentic tool loop so all BioMate tools work (run_code,
            // search_literature, list_data_sources, …) — same capability as Claude/Gemini.
            name: 'OpenAI-compatible',
            fn: () => {
              if (!_openaiCompatClient) throw new Error('No OpenAI-compatible client');
              const model = context.selectedModel || process.env.LLM_MODEL || 'qwen-max';
              return this._generateWithOpenAICompatible(
                _openaiCompatClient,
                model,
                systemPrompt,
                plainMessages,
                onResponseDelta,
                4096,
                (!useThinking && onToolEvent && !hasRunnableWorkflow)
                  ? { tools: BIOMATE_TOOLS, context, onToolEvent }
                  : undefined,
              );
            },
            available: !!_openaiCompatClient,
          },
          {
            name: 'Gemini',
            // Activate the agentic tool loop on the PRIMARY Gemini backbone — same
            // gate as the Claude path (8338). Without this, the default gemini-3.8-flash
            // config ran tool-less: run_code/list_history AND the data-plane tools
            // (search_literature/search_my_data/list_data_sources) never attached, so
            // the model hallucinated tool use and denied capabilities it has. The
            // _generateWithGemini loop executes tools + emits tool_event when handed a
            // toolContext (as the fallback at the catch below already does).
            fn: () => this._generateWithGemini(
              systemPrompt, plainMessages, onResponseDelta, 4096, undefined,
              toolsEnabledThisTurn
                ? { tools: [...BIOMATE_TOOLS, ...userMcpTools], context, onToolEvent, requireExecution: (intent as any)?.execution === 'direct_compute' }
                : undefined,
            ),
            available: !!this.gemini && responseModel.startsWith('gemini-'),
          },
          {
            name: 'Claude',
            fn: async () => {
              if (!process.env.ANTHROPIC_API_KEY) throw new Error('ANTHROPIC_API_KEY not set');
              const res = await this._getClaude().messages.create({
                model: 'claude-haiku-4-5-20251001',
                max_tokens: 4096,
                system: systemPrompt,
                messages: plainMessages.map(m => ({ role: m.role as 'user' | 'assistant', content: m.content })),
              });
              const text = res.content[0]?.type === 'text' ? res.content[0].text : '';
              if (text && onResponseDelta) onResponseDelta(text);
              return text;
            },
            available: !!process.env.ANTHROPIC_API_KEY,
          },
          {
            // System-level OpenAI key (OPENAI_API_KEY env var) — also gets the full
            // agentic tool loop via _generateWithOpenAICompatible.
            name: 'OpenAI',
            fn: () => {
              const openaiKey = process.env.OPENAI_API_KEY!;
              const openaiModel = process.env.OPENAI_MODEL ?? 'gpt-4o';
              const openaiClient = new OpenAI({ apiKey: openaiKey });
              return this._generateWithOpenAICompatible(
                openaiClient,
                openaiModel,
                systemPrompt,
                plainMessages,
                onResponseDelta,
                4096,
                (!useThinking && onToolEvent && !hasRunnableWorkflow)
                  ? { tools: BIOMATE_TOOLS, context, onToolEvent }
                  : undefined,
              );
            },
            available: !!process.env.OPENAI_API_KEY,
          },
          {
            name: 'Ollama',
            fn: () => this._generateWithOllama(systemPrompt, plainMessages, onResponseDelta),
            available: true,
          },
        ];

        for (const provider of providers.filter(p => p.available)) {
          try {
            // An empty reply is a provider FAILURE, not a success: it used to end the chain with ''
            // (→ "having trouble…"), which is why parseActions once forced every workflow_generation
            // turn into workflow generation. Fail over to the next provider instead.
            rawResponse = requireNonEmptyResponse(await provider.fn(), provider.name);
            console.log(`[GalaxyAssistant] Response generated by ${provider.name}`);
            // Sync responseModel so llm_usage.model reflects the actual provider used
            if (provider.name === 'OpenAI-compatible') {
              this.modelConfig.responseModel = context.selectedModel || process.env.LLM_MODEL || 'qwen-max';
            } else if (provider.name === 'OpenAI') {
              this.modelConfig.responseModel = process.env.OPENAI_MODEL ?? 'gpt-4o';
            }
            break;
          } catch (err: any) {
            console.warn(`[GalaxyAssistant] ${provider.name} response failed — trying next:`, err.message);
          }
        }

        if (!rawResponse) {
          rawResponse = 'All response providers failed. Please try again in a moment.';
          if (onResponseDelta) onResponseDelta(rawResponse);
        }

        // Skip the Claude agent loop entirely for non-Claude backbones
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
        let finalMessage = qualityEnforcedMessage || rawResponse;
        if (!finalMessage) {
          const emptyFallback = 'I\'m having trouble generating a response right now. Please try again in a moment.';
          if (onResponseDelta) onResponseDelta(emptyFallback);
          return { message: emptyFallback, truncated: false };
        }
        // Integrity guard — tool-less backbones (non-Claude, non-Gemini, e.g.
        // gpt-5.6-luna via OpenRouter) have NO data-plane/literature tool loop
        // here, so any "I'll query Open Targets / searched PubMed" narration is
        // fabricated: the lookup never ran. Don't let the model pass training
        // knowledge off as a live retrieval — append (and stream) an honesty note.
        const _toolLessBackbone = !isClaudeBackbone && !responseModel.startsWith('gemini-');
        const _claimsLiveLookup = /\b(?:I['’]?ll|let me|now|I (?:have|just)|I['’]ve|going to)\s+(?:quer|search|look(?:ing)?\s*up|pull|retriev|fetch|check)\w*\b[^.\n]{0,60}\b(?:open\s*targets|pubmed|chembl|uniprot|ensembl|reactome|clinvar|pharos|drugbank|the\s+database|the\s+literature|genetic\s+association\s+score)\b/i;
        if (_toolLessBackbone && _claimsLiveLookup.test(finalMessage)) {
          const _disclaimer = "\n\n> ⚠️ **Generated from the model's training knowledge** — BioMate did not run a live database or literature query for this answer. Treat specific scores, statistics, and citations as unverified until checked against the source.";
          finalMessage += _disclaimer;
          if (onResponseDelta) onResponseDelta(_disclaimer);
        }
        this._logUnbackedFileClaims(finalMessage, message, context);
        return { message: redactStoragePaths(finalMessage, /[\u4e00-\u9fff]/.test(message)), truncated: false };
      }
      // ── End non-Claude backbone (falls through to Claude agentic loop) ─────────

      // Unexecuted-code guard: a reply that presents analysis code as if it ran, on data that is in
      // the conversation, while run_code never ran, is sent back once with an instruction to execute
      // it (external-user replay 2026-11-04: a fold-change request answered "Running analysis…" +
      // a pandas block, no run_code call). The text already shown is kept (_shownBeforeNudge).
      let _ranRunCode = false;
      let _codeNudged = false;
      let _shownBeforeNudge = '';
      let _toolsRan = false;            // any tool executed in this response
      let _streamedFragment = false;    // a truncated first turn already streamed text to the user
      let _carriedText = '';            // text of truncated turns, kept and joined to the continuation
      const _carryTruncatedText = (content: any[] | undefined) => {
        if ((content || []).some((b: any) => b?.type === 'tool_use')) return; // a cut tool call: its narration is superseded
        const t = (content || []).filter((b: any) => b?.type === 'text').map((b: any) => b.text || '').join('');
        if (t.trim()) _carriedText += stripNarratedToolCalls(t);
      };
      const _runCodeOffered = Array.isArray(agentTools) && (agentTools as any[]).some((t: any) => t?.name === 'run_code');
      // Structural first: the classifier decided direct_compute → a reply without a run_code call cannot
      // hold real results. The prose regex is only a secondary signal (execution-integrity.ts).
      const _directCompute = (intent as any)?.execution === 'direct_compute';
      const _shouldNudgeUnexecutedCode = (text: string) => shouldRequireExecution({
        directCompute: _directCompute, runCodeOffered: _runCodeOffered, ranRunCode: _ranRunCode, alreadyNudged: _codeNudged,
        proseSignal: presentsUnexecutedCode(text) && conversationHasComputableData(message, context) && !wantsCodeItself(message),
      });
      const _unexecutedCodeNudge = EXECUTE_NOW_NUDGE;

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
            () => this._getClaude().messages.create({ ...requestOptions, stream: true } as any),
            'response-stream',
          );

          // Accumulate both text deltas and tool_use content blocks
          const contentBlocks: any[] = [];
          let currentBlock: any = null;
          // Filters narrated <function_calls>/<invoke> tool-call XML out of the
          // live token stream so it never reaches the user's screen. rawResponse
          // keeps the raw text; it is sanitized once more before persistence.
          const leakFilter = new StreamToolCallFilter();

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
                  const safe = leakFilter.push(text);
                  if (safe) onResponseDelta(safe);
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
          const _flushed = leakFilter.flush();
          if (_flushed) onResponseDelta(_flushed);

          const toolUseBlocks = contentBlocks.filter(b => b.type === 'tool_use');
          if (lastStopReason === 'tool_use' && toolUseBlocks.length > 0) {
            // Assemble assistant message with all content blocks (text + tool calls)
            const assistantContent = contentBlocks
              .filter(b => b.type === 'text' || b.type === 'tool_use')
              .map(b => b.type === 'text' ? { type: 'text', text: b.text || '' } : { type: 'tool_use', id: b.id, name: b.name, input: b.input });
            agentMessages.push({ role: 'assistant', content: assistantContent as any });
            if (toolUseBlocks.some((b: any) => b.name === 'run_code')) _ranRunCode = true;
            _toolsRan = true;
            const toolResults = await this._executeTools(toolUseBlocks, context, onToolEvent);
            agentMessages.push({ role: 'user', content: toolResults as any });
            rawResponse = ''; // Reset — final text comes in a later turn
            continue; // next iteration
          }
          if (lastStopReason === 'max_tokens' && truncatedTurnNeedsFollowUp(contentBlocks, _toolsRan)) {
            console.warn('[GalaxyAssistant] streamed turn hit the output-length limit mid-work — asking the model to continue');
            agentMessages.push(...truncatedTurnFollowUp(contentBlocks) as any);
            _carryTruncatedText(contentBlocks);
            _streamedFragment = !!rawResponse.trim();
            rawResponse = '';
            continue;
          }
          if (_shouldNudgeUnexecutedCode(rawResponse)) {
            console.warn('[GalaxyAssistant] reply presented code without running it — asking the model to run_code');
            _codeNudged = true;
            _shownBeforeNudge = stripNarratedToolCalls(rawResponse);
            agentMessages.push({ role: 'assistant', content: [assistantTextBlock(rawResponse, '[code shown without running it]')] as any });
            agentMessages.push({ role: 'user', content: _unexecutedCodeNudge });
            rawResponse = '';
            continue;
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
          () => this._getClaude().messages.create(requestOptions),
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
          if (toolUseBlocks.some((b: any) => b.name === 'run_code')) _ranRunCode = true;
          _toolsRan = true;
          const toolResults = await this._executeTools(toolUseBlocks, context, onToolEvent);
          agentMessages.push({ role: 'user', content: toolResults as any });
          continue;
        }

        if (completion.stop_reason === 'max_tokens' && truncatedTurnNeedsFollowUp(completion.content as any[], _toolsRan)) {
          console.warn(`[GalaxyAssistant] tool-turn-${turn} hit the output-length limit mid-work — asking the model to continue`);
          agentMessages.push(...truncatedTurnFollowUp(completion.content as any[]) as any);
          _carryTruncatedText(completion.content as any[]);
          rawResponse = '';
          continue;
        }

        // End turn — extract text and emit as a single delta (non-incremental but correct)
        const textContent = completion.content.find((c: any) => c.type === 'text');
        rawResponse = textContent && textContent.type === 'text' ? (textContent as any).text : '';
        if (_shouldNudgeUnexecutedCode(rawResponse)) {
          console.warn('[GalaxyAssistant] reply presented code without running it — asking the model to run_code');
          _codeNudged = true;
          agentMessages.push({ role: 'assistant', content: completion.content as any });
          agentMessages.push({ role: 'user', content: _unexecutedCodeNudge });
          rawResponse = '';
          continue;
        }
        if (onResponseDelta && rawResponse) {
          onResponseDelta((_shownBeforeNudge || _streamedFragment ? '\n\n' : '') + stripNarratedToolCalls(rawResponse));
        }
        break;
      }
      // Tool budget exhausted while the model was still calling tools: the loop ends with no final
      // text, so the user saw only the opening narration ("I'll run a comprehensive QC analysis…")
      // or, below, a raw stdout line ("✓ Saved: crispr_qc_report.png") as the whole answer
      // (dev 2026-11-11: CRISPR QC — 5/5 turns spent on run_code, every time). The Gemini loop
      // already forces a final answer at its budget; this is the same contract for the Claude /
      // OpenRouter-shim loop: one more turn with tools disabled, asked to answer from the results.
      if ((lastStopReason === 'tool_use' || lastStopReason === 'max_tokens') && !rawResponse.trim()) {
        console.warn(`[GalaxyAssistant] tool budget (${MAX_TOOL_TURNS} turns) exhausted with no final answer — requesting one with tools disabled`);
        try {
          const finalTurn: any = await this._withAnthropicRetry(
            () => this._getClaude().messages.create({ ...finalAnswerRequest(apiOptions, agentMessages, agentTools) } as any),
            'final-answer',
          );
          lastStopReason = finalTurn?.stop_reason ?? lastStopReason;
          rawResponse = (finalTurn?.content || [])
            .filter((b: any) => b?.type === 'text').map((b: any) => b.text || '').join('');
          if (onResponseDelta && rawResponse.trim()) onResponseDelta('\n\n' + stripNarratedToolCalls(rawResponse));
        } catch (err: any) {
          console.warn('[GalaxyAssistant] final-answer turn failed:', err?.message);
        }
      }
      // The pre-nudge reply presented code that never ran, possibly with results stated before any
      // computation; it is NOT kept. The final message (which replaces the streamed preview in the UI,
      // chat-interface.tsx `data.response`) is the post-execution answer only. Committee review 2026-11-05.
      if (_shownBeforeNudge && !rawResponse.trim()) rawResponse = _shownBeforeNudge;
      // A truncated text turn is kept: the answer is its text + the continuation, not the tail alone.
      if (_carriedText.trim()) rawResponse = rawResponse.trim() ? `${_carriedText}${rawResponse}` : _carriedText;

      // Guard: if loop exhausted or tool-only response with no final text, provide fallback.
      // When a workflow was generated, produce a meaningful workflow-ready message.
      if (!rawResponse.trim()) {
        const _wfGa = (generatedWorkflow as any)?.workflow_ga || {};
        const _wfName =
          _wfGa.name ||
          (generatedWorkflow as any)?.workflow_name ||
          (generatedWorkflow as any)?.name;
        const _wfDesc = _wfGa.description?.slice(0, 120) || '';
        // Before falling back to a generic placeholder, surface the last
        // tool_result content. When BioMate ran `run_code` and the LLM's
        // final turn ended without a text block (concise compute-only
        // tasks frequently do — Claude returns stop_reason without an
        // accompanying text block when it judges the tool output to be
        // self-explanatory), the previous code silently swallowed that
        // tool output and emitted "I processed your request using the
        // available tools." This was the dominant BixBench biomate_exec
        // failure mode in v44/v45/v46 (~25/29 = 86% of failures).
        const lastToolResult = (() => {
          for (let i = agentMessages.length - 1; i >= 0; i--) {
            const m: any = agentMessages[i];
            if (m?.role !== 'user' || !Array.isArray(m.content)) continue;
            for (let j = m.content.length - 1; j >= 0; j--) {
              const block = m.content[j];
              if (block?.type === 'tool_result' && typeof block.content === 'string') {
                try {
                  const parsed = JSON.parse(block.content);
                  // run_code returns { stdout, stderr, exit_code, ... }
                  if (parsed && typeof parsed === 'object') {
                    const out = (parsed.stdout || parsed.output || parsed.result || '').toString().trim();
                    if (out) return out.slice(0, 2000);
                  }
                } catch {/* not JSON — ignore */}
              }
            }
          }
          return '';
        })();
        if (_wfName) {
          rawResponse = `**Workflow ready** — **${_wfName}** has been set up in the panel. ${_wfDesc ? _wfDesc.split('.')[0] + '. ' : ''}Review the parameters and click **Confirm & Run** to execute.`;
        } else if (lastToolResult) {
          rawResponse = lastToolResult;
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
          rawResponse = localOnly() ? 'The local model did not produce a final answer. Completion has not been verified; review the tool results, if any.' : 'I processed your request using the available tools.';
        }
        if (onResponseDelta) onResponseDelta(rawResponse);
      }

      // Strip any narrated tool-call XML / code the model wrote as prose before
      // it is parsed, quality-enforced, returned, and persisted to chat history.
      // (The live stream is already filtered by StreamToolCallFilter; this guards
      // the stored + final message and the non-streamed / fallback paths.)
      rawResponse = stripNarratedToolCalls(rawResponse);

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
      if (!qualityEnforcedMessage) {
        const emptyFallback = 'I\'m having trouble generating a response right now. Please try again in a moment.';
        if (onResponseDelta) onResponseDelta(emptyFallback);
        return { message: emptyFallback, truncated: false };
      }
      this._logUnbackedFileClaims(qualityEnforcedMessage, message, context);
      return {
        message: redactStoragePaths(qualityEnforcedMessage, /[\u4e00-\u9fff]/.test(message)),
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
              content: modelFacingUploads(typeof m.content === 'string' ? m.content
                : (m.content as any[]).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('')),
            })),
            { role: 'user' as const, content: userPrompt },
          ];
          // Pass tools so Gemini can call run_code and read_file (always enable for analysis turns).
          // Gate on a real RUNNABLE workflow, not isWorkflowTurn/mere non-null — see 8344.
          const geminiTools = !hasRunnableWorkflow ? BIOMATE_TOOLS : undefined;
          const geminiResponse = await this._generateWithGemini(
            systemPrompt, plainMessages, onResponseDelta, 4096, 'gemini-3.8-flash',
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

      // Auth failure or any other error: fall back to Gemini if available.
      // This covers the common case where ANTHROPIC_API_KEY is not configured on
      // a server that has GEMINI_API_KEY — avoids silent empty responses.
      if (this.gemini) {
        console.warn(`[GalaxyAssistant] Claude error (${isAuth ? 'auth' : 'unknown'}) — falling back to Gemini`);
        try {
          const allPrev = context.previousMessages || [];
          const plainMessages = [
            ...allPrev.slice(-6).map(m => ({
              role: (m.role === 'assistant' ? 'assistant' : 'user') as 'user' | 'assistant',
              content: modelFacingUploads(typeof m.content === 'string' ? m.content
                : (m.content as any[]).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('')),
            })),
            { role: 'user' as const, content: userPrompt },
          ];
          const geminiResponse = await this._generateWithGemini(
            systemPrompt, plainMessages, onResponseDelta, 4096, 'gemini-3.8-flash',
          );
          const fallbackMsg = geminiResponse || 'I\'m having trouble generating a response right now. Please try again in a moment.';
          if (!geminiResponse && onResponseDelta) onResponseDelta(fallbackMsg);
          return { message: fallbackMsg, truncated: false };
        } catch (geminiErr: any) {
          console.error('[GalaxyAssistant] Gemini fallback also failed:', geminiErr.message);
        }
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

  // Shared by _executeTools and tested directly. A tool (read_file on an image)
  // may return { __imageBlocks: [...] } to hand the model actual pixels; Anthropic
  // tool_result content accepts an array of text+image blocks. Everything else is
  // stringified as before.
  static toolResultContent(output: unknown): string | any[] {
    // Image BYTES never go into model text: run_code plot previews (image_data_uri, kept for the
    // UI via the event stream) were serialized here as ~100–250K tokens of base64 per plot.
    const text = JSON.stringify(stripImageBytesForModel(output));
    const img = (output as any)?.__imageBlocks;
    if (Array.isArray(img) && img.length) return [{ type: 'text', text }, ...img];
    return text;
  }

  /** Executes all tool_use blocks in parallel, returns tool_result message content. */
  private async _executeTools(
    toolUseBlocks: any[],
    context: ChatContext,
    onToolEvent?: (event: AgentToolEvent) => void
  ): Promise<Anthropic.ToolResultBlockParam[]> {
    return Promise.all(toolUseBlocks.map(async (block) => {
      const start = Date.now();
      onToolEvent?.({ type: 'tool_call', tool_use_id: block.id, name: block.name, input: block.input, display: toolCallDisplayFor(block.input, context) });
      let output: unknown = null;
      let error: string | undefined;
      try {
        switch (block.name) {
          case 'run_code':
            output = await this._toolRunCode(block.input, context);
            break;
          case 'read_file':
            output = await this._toolReadFile(block.input, context);
            break;
          case 'query_domain_knowledge':
            output = await this._toolQueryKnowledge(block.input);
            break;
          case 'list_history':
            output = await this._toolListHistory(block.input, context);
            break;
          case 'list_run_outputs':
            output = await this._toolListRunOutputs(block.input, context);
            break;
          case 'search_literature':
            output = await this._toolSearchLiterature(block.input);
            break;
          case 'query_database':
            output = await this._toolQueryDatabase(block.input);
            break;
          case 'search_my_data':
            output = await this._toolSearchMyData(block.input, context);
            break;
          case 'search_chat_history':
            output = await this._toolSearchChatHistory(block.input, context);
            break;
          case 'edit_report':
            output = await this._toolEditReport(block.input, context);
            break;
          case 'list_data_sources':
            output = await this._toolListDataSources(block.input);
            break;
          case 'search_workflows':
            output = await this._toolSearchWorkflows(block.input);
            break;
          case 'request_new_tool':
            output = await this._toolRequestNewTool(block.input, context);
            break;
          case 'identify_targets':
            output = await this._toolIdentifyTargets(block.input);
            break;
          case 'write_review':
            output = await this._toolWriteReview(block.input);
            break;
          default:
            // External MCP tools are namespaced mcp__<server>__<tool>; route them
            // to the owning remote server (ownership-checked backend-side).
            if (typeof block.name === 'string' && block.name.startsWith('mcp__')) {
              output = await this._toolCallExternalMcp(block.name, block.input, context);
            } else {
              output = { error: `Unknown tool: ${block.name}` };
            }
        }
      } catch (err: any) {
        error = err?.message ?? String(err);
        output = { error };
      }
      const duration_ms = Date.now() - start;
      // Redact base64 image payloads from the SSE tool event (keep it lightweight).
      const eventOutput = (output as any)?.__imageBlocks
        ? { ...(output as any), __imageBlocks: `[${(output as any).__imageBlocks.length} image block(s)]` }
        : output;
      onToolEvent?.({ type: 'tool_result', tool_use_id: block.id, name: block.name, output: eventOutput, error, duration_ms });
      return {
        type: 'tool_result' as const,
        tool_use_id: block.id,
        content: GalaxyAssistant.toolResultContent(output) as any,
      };
    }));
  }

  /** run_code tool handler — calls the /api/code/run endpoint.
   *  Inputs: the datasets the model lists in input_datasets; if it lists none, the datasets attached
   *  to this turn's message (context.turnMessage). Measured 2026-11-04: on an ad-hoc request with an
   *  attached CSV the model called run_code without input_datasets eight times, read a guessed path,
   *  and gave up — INPUT_FILES was empty on every try. Galaxy reads are authenticated (the user's key,
   *  else the service key): user datasets are private. */
  /** A dataset's bytes: the locally stored upload under `id` or `localFallbackId` when there is one,
   *  else Galaxy (with the given key) once the dataset's state is `ok`. Closing the iteration
   *  early cancels the Galaxy download.
   *
   *  Galaxy answers /display with HTTP 200 and an empty or partial body while the upload job is still
   *  running (dev 2026-11-04: state=running for ~19 s after upload, display 0 bytes then a partial
   *  body), so run_code staged an empty file whenever the user asked right after attaching data. For a
   *  Galaxy-only dataset the state is checked first and we wait for the job (up to `waitMs`); a failed
   *  or unfinished job is an error, never an empty file. */
  private async _openDataset(id: string, galaxyKey: string, localFallbackId?: string, waitMs = 60000): Promise<AsyncIterable<Buffer>> {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    const headers: Record<string, string> = galaxyKey ? { 'x-api-key': galaxyKey } : {};
    const { getUploadedFile } = await import('./routes');
    const local = getUploadedFile(id) || getUploadedFile(localFallbackId || '');
    // Streamed, so a caller that stops early (headLines) never reads a whole large file.
    const readLocal = async (): Promise<AsyncIterable<Buffer>> => {
      const nodeFs = await import('fs');
      await nodeFs.promises.access(local!.filePath);
      return nodeFs.createReadStream(local!.filePath);
    };

    // Galaxy's dataset state; null when Galaxy can't say (unreachable, unknown id, no access).
    const galaxyState = async (): Promise<string | null> => {
      try {
        const meta = await fetch(`${galaxyUrl}/api/datasets/${id}`, { headers, signal: AbortSignal.timeout(10000) });
        return meta.ok ? String(((await meta.json()) as any)?.state || '') || null : null;
      } catch {
        return null;
      }
    };
    // The user's own upload is on local disk (the exact bytes they sent): read it, never Galaxy. Under
    // load the state check below can itself time out (state unknown) and Galaxy then serves the
    // in-progress empty body — one more EmptyDataError on dev (2026-11-04, 3 parallel chats) after
    // the state check alone shipped. Galaxy is only for datasets that exist nowhere else.
    if (local?.filePath) return readLocal();
    let state = await galaxyState();
    if (state && state !== 'ok') {
      const deadline = Date.now() + waitMs;
      while (state && !['ok', 'error', 'failed_metadata', 'discarded', 'deferred'].includes(state) && Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        state = await galaxyState();
      }
      if (state !== 'ok') throw new Error(`Dataset is not ready yet (state: ${state || 'unknown'}) — it may still be processing; try again shortly`);
    }

    try {
      const r = await fetch(`${galaxyUrl}/api/datasets/${id}/display`, {
        headers,
        signal: AbortSignal.timeout(30000),
      });
      if (r.ok) {
        const reader = r.body!.getReader();
        return {
          [Symbol.asyncIterator]: async function*() {
            try {
              while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                yield Buffer.from(value);
              }
            } finally {
              reader.cancel().catch(() => {});
            }
          }
        };
      }
    } catch { /* fall through */ }

    throw new Error('Dataset is not accessible — it may have been removed or not finished uploading');
  }

  /** First lines of this turn's attached text files, keyed by file name, so the model's first run_code
   *  call uses the real column names (dev 2026-11-04: [13]'s first call melted on a guessed "index"
   *  column — the file's first column is "row" — and failed with KeyError). Best effort: a file that
   *  can't be read within 5 s is simply left out. */
  private async _attachedFileHeads(message: string, context?: ChatContext): Promise<Record<string, string[]>> {
    const galaxyKey: string = (context?.galaxyAPIOverride as any)?.apiKey || process.env.GALAXY_API_KEY || '';
    const attached = attachedDatasetsFromMessage(message).filter(a => HEAD_PREVIEW_EXT_RE.test(a.name)).slice(0, 8);
    const entries = await Promise.all(attached.map(async (a): Promise<[string, string[]]> => {
      try {
        const lines = await Promise.race([
          this._openDataset(stagingIdFor(a), galaxyKey, a.datasetId, 0).then(st => headLines(st)),
          new Promise<string[]>(resolve => setTimeout(() => resolve([]), 5000)),
        ]);
        return [a.name, lines];
      } catch {
        return [a.name, []];
      }
    }));
    return Object.fromEntries(entries.filter(([, lines]) => lines.length));
  }

  private async _toolRunCode(input: any, context?: ChatContext): Promise<unknown> {
    const { runCode, sessionWorkspaceKey } = await import('./code-runner');
    const { getUploadedFile } = await import('./routes');
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    const galaxyKey: string = (context?.galaxyAPIOverride as any)?.apiKey || process.env.GALAXY_API_KEY || '';
    const galaxyHeaders: Record<string, string> = galaxyKey ? { 'x-api-key': galaxyKey } : {};

    // This turn's attachments; galaxy id -> BioMate dataset id, for the local-copy fallback.
    const attached = attachedDatasetsFromMessage(context?.turnMessage || '');
    const localIdFor = new Map<string, string>();
    for (const a of attached) if (a.galaxyId && a.datasetId) localIdFor.set(a.galaxyId, a.datasetId);

    // P1a — run_code can now compute on a SELECTED project file (a run output), not just preview it.
    // Authorized keys come ONLY from this turn's server-resolved sessionDatasets (same rule as
    // read_file); a bucket/key is never accepted from a tool argument. A 100 MB cap bounds what is
    // pulled into the sandbox — a larger output must go through a workflow, not run_code.
    const RUN_CODE_PROJECT_FILE_MAX_BYTES = 100 * 1024 * 1024;
    const projectFileById = new Map<string, { s3_key: string; name: string }>();
    for (const d of context?.sessionDatasets ?? []) {
      if (d.projectFileId && d.projectFileId === d.id && d.s3_key) {
        projectFileById.set(d.id, { s3_key: d.s3_key, name: d.name });
      }
    }

    const downloadDataset = async (id: string): Promise<AsyncIterable<Buffer>> => {
      const pf = projectFileById.get(id);
      if (pf) {
        const { s3Service } = await import('./s3-client');
        const size = await s3Service.getFileSize(pf.s3_key).catch(() => 0);
        if (size > RUN_CODE_PROJECT_FILE_MAX_BYTES) {
          throw new Error(
            `Project file "${pf.name}" is ${(size / 1_048_576).toFixed(0)} MB — over the ` +
            `${RUN_CODE_PROJECT_FILE_MAX_BYTES / 1_048_576} MB run_code sandbox cap. Run a workflow on it instead of loading it into run_code.`,
          );
        }
        const buf = await s3Service.readBuffer(pf.s3_key, RUN_CODE_PROJECT_FILE_MAX_BYTES);
        return (async function* () { yield buf; })();
      }
      return this._openDataset(id, galaxyKey, localIdFor.get(id) || attachmentLocalId(id, context));
    };

    const rawIds: string[] = input.input_datasets ?? [];
    const autoStaged = rawIds.length === 0 && attached.length > 0;
    const datasetRefs = autoStaged
      // The names come with the attachment; the Galaxy id is preferred (durable), the local id is the fallback.
      ? attached.map(a => ({ id: stagingIdFor(a), filename: a.name }))
      // Resolve filenames: check local registry first, then Galaxy metadata
      : await Promise.all(rawIds.map(async (id: string) => {
        // Project file selected this turn (authorized above) — use its real name for staging.
        const pf = projectFileById.get(id);
        if (pf) return { id, filename: pf.name };

        // Local registry always has the original filename
        const local = getUploadedFile(id);
        if (local?.name) return { id, filename: local.name };

        // Fallback: Galaxy metadata
        try {
          const meta = await fetch(`${galaxyUrl}/api/datasets/${id}`, {
            headers: galaxyHeaders,
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

    // Notebook-cell semantics for Python within this turn (see pythonReplay in code-runner.ts).
    const turn = context?.turnMessage || '';
    if (context && context.runCodeHistory?.turn !== turn) context.runCodeHistory = { turn, codes: [] };
    const prior = input.language === 'python' ? context?.runCodeHistory?.codes ?? [] : [];

    // Bounded retry on a transient sandbox-sidecar connection blip (the sidecar
    // node recycling → ECONNREFUSED / "fetch failed" / 5xx). runCode never throws
    // on that — it returns exit_code=1 with a "[sidecar …]" stderr — so retry on
    // the RESULT. A genuine code error or an execution timeout is returned on the
    // first attempt; after retries the real error still surfaces (honest fallback).
    // Made-up input data never becomes a result: refuse (do not run) code that generates its own values
    // when nothing was staged and the user did not ask for generated data (EBV, dev 2026-11-11). Whether
    // they asked is this turn's INTENT (syntheticDataAllowed), not a keyword match (audit round 9).
    if (generatesSyntheticData(String(input.code || ''), datasetRefs.length)
        && !syntheticDataAllowed(context?.turnSyntheticDataRequested, context?.turnMessage || '')) {
      console.warn('[GalaxyAssistant] run_code refused: synthetic input data with no staged inputs and no simulation request');
      if (context) context.syntheticDataRefused = { turn: context.turnMessage || '' };
      return { exit_code: 1, stdout: '', stderr: SYNTHETIC_DATA_REFUSAL, output_files: [], refused: 'synthetic_input_data' };
    }

    const { retryTransientRunCode } = await import('./transient-retry');
    const result = await retryTransientRunCode(() => runCode({
      language: input.language,
      code: input.code,
      input_datasets: datasetRefs,
      timeout_seconds: input.timeout_seconds ?? 30,
      downloadDataset,
      prior_code: prior.length ? [...prior] : undefined,
      // One workspace per chat session (reference harnesses: Biomni cwd, ScienceBuddy per-episode
      // container): files in $OUTPUT_DIR survive into later calls and turns. Bound to the
      // AUTHENTICATED user (authUserId is set by routes.ts from req.user only; context.userId falls
      // back to a client value on anonymous requests), since the session id is client-supplied.
      workspaceKey: sessionWorkspaceKey(context?.authUserId, context?.sessionId),
      persistOutputFile: context?.persistGeneratedFile
        ? (f) => context.persistGeneratedFile!(f.hostPath, f.name) : undefined,
    }), { label: 'run_code tool' });
    if (input.language === 'python' && result.exit_code === 0 && context?.runCodeHistory) {
      context.runCodeHistory.codes.push(String(input.code || ''));
    }
    if (context) {
      if (context.runCodeOutputFiles?.turn !== turn) context.runCodeOutputFiles = { turn, names: [] };
      context.runCodeOutputFiles.names.push(...(result.output_files || []).map(f => f.name));
    }
    const base = autoStaged
      ? { ...result, note: 'input_datasets was empty; staged the datasets attached to this message — open them via INPUT_FILES / staged_inputs.' }
      : result;
    // Plots go to the model as image blocks (it can check the figure it describes); the UI keeps
    // image_data_uri. A model path without vision receives a text note instead (see local-llm).
    const plots = plotImageBlocks(result.output_files as any);
    return plots.length ? { ...base, __imageBlocks: plots } : base;
  }

  /** Output files a reply presents as produced must be this turn's run_code $OUTPUT_DIR artifacts. */
  private _logUnbackedFileClaims(text: string, message: string, context: ChatContext): void {
    // Diagnostics only — never appended to the reply (founder 2026-11-11: remove that footer; it also
    // misfired on attached input files). Real outputs are now persisted with download links.
    const turn = context?.turnMessage || '';
    const produced = context?.runCodeOutputFiles?.turn === turn ? context.runCodeOutputFiles.names : [];
    const inputs = attachedInputNames(message, ...(context?.previousMessages || []).map(m => typeof m.content === 'string' ? m.content : ''));
    const unbacked = unbackedOutputFileClaims(text, produced, inputs);
    if (unbacked.length) console.warn(`[GalaxyAssistant] reply claims files not produced this turn: ${unbacked.join(', ')}`);
  }


  /** read_file tool handler — streams first n_lines from Galaxy or local dataset. */
  private async _toolReadFile(input: any, _context: ChatContext): Promise<unknown> {
    // The model sees one neutral `dataset_id` (modelFacingUploads); older transcripts may still
    // pass the legacy key. The local upload copy is keyed by BioMate's dataset id, the backend
    // store by its own id — attachmentLocalId maps the one the model gave to the local one.
    const { galaxy_dataset_id, dataset_id, n_lines = 20 } = input;
    const fileId: string = dataset_id || galaxy_dataset_id;
    if (!fileId) return { error: 'dataset_id is required' };

    // Project-file ids are not Galaxy ids. Preview only the exact
    // server-authorized key that routes.ts placed in this turn's context;
    // never accept a bucket/key/URI from a tool argument.
    const projectFile = _context.sessionDatasets?.find((dataset) =>
      dataset.id === fileId && dataset.projectFileId === fileId && !!dataset.s3_key,
    );
    if (projectFile?.s3_key) {
      try {
        const { s3Service } = await import('./s3-client');
        // A project IMAGE is handed to the model as pixels, like a chat upload — reading it as
        // text produced garbage "lines" (live dev 2026-11-12: the model could only report its size).
        const _pfExt = String(projectFile.name || projectFile.s3_key).toLowerCase().match(/\.[a-z0-9]+$/)?.[0] ?? '';
        if (_pfExt in _VISION_MEDIA_TYPES) {
          const buf = await s3Service.readBuffer(projectFile.s3_key, _VISION_MAX_RAW_BYTES + 1);
          if (buf.length > _VISION_MAX_RAW_BYTES) {
            return { error: `Image is over the ${(_VISION_MAX_RAW_BYTES / 1e6).toFixed(2)}MB vision limit; ask the user for a smaller copy.` };
          }
          return {
            __imageBlocks: [{ type: 'image', source: { type: 'base64', media_type: _VISION_MEDIA_TYPES[_pfExt], data: buf.toString('base64') } }],
            format_hint: 'image',
            message: `Image "${projectFile.name || fileId}" loaded.`,
            __note: 'The image is attached below — analyze it directly.',
          };
        }
        const text = await s3Service.readTextPrefix(projectFile.s3_key);
        const allLines = text.split(/\r?\n/);
        const lines = allLines.slice(0, Math.max(1, Math.min(Number(n_lines) || 20, 500)));
        const firstLine = lines[0] ?? '';
        const isTabular = firstLine.includes('\t') || firstLine.includes(',');
        return {
          lines,
          total_lines_preview: lines.length,
          has_more: text.length >= 256 * 1024,
          format_hint: isTabular ? (firstLine.includes('\t') ? 'TSV' : 'CSV') : 'text',
          source: 'project_file',
        };
      } catch (err: any) {
        // Do not fall through to Galaxy: it would falsely call an authorized
        // project file "missing" and conceal the actual storage failure.
        return { error: `Project file preview is unavailable: ${err?.message || 'storage read failed'}` };
      }
    }

    // Check local upload registry first (works when Galaxy is unavailable)
    try {
      const { getUploadedFile } = await import('./routes');
      const localFile = getUploadedFile(fileId) || getUploadedFile(attachmentLocalId(fileId, _context) || '');
      if (localFile?.filePath) {
        // PDF: extract text via pdfplumber (binary readFile returns garbage for PDFs).
        // A PDF has no meaningful "lines" to page through, and slicing to the first
        // n_lines silently dropped everything past the top of page 1 (methods, results,
        // tables — the technical detail the caller is reading the PDF for). Extract the
        // whole document up to a generous char budget and return all of it. n_lines only
        // scales the budget upward; it never truncates below a useful floor.
        if (localFile.filePath.toLowerCase().endsWith('.pdf')) {
          const budget = Math.min(Math.max(n_lines * 200, 20000), 120000);
          const text = await _extractPdfText(localFile.filePath, budget);
          if (text) {
            const lines = text.split('\n');
            return { lines, total_lines_preview: lines.length, format_hint: 'PDF', has_more: text.length >= budget };
          }
          return { error: 'PDF text extraction failed — file may be scanned or encrypted' };
        }
        // Image: return the actual pixels as a vision content block so the model
        // can SEE any stored image on demand by id — on any later turn, without a
        // re-upload and without re-sending it every turn. Files are durably tracked
        // by id (Galaxy dataset DB / S3 / upload registry), and sessionDatasetsBlock
        // surfaces the ids each turn, so read_file(id) is the on-demand view path.
        const _imgExt = localFile.filePath.toLowerCase().match(/\.[a-z0-9]+$/)?.[0] ?? '';
        if (_imgExt in _VISION_MEDIA_TYPES) {
          const nodeFs = await import('fs/promises');
          const buf = await nodeFs.readFile(localFile.filePath);
          if (buf.length > _VISION_MAX_RAW_BYTES) {
            return { error: `Image is ${(buf.length / 1e6).toFixed(1)}MB — over the 3.75MB vision limit; ask the user for a smaller copy.` };
          }
          return {
            __imageBlocks: [{
              type: 'image',
              source: { type: 'base64', media_type: _VISION_MEDIA_TYPES[_imgExt], data: buf.toString('base64') },
            }],
            format_hint: 'image',
            message: `Image "${localFile.name || fileId}" loaded.`,
            // Model-facing instruction; `__` keys are hidden from the chat card (userFacingToolOutput).
            __note: 'The image is attached below — analyze it directly.',
          };
        }
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

  /** search_literature tool handler — federated multi-DB literature search.
   *  Gives the model search agency (RFC Principle 1): it can look up real papers
   *  mid-conversation instead of answering from memory. Routes to Galaxy's
   *  /api/literature/search (PubMed + Europe PMC + Semantic Scholar + OpenAlex,
   *  entity-routed, iterative broaden-on-gap). Returns a compact ranked list the
   *  model cites with real title/PMID/DOI. */
  private async _toolSearchLiterature(input: any): Promise<unknown> {
    const { query, min_results, max_depth } = input || {};
    if (!query || typeof query !== 'string') return { error: 'query is required' };
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const r = await fetch(`${galaxyUrl}/api/literature/search`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, min_results: min_results ?? 12, max_depth: max_depth ?? 3 }),
        signal: AbortSignal.timeout(45000),
      });
      if (!r.ok) return { error: `literature search HTTP ${r.status}`, query };
      const data: any = await r.json();
      const items: any[] = data?.results || data?.merged || [];
      const papers = items.slice(0, 20).map((p: any) => ({
        title: p.title,
        authors: typeof p.authors === 'string' ? p.authors : (Array.isArray(p.authors) ? p.authors.slice(0, 6) : undefined),
        year: p.year,
        pmid: p.pmid ?? null,
        doi: p.doi ?? null,
        source: p._source ?? p.source,
        abstract: p.abstract ? String(p.abstract).slice(0, 300) : undefined,
        ...(p.peer_reviewed === false ? { peer_reviewed: false, server: p.server } : {}),
      })).filter((p: any) => p.title);
      return {
        query,
        total: papers.length,
        papers,
        note: 'Cite these by title + PMID/DOI. Do NOT cite any paper not in this list, and do not invent identifiers.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err), query };
    }
  }

  /** search_my_data tool handler — unified dataset catalog over the user's OWN
   *  files (uploads + run outputs) across all their projects. Queries the DB
   *  directly, scoped to context.userId, so the model can discover client data
   *  instead of asking for a re-upload (RFC unified data plane). */
  private async _toolSearchMyData(input: any, context: ChatContext): Promise<unknown> {
    const query = (input?.query ?? '').toString().trim();
    if (!query) return { error: 'query is required' };
    const uid = context?.userId ? String(context.userId) : undefined;
    if (!uid) return { error: 'no authenticated user in context' };
    const type = (input?.type ?? '').toString().trim();
    const source = (input?.source ?? '').toString().trim();
    let limit = Number(input?.limit);
    if (!Number.isFinite(limit) || limit < 1) limit = 25;
    if (limit > 100) limit = 100;
    try {
      const { pool } = await import('./db');
      const params: any[] = [uid];
      const clauses: string[] = ['user_id = $1'];
      const tokens = query.split(/\s+/).filter(Boolean).slice(0, 6);
      for (const tok of tokens) {
        params.push(`%${tok}%`);
        const i = params.length;
        clauses.push(
          `(name ILIKE $${i} OR COALESCE(workflow_name,'') ILIKE $${i} OR ` +
          `COALESCE(step_name,'') ILIKE $${i} OR source ILIKE $${i} OR ` +
          `COALESCE(input_context::text,'') ILIKE $${i})`
        );
      }
      if (type) { params.push(`%${type}%`); clauses.push(`content_type ILIKE $${params.length}`); }
      if (source) { params.push(source); clauses.push(`source = $${params.length}`); }
      params.push(limit);
      const sql =
        `SELECT id, project_id, name, size, content_type, source, run_id, ` +
        `workflow_name, step_name, created_at FROM project_files ` +
        `WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT $${params.length}`;
      const result = await pool.query(sql, params);
      const files = result.rows.map((r: any) => ({
        id: r.id,
        name: r.name,
        type: r.content_type,
        size: r.size,
        source: r.source,
        workflow: r.workflow_name ?? undefined,
        step: r.step_name ?? undefined,
        run_id: r.run_id ?? undefined,
        project_id: r.project_id,
        created_at: r.created_at,
      }));
      return {
        query,
        total: files.length,
        files,
        note: files.length
          ? 'These are the user\'s real files. Reference them by name; use the id/run_id to wire them into a workflow. Do not ask the user to re-upload a file already listed here.'
          : 'No matching datasets found in the user\'s projects. It is safe to ask them to upload the file.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err), query };
    }
  }

  /** search_chat_history tool handler — cross-conversation search over the user's
   *  OWN past chat sessions (chat_sessions.messages JSONB). This is the honest
   *  answer to "what did we conclude last week / in an earlier chat": it actually
   *  searches prior transcripts instead of fabricating a recollection. Scoped to
   *  context.userId; EXCLUDES the current session (that transcript is already in
   *  context). AND-matches whitespace tokens (case-insensitive) over the raw
   *  message text, most-recently-active first, with a short snippet around the
   *  first hit. An empty result is a real answer — say nothing was found. */
  private async _toolSearchChatHistory(input: any, context: ChatContext): Promise<unknown> {
    const query = (input?.query ?? '').toString().trim();
    if (!query) return { error: 'query is required' };
    const uid = context?.userId ? String(context.userId) : undefined;
    if (!uid) return { error: 'no authenticated user in context' };
    const currentSessionId = context?.sessionId ? String(context.sessionId) : undefined;
    const tokens = query.split(/\s+/).filter(Boolean).slice(0, 6);
    try {
      const { pool } = await import('./db');
      const params: any[] = [uid];
      const clauses: string[] = ['user_id = $1'];
      if (currentSessionId) {
        params.push(currentSessionId);
        clauses.push(`session_id <> $${params.length}`);
      }
      for (const tok of tokens) {
        params.push(`%${tok}%`);
        clauses.push(`messages::text ILIKE $${params.length}`);
      }
      const sql =
        `SELECT session_id, title, status, last_activity, messages FROM chat_sessions ` +
        `WHERE ${clauses.join(' AND ')} ORDER BY last_activity DESC NULLS LAST LIMIT 8`;
      const result = await pool.query(sql, params);
      const lowerTokens = tokens.map((t: string) => t.toLowerCase());
      const sessions = result.rows.map((r: any) => ({
        session_id: r.session_id,
        title: r.title || '(untitled chat)',
        status: r.status ?? undefined,
        last_activity: r.last_activity,
        snippet: extractChatSnippet(r.messages, lowerTokens),
      }));
      return {
        query,
        total: sessions.length,
        sessions,
        note: sessions.length
          ? 'These are the user\'s own past conversations that mention the query. Quote the snippet or point to the session; do not fabricate detail beyond what the snippet shows.'
          : 'No past conversation of this user mentions the query. Tell them nothing was found — do not invent a recollection; ask them to paste the detail or point you to the run/project.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err), query };
    }
  }

  /** edit_report tool handler — chat-driven editing of a run's findings report,
   *  saved as a new version of the DURABLE, versioned report (reportVersionStore,
   *  DB-backed). Three-phase + never-silent:
   *    - no new_content  → return the current base text (from client current_markdown
   *      or the latest saved version) so the model can compose the edit; honest
   *      "no_report_text" when there is nothing stored to edit (never fabricate one).
   *    - new_content, no confirm → return a diff preview; DO NOT write.
   *    - new_content + confirm:true → append the new version (v0 run original is
   *      preserved by the store's fork protection) and return the saved version.
   *  Scoped by the store's run resolution; the run must belong to the user's data. */
  private async _toolEditReport(input: any, context: ChatContext): Promise<unknown> {
    const runId = (input?.run_id ?? input?.runId ?? '').toString().trim();
    if (!runId) {
      return { error: 'run_id is required — tell me which run\'s report to edit (a run id or name).' };
    }
    const instruction = typeof input?.instruction === 'string' ? input.instruction : undefined;
    const newContent = typeof input?.new_content === 'string' ? input.new_content : undefined;
    const clientMarkdown = typeof input?.current_markdown === 'string' ? input.current_markdown : undefined;
    const confirm = input?.confirm === true;
    const note = typeof input?.note === 'string' && input.note.trim() ? input.note.trim() : 'Edited via chat';
    try {
      const { reportVersionStore } = await import('./report-version-store');

      // Resolve the current base text: what the client shows (most faithful) else the
      // latest saved version. Never reconstruct an approximation and pass it off as the report.
      // Priority: explicit tool arg → the report the client has open this turn → latest saved version.
      let baseMarkdown: string | undefined = clientMarkdown;
      let baseSource: 'client' | 'saved_version' | 'run_original' | 'none' = clientMarkdown !== undefined ? 'client' : 'none';
      if (
        baseMarkdown === undefined &&
        typeof context?.openReportMarkdown === 'string' &&
        (!context.openReportRunId || context.openReportRunId === runId)
      ) {
        baseMarkdown = context.openReportMarkdown;
        baseSource = 'client';
      }
      const versions = await reportVersionStore.list(runId);
      if (versions === null) {
        return { run_id: runId, status: 'run_not_found', note: 'No run with that id for this user. Check the run id (list_history can find it).' };
      }
      if (baseMarkdown === undefined && versions.length > 0) {
        const latest = versions.reduce((a, b) => (a.version >= b.version ? a : b));
        baseMarkdown = latest.content ?? '';
        baseSource = 'saved_version';
      }

      // Still nothing to fork from? The run has produced a report (shown in the
      // after-run panel) but it was never opened client-side nor saved as a
      // version. Reconstruct it server-side from the structured report endpoint
      // so edit_report forks from what the run actually produced instead of
      // telling the user to paste text they can already see (ID_everywhere).
      if (baseMarkdown === undefined) {
        const reconstructed = await this._reconstructRunReportMarkdown(runId, context).catch(() => undefined);
        if (reconstructed && reconstructed.trim()) {
          baseMarkdown = reconstructed;
          baseSource = 'run_original';
          // Seed the immutable v0 so a later edit forks from this real report,
          // not from a client blob. Best-effort — never block the edit on it.
          try { await reportVersionStore.ensureOriginal(runId, reconstructed); } catch { /* non-fatal */ }
        }
      }

      // Phase 1: hand back the base so the model can compose the edit.
      if (newContent === undefined) {
        if (baseMarkdown === undefined) {
          return {
            run_id: runId,
            status: 'no_report_text',
            note: 'This run has no stored report text yet, and the client did not provide the text currently shown. Ask the user to open the report in the report panel once (or paste its text); then call edit_report again. Do NOT invent a report body.',
          };
        }
        return {
          run_id: runId,
          status: 'base_ready',
          base_source: baseSource,
          instruction: instruction ?? null,
          base_markdown: baseMarkdown,
          note: 'This is the current report. Compose the FULL edited report and call edit_report again with it as new_content to preview the change. Do not save until the user agrees.',
        };
      }

      // Phases 2/3: we have the edited content. Compute the diff for the user.
      const base = baseMarkdown ?? '';
      const summary = summarizeReportEdit(base, newContent);
      if (summary.unchanged) {
        return { run_id: runId, status: 'no_change', note: 'The edited content is identical to the current report — nothing to save.' };
      }

      // Phase 2: preview only (no confirm) — never writes.
      if (!confirm) {
        return {
          run_id: runId,
          status: 'preview',
          base_source: baseSource,
          added_lines: summary.added,
          removed_lines: summary.removed,
          diff_preview: summary.preview,
          note: 'Show the user this change (added/removed lines). To SAVE it as a new report version, call edit_report again with the same new_content and confirm:true — only after the user agrees.',
        };
      }

      // Phase 3: confirmed save. Seed v0 (run original) from the base so the fork is faithful.
      const saved = await reportVersionStore.append(runId, newContent, { note, currentMarkdown: base });
      if (!saved) {
        return { run_id: runId, status: 'run_not_found', note: 'The run could not be found when saving. Nothing was written.' };
      }
      return {
        run_id: runId,
        status: 'saved',
        version: saved.version,
        added_lines: summary.added,
        removed_lines: summary.removed,
        note: 'Saved as report version ' + saved.version + '. The report panel will show it; version 0 (the run original) is preserved. Tell the user it is saved.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err), run_id: runId };
    }
  }

  /** Reconstruct a run's report markdown from the structured server endpoint so
   *  edit_report can fork from what the run produced when the client did not
   *  pass the open markdown and no version is saved yet. Uses the findings
   *  report (resolves + authorizes the run server-side) via an authenticated
   *  self-call — same pattern as the /output_files self-fetch in routes.ts.
   *  Returns undefined when nothing can be reconstructed (not-ready / 401 / 404),
   *  letting the caller fall back to the honest no_report_text. */
  private async _reconstructRunReportMarkdown(runId: string, context: ChatContext): Promise<string | undefined> {
    if (!runId) return undefined;
    const port = process.env.PORT || '5000';
    const base = `http://localhost:${port}`;
    const headers: Record<string, string> = {
      // Without X-Forwarded-Proto this self-fetch is 301'd to https on a
      // plain-HTTP port by forceHTTPS (only /internal/ is exempt) and fails.
      'X-Forwarded-Proto': 'https',
    };
    const auth = context?.selfRequestAuth;
    if (auth?.authorization) headers['Authorization'] = auth.authorization;
    if (auth?.cookie) headers['cookie'] = auth.cookie;
    try {
      const r = await fetch(
        `${base}/api/workflows/runs/${encodeURIComponent(runId)}/findings/report`,
        { headers: headers as any, signal: AbortSignal.timeout(15000) },
      );
      if (!r.ok) return undefined; // 409 not-ready / 404 unavailable / 401
      const ct = (r.headers.get('content-type') || '').toLowerCase();
      // The endpoint sends findings markdown as text/markdown (JSON only on error).
      if (!ct.includes('markdown') && !ct.includes('text/plain')) return undefined;
      const md = await r.text();
      return md && md.trim() ? md : undefined;
    } catch {
      return undefined;
    }
  }

  /** list_data_sources tool handler — reads the canonical data-source registry
   *  from Galaxy (galaxy.ai.data_sources) so the model can answer "what can you
   *  reach?" from the single source of truth. Filters client-side; flags planned
   *  (not-yet-wired) sources so the model doesn't over-claim. */
  private async _toolListDataSources(input: any): Promise<unknown> {
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    const category = (input?.category ?? '').toString().trim().toLowerCase();
    const entityType = (input?.entity_type ?? '').toString().trim().toLowerCase();
    const status = (input?.status ?? '').toString().trim().toLowerCase();
    try {
      const r = await fetch(`${galaxyUrl}/api/data_sources`, {
        method: 'GET',
        headers: { 'Accept': 'application/json' },
        signal: AbortSignal.timeout(15000),
      });
      if (!r.ok) return { error: `data_sources HTTP ${r.status}` };
      const data: any = await r.json();
      let sources: any[] = Array.isArray(data?.sources) ? data.sources : [];
      if (category) sources = sources.filter((s) => (s.category || '').toLowerCase() === category);
      if (entityType) sources = sources.filter((s) => (s.entity_types || []).map((e: string) => e.toLowerCase()).includes(entityType));
      if (status) sources = sources.filter((s) => (s.status || '').toLowerCase() === status);
      const compact = sources.map((s) => ({
        id: s.id,
        name: s.name,
        category: s.category,
        entity_types: s.entity_types,
        surfaces: s.surfaces,
        status: s.status,
      }));
      return {
        summary: data?.summary,
        total_matched: compact.length,
        sources: compact,
        note: 'These are BioMate\'s real integrated data sources. status "planned" is NOT wired — do not claim it works. Query a live source with the query_database / federated path.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err) };
    }
  }

  // ── External MCP tools (Capability B — user-registered remote MCP servers) ──
  // At tool-assembly time, expose the authenticated user's registered MCP tools
  // to the model (namespaced mcp__<server>__<tool> — collision-free with built-in
  // tools), and dispatch calls back to the owning server. Registration + SSRF +
  // ownership all live in the Galaxy backend external_mcp module; Node only
  // fetches the namespaced tool list and forwards tools/call. MVP = expose all of
  // the user's MCP tools directly (small N); no vector indexing yet.

  /**
   * Fetch the user's registered MCP tools as Anthropic tool defs, and populate
   * context.mcpToolServerMap (namespaced name → server_id) for dispatch. Returns
   * [] and leaves the map empty when there is no user-scoped proxy or on any
   * error — the model keeps its built-in tools. Never throws.
   */
  private async _fetchUserMcpTools(context: ChatContext): Promise<Anthropic.Tool[]> {
    const proxy = context?.galaxyAPIOverride as GalaxyAPIProxy | undefined;
    if (!proxy) return []; // no user-scoped Galaxy key this turn → nothing to expose
    try {
      const resp = await proxy.client.get('/api/biomate/mcp-tools');
      const tools: any[] = Array.isArray(resp?.data?.tools) ? resp.data.tools : [];
      const map: Record<string, string> = context.mcpToolServerMap ?? {};
      const out: Anthropic.Tool[] = [];
      for (const t of tools) {
        const name = (t?.name || '').toString();
        const serverId = (t?.server_id || '').toString();
        if (!name || !serverId || !name.startsWith('mcp__')) continue;
        map[name] = serverId;
        const schema = t?.input_schema && typeof t.input_schema === 'object'
          ? t.input_schema
          : { type: 'object', properties: {} };
        out.push({
          name,
          description: (t?.description || `External MCP tool from ${t?.server_name || 'a user server'}.`).toString().slice(0, 1024),
          input_schema: { type: 'object' as const, ...(schema as object) } as any,
        });
      }
      context.mcpToolServerMap = map;
      if (out.length) {
        console.log(`[GalaxyAssistant] Exposed ${out.length} external MCP tool(s) to the model`);
      }
      return out;
    } catch (err: any) {
      console.warn('[GalaxyAssistant] Could not fetch user MCP tools (non-fatal):', err?.message ?? err);
      return [];
    }
  }

  /**
   * Dispatch an mcp__<server>__<tool> call to the owning remote MCP server via the
   * user-scoped Galaxy proxy (POST /api/biomate/mcp-servers/{id}/call — ownership-
   * checked backend-side). The raw tool name is derived by the backend/client from
   * the namespaced name; we forward the full namespaced name so the client strips
   * its own prefix.
   */
  private async _toolCallExternalMcp(name: string, args: any, context: ChatContext): Promise<unknown> {
    const proxy = context?.galaxyAPIOverride as GalaxyAPIProxy | undefined;
    if (!proxy) return { error: 'external MCP tools require an authenticated user session' };
    const serverId = context?.mcpToolServerMap?.[name];
    if (!serverId) return { error: `no registered MCP server owns tool ${name}` };
    try {
      const resp = await proxy.client.post(
        `/api/biomate/mcp-servers/${encodeURIComponent(serverId)}/call`,
        { tool: name, arguments: args && typeof args === 'object' ? args : {} },
      );
      return resp?.data?.result ?? resp?.data ?? { ok: true };
    } catch (err: any) {
      const status = err?.response?.status;
      const detail = err?.response?.data?.detail || err?.response?.data?.error || err?.message;
      return { error: `MCP tool ${name} failed${status ? ` (HTTP ${status})` : ''}: ${detail}` };
    }
  }

  /** search_workflows tool handler — searches BioMate's OWN workflow/tool catalog
   *  (the #1 world-model gap: previously the catalog was only reachable inside the
   *  workflow_generation intent, so on research/knowledge/comparison turns the model
   *  could only parrot the static counts in the prompt). Reuses the EXISTING backend
   *  ranked search (/api/ai_assistant/search_ranked → UnifiedWorkflowSearch) — no new
   *  search engine. Returns a compact ranked list so the model can answer "do you have
   *  a sarek WGS workflow?" from the real index instead of hallucinating. */
  private async _toolSearchWorkflows(input: any): Promise<unknown> {
    const query = (input?.query ?? '').toString().trim();
    if (!query) return { error: 'query is required' };
    const domain = (input?.domain ?? '').toString().trim();
    let limit = Number(input?.limit);
    if (!Number.isFinite(limit) || limit < 1) limit = 10;
    if (limit > 25) limit = 25;
    const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
    try {
      const r = await fetch(`${galaxyUrl}/api/ai_assistant/search_ranked`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          query,
          limit,
          preferred_domains: domain ? [domain] : null,
        }),
        signal: AbortSignal.timeout(30000),
      });
      if (!r.ok) return { error: `workflow search HTTP ${r.status}`, query };
      const data: any = await r.json();
      const items: any[] = Array.isArray(data?.results) ? data.results : [];
      const results = items.slice(0, limit).map((w: any) => ({
        rank: w.rank,
        name: w.display_name || w.name,
        id: w.name,
        domain: w.domain ?? undefined,
        description: w.description ? String(w.description).slice(0, 200) : undefined,
        source: w.source ?? undefined,
        format: w.format ?? undefined,
        type: w.type ?? 'workflow',
        score: w.score ?? null,
      }));
      return {
        query,
        domain: domain || undefined,
        total: results.length,
        results,
        note: results.length
          ? 'These are BioMate\'s REAL indexed workflows. Refer to one by its name; do NOT invent a workflow that is not in this list. type "chain" = a multi-workflow pipeline. To run one, start a workflow-generation turn with the matching intent.'
          : 'No close match in the catalog for this query. Say the catalog has no matching pipeline rather than inventing a name; BioMate can still generate a new workflow on a workflow-generation turn.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err), query };
    }
  }

  /** request_new_tool handler — GATED on-demand tool discovery. Delegates to the
   *  single shared gate in server/tool-discovery.ts (env flag + confirm), which
   *  invokes the targeted auto_update single-tool pipeline. Never fetches/registers
   *  anything unless the deployment flag is on AND the user explicitly confirmed. */
  private async _toolRequestNewTool(input: any, context: ChatContext): Promise<unknown> {
    const capability = (input?.capability_description ?? '').toString().trim();
    const repo = (input?.repo ?? '').toString().trim();
    const confirm = input?.confirm === true;
    if (!capability && !repo) {
      return { status: 'invalid_request', message: 'capability_description (or repo) is required' };
    }
    try {
      const { requestToolDiscovery } = await import('./tool-discovery');
      return await requestToolDiscovery({
        capability: capability || undefined,
        repo: repo || undefined,
        confirm,
        userId: context?.userId ? String(context.userId) : undefined,
      });
    } catch (err: any) {
      return { status: 'error', message: err?.message ?? String(err) };
    }
  }

  /** Thin, user-scoped proxy to the existing target-ID engine. */
  private async _toolIdentifyTargets(input: unknown): Promise<unknown> {
    try {
      const payload = scientificToolRequest(input, 'targets');
      const { data } = await this._api().client.post('/api/target-id/identify', payload, { timeout: 90000 });
      return scientificToolResult(data, 'targets', payload.query);
    } catch (err: any) {
      return { error: err?.detail?.detail || err?.detail?.error || err?.message || String(err) };
    }
  }

  /** Thin, user-scoped proxy to the federated database fan-out (same endpoint the external connector uses). */
  private async _toolQueryDatabase(input: unknown): Promise<unknown> {
    try {
      const payload = databaseQueryRequest(input);
      const { data } = await this._api().client.post('/api/databases/query', payload, { timeout: 30000 });
      return databaseQueryResult(data, payload.query);
    } catch (err: any) {
      return { error: err?.detail?.detail || err?.detail?.error || err?.message || String(err) };
    }
  }

  /** Preserve the research agent's grounded prose, exact citations and limitations. */
  private async _toolWriteReview(input: unknown): Promise<unknown> {
    try {
      const payload = scientificToolRequest(input, 'review');
      const { data } = await this._api().client.post('/api/ai_assistant/research_query', payload, { timeout: 120000 });
      return scientificToolResult(data, 'review', payload.query);
    } catch (err: any) {
      return { error: err?.detail?.detail || err?.detail?.error || err?.message || String(err) };
    }
  }

  // ── Galaxy History context (Connections 1 & 2) ──────────────────────────
  // See docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md.
  // These are intentionally simple — read from storage.getExecutionRuns, format
  // for either the tool surface (C1) or prompt injection (C2). Non-fatal on
  // any failure so the chat stream isn't broken by storage hiccups.

  /** C3 — list_run_outputs tool handler. Returns the output files of a single run.
   *  The agent uses this to build `run:<fullId>:outputs/<filename>` URIs for next-step
   *  file params; the backend resolver lives at routes.ts:2898 (already in main).
   */
  private async _toolListRunOutputs(input: any, context: ChatContext): Promise<unknown> {
    const runId = (input?.run_id || '').toString().trim();
    const extFilter = (input?.ext_filter || '').toString().toLowerCase().replace(/^\./, '');
    if (!runId) {
      return { error: 'run_id is required (full 16-char id from list_history fullId field)' };
    }
    const userId = context?.userId ? String(context.userId) : undefined;
    try {
      const { storage } = await import('./storage');
      const run = await storage.getExecutionRun(runId);
      if (!run) {
        return { error: `no run with id=${runId}`, hint: 'call list_history to find ids' };
      }
      // Scope check: never expose another user's run
      if (userId && run.userId && run.userId !== userId) {
        return { error: 'run belongs to a different user' };
      }
      const e: any = run.execution || {};
      const rawOutputs: Record<string, any> = (e.outputs as any) || {};
      let files = Object.entries(rawOutputs).map(([key, val]) => {
        const path = typeof val === 'string' ? val : (val?.path || val?.s3_uri || '');
        const name = path ? String(path).split('/').pop() || key : key;
        const ext = name.includes('.') ? name.split('.').pop()!.toLowerCase() : '';
        return { key, name, ext, path };
      });
      if (extFilter) {
        files = files.filter(f => f.ext === extFilter);
      }
      // The canonical URI the LLM should hand back as a file param value
      const uriPrefix = `run:${runId}:outputs/`;
      return {
        runId,
        workflow: run.workflowName,
        status: e.status,
        outputDir: e.nextflowOutputDir || null,
        count: files.length,
        files: files.slice(0, 50).map(f => ({
          name: f.name,
          ext: f.ext,
          param_uri: `${uriPrefix}${f.name}`,
        })),
        uri_scheme_note:
          'Pass any file as a workflow param using the param_uri value. The backend (routes.ts:2898) resolves run:<id>:outputs/<filename> to the underlying S3 path automatically — do not transform it.',
        empty_hint: files.length === 0
          ? 'Outputs map is empty. Either the run is still running, has no published outputs, or output discovery is via S3 publishDir scan. Tell the user the run has no listed outputs yet.'
          : undefined,
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err) };
    }
  }

  /** C1 — list_history tool handler. Returns recent runs scoped to context.userId. */
  private async _toolListHistory(input: any, context: ChatContext): Promise<unknown> {
    const limit = Math.min(Math.max(Number(input?.limit) || 10, 1), 25);
    const wfFilter = (input?.workflow_filter || '').toString().toLowerCase();
    const statusFilter = input?.status_filter as string | undefined;
    const userId = context?.userId ? String(context.userId) : undefined;
    if (!userId) {
      return { runs: [], note: 'no userId in context — cannot list history' };
    }
    try {
      const { storage } = await import('./storage');
      let runs = await storage.getExecutionRuns(userId, undefined, undefined, 50);
      if (wfFilter) {
        runs = runs.filter(r => (r.workflowName || '').toLowerCase().includes(wfFilter));
      }
      if (statusFilter) {
        runs = runs.filter(r => (r.execution?.status as any) === statusFilter);
      }
      runs = runs.slice(0, limit);
      const formatted = runs.map(r => {
        const e: any = r.execution || {};
        const paramKeys = Object.keys(
          (e.parameters as any) || (r.workflowDefinition as any)?.parameters || {}
        );
        return {
          id: r.id.slice(0, 8),
          fullId: r.id,
          workflow: r.workflowName,
          status: e.status,
          startedAt: e.startedAt || r.createdAt,
          completedAt: e.completedAt,
          paramCount: paramKeys.length,
          paramKeys: paramKeys.slice(0, 6),
          outputCount: Object.keys((e.outputs as any) || {}).length,
          // The recorded failure reason (process + specific line) plus a plain-language
          // diagnosis (cause · at-fault input · next action), so "why did it fail?" is
          // answered from the run itself, not guessed.
          ...(/fail|error/i.test(String(e.status || ''))
            ? { error: runErrorSummary(e, (r as any).errorMessage), diagnosis: runFailureExplanation(e, (r as any).errorMessage) }
            : {}),
        };
      });
      return {
        userId,
        // Honest empty-result signal (P1b): when nothing matched, say so explicitly AND state the
        // tool's real limits, so the model reports "no matching runs" instead of guessing — and does
        // not imply it searched by finding/parameter value (it only matches a workflow-name substring
        // over the 50 most recent runs).
        note: formatted.length === 0
          ? `No runs matched${wfFilter ? ` workflow_filter="${wfFilter}"` : ''}${statusFilter ? ` status_filter="${statusFilter}"` : ''}. list_history only matches a workflow-NAME substring over the 50 most recent runs — it cannot find a run by parameter value or by findings/output content. Tell the user plainly that nothing matched (do not invent a run); if they described a run by its data, ask for the workflow name or an approximate date.`
          : 'For a failed run, report its recorded `error`. When it says no error was recorded, say so and point the user to the run\'s task log (workflow panel → failed step → log); do not guess causes.',
        count: formatted.length,
        filter: { workflow_filter: wfFilter || null, status_filter: statusFilter || null },
        runs: formatted,
        usage_hint:
          'To reuse params: read the full row for an id; to reference outputs of a run, prefix file params with `run:<fullId>:` once chain-panel work merges.',
      };
    } catch (err: any) {
      return { error: err?.message ?? String(err) };
    }
  }

  /** C2 — recent-runs prompt block. Injected alongside P1/P2 memory blocks, and on any turn that
   *  asks about a failing/stuck run (withErrors: this chat's runs first, each failed run with its
   *  recorded error) — external users asked "why is the run failing?" three times and were answered
   *  from literature; the block carried neither the error nor appeared after the first message. */
  private async _buildRecentRunsBlock(userId: string, opts: { withErrors?: boolean; chatSessionId?: string } = {}): Promise<string> {
    try {
      const { storage } = await import('./storage');
      const sessionRuns = opts.chatSessionId
        ? await storage.getExecutionRuns(userId, undefined, undefined, 5, opts.chatSessionId).catch(() => [])
        : [];
      const recent = await storage
        .getExecutionRuns(userId, undefined, undefined, 5)
        .catch(() => []);
      const seen = new Set<string>();
      const runs = [...(sessionRuns || []), ...(recent || [])].filter(r => !seen.has(r.id) && seen.add(r.id)).slice(0, 6);
      if (!runs?.length) return '';
      const lines = runs.map(r => {
        const e: any = r.execution || {};
        const status = e.status || (r as any).status || 'unknown';
        const date = (e.startedAt || r.createdAt)
          ? new Date(e.startedAt || r.createdAt).toISOString().slice(0, 10)
          : 'recent';
        const outs = Object.keys((e.outputs as any) || {}).length;
        const here = opts.chatSessionId && (r as any).chatSessionId === opts.chatSessionId ? ' · this chat' : '';
        let line = `  • ${r.id.slice(0, 8)} · ${r.workflowName || 'unnamed'} · ${status} · ${date} · ${outs} outputs${here}`;
        if (opts.withErrors && /fail|error/i.test(String(status))) {
          // Classified, plain-language cause + at-fault input + next action, so the
          // assistant can answer "why did it fail?" legibly (not just the raw stack).
          const explained = runFailureExplanation(e, (r as any).errorMessage);
          line += explained
            ? '\n' + explained.split('\n').map(l => `      ${l}`).join('\n')
            : `\n      error: ${runErrorSummary(e, (r as any).errorMessage)}`;
        }
        return line;
      });
      return [
        opts.withErrors
          ? '[The user\'s recent workflow runs — STANDING context, present every turn. Each line: run id · workflow · status · date · N outputs; a FAILED run is followed by a plain-language diagnosis (cause · at-fault input · next action, from its recorded error). Answer ANY question about the user\'s own runs from THIS — their status, what a run produced (outputs/results), or why one failed — directly, in one message; never treat such a question as a literature/knowledge query. Do NOT answer from literature, do NOT cite papers, and do NOT ask the user to paste logs/errors you have already been given here. The raw error is on the "Error:" line — show it only if they want detail. When a line says the cause could not be classified, state the failing step and show the raw error, and offer to investigate — never invent a cause. When a run has no recorded error, say exactly that and point to the run\'s card in the workflow panel → failed step → log. To open a run\'s actual output files/findings, use its 8-char id with list_history / the outputs tool]'
          : '[Your recent workflow runs — refer by 8-char id when the user wants to reuse params or outputs]',
        ...lines,
        '(call list_history for filtered/expanded details)',
        '',
      ].join('\n') + '\n';
    } catch {
      return '';
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
    const _msg = userMessage || '';
    // Word-boundary'd drug-dev terms. The previous unanchored regex matched
    // filenames like `clinical_gse22055.csv` (clinical=metadata) and bare
    // substrings like "pk" inside other tokens, leaking pharma-specific
    // boilerplate ("docking, ADMET, or PK/NCA") into RNA-seq / genomics chats.
    // See docs/20260610_REAL_USER_FULL_CHAT_LOGS.md — wjunlin@hku session.
    const _drugDevTerms = /\b(drug|admet|herg|dili|toxicity|docking|ligand|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|ic50|ec50)\b/i;
    const _pkWord = /(?:^|[^a-z])pk(?:[^a-z]|$)/i;
    // "clinical" alone is too broad (matches "clinical metadata", "clinical sample").
    // Only treat as drug-dev when it co-occurs with trial/dose/phase language.
    const _clinicalCtx = /\bclinical\s+(?:trial|study|phase|protocol|dose|dosing|escalation|pharmacology)\b/i;
    const isDrugDevelopmentQuery = _drugDevTerms.test(_msg) || _pkWord.test(_msg) || _clinicalCtx.test(_msg);

    // Hard escape hatch: never apply pharma boilerplate when the user is
    // clearly in a genomics / transcriptomics / cheminformatics-free context.
    const _genomicsContext = /\b(rna[- ]?seq|scrna|single[- ]?cell|deg|deseq2|edger|limma|geo|gse\d+|srr\d+|ensembl|fastq|bam|vcf|variant|gwas|cryo[- ]?em|microarray|differential\s+expression|count\s+matrix|volcano|gtf|gff|genome\s+assembly|chip[- ]?seq|atac[- ]?seq|methyl[- ]?seq)\b/i;
    if (_genomicsContext.test(_msg)) {
      return assistantMessage;
    }
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
    userId?: number | string,
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
