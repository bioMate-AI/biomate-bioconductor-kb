import { useState, useEffect, useCallback } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Brain, Database, CheckSquare, Square } from 'lucide-react';
import {
  ResidencyBadge, ScopeSelector, NOT_DECLARED,
  type Residency, type Scope, type DeclaredFacts,
} from './connector-residency';

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

type TabId = 'databases' | 'ai';

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
      style={{ fontSize: 11, color: 'var(--muted-foreground)', whiteSpace: 'nowrap' }}
    >
      <span style={{ opacity: 0.7 }}>{label}:</span>{' '}
      <span style={{ fontStyle: declared ? 'normal' : 'italic', opacity: declared ? 1 : 0.7 }}>
        {declared ? value : NOT_DECLARED}
      </span>
    </span>
  );
}

function ConnectorTable({
  rows, selected, onToggle, scopes, onScopeChange,
}: {
  rows: Connector[];
  selected?: string[];
  onToggle?: (name: string) => void;
  scopes: Record<string, Scope>;
  onScopeChange: (name: string, scope: Scope) => void;
}) {
  const checkable = !!onToggle;
  return (
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }} data-testid="connector-table">
      <thead>
        <tr style={{ borderBottom: '1px solid var(--border)' }}>
          {checkable && <th style={{ width: 36, padding: '6px 4px 6px 12px' }} />}
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 200 }}>Name</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 120 }}>Category</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 96 }}>Residency</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600 }}>Declared facts</th>
          <th
            title="A preference for how widely you would scope this source (account / project / request). Informational only — scope is not enforced yet; BioMate queries public sources as each chat request needs them."
            style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 180 }}
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
                <div style={{ fontSize: 11, color: 'var(--muted-foreground)', fontWeight: 400, marginTop: 2, lineHeight: 1.4 }}>{row.description}</div>
              </td>
              <td style={{ padding: '8px 12px', verticalAlign: 'top', whiteSpace: 'nowrap' }}>
                <span style={{ fontSize: 11, padding: '2px 7px', borderRadius: 4, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>{row.category}</span>
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
                  <DeclaredFact label="where it runs" value={row.runsIn} />
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
  selected, onToggle, scopes, onScopeChange,
}: {
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
                fontSize: 12, fontWeight: active ? 600 : 400,
                color: active ? 'var(--foreground)' : 'var(--muted-foreground)',
                background: 'transparent',
                borderBottom: active ? '2px solid var(--foreground)' : '2px solid transparent',
                marginBottom: -1,
              }}
            >
              {g.label}
              <span style={{ fontSize: 10, padding: '0 4px', borderRadius: 3, background: active ? 'var(--foreground)' : 'var(--border)', color: active ? 'var(--background)' : 'var(--muted-foreground)' }}>
                {groupCount(g)}
              </span>
              {sel > 0 && (
                <span style={{ fontSize: 10, padding: '0 4px', borderRadius: 3, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}>
                  {sel}✓
                </span>
              )}
            </button>
          );
        })}
      </div>
      <ConnectorTable rows={rows} selected={selected} onToggle={onToggle} scopes={scopes} onScopeChange={onScopeChange} />
    </div>
  );
}

// ── Tab config ─────────────────────────────────────────────────────────────────

const TABS: { id: TabId; label: string; icon: React.ReactNode; count?: number; tip: string }[] = [
  { id: 'databases', label: 'Public Databases',   icon: <Database style={{ width: 13, height: 13 }} />, count: DB.length, tip: 'Public protein, genomics, omics, chemical, pathway, disease, literature, and imaging sources BioMate can query from chat' },
  { id: 'ai',        label: 'AI & Platforms',      icon: <Brain    style={{ width: 13, height: 13 }} />, count: AI.length, tip: 'LLM providers and messaging / IDE surfaces BioMate exposes — reference only, not configured here' },
  // A "Skills" tab was removed, not merely hidden: no backend read its selection,
  // so it advertised an activation capability that did not exist. Add a real
  // endpoint before re-introducing it — do not restore the facade.
];

// ── Dialog ─────────────────────────────────────────────────────────────────────

interface ConnectorsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ConnectorsDialog({ open, onOpenChange }: ConnectorsDialogProps) {
  const [activeTab, setActiveTab] = useState<TabId>('databases');
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
    ? <>All {DB.length} sources listed — BioMate queries whichever your request needs. <button onClick={() => { saveActiveDbs([]); setSelectedDbs([]); }} style={{ fontSize: 11, color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Clear your stars</button></>
    : selectedDbs.length > 0
      ? <><strong>{selectedDbs.length}</strong> of {DB.length} sources starred for your reference (local view filter — does not change what BioMate queries). <button onClick={() => { const all = DB.map(d => d.name); saveActiveDbs(all); setSelectedDbs(all); }} style={{ fontSize: 11, color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Star all</button></>
      : <>{DB.length} public sources BioMate can query from chat. Click a row to star it for your own reference. <button onClick={() => { const all = DB.map(d => d.name); saveActiveDbs(all); setSelectedDbs(all); }} style={{ fontSize: 11, color: 'oklch(0.45 0.15 260)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Star all</button></>;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        style={{ maxWidth: 1040, width: '96vw', maxHeight: '82vh', display: 'flex', flexDirection: 'column', padding: 0, overflow: 'hidden', gap: 0 }}
        data-testid="connectors-dialog"
      >
        <DialogHeader style={{ padding: '16px 20px 0', flexShrink: 0 }}>
          <DialogTitle>Connectors reference</DialogTitle>
          <p style={{ fontSize: 12, color: 'var(--muted-foreground)', margin: '3px 0 0' }}>
            A reference directory of the public data sources BioMate can already reach from chat, plus the
            AI models and messaging surfaces it exposes. Ask in chat and BioMate queries the relevant sources
            automatically — there is nothing to connect or switch on here. Each row carries where it runs,
            because the question behind most of them is whether your data leaves the estate.
          </p>
          {/* Residency legend (§0.9.3): the five values, so a badge is readable at a glance */}
          <div data-testid="residency-legend" style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 8px', marginTop: 8, fontSize: 10.5, color: 'var(--muted-foreground)' }}>
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
        </DialogHeader>

        <div style={{ display: 'flex', borderBottom: '1px solid var(--border)', padding: '10px 20px 0', gap: 2, flexShrink: 0 }}>
          {TABS.map(t => (
            <button
              key={t.id}
              data-testid={`connector-tab-${t.id}`}
              title={t.tip}
              onClick={() => setActiveTab(t.id)}
              style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '6px 14px', border: 'none', cursor: 'pointer',
                fontSize: 13, fontWeight: activeTab === t.id ? 600 : 400,
                color: activeTab === t.id ? 'var(--foreground)' : 'var(--muted-foreground)',
                background: 'transparent',
                borderBottom: activeTab === t.id ? '2px solid var(--foreground)' : '2px solid transparent',
                marginBottom: -1,
              }}
            >
              {t.icon}
              {t.label}
              {t.count !== undefined && (
                <span style={{ fontSize: 10, padding: '1px 5px', borderRadius: 999, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>
                  {t.count}
                </span>
              )}
              {t.id === 'databases' && selectedDbs.length > 0 && selectedDbs.length < DB.length && (
                <span
                  title="Rows you have starred for your own reference. This is a local view filter only — it does not change which sources BioMate queries."
                  style={{ fontSize: 10, padding: '1px 5px', borderRadius: 999, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}
                >
                  {selectedDbs.length} starred
                </span>
              )}
            </button>
          ))}
        </div>

        <div style={{ flex: 1, overflowY: 'auto', overflowX: 'auto', display: 'flex', flexDirection: 'column' }}>
          {activeTab === 'databases' && <DatabasesTab selected={selectedDbs} onToggle={toggleDb} scopes={scopes} onScopeChange={setScope} />}
          {activeTab === 'ai'        && <ConnectorTable rows={AI} scopes={scopes} onScopeChange={setScope} />}
        </div>

        <div style={{ flexShrink: 0, padding: '6px 20px', borderTop: '1px solid var(--border)', fontSize: 11, color: 'var(--muted-foreground)' }}>
          {activeTab === 'databases' && dbFooter}
          {activeTab === 'ai'        && `${AI.length} AI models and platform surfaces BioMate exposes — reference only. This panel does not configure them; set up messaging bots / IDE (MCP) / GPT-action access from their own tools or the BioMate MCP install flow.`}
        </div>
      </DialogContent>
    </Dialog>
  );
}
