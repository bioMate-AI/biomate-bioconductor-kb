import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Brain, Database, Zap } from 'lucide-react';

interface Connector {
  name: string;
  category: string;
  description: string;
}

interface SkillItem {
  id: string;
  name: string;
  description: string;
  category: string;
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

function ConnectorTable({ rows }: { rows: Connector[] }) {
  return (
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
      <thead>
        <tr style={{ borderBottom: '1px solid var(--border)' }}>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 220 }}>Name</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 140 }}>Category</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600 }}>Description</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row, i) => (
          <tr key={row.name} style={{ borderBottom: i < rows.length - 1 ? '1px solid var(--border)' : 'none' }}>
            <td style={{ padding: '8px 12px', fontWeight: 500, verticalAlign: 'top', color: 'var(--foreground)', whiteSpace: 'nowrap' }}>{row.name}</td>
            <td style={{ padding: '8px 12px', verticalAlign: 'top', whiteSpace: 'nowrap' }}>
              <span style={{ fontSize: 11, padding: '2px 7px', borderRadius: 4, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>{row.category}</span>
            </td>
            <td style={{ padding: '8px 12px', color: 'var(--muted-foreground)', verticalAlign: 'top', lineHeight: 1.5 }}>{row.description}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function SkillsTab() {
  const [skills, setSkills] = useState<SkillItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/ai_assistant/skills/available')
      .then(r => r.ok ? r.json() : Promise.reject(r.status))
      .then(data => {
        const items: SkillItem[] = [];
        if (Array.isArray(data)) {
          for (const cat of data) {
            for (const skill of (cat.skills ?? [])) {
              items.push({ id: skill.id ?? skill.name, name: skill.name, description: skill.description ?? '', category: cat.name ?? 'General' });
            }
          }
        }
        setSkills(items);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  if (loading) return <div style={{ padding: 24, color: 'var(--muted-foreground)', fontSize: 13 }}>Loading…</div>;
  if (skills.length === 0) return <div style={{ padding: 24, color: 'var(--muted-foreground)', fontSize: 13 }}>No skills available.</div>;

  return (
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
      <thead>
        <tr style={{ borderBottom: '1px solid var(--border)' }}>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 220 }}>Skill</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600, width: 140 }}>Category</th>
          <th style={{ textAlign: 'left', padding: '6px 12px', fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--muted-foreground)', fontWeight: 600 }}>Description</th>
        </tr>
      </thead>
      <tbody>
        {skills.map((s, i) => (
          <tr key={s.id} style={{ borderBottom: i < skills.length - 1 ? '1px solid var(--border)' : 'none' }}>
            <td style={{ padding: '8px 12px', fontWeight: 500, verticalAlign: 'top', color: 'var(--foreground)', whiteSpace: 'nowrap' }}>{s.name}</td>
            <td style={{ padding: '8px 12px', verticalAlign: 'top', whiteSpace: 'nowrap' }}>
              <span style={{ fontSize: 11, padding: '2px 7px', borderRadius: 4, background: 'var(--muted)', color: 'var(--muted-foreground)' }}>{s.category}</span>
            </td>
            <td style={{ padding: '8px 12px', color: 'var(--muted-foreground)', verticalAlign: 'top', lineHeight: 1.5 }}>{s.description || '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        style={{ maxWidth: 820, width: '95vw', maxHeight: '82vh', display: 'flex', flexDirection: 'column', padding: 0, overflow: 'hidden', gap: 0 }}
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
            </button>
          ))}
        </div>

        <div style={{ flex: 1, overflowY: 'auto', overflowX: 'auto' }}>
          {activeTab === 'databases' && <ConnectorTable rows={DB} />}
          {activeTab === 'ai'        && <ConnectorTable rows={AI} />}
          {activeTab === 'skills'    && <SkillsTab />}
        </div>

        <div style={{ flexShrink: 0, padding: '6px 20px', borderTop: '1px solid var(--border)', fontSize: 11, color: 'var(--muted-foreground)' }}>
          {activeTab === 'databases' && `${DB.length} databases`}
          {activeTab === 'ai'        && `${AI.length} connectors`}
          {activeTab === 'skills'    && 'Skills loaded from backend'}
        </div>
      </DialogContent>
    </Dialog>
  );
}
