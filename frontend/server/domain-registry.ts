/**
 * BioMate Canonical Domain Registry — TypeScript
 * ================================================
 * Single source of truth for domain definitions on the frontend.
 * Mirrors backend/lib/galaxy/ai/domain_registry.py
 *
 * CANONICAL SOURCE: domain_registry.py (Python).
 * When adding a new domain, update domain_registry.py first, then mirror here.
 *
 * Naming conventions:
 *   - Use underscore, never hyphen  (single_cell NOT single-cell)
 *   - Use drug_discovery, NOT pharmacology
 */

// ---------------------------------------------------------------------------
// 1. Canonical domain list — user-facing profile domains
// ---------------------------------------------------------------------------

export const CANONICAL_DOMAINS = [
  'genomics',
  'transcriptomics',
  'single_cell',
  'epigenomics',
  'proteomics',
  'metabolomics',
  'metagenomics',
  'structural_biology',
  'drug_discovery',
  'cryo_em',
  'systems_biology',
  'synthetic_biology',
  'bioimaging',
  'lab_automation',
] as const;

export type CanonicalDomain = typeof CANONICAL_DOMAINS[number];

// ---------------------------------------------------------------------------
// 2. Display labels (used by user domain profile UI)
// ---------------------------------------------------------------------------

export const DOMAIN_LABELS: Record<CanonicalDomain, string> = {
  genomics:          'Genomics',
  transcriptomics:   'Transcriptomics',
  single_cell:       'Single Cell',
  epigenomics:       'Epigenomics',
  proteomics:        'Proteomics',
  metabolomics:      'Metabolomics',
  metagenomics:      'Metagenomics',
  structural_biology: 'Structural Biology',
  drug_discovery:    'Drug Discovery & Pharmacology',
  cryo_em:           'Cryo-EM',
  systems_biology:   'Systems Biology',
  synthetic_biology: 'Synthetic Biology',
  bioimaging:        'Bioimaging',
  lab_automation:    'Lab Automation',
};

// ---------------------------------------------------------------------------
// 3. Technical sub-domains used by _inferDomainWithLLM()
//    These are a finer level of granularity than user profile domains.
//    They map back to canonical domains via SUBDOMAIN_TO_CANONICAL.
// ---------------------------------------------------------------------------

export const TECHNICAL_SUBDOMAINS = [
  'cryo_em',
  'rna_seq',
  'variant_calling_germline',
  'variant_calling_somatic',
  'single_cell',
  'epigenomics_chip',
  'epigenomics_atac',
  'proteomics',
  'drug_discovery',
  'metagenomics_16s',
  'metagenomics_shotgun',
  'methylation',
  'genome_assembly',
  'structural_biology',
] as const;

export type TechnicalSubdomain = typeof TECHNICAL_SUBDOMAINS[number];

// ---------------------------------------------------------------------------
// 4. Sub-domain → canonical domain mapping
// ---------------------------------------------------------------------------

export const SUBDOMAIN_TO_CANONICAL: Record<TechnicalSubdomain, CanonicalDomain> = {
  rna_seq:                  'transcriptomics',
  variant_calling_germline: 'genomics',
  variant_calling_somatic:  'genomics',
  genome_assembly:          'genomics',
  methylation:              'epigenomics',
  single_cell:              'single_cell',
  epigenomics_chip:         'epigenomics',
  epigenomics_atac:         'epigenomics',
  proteomics:               'proteomics',
  drug_discovery:           'drug_discovery',
  metagenomics_16s:         'metagenomics',
  metagenomics_shotgun:     'metagenomics',
  cryo_em:                  'cryo_em',
  structural_biology:       'structural_biology',
};

// ---------------------------------------------------------------------------
// 5. analyzeIntent() preferred_domains prompt string (canonical list)
//    Used in the LLM system prompt to constrain what domains it may return.
// ---------------------------------------------------------------------------

export const PREFERRED_DOMAINS_PROMPT_LIST = CANONICAL_DOMAINS.join(', ');
// → "genomics, transcriptomics, single_cell, epigenomics, proteomics, metabolomics,
//    metagenomics, structural_biology, drug_discovery, cryo_em, systems_biology,
//    synthetic_biology, bioimaging, lab_automation"
