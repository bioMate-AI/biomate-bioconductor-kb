import { useState, useEffect, useCallback } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Brain, Database, CheckSquare, Square, Plug } from 'lucide-react';
import {
  ResidencyBadge, ScopeSelector, NOT_DECLARED, runsInFromResidency,
  type Residency, type Scope, type DeclaredFacts,
} from './connector-residency';
import { PrivateDbConnectionForm } from './private-db-connection-form';
import { AddConnectorFlow } from './add-connector-flow';
import { SettingsDialog } from './settings-dialog';
import { normalizeSkillPack, type SkillPack } from './skills-selector';
import { InstrumentsSection } from './instruments-section';
import { CONNECTOR_INSTRUMENTS_ENABLED } from '@/lib/feature-flags';
import { McpServerForm } from './mcp-server-form';
import { RegisterModelForm } from './register-model-form';
import { tOr } from '@/lib/i18n';
import { HintTip } from '@/components/ui/hint-tip';
import { ImportSkillForm } from './import-skill-form';
import { AddSkillForm } from './add-skill-form';

const ACTIVE_DBS_KEY = 'biomate-active-databases';
const CONNECTOR_SCOPES_KEY = 'biomate-connector-scopes';

// Per-connector scope (§0.9.2). One library, one state: the selection is
// persisted and read back — the dialog does not keep a private list.
function loadConnectorScopes(): Record<string, Scope> {
  try { return JSON.parse(localStorage.getItem(CONNECTOR_SCOPES_KEY) || '{}'); } catch { return {}; }
}
function saveConnectorScopes(scopes: Record<string, Scope>) {
  localStorage.setItem(CONNECTOR_SCOPES_KEY, JSON.stringify(scopes));
}

function loadActiveDbs(allNames: string[]): string[] {
  try {
    const stored = localStorage.getItem(ACTIVE_DBS_KEY);
    if (stored === null) return allNames; // default: all selected
    return JSON.parse(stored);
  } catch { return allNames; }
}
function saveActiveDbs(names: string[]) {
  localStorage.setItem(ACTIVE_DBS_KEY, JSON.stringify(names));
}

interface Connector extends DeclaredFacts {
  name: string;
  category: string;
  description: string;
  // Declared facts (§0.9.1): residency, needs, produces, runsIn — all optional.
  // Absent facts render as an honest "not declared" / "unspecified", never guessed.
}

// Default scope shown for a source (§0.9.2 display). NOTE: scope is an
// informational preview only — nothing in BioMate enforces it and no backend
// reads `biomate-connector-scopes`. BioMate queries whichever public sources a
// chat request needs regardless of what is shown here. The selector persists the
// user's stated preference locally so the UI is stable, not because it gates access.
const DEFAULT_SCOPE: Scope = 'account';

type TabId = 'databases' | 'ai' | 'yours' | 'instruments' | 'skills' | 'mcp' | 'model';

// NOTE: A "Skills" tab (upload / activate .md skill files) was scaffolded here but
// removed — no backend read the selection (`/api/skills` returned nothing and
// nothing consumed `biomate-active-skills`), so it implied an activation capability
// that did not exist. Do not re-add it as a facade; wire a real endpoint first.

// ── Scientific databases ───────────────────────────────────────────────────────

// Every entry below is a remote public database or web API: a query is sent out
// of the estate to retrieve the answer. That makes `cloud` a genuine DECLARED
// fact for the whole list (§0.9.1 residency), not a guess — so it is stamped
// uniformly by `withDbFacts` rather than hand-repeated on 60 rows. Where a source
// declares nothing further (no per-row needs/produces), those facts stay absent
// and render as an honest "not declared".
const DB_RAW: Connector[] = [
  // Protein & Structure
  { name: 'UniProt / Swiss-Prot', category: 'Protein', description: 'Protein sequences, function, variants, and disease associations' },
  { name: 'PDB / RCSB', category: 'Structure', description: 'Experimental 3D protein and ligand structures' },
  { name: 'AlphaFold DB', category: 'Structure', description: 'AI-predicted protein structures with per-residue confidence scores' },
  { name: 'EMDB', category: 'Structure', description: 'Cryo-EM density maps and fitting models' },
  { name: 'InterPro', category: 'Protein', description: 'Protein domain architecture and family classification' },
  { name: 'STRING', category: 'Protein', description: 'Protein–protein interaction networks with confidence scores' },
  // Genomics & Variants
  { name: 'Ensembl', category: 'Genomics', description: 'Gene annotation, transcripts, and variant consequences across 300+ species' },
  { name: 'NCBI Gene', category: 'Genomics', description: 'Gene summaries, location, and cross-references' },
  { name: 'NCBI RefSeq', category: 'Genomics', description: 'Curated reference sequences for genomes, transcripts, and proteins' },
  { name: 'gnomAD', category: 'Variants', description: 'Population allele frequencies from 125,000+ diverse exomes and genomes' },
  { name: 'ClinVar', category: 'Variants', description: 'Clinical variant classifications and pathogenicity verdicts' },
  { name: 'dbSNP', category: 'Variants', description: 'Variant identifiers (rs numbers) and allele frequencies' },
  { name: 'GWAS Catalog', category: 'Variants', description: 'Trait–variant associations and GWAS summary statistics' },
  { name: 'COSMIC', category: 'Variants', description: 'Somatic mutations, gene fusions, and copy-number signatures in cancer' },
  { name: 'iGenomes (AWS S3)', category: 'Reference', description: 'Pre-built genome indices, annotation GTFs, and GATK resource bundles' },
  // Omics Archives
  { name: 'GEO (NCBI)', category: 'Omics Archive', description: 'Gene expression datasets — series metadata, sample tables, and matrices' },
  { name: 'SRA (NCBI)', category: 'Omics Archive', description: 'Raw sequencing runs in FASTQ; direct download by accession' },
  { name: 'ENA (EBI)', category: 'Omics Archive', description: 'European mirror of SRA with EBI-curated metadata' },
  { name: 'ArrayExpress (EBI)', category: 'Omics Archive', description: 'Functional genomics archive for microarray and sequencing studies' },
  { name: 'PRIDE (EBI)', category: 'Omics Archive', description: 'ProteomeXchange proteomics data — raw spectra and search results' },
  { name: 'EGA', category: 'Omics Archive', description: 'Controlled-access genomic and phenotypic data' },
  { name: 'Metabolights (EBI)', category: 'Omics Archive', description: 'Metabolomics studies and LC-MS spectra' },
  { name: 'OmicsDI', category: 'Omics Archive', description: 'Cross-repository omics dataset discovery across GEO, PRIDE, and more' },
  { name: 'SYNAPSE (Sage Bionetworks)', category: 'Omics Archive', description: 'Open biomedical datasets — TCGA, ROSMAP, AD Knowledge Portal' },
  { name: 'MGnify (EBI)', category: 'Omics Archive', description: 'Metagenomics assemblies and annotations for microbiome workflows' },
  // Chemical & Drug
  { name: 'ChEMBL', category: 'Chemical / Drug', description: 'Bioactivity data and drug-likeness metrics for 2M+ compounds' },
  { name: 'ChEBI (EBI)', category: 'Chemical / Drug', description: 'Chemical identity, SMILES, InChI keys, and ontology classification' },
  { name: 'PubChem (NCBI)', category: 'Chemical / Drug', description: 'Compound structures, bioassay data, and SMILES lookups' },
  { name: 'DrugBank', category: 'Chemical / Drug', description: 'Drug mechanism, pharmacokinetics, targets, and approved indications' },
  { name: 'GTOPDB', category: 'Chemical / Drug', description: 'Pharmacology targets and ligand–receptor binding data' },
  { name: 'PharmGKB', category: 'Chemical / Drug', description: 'Genetic variants linked to drug response and dosing guidelines' },
  { name: 'MaveDB', category: 'Chemical / Drug', description: 'Deep mutational scanning scores for variant effect interpretation' },
  // Pathways & Ontologies
  { name: 'KEGG', category: 'Pathways', description: 'Metabolic and signalling pathway maps with gene-to-pathway membership' },
  { name: 'Reactome', category: 'Pathways', description: 'Curated pathway hierarchy for enrichment analysis' },
  { name: 'BRENDA', category: 'Pathways', description: 'Enzyme kinetics and functional annotations for metabolic modelling' },
  { name: 'Gene Ontology (GO)', category: 'Ontology', description: 'Biological process, molecular function, and cellular component terms' },
  { name: 'HPO', category: 'Ontology', description: 'Standardised phenotype terms for rare disease genomics' },
  { name: 'OMIM', category: 'Ontology', description: 'Genetic basis of inherited diseases and phenotype-to-gene mapping' },
  { name: 'Monarch Initiative', category: 'Ontology', description: 'Cross-species phenotype–gene associations for comparative genomics' },
  // Disease & Clinical
  { name: 'Open Targets', category: 'Disease / Target', description: 'Target–disease association scores across 60,000+ targets' },
  { name: 'cBioPortal / TCGA', category: 'Disease / Target', description: 'Mutation, copy number, and expression data across 300+ cancer studies' },
  { name: 'DisGeNET', category: 'Disease / Target', description: 'Curated gene–disease associations with evidence scores' },
  { name: 'ClinicalTrials.gov', category: 'Clinical', description: 'Active and completed clinical trials by target, indication, or phase' },
  { name: 'OpenFDA', category: 'Clinical', description: 'FDA adverse event reports, drug labels, and approval history' },
  { name: 'IEDB', category: 'Immunology', description: 'T-cell and B-cell epitope binding assays and MHC restriction data' },
  { name: 'NetMHCpan / NetMHCIIpan', category: 'Immunology', description: 'MHC-I and MHC-II binding affinity predictions for neoantigen design' },
  { name: 'iReceptor', category: 'Immunology', description: 'BCR and TCR repertoire sequences across studies and disease cohorts' },
  // Epigenomics & Expression
  { name: 'JASPAR', category: 'Epigenomics', description: 'Transcription factor binding matrices for motif scanning' },
  { name: 'REGULOMEDB', category: 'Epigenomics', description: 'Regulatory variant annotation from TF binding and eQTL evidence' },
  { name: 'REMAP', category: 'Epigenomics', description: 'ChIP-seq and ATAC-seq regulatory regions across many cell types' },
  { name: 'miRBase', category: 'Epigenomics', description: 'microRNA sequences and annotation for small RNA-seq workflows' },
  { name: 'Rfam', category: 'Epigenomics', description: 'Non-coding RNA families and covariance models' },
  { name: 'GTEx', category: 'Expression', description: 'Tissue-specific expression and eQTLs across 54 human tissues' },
  { name: 'UCSC Genome Browser', category: 'Expression', description: 'Genome annotation tracks — conservation, regulatory, and repeat elements' },
  // Literature
  { name: 'PubMed (NCBI)', category: 'Literature', description: 'Publication abstracts and MeSH terms for live literature search' },
  { name: 'bioRxiv / medRxiv / arXiv', category: 'Literature', description: 'Preprint servers for biology, medicine, and computational science' },
  { name: 'Europe PMC', category: 'Literature', description: 'Open-access literature with full-text search and grant linkage' },
  { name: 'Semantic Scholar', category: 'Literature', description: 'Citation graph and semantic search across 200M+ scientific papers' },
  // Other
  { name: 'IDR / OMERO', category: 'Imaging', description: 'High-content imaging datasets and phenotypic screen results' },
  { name: 'WORMS / IUCN', category: 'Ecology', description: 'Marine species taxonomy and conservation status' },
  { name: 'Paleobiology Database', category: 'Ecology', description: 'Fossil occurrence records and stratigraphic range data' },
  { name: 'Worldclim', category: 'Ecology', description: 'Global climate rasters for species distribution modelling' },
  { name: 'ENCODE QC Metrics', category: 'Standards', description: 'QC thresholds for RNA-seq, ChIP-seq, and ATAC-seq pipelines' },
  { name: 'GATK Best Practices', category: 'Standards', description: 'Variant calling guidelines and truth resource bundles from Broad' },
];

// Stamp the uniform declared fact: remote public source → cloud residency.
// `needs`/`produces`/`runsIn` remain absent (rendered "not declared") because the
// list does not declare per-source connection scopes or output artifacts.
const DB: Connector[] = DB_RAW.map(d => ({ residency: 'cloud' as Residency, ...d }));

// ── Database category groups (for sub-tabs) ──────────────────────────────────

const DB_GROUPS: { label: string; categories: string[] }[] = [
  { label: 'All',                  categories: [] },
  { label: 'Protein & Structure',  categories: ['Protein', 'Structure'] },
  { label: 'Genomics & Variants',  categories: ['Genomics', 'Variants', 'Reference'] },
  { label: 'Omics Archives',       categories: ['Omics Archive'] },
  { label: 'Chemical & Drug',      categories: ['Chemical / Drug'] },
  { label: 'Pathways & Ontology',  categories: ['Pathways', 'Ontology'] },
  { label: 'Disease & Clinical',   categories: ['Disease / Target', 'Clinical', 'Immunology'] },
  { label: 'Epigenomics',          categories: ['Epigenomics', 'Expression'] },
  { label: 'Literature',           categories: ['Literature'] },
  { label: 'Other',                categories: ['Imaging', 'Ecology', 'Standards'] },
];

// ── AI models & platform connectors ───────────────────────────────────────────

// Residency here is genuinely per-connector (a hosted LLM leaves the estate; a
// self-hosted runner never does), so it is declared per row. `needs`/`produces`
// are declared where they are real facts; left absent (→ "not declared") elsewhere.
const AI: Connector[] = [
  { name: 'Anthropic Claude', category: 'LLM', description: 'Primary model for workflow generation, QC analysis, and scientific planning',
    residency: 'cloud', needs: 'API key', produces: 'text completions', runsIn: 'Anthropic-hosted endpoint' },
  { name: 'Google Gemini', category: 'LLM', description: 'Alternative backbone for long-context and multimodal tasks',
    residency: 'cloud', needs: 'API key', produces: 'text completions', runsIn: 'Google-hosted endpoint' },
  { name: 'OpenAI GPT', category: 'LLM', description: 'Fallback LLM for completions and embeddings',
    residency: 'cloud', needs: 'API key', produces: 'completions and embeddings', runsIn: 'OpenAI-hosted endpoint' },
  { name: 'Ollama', category: 'Local LLM', description: 'Self-hosted model runner for air-gapped deployments',
    residency: 'local', needs: 'local Ollama daemon', produces: 'text completions', runsIn: 'this host — never leaves' },
  { name: 'ChatGPT (GPT Actions)', category: 'AI Platform', description: 'Expose BioMate as a custom GPT action in ChatGPT',
    residency: 'cloud', needs: 'GPT Action manifest + auth', runsIn: 'ChatGPT-hosted' },
  { name: 'Cursor', category: 'AI Platform', description: 'MCP connector — run workflows from within the Cursor IDE',
    residency: 'local', needs: 'MCP endpoint', runsIn: 'the Cursor IDE on your host' },
  { name: 'Coze', category: 'AI Platform', description: 'Plugin connector for building bioscience bots on the Coze platform',
    residency: 'cloud', needs: 'plugin credentials', runsIn: 'Coze-hosted' },
  { name: 'Open-Claw', category: 'AI Platform', description: 'Open-source agent framework integration' },
  { name: 'Slack', category: 'Messaging', description: 'Trigger workflows and receive run alerts in Slack channels',
    residency: 'cloud', needs: 'workspace OAuth token', runsIn: 'Slack-hosted' },
  { name: 'Telegram', category: 'Messaging', description: 'Run BioMate sessions and receive results via Telegram bot',
    residency: 'cloud', needs: 'bot token', runsIn: 'Telegram-hosted' },
  { name: 'WeChat / Feishu', category: 'Messaging', description: 'WeChat and Feishu bot connectors for teams in China',
    residency: 'cloud', needs: 'bot credentials', runsIn: 'WeChat / Feishu-hosted' },
];

// ── Helpers ────────────────────────────────────────────────────────────────────

// One declared fact rendered as "label: value", honest "not declared" when absent.
function DeclaredFact({ label, value }: { label: string; value?: string }) {
  const declared = !!value;
  return (
    <span
      data-testid={`fact-${label}`}
      data-declared={declared ? 'yes' : 'no'}
      style={{ fontSize: 'var(--fs-micro)', color: 'var(--muted-foreground)', whiteSpace: 'nowrap' }}
    >
      <span style={{ opacity: 0.7 }}>{label}:</span>{' '}
      <span style={{ fontStyle: declared ? 'normal' : 'italic', opacity: declared ? 1 : 0.7 }}>
        {declared ? value : NOT_DECLARED}
      </span>
    </span>
  );
}

function ConnectorTable({
  rows, selected, onToggle, scopes, onScopeChange, compact = false,
}: {
  compact?: boolean;
  rows: Connector[];
  selected?: string[];
  onToggle?: (name: string) => void;
  scopes: Record<string, Scope>;
  onScopeChange: (name: string, scope: Scope) => void;
}) {
  // Embedded surface: a bordered card with zebra-striped rows, mirroring the
  // reference `.card2` / `.connrow` treatment (data_centroid_design_v2). Even
  // rows get a subtle edge-to-edge band (--bm-surface-2, dark-mode safe) so a
  // wide row stays followable across; horizontal padding lives on the rows so
  // the band spans the full card width.
  if (compact) return <div className="p-5"><div className="rounded-lg border border-border bg-background overflow-hidden" data-testid="connector-table">{rows.map((row, i) => <article key={row.name} data-testid={`connector-row-${row.name}`} className="grid grid-cols-[minmax(0,1fr)_auto] sm:grid-cols-[minmax(0,1fr)_auto_auto] gap-3 items-center px-4 py-3 border-b border-border last:border-0" style={{ background: i % 2 === 1 ? 'var(--bm-surface-2)' : 'transparent' }}><div className="min-w-0"><h3 className="text-fs-base font-semibold">{row.name}</h3><p className="text-xs text-muted-foreground mt-1">{row.description}</p>{row.needs && <p className="text-xs text-muted-foreground mt-1">Requires {row.needs}</p>}</div><ResidencyBadge residency={row.residency} /><span className="text-fs-xs text-muted-foreground">{row.category}</span></article>)}</div></div>;
  const checkable = !!onToggle;
  return (
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--fs-meta)' }} data-testid="connector-table">
      <thead>
        <tr style={{ borderBottom: '1px solid var(--border)' }}>
          {checkable && <th style={{ width: 36, padding: '6px 4px 6px 12px' }} />}
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 'var(--fs-micro)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 200 }}>Name</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 'var(--fs-micro)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 120 }}>Category</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 'var(--fs-micro)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 96 }}>Residency</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 'var(--fs-micro)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600 }}>Declared facts</th>
          <th
            title="A preference for how widely you would scope this source (account / project / request). Informational only — scope is not enforced yet; BioMate queries public sources as each chat request needs them."
            style={{ textAlign: 'left', padding: '6px 12px', fontSize: 'var(--fs-micro)', textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 180 }}
          >Scope (preview)</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row, i) => {
          const active = selected?.includes(row.name) ?? false;
          const scope = scopes[row.name] || DEFAULT_SCOPE;
          return (
            <tr
              key={row.name}
              data-testid={`connector-row-${row.name}`}
              onClick={checkable ? () => onToggle?.(row.name) : undefined}
              style={{ borderBottom: i < rows.length - 1 ? '1px solid var(--border)' : 'none', cursor: checkable ? 'pointer' : 'default', background: active ? 'oklch(0.97 0.01 260 / 0.5)' : 'transparent' }}
            >
              {checkable && (
                <td style={{ padding: '8px 4px 8px 12px', verticalAlign: 'middle' }}>
                  {active
                    ? <CheckSquare style={{ width: 14, height: 14, color: 'var(--primary)' }} />
                    : <Square style={{ width: 14, height: 14, color: 'var(--muted-foreground)', opacity: 0.4 }} />}
                </td>
              )}
              <td style={{ padding: '8px 12px', fontWeight: active ? 600 : 500, verticalAlign: 'top', color: 'var(--foreground)' }}>
                <div>{row.name}</div>
                <div style={{ fontSize: 'var(--fs-micro)', color: 'var(--muted-foreground)', fontWeight: 400, marginTop: 2, lineHeight: 1.4 }}>{row.description}</div>
              </td>
              <td style={{ padding: '8px 12px', verticalAlign: 'top', whiteSpace: 'nowrap' }}>
                <span style={{ fontSize: 'var(--fs-micro)', padding: '2px 7px', borderRadius: 4, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>{row.category}</span>
              </td>
              {/* Residency (§0.9.3) — on every row, honest "unspecified" when undeclared */}
              <td style={{ padding: '8px 12px', verticalAlign: 'top' }}>
                <ResidencyBadge residency={row.residency} />
              </td>
              {/* Declared facts (§0.9.1) — needs / produces / where-it-runs */}
              <td style={{ padding: '8px 12px', verticalAlign: 'top' }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, lineHeight: 1.4 }}>
                  <DeclaredFact label="needs" value={row.needs} />
                  <DeclaredFact label="produces" value={row.produces} />
                  <DeclaredFact label="where it runs" value={row.runsIn ?? runsInFromResidency(row.residency)} />
                </div>
              </td>
              {/* Three scopes (§0.9.2) — account / project / request; one library, one state */}
              <td style={{ padding: '8px 12px', verticalAlign: 'top' }}>
                <ScopeSelector
                  idBase={row.name}
                  scope={scope}
                  onChange={s => onScopeChange(row.name, s)}
                />
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function DatabasesTab({
  selected, onToggle, scopes, onScopeChange, compact = false,
}: {
  compact?: boolean;
  selected: string[];
  onToggle: (name: string) => void;
  scopes: Record<string, Scope>;
  onScopeChange: (name: string, scope: Scope) => void;
}) {
  const [groupLabel, setGroupLabel] = useState('All');

  const group = DB_GROUPS.find(g => g.label === groupLabel) || DB_GROUPS[0];
  const rows = group.categories.length === 0
    ? DB
    : DB.filter(r => group.categories.includes(r.category));

  const groupCount = (g: typeof DB_GROUPS[0]) =>
    g.categories.length === 0 ? DB.length : DB.filter(r => g.categories.includes(r.category)).length;

  const groupSelected = (g: typeof DB_GROUPS[0]) => {
    const relevant = g.categories.length === 0 ? DB : DB.filter(r => g.categories.includes(r.category));
    return relevant.filter(r => selected.includes(r.name)).length;
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Sub-tabs */}
      <div style={{ display: 'flex', overflowX: 'auto', borderBottom: '1px solid var(--border)', background: 'var(--muted)', padding: '0 12px', gap: 2, flexShrink: 0, scrollbarWidth: 'none' }}>
        {DB_GROUPS.map(g => {
          const sel = groupSelected(g);
          const active = g.label === groupLabel;
          return (
            <button
              key={g.label}
              onClick={() => setGroupLabel(g.label)}
              style={{
                display: 'inline-flex', alignItems: 'center', gap: 5,
                padding: '6px 10px', border: 'none', cursor: 'pointer', whiteSpace: 'nowrap',
                fontSize: 'var(--fs-meta)', fontWeight: active ? 600 : 400,
                color: active ? 'var(--foreground)' : 'var(--muted-foreground)',
                background: 'transparent',
                borderBottom: active ? '2px solid var(--foreground)' : '2px solid transparent',
                marginBottom: -1,
              }}
            >
              {g.label}
              <span style={{ fontSize: 'var(--fs-xs)', padding: '0 4px', borderRadius: 3, background: active ? 'var(--foreground)' : 'var(--border)', color: active ? 'var(--background)' : 'var(--muted-foreground)' }}>
                {groupCount(g)}
              </span>
              {sel > 0 && (
                <span style={{ fontSize: 'var(--fs-xs)', padding: '0 4px', borderRadius: 3, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}>
                  {sel}✓
                </span>
              )}
            </button>
          );
        })}
      </div>
      <ConnectorTable compact={compact} rows={rows} selected={selected} onToggle={onToggle} scopes={scopes} onScopeChange={onScopeChange} />
    </div>
  );
}

// ── Your connections tab ─────────────────────────────────────────────────────

// This is the ONE genuinely writable surface in the dialog. Unlike the public
// databases and AI/platform tabs — which are an honest READ-ONLY reference
// directory (nothing to connect or switch on there) — this tab connects the
// user's OWN private database and MCP server via real backend endpoints. Keep the
// distinction sharp: the copy here says "connect", the reference tabs never do.
function YourConnectionsTab() {
  const [section, setSection] = useState<'db' | 'mcp'>('db');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }} data-testid="your-connections-tab">
      {/* Sub-tabs: Private databases | MCP servers */}
      <div style={{ display: 'flex', borderBottom: '1px solid var(--border)', background: 'var(--muted)', padding: '0 12px', gap: 2, flexShrink: 0 }}>
        {([['db', 'Private databases'], ['mcp', 'MCP servers']] as const).map(([id, label]) => {
          const active = section === id;
          return (
            <button
              key={id}
              data-testid={`your-connections-sub-${id}`}
              onClick={() => setSection(id)}
              style={{
                padding: '6px 10px', border: 'none', cursor: 'pointer', whiteSpace: 'nowrap',
                fontSize: 'var(--fs-meta)', fontWeight: active ? 600 : 400,
                color: active ? 'var(--foreground)' : 'var(--muted-foreground)',
                background: 'transparent',
                borderBottom: active ? '2px solid var(--foreground)' : '2px solid transparent',
                marginBottom: -1,
              }}
            >
              {label}
            </button>
          );
        })}
      </div>
      <div style={{ padding: 16 }}>
        {section === 'db' && <PrivateDbConnectionForm />}
        {section === 'mcp' && <McpServerForm />}
      </div>
    </div>
  );
}

// ── Tab config ─────────────────────────────────────────────────────────────────

const TABS: { id: TabId; label: string; icon: React.ReactNode; count?: number; tip: string }[] = [
  { id: 'databases', label: 'Data sources',   icon: <Database style={{ width: 13, height: 13 }} />, count: DB.length, tip: 'Public protein, genomics, omics, chemical, pathway, disease, literature, and imaging sources BioMate can query from chat' },
  { id: 'ai',        label: 'Models & LLMs',      icon: <Brain    style={{ width: 13, height: 13 }} />, count: AI.length, tip: 'LLM providers and messaging / IDE surfaces BioMate exposes — reference only, not configured here' },
  { id: 'skills', label: 'Skills & experts', icon: <Brain style={{ width: 13, height: 13 }} />, tip: 'Available expert packs; select packs for a request in the chat composer' },
  { id: 'mcp', label: 'MCP servers', icon: <Plug style={{ width: 13, height: 13 }} />, tip: 'Manage your MCP server connections' },
  { id: 'yours',     label: 'Private databases',    icon: <Plug     style={{ width: 13, height: 13 }} />,                   tip: 'Connect your OWN private database and MCP server — the one writable surface here, backed by real endpoints' },
  { id: 'instruments', label: 'Instruments', icon: <Database style={{ width: 13, height: 13 }} />, tip: 'Manage laboratory instruments and data feeds' },
  // A "Skills" tab was removed, not merely hidden: no backend read its selection,
  // so it advertised an activation capability that did not exist. Add a real
  // endpoint before re-introducing it — do not restore the facade.
];

// ── Dialog ─────────────────────────────────────────────────────────────────────

interface ConnectorsDialogProps {
  embedded?: boolean;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ConnectorsDialog({ open, onOpenChange, embedded = false }: ConnectorsDialogProps) {
  const [sourceView, setSourceView] = useState<'public' | 'private' | 'instruments'>('public');
  const [adding, setAdding] = useState(false);
  const [setupOrigin, setSetupOrigin] = useState<{tab: TabId; view: 'public' | 'private' | 'instruments'} | null>(null);
  const beginAdding = () => { setSetupOrigin({ tab: activeTab, view: sourceView }); setAdding(true); };
  const cancelAdding = () => { if (setupOrigin) { setActiveTab(setupOrigin.tab); setSourceView(setupOrigin.view); } setSetupOrigin(null); setAdding(false); };
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [packs, setPacks] = useState<SkillPack[] | null>(null);
  const [packsError, setPacksError] = useState(false);
  const [activeTab, setActiveTab] = useState<TabId>('databases');
  const loadPacks = useCallback(() => {
    setPacksError(false);
    return fetch('/api/skills', { credentials: 'include' })
      .then(r => { if (!r.ok) throw new Error('skills'); return r.json(); })
      .then(d => setPacks((d.skills || []).map(normalizeSkillPack)))
      .catch(() => setPacksError(true));
  }, []);
  useEffect(() => {
    if (!open || activeTab !== 'skills') return;
    void loadPacks();
  }, [open, activeTab, loadPacks]);
  const [selectedDbs, setSelectedDbs] = useState<string[]>(() => loadActiveDbs(DB.map(d => d.name)));
  // Three scopes (§0.9.2): one library, one state — the selector writes it, both
  // tabs read it. Persisted so the "connected once, switched per project" choice survives.
  const [scopes, setScopes] = useState<Record<string, Scope>>(loadConnectorScopes);

  const toggleDb = useCallback((name: string) => {
    setSelectedDbs(prev => {
      const next = prev.includes(name) ? prev.filter(n => n !== name) : [...prev, name];
      saveActiveDbs(next);
      return next;
    });
  }, []);

  const setScope = useCallback((name: string, scope: Scope) => {
    setScopes(prev => {
      const next = { ...prev, [name]: scope };
      saveConnectorScopes(next);
      return next;
    });
  }, []);

  // The row checkbox is a personal reference shortlist stored in this browser only
  // (localStorage). BioMate always queries whichever public sources a chat request
  // needs — starring here does NOT enable, disable, or scope a source. The copy
  // says so plainly so no one thinks a click connected or activated anything.
  const dbFooter = selectedDbs.length === DB.length
    ? <>All {DB.length} sources listed — BioMate queries whichever your request needs. <button onClick={() => { saveActiveDbs([]); setSelectedDbs([]); }} style={{ fontSize: 'var(--fs-micro)', color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Clear your stars</button></>
    : selectedDbs.length > 0
      ? <><strong>{selectedDbs.length}</strong> of {DB.length} sources starred for your reference (local view filter — does not change what BioMate queries). <button onClick={() => { const all = DB.map(d => d.name); saveActiveDbs(all); setSelectedDbs(all); }} style={{ fontSize: 'var(--fs-micro)', color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Star all</button></>
      : <>{DB.length} public sources BioMate can query from chat. Click a row to star it for your own reference. <button onClick={() => { const all = DB.map(d => d.name); saveActiveDbs(all); setSelectedDbs(all); }} style={{ fontSize: 'var(--fs-micro)', color: 'oklch(0.45 0.15 260)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Star all</button></>;

  const Container = embedded ? 'section' : DialogContent;
  const content = (
      <Container
        style={{ maxWidth: embedded ? 'none' : 1040, width: embedded ? '100%' : '96vw', height: embedded ? '100%' : '82vh', minHeight: 0, maxHeight: embedded ? '100%' : '82vh', display: 'flex', flexDirection: 'column', padding: 0, overflow: 'hidden', gap: 0 }}
        data-testid="connectors-dialog"
      >
        <div style={{ padding: '16px 20px 0', flexShrink: 0 }}>
          {embedded ? <><p className="text-xs text-muted-foreground mb-2">Workspace / Connectors</p><div className="flex items-center justify-between gap-4 flex-wrap"><h1 className="text-xl font-semibold">Connectors</h1><div className="flex items-center gap-2"><button className="text-sm border border-border rounded-md px-3 py-1.5" onClick={() => adding || setupOrigin ? cancelAdding() : beginAdding()}>{adding || setupOrigin ? tOr('connectors.cancel_add', 'Cancel adding') : tOr('connectors.add', 'Add a connector')}</button><button className="text-sm border border-border rounded-md px-3 py-1.5" data-testid="connectors-close" onClick={() => onOpenChange(false)}>{tOr('actions.close', 'Close')}</button></div></div></> : <div className="flex items-center justify-between gap-3 pr-8"><DialogTitle>Connectors</DialogTitle><button className="text-sm border border-border rounded-md px-3 py-1.5" onClick={() => adding || setupOrigin ? cancelAdding() : beginAdding()}>{adding || setupOrigin ? tOr('connectors.cancel_add', 'Cancel adding') : tOr('connectors.add', 'Add a connector')}</button></div>}
          <p style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)', margin: '8px 0' }}>Browse public sources or manage your private database, MCP server, and instrument connections.</p>
          {/* Residency legend (§0.9.3): the five values, so a badge is readable at a glance */}
          <div data-testid="residency-legend" style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 8px', marginTop: 8, fontSize: 'var(--fs-xs)', color: 'var(--muted-foreground)' }}>
            <span title="data leaves the estate"><strong>cloud</strong> data leaves</span>
            <span style={{ opacity: 0.4 }}>·</span>
            <span title="stays inside your network"><strong>on-prem</strong> stays inside</span>
            <span style={{ opacity: 0.4 }}>·</span>
            <span title="read in place, never copied"><strong>mounted</strong> read in place</span>
            <span style={{ opacity: 0.4 }}>·</span>
            <span title="never leaves the host"><strong>this machine</strong> on your host</span>
            <span style={{ opacity: 0.4 }}>·</span>
            <span title="instruction text — moves no data"><strong>prompt only</strong> no data moves</span>
          </div>
        </div>

        <div style={{ display: 'flex', borderBottom: '1px solid var(--border)', padding: '10px 20px 0', gap: 2, overflowX: 'auto', flexShrink: 0 }}>
          {TABS.filter(t => t.id !== 'yours' && t.id !== 'instruments').map(t => (
            <HintTip key={t.id} hint={tOr(`hint.connectors.${t.id}`, t.tip)} side="bottom">
            <button
              data-testid={`connector-tab-${t.id}`}
              onClick={() => setActiveTab(t.id)}
              style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '6px 14px', border: 'none', cursor: 'pointer',
                fontSize: 'var(--fs-meta)', fontWeight: activeTab === t.id ? 600 : 400,
                color: activeTab === t.id ? 'var(--foreground)' : 'var(--muted-foreground)',
                background: 'transparent',
                borderBottom: activeTab === t.id ? '2px solid var(--foreground)' : '2px solid transparent',
                marginBottom: -1,
              }}
            >
              {t.icon}
              {t.label}
              {t.count !== undefined && (
                <span style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px', borderRadius: 999, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>
                  {t.count}
                </span>
              )}
              {t.id === 'databases' && selectedDbs.length > 0 && selectedDbs.length < DB.length && (
                <span
                  title="Rows you have starred for your own reference. This is a local view filter only — it does not change which sources BioMate queries."
                  style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px', borderRadius: 999, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}
                >
                  {selectedDbs.length} starred
                </span>
              )}
            </button>
            </HintTip>
          ))}
        </div>

        {setupOrigin && !adding && <div className="px-5 py-2 border-b border-border shrink-0"><button data-testid="connector-setup-back" className="text-sm underline" onClick={() => setAdding(true)}>{tOr('connectors.all_kinds', 'Back to connector kinds')}</button></div>}
        <div data-testid="connectors-scroll" style={{ flex: '1 1 0%', minHeight: 0, minWidth: 0, overflowY: 'auto', overflowX: 'hidden', overscrollBehavior: 'contain' }}>
        {adding && (
          <div className="p-5 border-b border-border">
            <AddConnectorFlow
              onPickDatabase={() => { setActiveTab('databases'); setSourceView('private'); setAdding(false); }}
              onPickMcp={() => { setActiveTab('mcp'); setAdding(false); }}
              onPickModel={() => { setActiveTab('model'); setAdding(false); }}
              onPickSkill={() => { setActiveTab('skills'); setAdding(false); }}
              onPickInstrument={() => { setActiveTab('databases'); setSourceView('instruments'); setAdding(false); }}
            />
          </div>
        )}
          {!adding && <>
          {activeTab === 'databases' && <><div className="flex flex-wrap gap-2 px-5 py-3 border-b border-border">{((['public', 'private', 'instruments'] as const).filter(v => v !== 'instruments' || CONNECTOR_INSTRUMENTS_ENABLED)).map(view => <button key={view} className={sourceView === view ? 'text-xs rounded-md px-3 py-1.5 bg-muted font-semibold' : 'text-xs rounded-md px-3 py-1.5 text-muted-foreground'} onClick={() => setSourceView(view)}>{view === 'public' ? 'Public databases' : view === 'private' ? 'Private databases' : 'Instruments'}</button>)}</div>{sourceView === 'public' ? <DatabasesTab compact={embedded} selected={selectedDbs} onToggle={toggleDb} scopes={scopes} onScopeChange={setScope} /> : sourceView === 'private' ? <div className="p-5"><PrivateDbConnectionForm /></div> : (CONNECTOR_INSTRUMENTS_ENABLED ? <InstrumentsSection /> : <DatabasesTab compact={embedded} selected={selectedDbs} onToggle={toggleDb} scopes={scopes} onScopeChange={setScope} />)}</>}
          {activeTab === 'ai' && <><div className="p-4"><button className="text-sm underline" onClick={() => setSettingsOpen(true)}>Configure model providers and API keys</button></div><ConnectorTable compact={embedded} rows={AI} scopes={scopes} onScopeChange={setScope} /></>}
          {activeTab === 'yours' && <div className="p-5"><PrivateDbConnectionForm /></div>}
          {activeTab === 'mcp' && <div className="p-5"><McpServerForm /></div>}
          {activeTab === 'model' && <div className="p-5"><RegisterModelForm /></div>}
          {activeTab === 'skills' && <div className="p-5 space-y-6">
            <ImportSkillForm onImported={loadPacks} />
            <AddSkillForm onCreated={loadPacks} />
            <div>
              <p className="text-sm text-muted-foreground mb-4">Your experts. Switch them on per request using Skills &amp; experts in the chat composer.</p>
              {packsError ? <p role="alert">Could not load expert packs. Please reload to try again.</p> : packs === null ? <p>Loading expert packs…</p> : packs.length === 0 ? <p className="text-sm text-muted-foreground">No experts yet — create one above.</p> : packs.map(pack => <article key={pack.id} className="py-4 border-b border-border"><h3 className="text-sm font-medium">{pack.label}</h3>{pack.description && <p className="text-sm text-muted-foreground mt-1">{pack.description}</p>}</article>)}
            </div>
          </div>}
          {activeTab === 'instruments' && CONNECTOR_INSTRUMENTS_ENABLED && <InstrumentsSection />}
          </>}
        </div>

        {!adding && <div style={{ flexShrink: 0, padding: '6px 20px', borderTop: '1px solid var(--border)', fontSize: 'var(--fs-micro)', color: 'var(--muted-foreground)' }}>
          {activeTab === 'databases' && sourceView === 'public' && (embedded ? 'Public sources are queried automatically when relevant to your request.' : dbFooter)}
          {activeTab === 'ai'        && `${AI.length} AI models and platform surfaces BioMate exposes — reference only. This panel does not configure them; set up messaging bots / IDE (MCP) / GPT-action access from their own tools or the BioMate MCP install flow.`}
          {activeTab === 'yours'     && 'Your own private database and MCP server — the one writable surface here. Connections you add are used by BioMate chat; DB queries are read-only and credentials are encrypted at rest.'}
        </div>}

      </Container>
  );
  return <>{embedded ? content : <Dialog open={open} onOpenChange={onOpenChange}>{content}</Dialog>}{settingsOpen && <SettingsDialog open onOpenChange={setSettingsOpen} />}</>;
}
