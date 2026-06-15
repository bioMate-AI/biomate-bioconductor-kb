/**
 * Canonical chain-step path resolver.
 *
 * Background: when the multi-step planner decomposes a request like
 * "complete RNA-seq pipeline from raw reads to GO enrichment" into
 * sequential steps, each step is routed independently through
 * generateForSingleIntent → workflow search. When a step's free-text
 * description doesn't tokenize well against the indexed workflow
 * names (e.g. "Perform quality control and adapter trimming on raw
 * RNA-seq FASTQ files." vs the indexed name "nf-core/fastqc"), the
 * per-step search returns nothing and the chain renders with
 * "(workflow path TBD)" on every step — exactly what wjunlin@HKU saw
 * in docs/20260610_REAL_USER_FULL_CHAT_LOGS.md.
 *
 * This module is a deterministic last-resort: take the step's
 * workflow_name (which the LLM phrases in plain English), pattern-match
 * it against known canonical steps, and return the production
 * nextflow_path. Same idea as canonical-fixtures.ts but for chain steps.
 *
 * Patterns must be conservative — only fire when the description
 * unambiguously names a single intent. The fallback is "return null"
 * which preserves the prior "(workflow path TBD)" behavior.
 */

export interface CanonicalChainStep {
  /** Regex that the step's workflow_name / description must match. */
  pattern: RegExp;
  /** Production nextflow_path that handles this step. */
  nextflow_path: string;
}

export const CANONICAL_CHAIN_STEPS: CanonicalChainStep[] = [
  // ── RNA-seq classical 4-step chain ──────────────────────────────────────
  {
    pattern: /(quality\s*control|qc).*\b(trim|adapter|fastq)\b|fastqc|fastp|trim[_ ]?galore|adapter\s+trim/i,
    nextflow_path: "nextflow_nfcore/rnaseq/main.nf",
  },
  {
    pattern: /\balign(ment)?\b.*\b(rna|reference|genome|read)\b|\bSTAR\b|\bHISAT2\b|\bsalmon\b|\bkallisto\b|quantify\s+gene\s+expression|gene[- ]level\s+quantif/i,
    nextflow_path: "nextflow_nfcore/rnaseq/main.nf",
  },
  // NOTE: limma rule comes first — it's the more specific case. The generic
  // "differential expression" rule below would otherwise win on any string
  // containing those words, routing microarray data to DESeq2 (issue #7).
  {
    pattern: /\b(microarray|limma)\b.*\bdifferential\b|\bdifferential\b.*\blimma\b|\blimma[- ]?voom\b/i,
    nextflow_path: "biomni_workflows/bioconductor/limma_microarray/main.nf",
  },
  {
    pattern: /\bdifferential\s+expression\b|\bDE(G|GS)?\s+analys|\bDESeq2\b|\bedgeR\b|count\s+matrix.*differential/i,
    nextflow_path: "nextflow_nfcore/differentialabundance/main.nf",
  },
  {
    pattern: /\bpathway.*enrichment|\bGO\s+term\s+enrichment|\bGSEA\b|gene\s+set\s+enrichment|clusterProfiler|enrichGO|enrichKEGG/i,
    nextflow_path: "biomni_workflows/bioconductor/clusterprofiler_enrichgo/main.nf",
  },

  // ── Variant calling chain ──────────────────────────────────────────────
  {
    pattern: /\bvariant\s+calling|\bSNP\b.*call|\bindel\b.*call|\bGATK\b|HaplotypeCaller|Mutect2|sarek/i,
    nextflow_path: "nf-core-pipelines/sarek/main.nf",
  },
  {
    pattern: /\bvariant\s+annotation|annotat.*variant|\bVEP\b|SnpEff|SnpSift/i,
    nextflow_path: "biomni_workflows/genomics/variant_annotation/main.nf",
  },

  // ── ChIP-seq / ATAC-seq ────────────────────────────────────────────────
  {
    pattern: /\bChIP[- ]?seq\b|peak\s+calling|MACS2|histone\s+modification/i,
    nextflow_path: "nf-core-pipelines/chipseq/main.nf",
  },
  {
    pattern: /\bATAC[- ]?seq\b|chromatin\s+accessibility/i,
    nextflow_path: "nf-core-pipelines/atacseq/main.nf",
  },
];

/**
 * Returns the canonical nextflow_path for a step description, or null
 * when no rule matches. Caller can then keep the existing
 * "(workflow path TBD)" UX for unmatched steps.
 */
export function resolveCanonicalChainStepPath(description: string): string | null {
  if (!description) return null;
  for (const rule of CANONICAL_CHAIN_STEPS) {
    if (rule.pattern.test(description)) return rule.nextflow_path;
  }
  return null;
}
