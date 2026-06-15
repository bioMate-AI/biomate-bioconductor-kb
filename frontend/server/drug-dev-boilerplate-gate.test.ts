/**
 * Regression test for the pharma-boilerplate bleed bug surfaced by the
 * wjunlin@HKU production chat (docs/20260610_REAL_USER_FULL_CHAT_LOGS.md):
 * the filename `clinical_gse22055.csv` made the chat hallucinate
 * "docking, ADMET, or PK/NCA" follow-up questions on top of an RNA-seq
 * differential-expression answer. Root cause was an unanchored
 * `/clinical/` regex (plus `/pk/`, `/nca/`, `/auc/`) inside
 * enforceDrugDevelopmentResponseQuality.
 *
 * This test pokes the gating regex directly via a tiny inline replica
 * (kept in sync with galaxy-assistant.ts) so we don't need DATABASE_URL
 * to exercise the class. If the production regex drifts away from the
 * one here, fix both together.
 */
import { describe, expect, it } from "vitest";

const _drugDevTerms = /\b(drug|admet|herg|dili|toxicity|docking|ligand|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|ic50|ec50)\b/i;
const _pkWord = /(?:^|[^a-z])pk(?:[^a-z]|$)/i;
const _clinicalCtx = /\bclinical\s+(?:trial|study|phase|protocol|dose|dosing|escalation|pharmacology)\b/i;
const _genomicsContext = /\b(rna[- ]?seq|scrna|single[- ]?cell|deg|deseq2|edger|limma|geo|gse\d+|srr\d+|ensembl|fastq|bam|vcf|variant|gwas|cryo[- ]?em|microarray|differential\s+expression|count\s+matrix|volcano|gtf|gff|genome\s+assembly|chip[- ]?seq|atac[- ]?seq|methyl[- ]?seq)\b/i;

function shouldApplyDrugDevBoilerplate(userMessage: string): boolean {
  if (_genomicsContext.test(userMessage)) return false;
  return _drugDevTerms.test(userMessage) || _pkWord.test(userMessage) || _clinicalCtx.test(userMessage);
}

describe("drug-dev boilerplate gate (regression: wjunlin@hku clinical_gse22055.csv bleed)", () => {
  it("does NOT trigger on RNA-seq + clinical_gse22055.csv filename", () => {
    expect(shouldApplyDrugDevBoilerplate(
      "[Galaxy dataset: gse22055_expression.csv] is expression matrix and " +
      "[Galaxy dataset: clinical_gse22055.csv] is Sample metadata file. Run DEG"
    )).toBe(false);
  });

  it("does NOT trigger on plain 'tumor vs normal' DEG request", () => {
    expect(shouldApplyDrugDevBoilerplate("DEG: tumor vs. normal, GEO accession=GSE22055")).toBe(false);
  });

  it("does NOT trigger on RNA-seq pipeline request", () => {
    expect(shouldApplyDrugDevBoilerplate(
      "I have RNA-seq data from a cancer study and need to perform differential expression analysis."
    )).toBe(false);
  });

  it("does NOT trigger on 'clinical metadata' as a noun-phrase (no trial/dose/phase)", () => {
    expect(shouldApplyDrugDevBoilerplate("Use the clinical metadata column to set the contrast")).toBe(false);
  });

  it("does NOT trigger on bare substrings (pk inside other words, nca inside cancer)", () => {
    expect(shouldApplyDrugDevBoilerplate("the spkike protein analysis")).toBe(false);
    expect(shouldApplyDrugDevBoilerplate("pancreatic cancer DESeq2 run")).toBe(false);
  });

  it("DOES trigger on genuine ADMET request", () => {
    expect(shouldApplyDrugDevBoilerplate("Run ADMET profiling on this SMILES")).toBe(true);
  });

  it("DOES trigger on genuine PK/NCA terms as standalone words", () => {
    expect(shouldApplyDrugDevBoilerplate("compute AUC and Cmax from this concentration-time table")).toBe(true);
    expect(shouldApplyDrugDevBoilerplate("run NCA on the PK profile")).toBe(true);
  });

  it("DOES trigger on real clinical-trial context", () => {
    expect(shouldApplyDrugDevBoilerplate("design a Phase 2 clinical trial with BOIN dose escalation")).toBe(true);
  });

  it("DOES trigger on hERG / DILI toxicity gates", () => {
    expect(shouldApplyDrugDevBoilerplate("predict hERG and DILI for this compound")).toBe(true);
  });

  it("genomics-context escape hatch beats a coincidental pharma term", () => {
    // Edge case: someone says "RNA-seq + DILI gene expression" — genomics wins,
    // we don't want to corrupt the DEG answer with PK/NCA follow-ups.
    expect(shouldApplyDrugDevBoilerplate("RNA-seq differential expression of DILI biomarker genes")).toBe(false);
  });
});
