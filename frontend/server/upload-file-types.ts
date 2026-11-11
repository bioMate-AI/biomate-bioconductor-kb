// File types accepted by the chat/data upload endpoint (POST /api/datasets/upload).
//
// One list, tested against every demo asset the cold-start UI attaches
// (upload-file-types.test.ts), because this allowlist has silently rejected BioMate's own
// example inputs more than once: chat-attached .md uploads (demo_notes.md) 500'd until .md was
// added, and on 2026-11-04 the docking / design / structure / rank examples' PDB structures
// (1IEP.pdb, 1BXL.pdb, 1LYZ.pdb, 6Z43.pdb) and SMILES reference actives (.smi) were still
// rejected — those examples lost their target structure on upload.
export const ALLOWED_UPLOAD_EXTENSIONS: readonly string[] = [
  '.fastq', '.fastq.gz', '.fq', '.fq.gz',
  '.bam', '.sam', '.cram',
  '.mzml', '.mzxml', '.mgf',
  '.csv', '.tsv', '.txt', '.tab',
  // Markdown — provenance/notes (cold-start demo_notes.md, pilot_README.md),
  // IND report sections, and after-run reports are all .md. Omitting it made
  // chat-attached .md uploads 500 (fileFilter reject -> Internal server error).
  '.md', '.markdown',
  '.fasta', '.fa', '.fna', '.fas', '.faa', '.fap',
  '.vcf', '.vcf.gz', '.bed', '.gff', '.gtf', '.ped',
  '.h5ad', '.h5', '.hdf5', '.loom',
  '.json', '.xml',
  // Research papers / literature
  '.pdf',
  // Images for multimodal biomedical read (histology, gels/blots, plots, scans)
  '.png', '.jpg', '.jpeg', '.gif', '.webp',
  // Cryo-EM / electron microscopy formats
  '.mrc', '.mrcs', '.tif', '.tiff', '.eer', '.spi', '.dm4', '.map',
  // Archive formats (capsule data, bulk uploads)
  '.zip', '.tar', '.tar.gz', '.tgz',
  // Notebook and R formats
  '.ipynb', '.rds', '.rda', '.xlsx', '.xls',
  // Phylogenomics / alignment formats
  '.nwk', '.newick', '.treefile', '.tree', '.mafft', '.clipkit', '.iqtree', '.log',
  // Generic compressed and model/distance/tree files
  '.gz', '.mldist', '.model', '.phy', '.phylip', '.aln', '.bionj', '.contree', '.splits', '.nxs', '.nexus',
  // Nextflow / workflow definition files (user-uploaded .nf pipelines for sandbox execution)
  '.nf', '.config', '.groovy',
  // Structural biology + cheminformatics inputs (targets, ligands, docking, design)
  '.pdb', '.ent', '.cif', '.mmcif', '.pdbqt', '.sdf', '.mol', '.mol2', '.smi', '.smiles', '.xyz',
  // R workspace (.RData) alongside .rds / .rda
  '.rdata',
];

export function isAllowedUploadName(name: string): boolean {
  const lower = (name || '').toLowerCase();
  return ALLOWED_UPLOAD_EXTENSIONS.some(ext => lower.endsWith(ext));
}

/** A client error (HTTP 415), not a server fault: the terminal error handler returns it as such
 *  instead of a generic 500 "Internal server error" the user can't act on. */
export class UnsupportedUploadTypeError extends Error {
  readonly status = 415;
  constructor(message: string) {
    super(message);
    this.name = 'UnsupportedUploadTypeError';
  }
}
