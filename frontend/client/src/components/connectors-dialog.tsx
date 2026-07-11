import { useState, useEffect, useCallback } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Brain, Database, Zap, CheckSquare, Square, ToggleLeft, ToggleRight } from 'lucide-react';

const ACTIVE_SKILLS_KEY = 'biomate-active-skills';
const ACTIVE_DBS_KEY = 'biomate-active-databases';

function loadActiveSkills(): string[] {
  try { return JSON.parse(localStorage.getItem(ACTIVE_SKILLS_KEY) || '[]'); } catch { return []; }
}
function saveActiveSkills(ids: string[]) {
  localStorage.setItem(ACTIVE_SKILLS_KEY, JSON.stringify(ids));
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

interface Connector {
  name: string;
  category: string;
  description: string;
}

interface SkillItem {
  id: string;
  title: string;
  domains: string[];
  domain?: string;
  triggers: string[];
  version?: string;
  source?: string;
  description?: string;
  when_to_use?: string;
  score?: number;
}

type TabId = 'databases' | 'ai' | 'skills';

// ── Scientific databases ───────────────────────────────────────────────────────

const DB: Connector[] = [
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

const AI: Connector[] = [
  { name: 'Anthropic Claude', category: 'LLM', description: 'Primary model for workflow generation, QC analysis, and scientific planning' },
  { name: 'Google Gemini', category: 'LLM', description: 'Alternative backbone for long-context and multimodal tasks' },
  { name: 'OpenAI GPT', category: 'LLM', description: 'Fallback LLM for completions and embeddings' },
  { name: 'Ollama', category: 'Local LLM', description: 'Self-hosted model runner for air-gapped deployments' },
  { name: 'ChatGPT (GPT Actions)', category: 'AI Platform', description: 'Expose BioMate as a custom GPT action in ChatGPT' },
  { name: 'Cursor', category: 'AI Platform', description: 'MCP connector — run workflows from within the Cursor IDE' },
  { name: 'Coze', category: 'AI Platform', description: 'Plugin connector for building bioscience bots on the Coze platform' },
  { name: 'Open-Claw', category: 'AI Platform', description: 'Open-source agent framework integration' },
  { name: 'Slack', category: 'Messaging', description: 'Trigger workflows and receive run alerts in Slack channels' },
  { name: 'Telegram', category: 'Messaging', description: 'Run BioMate sessions and receive results via Telegram bot' },
  { name: 'WeChat / Feishu', category: 'Messaging', description: 'WeChat and Feishu bot connectors for teams in China' },
];

// ── Helpers ────────────────────────────────────────────────────────────────────

function ConnectorTable({ rows, selected, onToggle }: { rows: Connector[]; selected?: string[]; onToggle?: (name: string) => void }) {
  const checkable = !!onToggle;
  return (
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
      <thead>
        <tr style={{ borderBottom: '1px solid var(--border)' }}>
          {checkable && <th style={{ width: 36, padding: '6px 4px 6px 12px' }} />}
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 220 }}>Name</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 140 }}>Category</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600 }}>Description</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row, i) => {
          const active = selected?.includes(row.name) ?? false;
          return (
            <tr
              key={row.name}
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
              <td style={{ padding: '8px 12px', fontWeight: active ? 600 : 500, verticalAlign: 'top', color: 'var(--foreground)', whiteSpace: 'nowrap' }}>{row.name}</td>
              <td style={{ padding: '8px 12px', verticalAlign: 'top', whiteSpace: 'nowrap' }}>
                <span style={{ fontSize: 11, padding: '2px 7px', borderRadius: 4, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>{row.category}</span>
              </td>
              <td style={{ padding: '8px 12px', color: 'var(--muted-foreground)', verticalAlign: 'top', lineHeight: 1.5 }}>{row.description}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

const BIOC_DOMAIN_LABELS: Record<string, string> = {
  general: 'General', genomics: 'Genomics', transcriptomics: 'Transcriptomics',
  'single-cell': 'Single Cell', epigenomics: 'Epigenomics', proteomics: 'Proteomics',
  'variant-calling': 'Variant Calling', metagenomics: 'Metagenomics',
  metabolomics: 'Metabolomics', imaging: 'Imaging', annotation: 'Annotation',
  enrichment: 'Enrichment',
};

function SkillRow({ s, active, onToggle }: { s: SkillItem; active: boolean; onToggle: (id: string) => void }) {
  const isExpert = s.source === 'expert' || !s.source;
  return (
    <tr
      onClick={() => onToggle(s.id)}
      style={{ borderBottom: '1px solid var(--border)', cursor: 'pointer', background: active ? 'oklch(0.96 0.02 260 / 0.5)' : 'transparent' }}
    >
      <td style={{ padding: '8px 4px 8px 14px', verticalAlign: 'middle' }}>
        <button
          onClick={e => { e.stopPropagation(); onToggle(s.id); }}
          style={{ background: 'transparent', border: 'none', cursor: 'pointer', display: 'flex' }}
          title={active ? 'Deactivate' : 'Activate'}
        >
          {active
            ? <ToggleRight style={{ width: 22, height: 22, color: 'oklch(0.55 0.15 260)' }} />
            : <ToggleLeft style={{ width: 22, height: 22, color: 'var(--muted-foreground)', opacity: 0.4 }} />}
        </button>
      </td>
      <td style={{ padding: '8px 12px', fontWeight: active ? 600 : 500, verticalAlign: 'top', color: 'var(--foreground)' }}>
        <span>{s.title}</span>
        {active && <span style={{ marginLeft: 6, fontSize: 10, padding: '1px 5px', borderRadius: 99, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}>ACTIVE</span>}
        {!isExpert && <span style={{ marginLeft: 5, fontSize: 10, padding: '1px 4px', borderRadius: 3, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>Bioconductor</span>}
      </td>
      <td style={{ padding: '8px 12px', color: 'var(--muted-foreground)', verticalAlign: 'top', fontSize: 12, lineHeight: 1.5 }}>
        {isExpert
          ? (s.triggers || []).slice(0, 4).join(', ') + ((s.triggers || []).length > 4 ? ` +${s.triggers!.length - 4}` : '')
          : (s.description || s.when_to_use || '').slice(0, 120) + ((s.description || '').length > 120 ? '…' : '')}
      </td>
    </tr>
  );
}

function SkillTable({ skills, activeIds, onToggle }: { skills: SkillItem[]; activeIds: string[]; onToggle: (id: string) => void }) {
  const isExpert = skills[0]?.source === 'expert' || !skills[0]?.source;
  return (
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
      <thead>
        <tr style={{ borderBottom: '1px solid var(--border)' }}>
          <th style={{ width: 44, padding: '6px 4px 6px 14px' }} />
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 220 }}>Skill</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600 }}>{isExpert ? 'Key triggers' : 'Description'}</th>
        </tr>
      </thead>
      <tbody>
        {skills.map(s => (
          <SkillRow key={s.id} s={s} active={activeIds.includes(s.id)} onToggle={onToggle} />
        ))}
      </tbody>
    </table>
  );
}

function SkillsTab() {
  const [allSkills, setAllSkills] = useState<SkillItem[]>([]);
  const [biocDomains, setBiocDomains] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeIds, setActiveIds] = useState<string[]>(loadActiveSkills);
  const [activeTab, setActiveTab] = useState<string>('expert');

  useEffect(() => {
    fetch('/api/skills')
      .then(r => r.ok ? r.json() : Promise.reject(r.status))
      .then(data => {
        setAllSkills(Array.isArray(data.skills) ? data.skills : []);
        setBiocDomains(Array.isArray(data.bioc_domains) ? data.bioc_domains : []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const toggle = useCallback((id: string) => {
    setActiveIds(prev => {
      const next = prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id];
      saveActiveSkills(next);
      return next;
    });
  }, []);

  if (loading) return <div style={{ padding: 24, color: 'var(--muted-foreground)', fontSize: 13 }}>Loading skills…</div>;

  const expertSkills = allSkills.filter(s => s.source === 'expert' || !s.source);
  const biocSkills = allSkills.filter(s => s.source === 'bioconductor');
  const activeCount = activeIds.filter(id => allSkills.some(s => s.id === id)).length;

  const tabSkills = activeTab === 'expert'
    ? expertSkills
    : biocSkills.filter(s => s.domain === activeTab);

  const domainCount = (domain: string) =>
    domain === 'expert' ? expertSkills.length : biocSkills.filter(s => s.domain === domain).length;

  const domainSelected = (domain: string) => {
    const relevant = domain === 'expert' ? expertSkills : biocSkills.filter(s => s.domain === domain);
    return relevant.filter(s => activeIds.includes(s.id)).length;
  };

  const tabs = ['expert', ...biocDomains];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Capability banner */}
      <div style={{ padding: '10px 16px', borderBottom: '1px solid var(--border)', background: 'oklch(0.97 0.015 250)', display: 'flex', alignItems: 'flex-start', gap: 10, flexShrink: 0 }}>
        <Zap style={{ width: 14, height: 14, color: 'oklch(0.45 0.15 260)', flexShrink: 0, marginTop: 2 }} />
        <div style={{ fontSize: 12, lineHeight: 1.5, color: 'var(--foreground)' }}>
          <strong>BioMate has 4,000+ workflows across 36 biological domains</strong> — the right workflow is automatically matched to your request, no manual selection needed.{' '}
          <span style={{ color: 'var(--muted-foreground)' }}>Skills below add deep domain reasoning on top. You can also <span style={{ color: 'oklch(0.45 0.15 260)', cursor: 'pointer', textDecoration: 'underline' }}>upload your own .md skill files</span> to customise the AI's expertise.</span>
        </div>
      </div>
      {/* Active skills bar */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '6px 16px', borderBottom: '1px solid var(--border)', background: 'var(--muted)', fontSize: 12, color: 'var(--muted-foreground)', flexShrink: 0 }}>
        <span>{activeCount > 0
          ? <><strong style={{ color: 'var(--foreground)' }}>{activeCount}</strong> skills active — injected into every AI response</>
          : `${allSkills.length} skills (${expertSkills.length} expert + ${biocSkills.length} Bioconductor) — toggle to activate`}
        </span>
        {activeCount > 0 && (
          <button onClick={() => { saveActiveSkills([]); setActiveIds([]); }} style={{ fontSize: 11, color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}>Clear all</button>
        )}
      </div>
      {/* Domain sub-tabs */}
      <div style={{ display: 'flex', overflowX: 'auto', borderBottom: '1px solid var(--border)', padding: '0 12px', gap: 2, flexShrink: 0, scrollbarWidth: 'none' }}>
        {tabs.map(tab => {
          const isActive = tab === activeTab;
          const count = domainCount(tab);
          const sel = domainSelected(tab);
          const label = tab === 'expert' ? 'Expert Roles' : (BIOC_DOMAIN_LABELS[tab] || tab);
          return (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              style={{
                display: 'inline-flex', alignItems: 'center', gap: 5,
                padding: '6px 10px', border: 'none', cursor: 'pointer', whiteSpace: 'nowrap',
                fontSize: 12, fontWeight: isActive ? 600 : 400,
                color: isActive ? 'var(--foreground)' : 'var(--muted-foreground)',
                background: 'transparent',
                borderBottom: isActive ? '2px solid var(--foreground)' : '2px solid transparent',
                marginBottom: -1,
              }}
            >
              {label}
              <span style={{ fontSize: 10, padding: '0 4px', borderRadius: 3, background: isActive ? 'var(--foreground)' : 'var(--border)', color: isActive ? 'var(--background)' : 'var(--muted-foreground)' }}>{count}</span>
              {sel > 0 && <span style={{ fontSize: 10, padding: '0 4px', borderRadius: 3, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}>{sel}✓</span>}
            </button>
          );
        })}
      </div>
      <div style={{ flex: 1, overflowY: 'auto' }}>
        {tabSkills.length === 0
          ? <div style={{ padding: 24, color: 'var(--muted-foreground)', fontSize: 13 }}>No skills in this category.</div>
          : <SkillTable skills={tabSkills} activeIds={activeIds} onToggle={toggle} />}
      </div>
    </div>
  );
}

function DatabasesTab({ selected, onToggle }: { selected: string[]; onToggle: (name: string) => void }) {
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
      <ConnectorTable rows={rows} selected={selected} onToggle={onToggle} />
    </div>
  );
}

// ── Tab config ─────────────────────────────────────────────────────────────────

const TABS: { id: TabId; label: string; icon: React.ReactNode; count?: number; tip: string }[] = [
  { id: 'databases', label: 'Scientific Databases', icon: <Database style={{ width: 13, height: 13 }} />, count: DB.length, tip: 'Protein, genomics, omics, chemical, pathway, disease, literature, and imaging databases' },
  { id: 'ai',        label: 'AI & Platforms',       icon: <Brain    style={{ width: 13, height: 13 }} />, count: AI.length, tip: 'LLM providers, AI coding tools, and messaging platform connectors' },
  { id: 'skills',    label: 'Skills',                icon: <Zap      style={{ width: 13, height: 13 }} />, tip: 'Scientific reasoning and data-retrieval skills available to the AI assistant' },
];

// ── Dialog ─────────────────────────────────────────────────────────────────────

interface ConnectorsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ConnectorsDialog({ open, onOpenChange }: ConnectorsDialogProps) {
  const [activeTab, setActiveTab] = useState<TabId>('databases');
  const [selectedDbs, setSelectedDbs] = useState<string[]>(() => loadActiveDbs(DB.map(d => d.name)));

  const toggleDb = useCallback((name: string) => {
    setSelectedDbs(prev => {
      const next = prev.includes(name) ? prev.filter(n => n !== name) : [...prev, name];
      saveActiveDbs(next);
      return next;
    });
  }, []);

  const dbFooter = selectedDbs.length === DB.length
    ? <><strong>All {DB.length}</strong> databases selected — <button onClick={() => { saveActiveDbs([]); setSelectedDbs([]); }} style={{ fontSize: 11, color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Deselect all</button></>
    : selectedDbs.length > 0
      ? <><strong>{selectedDbs.length}</strong> of {DB.length} databases selected — <button onClick={() => { const all = DB.map(d => d.name); saveActiveDbs(all); setSelectedDbs(all); }} style={{ fontSize: 11, color: 'var(--muted-foreground)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Select all</button></>
      : <>{DB.length} databases — <button onClick={() => { const all = DB.map(d => d.name); saveActiveDbs(all); setSelectedDbs(all); }} style={{ fontSize: 11, color: 'oklch(0.45 0.15 260)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>Select all</button></>;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        style={{ maxWidth: 860, width: '95vw', maxHeight: '82vh', display: 'flex', flexDirection: 'column', padding: 0, overflow: 'hidden', gap: 0 }}
        data-testid="connectors-dialog"
      >
        <DialogHeader style={{ padding: '16px 20px 0', flexShrink: 0 }}>
          <DialogTitle>Connectors</DialogTitle>
          <p style={{ fontSize: 12, color: 'var(--muted-foreground)', margin: '3px 0 0' }}>
            External data sources and integrations available in BioMate
          </p>
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
              {t.id === 'databases' && selectedDbs.length > 0 && (
                <span style={{ fontSize: 10, padding: '1px 5px', borderRadius: 999, background: 'oklch(0.88 0.06 260)', color: 'oklch(0.35 0.12 260)', fontWeight: 600 }}>
                  {selectedDbs.length} on
                </span>
              )}
            </button>
          ))}
        </div>

        <div style={{ flex: 1, overflowY: 'auto', overflowX: 'auto', display: 'flex', flexDirection: 'column' }}>
          {activeTab === 'databases' && <DatabasesTab selected={selectedDbs} onToggle={toggleDb} />}
          {activeTab === 'ai'        && <ConnectorTable rows={AI} />}
          {activeTab === 'skills'    && <SkillsTab />}
        </div>

        <div style={{ flexShrink: 0, padding: '6px 20px', borderTop: '1px solid var(--border)', fontSize: 11, color: 'var(--muted-foreground)' }}>
          {activeTab === 'databases' && dbFooter}
          {activeTab === 'ai'        && `${AI.length} connectors`}
          {activeTab === 'skills'    && 'Active skills are injected into every AI response as domain expertise'}
        </div>
      </DialogContent>
    </Dialog>
  );
}
