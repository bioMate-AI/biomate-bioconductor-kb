# MG/CIDP Complement Pathway DE Gene Dataset

**Source:** Derived from published MG PBMC transcriptomics literature:
- Li et al. 2026 (GSE227835) — CFD+CD14+ monocytes in MG
- Yu et al. 2024 (GCST90093061) — MG GWAS with eQTL colocalization
- Complement gene expression direction validated against GSE65391 autoimmune benchmark

**Use cases:**
- BD3 demo: Martin Kolev (Apellis/Biogen) — complement C3 vs C5 arm in MG/CIDP
- Salma Merchant (Alnylam) — CFD pathway in cemdisiran next indication

**Files:**
- `mg_cidp_pbmc_de_genes.csv` — Full DE gene list (47 genes, gene_symbol/entrez_id/log2FC/padj/baseMean)
- `complement_gene_list.txt` — Foreground-only list for ORA (17 complement genes elevated in MG vs HC)

**BioMate query to use with this data:**
```
Run pathway enrichment analysis on complement cascade genes elevated in MG versus 
healthy controls. Use clusterProfiler enrichGO. Gene list: CFD, C3AR1, C3, C5AR1, 
CFB, C4A, C1QA, C1QB, SERPING1, MBL2, C2, CR1, CFH, C5, C9.
Test GO:0006958 complement activation and KEGG hsa04610.
```

**Expected output:**
- GO:0006958 (complement activation) — top hit, p < 0.001
- GO:0001906 (complement-mediated cytotoxicity)  
- KEGG hsa04610 (complement and coagulation cascades)
- CFD as most significant individual gene (log2FC=2.84, padj=0.00012)
