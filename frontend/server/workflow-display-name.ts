// The one place a workflow's user-facing name is derived. The workflow card
// (routes.ts `workflow_ready`) and the chat response that introduces it
// (galaxy-assistant.ts generateResponse) both use cardWorkflowName, so the name
// in the chat text and the card title cannot diverge.

const WORKFLOW_DISPLAY_NAMES: Record<string, string> = {
  allometric_scaling:         "Allometric Scaling / FIH Dose Prediction",
  clinical_trial_simulation:  "Clinical Trial Simulation",
  pbpk_pediatric:             "Pediatric PBPK Simulation",
  cyclic_peptide_design:      "Cyclic Peptide Design",
  magma_gene_analysis:        "MAGMA Gene-Set Analysis",
  clusterprofiler:            "ClusterProfiler Enrichment Analysis",
  deseq2:                     "DESeq2 Differential Expression",
  fcrn_antibody_pk:           "FcRn Antibody PK Simulation",
  lnp_formulation_optimization: "LNP Formulation Optimization",
  ich_s5_reproductive_tox:    "ICH S5 Reproductive Toxicology",
  ich_s7a_safety_pharmacology:"ICH S7A Safety Pharmacology",
  adaptive_trial_design:      "Adaptive Trial Design",
};

export function humanizeWorkflowName(name: string): string {
  if (!name) return name;
  const mapped = WORKFLOW_DISPLAY_NAMES[name.toLowerCase()];
  if (mapped) return mapped;
  // If the name is all-lowercase with underscores (slug), title-case it
  if (/^[a-z0-9_/-]+$/.test(name) && name.includes('_')) {
    return name.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  }
  return name;
}

/** The title the workflow card shows for a generate_workflow payload:
 *  workflow_ga.name (catalog) → workflow_name (Nextflow match) → chain_display_name
 *  (chain) → "" (composed workflow, name unknown yet). */
export function cardWorkflowName(payload: any): string {
  const ga = payload?.workflow_ga || {};
  return humanizeWorkflowName(ga.name || payload?.workflow_name || payload?.chain_display_name || "");
}
