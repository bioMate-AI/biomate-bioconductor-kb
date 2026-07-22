# Claude Design Update Requirements — 2026-07-21

Items that need updating in the Claude design reference and demo video to reflect the current product.

## 1. Demo video — re-record required

The existing demo video shows the MG 3-turn flow without file attachments. The product now auto-attaches sample files when the chip is clicked. The new flow is:

1. Click "scRNA-seq · myasthenia gravis" chip on the index page
2. Query fills in AND three file chips appear: `sample_metadata.csv`, `counts_matrix.csv`, `contrasts.csv`
3. User can delete/replace files or just hit Send
4. After Turn 1 completes, `de_genes.txt` auto-appears in the input for Turn 2

The video must show file chips in the input — without them, viewers will assume it's text-only and won't understand it's a real data upload.

## 2. Index page chip order (webpage_design_v2/index.html)

Current order (already updated in code):
1. scRNA-seq · myasthenia gravis (NEW — with demo file attachment)
2. ADMET · imatinib
3. Microarray · colon cancer
4. WGS · NA12878

SMILES strings should NOT be in chip text — BioMate fetches compound structures by name.

## 3. Tutorial pages — add file attachment section

Any tutorial that shows DESeq2 or RNA-seq should show:
- How to attach local CSV files via the paperclip button
- What the file chips look like in the input
- That the system accepts standard count matrix / samplesheet / contrasts format

## 4. What does NOT need changing

- The workflow panel design (unchanged)
- The ADMET/PBPK flow (text-only, no files needed)
- The sidebar and chat message design
