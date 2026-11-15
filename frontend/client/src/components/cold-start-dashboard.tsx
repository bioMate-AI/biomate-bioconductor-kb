/**
 * ColdStartDashboard — the cold-start function-module dashboard + intent router
 * (data-centric spec 00 §0.4 "the cold start" and §0.5 "the intent router").
 *
 * Shown when a fresh chat session has no messages yet, where the old
 * hardcoded suggested-query grid used to live (ReturningUserWelcome, which now
 * returns null). It answers the cold-start question — "what can I do here?" —
 * WITHOUT ever showing a browsable list of our inventory.
 *
 * Honesty contract (spec 00 §0.9 — the no-inventory rule):
 *   - It shows FUNCTION CATEGORIES (Search & evidence, Data analysis, Design &
 *     generate, Models) and, under each, a few EXAMPLE INTENTS phrased as
 *     things you might say. That is all.
 *   - It NEVER shows a fabricated workflow/tool count, and never claims a
 *     browsable catalogue. There are no numbers on these cards.
 *   - The intent bar routes a described goal to a LANE and a DOMAIN — it
 *     describes what it heard back to you; it does not return a list of names.
 *
 * Expand / collapse (spec 00 §0.4.2 — .modcard / .modhd, .trackbar, .schip):
 *   - A module card is collapsed by default. Clicking its header toggles it
 *     open; only ONE card is open at a time (state is lifted to the dashboard).
 *     A chevron rotates to indicate the open state (aria-expanded on the
 *     header button).
 *   - Inside an open card, .trackbar shows the module's tracks as tabs
 *     (e.g. Search & evidence → Literature · Databases · Patents · Internal).
 *     The first track is selected on open; switching a track clears any
 *     selected domain.
 *   - The Data analysis → "Validated workflows" track carries domain chips
 *     (.schip): selecting one replaces the example list with that domain's
 *     workflow SHAPES (title · what it needs · how long). Selecting again
 *     clears it. Categories and shapes only — never a list of names, never a
 *     count.
 *   - Example intents (.exrow) and shapes (.shaperow) SEED the composer via
 *     `onSeed` — they do not send. The user still reviews and sends.
 *
 * The four modules, their tracks, the domains and the router heuristic mirror
 * the reference design at
 * reference/claude_design/data_centroid_design/dataui/data-part3.js
 * (window.MODULES + window.DOMAINS + window.ROUTES) and ColdStart.jsx
 * (ModuleDash / ModuleCard / IntentBar). The two-way Instant/Cloud read reuses
 * `laneForText` from lane-preview.tsx so the front door cannot contradict the
 * composer's own lane preview; the DOMAIN read is a light domain-aware pass
 * layered on top (lane-preview only resolves the coarse Instant/Cloud lane,
 * not a domain).
 */

import { useState } from "react";
import { PREPARED_EXAMPLES, INTERNAL_EXAMPLES } from "./cold-start-examples";
import { Search, FlaskConical, Dna, Sparkles, ChevronRight, ChevronDown } from "lucide-react";
import { laneForText, type LaneKind } from "./lane-preview";
import { t } from "@/lib/i18n";

/**
 * Display copy for the card catalogue below. The catalogue stays canonical
 * English (it is the router self-test surface and the prepared-example lookup
 * key); what the user SEES goes through i18n, keyed by a slug of the English
 * text: cold_start.copy.<slug> in both locale bundles.
 */
export function coldCopyKey(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 64);
}
export function coldCopy(text: string): string {
  return t(`cold_start.copy.${coldCopyKey(text)}`);
}

// ── A validated-workflow SHAPE. Title + what it needs + how long. No pipeline
//    name, no count — a shape a scientist recognises, not a catalogue row.
//    (reference window.DOMAINS[].shapes) ──────────────────────────────────────
export interface ColdShape {
  /** Human title of the shape, e.g. "Screen a compound set for ADMET liabilities". */
  t: string;
  /** What the shape needs, e.g. "SMILES or SDF". */
  needs: string;
  /** Rough time class, e.g. "~15 min". */
  time: string;
  /** The seed sentence the composer is filled with on click. */
  seed: string;
  /**
   * An optional real, staged sample dataset attached to this example so a
   * first-time user can run it directly — or edit the seed to swap in their own.
   * `ref` is a public accession (or a path BioMate has already staged); the
   * same accession is embedded in `seed`, so clicking pre-loads a runnable goal.
   * Only set when the dataset genuinely exists (no fabricated demo data).
   */
  sampleDataset?: { label: string; ref: string };
}

// ── A domain inside the Data analysis → Validated workflows track. Chips that
//    swap the example list for that domain's shapes. (reference window.DOMAINS)
export interface ColdDomain {
  id: string;
  name: string;
  shapes: ColdShape[];
}

/**
 * The validated-workflow domains, with three editorial shapes each (reference
 * window.DOMAINS — three by design, never a count of the real inventory).
 */
export const COLD_DOMAINS: ColdDomain[] = [
  {
    id: "dd",
    name: "Drug discovery",
    shapes: [
      { t: "Screen a compound set for ADMET liabilities", needs: "sample provided — or your own SMILES/SDF", time: "~15 min", seed: "Screen these SMILES for ADMET liabilities and rank them by developability: CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CC(C)Cc1ccc(C(C)C(=O)O)cc1", sampleDataset: { label: "example SMILES", ref: "inline" } },
      { t: "Dock a series against a target and rank poses", needs: "sample provided — ligands + target structure", time: "~1 h", seed: "Dock this series against my target and rank the poses." },
      { t: "Explain why a hit series is failing on one property", needs: "sample provided — a series with measured target and hERG IC50s", time: "seconds", seed: "Why might this hit series be failing on hERG? Cite the evidence.", sampleDataset: { label: "MCHR1 chromone series", ref: "ChEMBL CHEMBL1137327" } },
    ],
  },
  {
    id: "txn",
    name: "Transcriptomics",
    shapes: [
      // Generic DE example with a NEUTRAL, standard public sample (airway,
      // Himes et al. — a textbook DESeq2 dataset, not anyone's collaborator
      // data). Run directly, or edit the goal to use your own counts matrix.
      { t: "Differential expression between two conditions", needs: "sample provided — or your own counts matrix", time: "~40 min", seed: "Run DESeq2 differential expression on the airway dataset (treated vs control), then GO enrichment. Human GRCh38.", sampleDataset: { label: "airway (example)", ref: "GSE52778" } },
      { t: "Subtype cells from single-cell RNA-seq", needs: "sample provided — a single-cell matrix (10x / h5ad)", time: "~1.5 h", seed: "Cluster and annotate my single-cell RNA-seq and find the cell-type composition and markers." },
      { t: "Integrate multi-omics across phenotypes", needs: "sample provided — 2+ omics tables", time: "~2 h", seed: "Integrate my multi-omics layers across phenotypes and show the shared factors that survive." },
    ],
  },
  {
    id: "gen",
    name: "Genomics",
    shapes: [
      { t: "Call variants and flag the clinically relevant ones", needs: "sample provided — reads + reference build", time: "~2 h", seed: "Call variants on these samples and flag the clinically relevant ones. Human GRCh38." },
      { t: "Compare variant burden between two cohorts", needs: "sample provided — cohort mutation calls + response labels", time: "~50 min", seed: "Compare variant burden between my responder and non-responder cohorts.", sampleDataset: { label: "NSCLC anti-PD-1 cohort", ref: "Rizvi 2015, Science (PMID 25765070)" } },
      { t: "Check contamination and relatedness before analysis", needs: "sample provided — multi-sample genotypes + a pedigree", time: "~25 min", seed: "Check these genotypes for contamination and relatedness before I analyse them.", sampleDataset: { label: "CEPH 1463 pedigree", ref: "Illumina Platinum Genomes" } },
    ],
  },
  {
    id: "fgen",
    name: "Functional genomics",
    shapes: [
      { t: "Call hits from a pooled CRISPR screen", needs: "sample provided — plasmid + replicate read counts", time: "~40 min", seed: "Analyze my pooled CRISPR screen: call enriched/depleted hits at an FDR cutoff and rank the candidate dependency genes.", sampleDataset: { label: "HT-29 MiniLibCas9 screen", ref: "CRISPRcleanR example" } },
      { t: "Compare screen hits across two cell lines", needs: "sample provided — initial/final counts for two lines", time: "~35 min", seed: "Compare my CRISPR screen hits between the two cell lines and flag line-specific dependencies.", sampleDataset: { label: "HL60 / KBM7 screen", ref: "MAGeCK demo" } },
      { t: "QC a screen before hit-calling", needs: "sample provided — replicate counts + control gene sets", time: "~15 min", seed: "QC my CRISPR screen — guide representation, replicate correlation, and control separation — before hit-calling.", sampleDataset: { label: "HT-29 Brunello screen", ref: "CRISPRcleanR example" } },
    ],
  },
  {
    id: "str",
    name: "Structural biology",
    shapes: [
      { t: "Process a cryo-EM set to a density map", needs: "sample provided — micrographs", time: "~6 h", seed: "Process this cryo-EM dataset to a density map and report the resolution." },
      { t: "Predict and assess a structure for a sequence", needs: "sample provided — or your own sequence", time: "~30 min", seed: "Predict the structure for this protein sequence and tell me where to trust it: MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEK", sampleDataset: { label: "example sequence", ref: "inline" } },
      { t: "Sharpen and post-process a cryo-EM map", needs: "sample provided — a density map", time: "~20 min", seed: "Sharpen and post-process this cryo-EM density map, then re-estimate the local resolution." },
    ],
  },
  {
    id: "prot",
    name: "Proteomics",
    shapes: [
      { t: "Quantify differential protein abundance between groups", needs: "sample provided — search output + design", time: "~45 min", seed: "Quantify differential protein abundance between my two groups." },
      { t: "Reconcile a proteomic signal with a transcriptomic one", needs: "sample provided — two result tables", time: "~35 min", seed: "Reconcile my proteomic signal with the transcriptomic result." },
      { t: "Assess run-to-run quality across a batch", needs: "sample provided — a 12-run search output + design", time: "~20 min", seed: "Assess run-to-run quality across this proteomics batch.", sampleDataset: { label: "LFQ-Analyst example batch", ref: "J Proteome Res 2020" } },
    ],
  },
  {
    id: "clin",
    name: "Clinical",
    shapes: [
      { t: "Compare trial arms and test the primary endpoint", needs: "sample provided — a randomised trial cohort", time: "~20 min", seed: "Compare the treatment arms in this trial cohort and test the primary endpoint.", sampleDataset: { label: "Mayo PBC trial cohort", ref: "survival::pbc" } },
      { t: "Discover a biomarker panel and build a risk model", needs: "sample provided — a cohort table + labels", time: "~30 min", seed: "From this cohort, discover a biomarker panel and build a cross-validated, reproducible risk-prediction model with an honest performance estimate." },
      { t: "Assemble the analysis section of a submission", needs: "sample provided — inputs for a first run", time: "~1 h", seed: "Assemble the analysis section of my submission from these runs." },
    ],
  },
];

// ── Modality of a design candidate (reference window.MODALITIES). The Design &
//    generate module's tracks switch their example list per modality, and the
//    picked modality is threaded into the seeded goal so the downstream run
//    opens in the right modality. ──────────────────────────────────────────────
export type ColdModality = "sm" | "pep" | "bio";

/** [key, chip label] pairs, in display order (reference window.MODALITIES). */
export const COLD_MODALITIES: Array<[ColdModality, string]> = [
  ["sm", "Small molecule"],
  ["pep", "Peptide"],
  ["bio", "Protein / biologic"],
];

/** Human word for a modality, used to phrase the seeded goal (reference MOD_WORD). */
export const COLD_MOD_WORD: Record<ColdModality, string> = {
  sm: "small molecule",
  pep: "peptide",
  bio: "protein",
};

// ── A track inside a module (reference window.MODULES[].tracks). A track is a
//    tab whose example intents (.exrow) seed the composer. The Data analysis →
//    Validated workflows track sets `domains`, which swaps in the domain chips.
export interface ColdTrack {
  /** Short track key shown on the tab, e.g. "Literature". */
  k: string;
  /** A few example intents — click-to-seed the composer. */
  ex: string[];
  /** When true, this track shows the validated-workflow domain chips. */
  domains?: boolean;
  /**
   * Per-modality example intents (reference tr.exBy). When present on a module
   * flagged `modalities`, the shown examples switch with the modality chip;
   * `ex` stays the small-molecule default (and the router self-test surface).
   */
  exBy?: Record<ColdModality, string[]>;
}

// ── Function modules. Categories + tracks + example intents only — no counts,
//    no inventory. Copy adapted from the reference window.MODULES. ────────────
export interface ColdModule {
  id: string;
  /** Short module key, e.g. "Search & evidence". */
  k: string;
  /** One-line description of what the module is for. */
  t: string;
  icon: "search" | "beaker" | "dna" | "sparkles";
  /** When true, the card shows a modality chip row (Small molecule / Peptide /
   *  Protein), and its tracks' examples switch per modality via `exBy`. */
  modalities?: boolean;
  /** The module's tracks (tabs shown when the card is open). */
  tracks: ColdTrack[];
  /**
   * Every example intent across all tracks, flattened. Kept as the module's
   * router self-test surface (spec 00 §0.5 — every example printed on a card
   * must route to a lane) and for the no-inventory count assertion. Derived
   * from `tracks`, so it can never drift from what the card actually renders.
   */
  ex: string[];
}

function withEx(m: Omit<ColdModule, "ex">): ColdModule {
  // The router self-test surface: every example printed on a card (across all
  // tracks and, for a modality module, every per-modality variant) must route.
  const ex = m.tracks.flatMap((tr) =>
    tr.exBy ? [...tr.ex, ...Object.values(tr.exBy).flat()] : tr.ex,
  );
  // De-dupe: the small-molecule exBy usually repeats the default `ex`.
  return { ...m, ex: Array.from(new Set(ex)) };
}

export const COLD_MODULES: ColdModule[] = [
  withEx({
    id: "search",
    k: "Search & evidence",
    t: "A cited answer over literature, databases and patents",
    icon: "search",
    tracks: [
      {
        k: "Literature",
        ex: [
          "What is the evidence linking LRRK2 to Parkinson's disease?",
          "Known SAR for imatinib-like phenylaminopyrimidines — what drives ABL1 potency?",
          "Why do JAK2 inhibitors usually fail on selectivity?",
        ],
      },
      {
        k: "Databases",
        ex: [
          "Pull every reported structure for KRAS G12C.",
          "Known off-targets for the celecoxib diarylpyrazole sulfonamide chemotype?",
          "Which trials targeted PD-1/PD-L1 in non-small-cell lung cancer, and what were their endpoints?",
        ],
      },
      {
        k: "Patents",
        ex: [
          "Who holds composition-of-matter claims on the sotorasib scaffold?",
          "Freedom-to-operate picture for this series.",
          "Are my generated candidates inside anyone's claims?",
        ],
      },
      {
        k: "Internal",
        ex: INTERNAL_EXAMPLES,
      },
    ],
  }),
  withEx({
    id: "analysis",
    k: "Data analysis",
    t: "Work on your own data, or try a prepared sample dataset",
    icon: "beaker",
    tracks: [
      {
        k: "Ad-hoc compute",
        ex: [
          "Summarise this assay table and plot potency against logP.",
          "Correlate predicted and measured IC50 for these compounds.",
          "Reshape this plate readout into long format and save it.",
        ],
      },
      {
        k: "Validated workflows",
        domains: true,
        ex: [
          "Screen these SMILES for ADMET liabilities, hERG first.",
          "Differential expression between treated and control, then GO enrichment.",
          "Call variants on these samples and flag the clinically relevant ones.",
        ],
      },
      { k: "Try sample data", ex: PREPARED_EXAMPLES.map(example => example.label) },
    ],
  }),
  withEx({
    id: "design",
    k: "Molecule design & generate",
    t: "Propose candidates — molecules, peptides, proteins — then optimise and rank them",
    icon: "dna",
    modalities: true,
    tracks: [
      {
        k: "Generate",
        ex: [
          "Generate candidates for this target with drug-like properties.",
          "Scaffold-hop away from this series but keep the binding pharmacophore.",
          "Grow this fragment into a lead-like molecule.",
        ],
        exBy: {
          sm: [
            "Generate 500 candidates for this target with drug-like properties.",
            "Scaffold-hop away from this series but keep the binding pharmacophore.",
            "Grow this fragment into a lead-like molecule.",
          ],
          pep: [
            "Design cyclic peptides against this binding site.",
            "Propose stapled-peptide analogues of this helix.",
            "Generate macrocycle candidates with good permeability.",
          ],
          bio: [
            "Design scFv antibody sequences from this antibody structure.",
            "Graft these CDRs onto a stable human framework.",
            "Propose enzyme variants with a redesigned active-site pocket.",
          ],
        },
      },
      {
        // Fold the candidate (or its complex with the target) and read where to
        // trust it — Boltz-2 cofold on Cloud GPU. Separate from "Predict & filter"
        // (affinity/dock): this produces the 3D structure + confidence, the input
        // the downstream pose/affinity steps read. Routes to the Structure
        // prediction domain (DOMAIN_RULES).
        k: "Fold & complex",
        ex: [
          "Predict the structure of this protein\u2013ligand complex and show me the pose.",
          "Model this complex and tell me where the model is unsure.",
          "Predict the fold of this candidate and flag the low-pLDDT regions.",
        ],
        exBy: {
          sm: [
            "Predict the structure of this protein\u2013ligand complex and show me the pose.",
            "Model this complex and tell me where the model is unsure.",
            "Predict the fold of this candidate and flag the low-pLDDT regions.",
          ],
          pep: [
            "Predict the structure of this cyclic peptide bound to my target.",
            "Model this complex for a macrocycle against my target, with interface confidence.",
            "Predict the fold of this stapled peptide and where to trust it.",
          ],
          bio: [
            "Predict the structure of this antibody\u2013antigen complex and report interface confidence.",
            "Model this complex for a nanobody and its antigen.",
            "Predict the fold of this designed binder against its target.",
          ],
        },
      },
      {
        // The evaluate step of the design chain: a ladder from fast (dock) to
        // rigorous (relative binding free energy / ΔΔG, a Cloud · GPU-hours run).
        k: "Predict & filter",
        ex: [
          "Predict binding affinity for these candidates against my target.",
          "Which of these would you expect to bind, and why?",
          "Dock the top 50 and check the poses are plausible.",
          "Compute the relative binding free energy between two analogues against my target.",
        ],
        exBy: {
          sm: [
            "Predict binding affinity for these candidates against my target.",
            "Which of these would you expect to bind, and why?",
            "Dock the top 50 and check the poses are plausible.",
            "Compute the relative binding free energy between two analogues against my target.",
          ],
          pep: [
            "Predict binding and serum stability for these peptides.",
            "Which macrocycles are likely to be cell-permeable?",
            "Screen these peptides for aggregation risk.",
            "Compute the relative binding free energy for a single-residue change in this peptide binder.",
          ],
          bio: [
            "Predict developability liabilities for these antibody candidates.",
            "Which variants keep affinity and lose aggregation risk?",
            "Flag expression and stability risks across these designs.",
          ],
        },
      },
      {
        k: "Optimise properties · one pass",
        ex: [
          "Optimise this series for potency without losing solubility.",
          "Improve druglikeness while keeping hERG above 30 µM.",
          "Fix the metabolic liability on this scaffold and re-score.",
        ],
        exBy: {
          sm: [
            "Optimise this series for potency without losing solubility.",
            "Improve druglikeness while keeping hERG above 30 µM.",
            "Fix the metabolic liability on this scaffold and re-score.",
          ],
          pep: [
            "Improve serum stability without losing affinity.",
            "Reduce charge while keeping cell permeability.",
            "Optimise these macrocycles for both potency and solubility.",
          ],
          bio: [
            "Optimise this antibody for developability — aggregation and viscosity.",
            "Humanise this nanobody and keep affinity.",
            "Raise thermostability without losing catalytic activity.",
          ],
        },
      },
      {
        k: "Rank candidates",
        ex: [
          "Rank these candidates for developability and show me the top 20.",
          "Which candidates pass every safety gate?",
          "Triage this library into synthesise-now and park.",
        ],
        exBy: {
          sm: [
            "Rank these 500 candidates for developability and show me the top 20.",
            "Which candidates pass every safety gate?",
            "Triage this library into synthesise-now and park.",
          ],
          pep: [
            "Rank these peptides on affinity, stability and permeability together.",
            "Which macrocycles pass every developability gate?",
            "Shortlist the top 20 peptides to synthesise first.",
          ],
          bio: [
            "Rank these designs on developability and expression risk.",
            "Which variants pass every liability gate?",
            "Triage this design set into express-now and park.",
          ],
        },
      },
    ],
  }),
  withEx({
    id: "models",
    k: "Models",
    t: "Train, adapt or optimise a model on your data",
    icon: "sparkles",
    tracks: [
      {
        k: "Train",
        ex: [
          "Train a potency predictor on our in-house assay data.",
          "Train an hERG classifier and gate the design loop on it.",
          "Train a solubility model from our historical plate data.",
        ],
      },
      {
        k: "Adapt",
        ex: [
          "Adapt the generative model to our chemical series.",
          "Fine-tune this property predictor on our measured compounds.",
        ],
      },
      {
        k: "Optimise",
        // These seeds deep-link to Models Molecular Rounds (campaign Bayesian DMTA),
        // not reinvent4_lead_design — see isDmtaLoopQuery / MODELS_DMTA_HREF.
        ex: [
          "Run the design–make–test loop on this series under a 96-assay budget.",
          "Propose the next round and refit on the results.",
        ],
      },
    ],
  }),
];

const ICONS = {
  search: Search,
  beaker: FlaskConical,
  dna: Dna,
  sparkles: Sparkles,
} as const;

// ── Domain read. lane-preview.laneForText resolves the coarse Instant/Cloud
//    lane; this adds a domain label, mirroring the ordering of the reference
//    window.ROUTES (evidence intents first so a topic keyword inside a "what
//    is known" question is not swallowed by a cloud rule). Categories/domains
//    only — never a list of names, never a count. ───────────────────────────
// Each rule carries the lane its domain lives in (reference window.ROUTES
// pairs every match with a lane). The domain read is the SOURCE OF TRUTH for
// the lane here: e.g. "Molecular design" is a Cloud lane regardless of whether
// the coarse lane-preview verb heuristic caught the specific verb form. When
// no domain rule matches, we fall back to lane-preview's Instant/Cloud read.
const DOMAIN_RULES: Array<{ m: RegExp; dom: string; lane: LaneKind }> = [
  // Evidence first.
  { m: /(patent|freedom.?to.?operate|\bfto\b|composition-of-matter|claims?\b)/i, dom: "Patents", lane: "instant" },
  { m: /(have we|did we|do we (have|know)|our (last|previous|in-house)|what did we conclude)/i, dom: "Internal record", lane: "instant" },
  { m: /(pull every|reported (structure|activit)|registr(y|ies)|curated database)/i, dom: "Databases", lane: "instant" },
  { m: /(evidence|literature|\bsar\b|known (off-?target|sar)|why do|mechanism|cite|trials?\b|endpoints)/i, dom: "Literature", lane: "instant" },
  // Model-side, before topic keywords.
  { m: /(predict the (fold|structure)|model this complex|fold of this|where the model is unsure|\bplddt\b|\bpae\b)/i, dom: "Structure prediction", lane: "cloud" },
  { m: /(score this (locus|sequence|region)|sequence model|per-?base score|what stands out)/i, dom: "Sequence scoring", lane: "cloud" },
  { m: /(screen this library|virtual (library|screen)|predicted hits|re-?rank these hits)/i, dom: "Library screening", lane: "cloud" },
  { m: /(train|fine-?tune|adapt (the |a )?model|re-?train)/i, dom: "Models & training", lane: "cloud" },
  // Design pipeline, most specific first.
  // Relative FEP / ΔΔG is the rigorous end of the evaluate ladder — matched
  // before "analogue"/"binding"/"optimise" so a free-energy goal reads as its
  // own Cloud capability (internally routed to openfe_rbfe or gromacs_pmx_fep),
  // not "Molecular design" or "Activity prediction".
  { m: /(relative binding free energy|free[- ]?energy perturbation|\bfep\b|\bddg\b|ΔΔg|alchemical|thermodynamic cycle)/i, dom: "Relative FEP", lane: "cloud" },
  { m: /(optimis|optimiz|multi-?objective|trade-?off|without losing|re-?score|improve.*(while|but|without))/i, dom: "Property optimisation", lane: "cloud" },
  // Peptide / protein-biologic design (reference INFER + design routes) —
  // before the small-molecule design rule so a modality-specific goal reads as
  // its own domain, not "Molecular design".
  { m: /(nanobod|antibod|\bcdr\b|humanise|humanize|enzyme variant|biologic|developab|thermostab|framework)/i, dom: "Protein & biologic design", lane: "cloud" },
  { m: /(peptide|macrocyc|stapled|helicit|serum stab|cell.?permeab|cyclic peptide)/i, dom: "Peptide design", lane: "cloud" },
  { m: /(generate|de novo|design (a |some )?molecul|scaffold.?hop|enumerat|analogue|grow this fragment)/i, dom: "Molecular design", lane: "cloud" },
  { m: /(affinity|binding|expect to bind|dock|pose|selectiv|predict.*potenc)/i, dom: "Activity prediction", lane: "cloud" },
  // Validated workflows by domain. ADMET before ranking.
  { m: /(herg|admet|smiles|liabilit|toxic|metabolic|solubil)/i, dom: "Drug discovery", lane: "cloud" },
  { m: /(rank|triage|shortlist|developab|prioriti|top \d+|pass every)/i, dom: "Candidate ranking", lane: "cloud" },
  { m: /(proteom|mass spec|protein abundance)/i, dom: "Proteomics", lane: "cloud" },
  { m: /(single-?cell|cell type|composition|doublet)/i, dom: "Transcriptomics", lane: "cloud" },
  { m: /(differential (expression|abundance)|rna-?seq|counts matrix|deseq|enrichment)/i, dom: "Transcriptomics", lane: "cloud" },
  { m: /(variant|wgs|wes|vcf|burden|contaminat|relatedness)/i, dom: "Genomics", lane: "cloud" },
  { m: /(cryo|density map|micrograph)/i, dom: "Structural biology", lane: "cloud" },
  { m: /(cohort|stratif|\bsap\b|primary endpoint)/i, dom: "Clinical", lane: "cloud" },
  { m: /(run-to-run|batch quality|assay batch)/i, dom: "Assay quality", lane: "cloud" },
  // Ad-hoc compute last — the cheap default.
  { m: /(plot|summari|mean|median|correlat|reshape|table|dose.?response|plate|curve)/i, dom: "Data analysis", lane: "instant" },
];

export interface IntentRead {
  lane: LaneKind;
  /** Short user-facing consequence label from lane-preview. */
  laneLabel: string;
  /** The coarse domain the intent reads as, or null if none matched. */
  domain: string | null;
}

/**
 * Route a described goal to a lane (from lane-preview) + a domain. Returns null
 * for text too short to route meaningfully — the reference gate is >6 chars, so
 * a stray keystroke does not flash a verdict. Never throws.
 */
export function readIntent(text: string | undefined | null): IntentRead | null {
  const t = (text || "").trim();
  if (t.length <= 6) return null;
  const coarse = laneForText(t);
  if (!coarse) return null;
  const dom = DOMAIN_RULES.find((r) => r.m.test(t));
  // The matched domain owns its lane (reference window.ROUTES pairs the two);
  // fall back to the coarse lane-preview read when no domain matched.
  const lane: LaneKind = dom ? dom.lane : coarse.lane;
  // Keep lane-preview's label when it agrees with the resolved lane; otherwise
  // use a plain label matching the resolved lane so chip and dot never disagree.
  const laneLabel =
    coarse.lane === lane
      ? coarse.label
      : lane === "cloud"
        ? "Prepare an analysis · review before starting"
        : "Answer here · with sources";
  return { lane, laneLabel, domain: dom ? dom.dom : null };
}

// NOTE (2026-11-09): the cold-start "describe your goal" IntentBar was removed.
// It duplicated the always-present bottom composer — a second text input into the
// exact same onSeed→composer path — which the user flagged as redundant. The
// cold-start now guides purely through the module cards + example rows (which seed
// the composer on click) and leaves typing to the single pinned composer below.
// `readIntent()` is retained and exported because the bottom composer's LanePreview
// reuses it for the same lane/domain classification.

interface ExampleRowProps {
  text: string;
  onSeed: (text: string) => void;
}

/** A single example-intent row (.exrow) — click seeds the composer, never sends. */
function ExampleRow({ text, onSeed }: ExampleRowProps) {
  return (
    <button
      type="button"
      data-testid="cold-example"
      onClick={() => onSeed(text)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 6,
        padding: "6px 8px",
        border: "none",
        borderRadius: 7,
        background: "transparent",
        cursor: "pointer",
        textAlign: "left",
        fontSize: 'var(--fs-base)',
        color: "var(--bm-text, oklch(0.22 0.01 260))",
      }}
    >
      <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis" }}>“{coldCopy(text)}”</span>
      <span style={{ flex: 1 }} />
      <ChevronRight size={12} aria-hidden style={{ flexShrink: 0, color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }} />
    </button>
  );
}

interface ShapeRowProps {
  shape: ColdShape;
  onSeed: (text: string) => void;
}

/** A validated-workflow shape row (.shaperow): title + what-it-needs · time. */
function ShapeRow({ shape, onSeed }: ShapeRowProps) {
  return (
    <button
      type="button"
      data-testid="cold-shape"
      onClick={() => onSeed(shape.seed)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "8px 8px",
        border: "none",
        borderRadius: 7,
        background: "transparent",
        cursor: "pointer",
        textAlign: "left",
      }}
    >
      <span style={{ display: "flex", flexDirection: "column", gap: 3, minWidth: 0 }}>
        <span style={{ fontWeight: 600, fontSize: 'var(--fs-base)', color: "var(--bm-text, oklch(0.22 0.01 260))" }}>{coldCopy(shape.t)}</span>
        <span style={{ fontSize: 'var(--fs-sm)', color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>
          {coldCopy(shape.needs)} · {coldCopy(shape.time)}
        </span>
      </span>
      <span style={{ flex: 1 }} />
      {shape.sampleDataset && (
        <span
          data-testid="cold-shape-sample"
          title={shape.sampleDataset.ref === 'inline' ? t('cold_start.sample_title_inline') : t('cold_start.sample_title', { ref: shape.sampleDataset.ref })}
          style={{
            flexShrink: 0,
            fontSize: 'var(--fs-xs)',
            fontWeight: 600,
            padding: "2px 6px",
            borderRadius: 999,
            background: "var(--bm-accent-weak, oklch(0.95 0.03 245))",
            color: "var(--bm-accent, oklch(0.5 0.14 245))",
          }}
        >
          ▶ {t('cold_start.sample_chip', { label: coldCopy(shape.sampleDataset.label) })}
        </span>
      )}
      <ChevronRight size={13} aria-hidden style={{ flexShrink: 0, color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }} />
    </button>
  );
}

/**
 * Thread the picked modality into a seeded design goal (reference onSeed(x, mod)).
 * The deployed onSeed is single-arg, so instead of a second argument we make the
 * modality explicit in the seed text — the downstream router reads the words, so
 * naming the modality in the goal is what actually opens the run in that
 * modality. A no-op for small molecule (the default reading) and for seeds that
 * already name the modality word, so we never double-qualify.
 */
export function seedWithModality(text: string, mod: ColdModality): string {
  const t = (text || "").trim();
  if (!t) return t;
  // Small molecule is the default reading — the design examples are already
  // phrased for it, so adding "(small molecule)" would be noise.
  if (mod === "sm") return t;
  const word = COLD_MOD_WORD[mod];
  // Already names the modality? Leave it alone. Stem matches (no strict suffix)
  // so "nanobody", "antibodies", "macrocycles" etc. all count.
  const already = new RegExp(`(${word}|peptide|macrocyc|stapled|nanobod|antibod|biologic|\\bprotein)`, "i");
  if (already.test(t)) return t;
  return `${t} (${word} design)`;
}

interface ModuleCardProps {
  m: ColdModule;
  open: boolean;
  onToggle: () => void;
  onSeed: (text: string) => void;
}

function ModuleCard({ m, open, onToggle, onSeed }: ModuleCardProps) {
  const Icon = ICONS[m.icon];
  // Track / domain selection is local to the card and resets whenever the card
  // is opened afresh (the tabs remount because they only render while open).
  const [ti, setTi] = useState(0);
  const [domId, setDomId] = useState<string | null>(null);
  // Modality selection (design module only). Resets to small molecule.
  const [mod, setMod] = useState<ColdModality>("sm");
  const track = m.tracks[Math.min(ti, m.tracks.length - 1)];
  const selectedDomain = domId ? COLD_DOMAINS.find((d) => d.id === domId) ?? null : null;
  // For a modality-flagged module, seeding threads the picked modality into the
  // goal; otherwise onSeed is passed straight through.
  const seedFn = m.modalities ? (text: string) => onSeed(seedWithModality(text, mod)) : onSeed;
  // Examples switch per modality when the track carries exBy on a modality module.
  const trackExamples = m.modalities && track.exBy ? track.exBy[mod] ?? track.ex : track.ex;

  return (
    <div
      data-testid="cold-module-card"
      data-module-id={m.id}
      data-open={open ? "true" : "false"}
      style={{
        display: "flex",
        flexDirection: "column",
        border: `1px solid ${open ? "var(--bm-border-strong, oklch(0.80 0.01 260))" : "var(--bm-border, oklch(0.90 0.005 260))"}`,
        borderRadius: 12,
        background: "var(--bm-surface, oklch(0.99 0.002 260))",
        overflow: "hidden",
        gridColumn: open ? "1 / -1" : "auto",
      }}
    >
      <button
        type="button"
        data-testid="cold-module-expand"
        aria-expanded={open}
        onClick={onToggle}
        style={{
          display: "flex",
          alignItems: "flex-start",
          gap: 10,
          padding: 16,
          border: "none",
          background: "transparent",
          cursor: "pointer",
          textAlign: "left",
          width: "100%",
        }}
      >
        <span
          aria-hidden
          style={{
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            width: 30,
            height: 30,
            borderRadius: 8,
            background: "var(--bm-chip, oklch(0.95 0.01 260))",
            color: "var(--bm-primary, oklch(0.55 0.20 265))",
            flexShrink: 0,
          }}
        >
          <Icon size={16} />
        </span>
        <span style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0, flex: 1 }}>
          <span style={{ fontWeight: 600, fontSize: 'var(--fs-base)', color: "var(--bm-text, oklch(0.22 0.01 260))" }}>{t('cold_start.mod_' + m.id + '_name')}</span>
          {/* Reserve exactly 2 lines so 1- and 2-line descriptions give every
              collapsed card the same height — fixes the broken grid row where the
              design card overflowed its border (founder 2026-11-11). */}
          <span style={{
            fontSize: 'var(--fs-sm)', color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
            lineHeight: 1.5, minHeight: open ? undefined : '3em',
            display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
          }}>{t('cold_start.mod_' + m.id + '_desc')}</span>
        </span>
        <span
          aria-hidden
          style={{
            flexShrink: 0,
            color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
            display: "inline-flex",
            paddingTop: 2,
          }}
        >
          {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        </span>
      </button>

      {open && (
        <div
          data-testid="cold-module-body"
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 10,
            padding: "0 16px 16px",
          }}
        >
          {/* .trackbar — the module's tracks as UNDERLINE TABS (one idiom per
              hierarchy level — tabs switch the task track; the modality below is a
              segmented filter). Reworked 2026-11-11 (founder "two-layers weird" +
              Gemini review): two stacked pill rows read as a confusing 2D matrix. */}
          <div role="tablist" aria-label={t('cold_start.mod_' + m.id + '_name')}
            style={{ display: "flex", flexWrap: "wrap", gap: 2, borderBottom: "1px solid var(--bm-border, oklch(0.90 0.005 260))" }}>
            {m.tracks.map((tr, i) => {
              const on = i === ti;
              return (
                <button
                  key={tr.k}
                  type="button"
                  role="tab"
                  aria-selected={on}
                  data-testid={`cold-track-${tr.k.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "")}`}
                  onClick={() => {
                    setTi(i);
                    setDomId(null);
                  }}
                  style={{
                    padding: "6px 10px",
                    marginBottom: -1,
                    border: "none",
                    borderBottom: `2px solid ${on ? "var(--bm-primary, oklch(0.55 0.20 265))" : "transparent"}`,
                    background: "transparent",
                    color: on ? "var(--bm-primary, oklch(0.55 0.20 265))" : "var(--bm-text-dim, oklch(0.50 0.01 260))",
                    fontSize: 'var(--fs-sm)',
                    fontWeight: on ? 600 : 500,
                    cursor: "pointer",
                  }}
                >
                  {coldCopy(tr.k)}
                </button>
              );
            })}
          </div>

          {/* Modality row as a SEGMENTED CONTROL — only on a modality-flagged
              module (Design & generate). A single mutually-exclusive filter, visually
              distinct from the task tabs above (founder "two-layers weird" + Gemini). */}
          {m.modalities && (
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ fontSize: 'var(--fs-sm)', color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>{t('cold_start.modality')}</span>
              <div role="group" style={{ display: "inline-flex", background: "var(--bm-chip, oklch(0.96 0.005 260))", borderRadius: 8, padding: 2, gap: 2 }}>
                {COLD_MODALITIES.map(([k]) => {
                  const on = mod === k;
                  return (
                    <button
                      key={k}
                      type="button"
                      data-testid={`cold-modality-${k}`}
                      aria-pressed={on}
                      onClick={() => setMod(k)}
                      style={{
                        padding: "3px 12px",
                        borderRadius: 6,
                        border: "none",
                        background: on ? "var(--bm-surface, oklch(1 0 0))" : "transparent",
                        boxShadow: on ? "0 1px 2px oklch(0 0 0 / 0.08)" : "none",
                        color: on ? "var(--bm-text, oklch(0.22 0.01 260))" : "var(--bm-text-dim, oklch(0.50 0.01 260))",
                        fontSize: 'var(--fs-sm)',
                        fontWeight: on ? 600 : 500,
                        cursor: "pointer",
                      }}
                    >
                      {t('cold_start.modality_' + k)}
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* Helper caption sits directly above the examples it describes. */}
          <p className="text-xs text-muted-foreground" style={{ margin: 0 }}>
            {track.k === "Internal"
              ? t('cold_start.caption_internal')
              : track.k === "Try sample data"
                ? t('cold_start.caption_sample_data')
                : t('cold_start.caption_default')}
          </p>

          {/* .schip — domain chips, only inside a domains-track. Selecting one
              swaps the example list for that domain's shapes. */}
          {track.domains && (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              {COLD_DOMAINS.map((d) => {
                const on = domId === d.id;
                return (
                  <button
                    key={d.id}
                    type="button"
                    data-testid={`cold-domain-${d.id}`}
                    aria-pressed={on}
                    onClick={() => setDomId(on ? null : d.id)}
                    style={{
                      padding: "3px 10px",
                      borderRadius: 999,
                      border: `1px solid ${on ? "var(--bm-primary, oklch(0.55 0.20 265))" : "var(--bm-border, oklch(0.90 0.005 260))"}`,
                      background: on ? "var(--bm-chip, oklch(0.95 0.01 260))" : "transparent",
                      color: "var(--bm-text, oklch(0.22 0.01 260))",
                      fontSize: 'var(--fs-sm)',
                      fontWeight: 500,
                      cursor: "pointer",
                    }}
                  >
                    {coldCopy(d.name)}
                  </button>
                );
              })}
            </div>
          )}

          {/* The body: a selected domain shows shapes; otherwise the track's
              example intents. */}
          {selectedDomain ? (
            <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
              {selectedDomain.shapes.map((s) => (
                <ShapeRow key={s.t} shape={s} onSeed={seedFn} />
              ))}
            </div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
              {trackExamples.map((x) => (
                <ExampleRow key={x} text={x} onSeed={seedFn} />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** The cards shown on the landing — every function module, molecule design included. */
export function landingModules(): ColdModule[] {
  return COLD_MODULES;
}

export interface ColdStartDashboardProps {
  /** Seed the composer with a goal / example intent. Does not send. */
  onSeed: (text: string) => void;
  /** Cards to show; defaults to the landing set. */
  modules?: ColdModule[];
}

/**
 * The cold-start dashboard: a centred column with the intent bar on top and the
 * four function-module cards below. Cards expand/collapse with single-open
 * logic; all the dashboard does is seed the composer.
 */
export function ColdStartDashboard({ onSeed, modules = landingModules() }: ColdStartDashboardProps) {
  // Single-open: at most one module card open at a time (spec 00 §0.4.2).
  const [openId, setOpenId] = useState<string | null>(null);
  return (
    <div
      data-testid="cold-start-dashboard"
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 20,
        width: "100%",
        maxWidth: 792,
        margin: "0 auto",
        padding: "24px 0 8px",
        // Rebalance (2026-11-01): center the cold-start content in the available
        // canvas instead of pinning it to the top with a large empty void below.
        minHeight: "52vh",
        justifyContent: "center",
      }}
    >
      {/* Cold-start hero: just the framing heading. The "describe your goal" input
          was removed 2026-11-09 — it duplicated the always-present bottom composer.
          The heading now titles the module cards below; the single pinned composer
          is the only place to type, and the cards/example rows seed it on click. */}
      <div style={{ display: "flex", flexDirection: "column", gap: 14, alignItems: "center" }}>
        <span style={{ fontSize: 'var(--fs-xl)', textAlign: "center", fontWeight: 600, letterSpacing: "-0.02em", color: "var(--bm-text, oklch(0.22 0.01 260))" }}>
          {t('cold_start.heading')}
        </span>
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))",
          gap: 12,
          alignItems: "stretch",
        }}
      >
        {modules.map((m) => (
          <ModuleCard
            key={m.id}
            m={m}
            open={openId === m.id}
            onToggle={() => setOpenId((cur) => (cur === m.id ? null : m.id))}
            onSeed={onSeed}
          />
        ))}
      </div>
    </div>
  );
}

export default ColdStartDashboard;
