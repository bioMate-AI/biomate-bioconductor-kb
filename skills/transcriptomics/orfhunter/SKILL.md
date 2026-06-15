---
name: bioconductor-orfhunter
description: The ORFhunteR package is a R and C++ library for an automatic determination and annotation of open reading frames (ORF) in a large set of RNA molecules. It efficiently implements the machine learning model based on vectorization of nucleotide sequences and the random forest classification algorithm. The ORFhunteR package consists of a set of functions written in the R language in conjunction with C++. The efficiency of the package was confirmed by the examples of the analysis of RNA molecules fr
when_to_use: Use when: The ORFhunteR package is a R and C++ library for an automatic determination and annotation of open reading frames (ORF); The ORFhunteR package: User’s manual. Not for: Requires R ≥ 4.0.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# ORFhunteR

## Workflows

### Predict And Annotate Orfs

```r
library(ORFhunteR)

trans <- system.file("extdata", "Set.trans_sequences.fasta", package = "ORFhunteR")
model <- "http://www.sstcenter.com/download/ORFhunteR/classRFmodel_1.rds"

# Predict ORFs
ORFs <- predictORF(tr = trans, model = model, prThr = 0)

# Write coordinates to a temporary file for downstream functions
orfs_path <- tempfile(fileext = ".txt")
write.table(ORFs, file = orfs_path, sep = "\t", row.names = FALSE, quote = FALSE)

# Extract sequences
seq_orfs <- getSeqORFs(orfs = orfs_path, tr = trans, genome = "BSgenome.Hsapiens.UCSC.hg38")

# Find PTCs
gtf_path <- system.file("extdata", "Set.trans_sequences.gtf", package = "ORFhunteR")
ptcs <- findPTCs(orfs = orfs_path, gtf = gtf_path)

# Translate ORFs
seq_orf_path <- system.file("extdata", "Set.trans_ORFs.sequences.fasta", package = "ORFhunteR")
prot_seqs <- translateORFs(seqORFs = seq_orf_path)

# Annotate ORFs
prts_path <- system.file("extdata", "Set.trans_proteins.sequences.fasta", package = "ORFhunteR")
anno_orfs <- annotateORFs(orfs = orfs_path, tr = trans, gtf = gtf_path, prts = prts_path)
```
*Input:* FASTA file of transcript sequences and a pre-trained Random Forest model.  
*Output:* Predicted ORFs, extracted sequences, PTC status, translated proteins, and a comprehensive annotation table.

### Standard Workflow

```r
library(ORFhunteR)

# Load pseudo-ORFs (lncRNAs) and true ORFs (mRNAs)
fileORFLncRNAs <- "http://www.sstcenter.com/download/ORFhunteR/NCBI_RefSeq_release_109_GRCh38.p12_ORF_candidates_sequences_lncRNAs.fasta.gz"
ORFLncRNAs <- loadTrExper(tr = fileORFLncRNAs)

fileORFmRNAs <- "http://www.sstcenter.com/download/ORFhunteR/NCBI_RefSeq_release_109_GRCh38.p12_ORFs_true_sequences_mRNAs.fasta.gz"
ORFmRNAs <- loadTrExper(tr = fileORFmRNAs)

# Train the Random Forest classifier
clt <- classifyORFsCandidates(
  ORFLncRNAs = ORFLncRNAs[1:10],
  ORFmRNAs = ORFmRNAs[1:10],
  pLearn = 0.75,
  nTrees = 10
)
```
*Input:* Lists of pseudo-ORFs and true coding ORFs.  
*Output:* A trained `randomForest` classifier object.

### Orf Prediction And Annotation

```r
library(ORFhunteR)

trans <- system.file("extdata", "Set.trans_sequences.fasta", package = "ORFhunteR")
model <- "http://www.sstcenter.com/download/ORFhunteR/classRFmodel_1.rds"

# 1. Predict true ORFs
ORFs <- predictORF(tr = trans, model = model, prThr = 0)

# 2. Extract nucleotide sequences of predicted ORFs
orfs_path <- system.file("extdata", "Set.trans_ORFs.coordinates.txt", package = "ORFhunteR")
seq_orfs <- getSeqORFs(orfs = orfs_path, tr = trans, genome = "BSgenome.Hsapiens.UCSC.hg38")

# 3. Detect premature termination codons (PTCs)
gtf_path <- system.file("extdata", "Set.trans_sequences.gtf", package = "ORFhunteR")
ptcs <- findPTCs(orfs = orfs_path, gtf = gtf_path)

# 4. Translate predicted ORFs into amino acid sequences
seq_orf_path <- system.file("extdata", "Set.trans_ORFs.sequences.fasta", package = "ORFhunteR")
prot_seqs <- translateORFs(seqORFs = seq_orf_path)

# 5. Generate a comprehensive annotation table
prts_path <- system.file("extdata", "Set.trans_proteins.sequences.fasta", package = "ORFhunteR")
anno_orfs <- annotateORFs(orfs = orfs_path, tr = trans, gtf = gtf_path, prts = prts_path)
```
*Input:* Transcript sequences, coordinates of ORFs, GTF file, and protein sequences.  
*Output:* Annotated ORF table containing molecular weight, isoelectric point, and potential protein interaction index.

## When to Use
- Automatically identifying and annotating open reading frames (ORFs) in large sets of RNA molecules.
- Vectorizing sequence features of ORFs (mono-, di-, trinucleotide frequencies, Bao model entropy, etc.) using `vectorizeORFs`.
- Training custom Random Forest classifiers to distinguish true ORFs from pseudo-ORFs using `classifyORFsCandidates`.
- Translating nucleotide sequences of identified ORFs into amino acid sequences using `translateORFs`.

## When NOT to Use
- For general gene annotation or transcript assembly from RNA-seq reads; use `StringTie` or `Scallop` instead.
- For predicting protein 3D structures or detailed functional domains; use specialized tools like `InterProScan` or `AlphaFold`.

## Data Requirements
- Transcript sequences in `fasta` or `fa` format (or `gtf`/`gff` format with a corresponding `BSgenome` package like `BSgenome.Hsapiens.UCSC.hg38`).
- Coordinates of ORFs in a tab-delimited TXT file (as generated by `predictORF`).
- Transcript structure in `gtf` or `gff` format for PTC detection.

## Key Parameters
- **tr**: Character string giving the path to the file with transcripts of interest (FASTA, FA, GTF, or GFF).
- **model**: Character string giving the path or connection to the pre-trained Random Forest model RDS file.
- **prThr** (`0`): Probability threshold for the winning class of ORFs.
- **codStart** (`"ATG"`): Start codon to scan for in `findORFs`.
- **pLearn** (`0.75`): Fraction of ORFs used for the training set in `classifyORFsCandidates`.
- **nTrees** (`500`): Number of trees to grow in the Random Forest model.
- **genome** (`"BSgenome.Hsapiens.UCSC.hg38"`): Name of the pre-installed BSgenome data package.

## Best Practices
- Use `loadTrExper` to safely load and parse transcript sequences from FASTA or GTF files.
- Filter out low-probability ORF candidates by setting a strict probability threshold `prThr` (e.g., 0.9) in `predictORF` to reduce false positives.
- Ensure that the transcript IDs in the coordinates file (`orfs`), transcript sequences (`tr`), and GTF file (`gtf`) match exactly when running `annotateORFs` or `findPTCs`.

## Common Pitfalls
- **Missing BSgenome Package**: Running `getSeqORFs` or `predictORF` with GTF/GFF inputs fails if the specified `genome` package is not installed. Fix: Install the required `BSgenome` package (e.g., `BSgenome.Hsapiens.UCSC.hg38`) before running.
- **Mismatched Transcript IDs**: Downstream annotation functions fail to find matching transcripts. Fix: Verify that the transcript IDs in the FASTA, GTF, and coordinates files are identical.
- **Low Random Forest Accuracy**: Training a model with too few trees or too small a dataset. Fix: Use a larger training set (e.g., N = 1000) and set `nTrees` to at least 500 in `classifyORFsCandidates`.

## Alternatives
- **systemPipeR**: For general workflow management including ORF prediction.
- **Biostrings**: For basic sequence manipulation and translation without machine learning-based ORF classification.

## Citations
- Vasily V. Grinev, Mikalai M. Yatskou, Victor V. Skakun, Maryna K. Chepeleva, Petr V. Nazarov (2021). ORFhunteR: an accurate approach for the automatic identification and annotation of open reading frames in human mRNA molecules. bioRxiv.

## References
- Homepage: https://bioconductor.org/packages/orfhunter
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/orfhunter/inst/doc/ORFhunteR.html
