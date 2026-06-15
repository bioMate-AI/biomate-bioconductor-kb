---
name: bioconductor-rblast
description: Seamlessly interfaces the Basic Local Alignment Search Tool (BLAST) to search genetic sequence data bases. This work was partially supported by grant no. R21HG005912 from the National Human Genome Research Institute.
when_to_use: Use when: rBLAST: R Interface for the Basic Local Alignment Search Tool with rBLAST. Not for: rBLAST requires R/Bioconductor; see installation guide
user-invocable: false
---

# rblast

## Workflows

### Create Custom Blast Db

Create a custom BLAST database from user-provided sequences and query it locally.

```r
library(rBLAST)
library(Biostrings)
# Load example sequences
seq <- readRNAStringSet(system.file("examples/RNA_example.fasta", package = "rBLAST"))
# Write to FASTA
writeXStringSet(seq, filepath = "seqs.fasta")
# Create database
makeblastdb("seqs.fasta", db_name = "db/small", dbtype = "nucl")
```
Note: Input is an `XStringSet` object, and output is a set of local BLAST database files written to disk.

### Standard Workflow

Download, extract, and query an existing NCBI BLAST database using local BLAST.

```r
library(rBLAST)
# Download and extract 16S database
tgz_file <- blast_db_get("16S_ribosomal_RNA.tar.gz")
untar(tgz_file, exdir = "16S_rRNA_DB")

# Load existing database
bl <- blast(db = "./16S_rRNA_DB/16S_ribosomal_RNA")

# Query database
seq <- readRNAStringSet(system.file("examples/RNA_example.fasta", package = "rBLAST"))[1]
cl <- predict(bl, seq)
```
Note: Input is a path to a local BLAST database and a query `XStringSet` object; output is a `data.frame` of matches.

### Create And Query Custom Db

Seamlessly interfaces the Basic Local Alignment Search Tool (BLAST) to search genetic sequence data

```r
library(rBLAST)
library(Biostrings)
# 1. Read reference sequences
seq <- readRNAStringSet(system.file("examples/RNA_example.fasta", package = "rBLAST"))
# 2. Write sequences to a FASTA file
writeXStringSet(seq, filepath = "seqs.fasta")
# 3. Create custom BLAST database
makeblastdb("seqs.fasta", db_name = "db/small", dbtype = "nucl")
# 4. Load custom database
db <- blast("db/small")
# 5. Extract a subsequence fragment
fragment <- subseq(seq[1], start = 101, end = 200)
# 6. Query custom database
res <- predict(db, fragment)
```
Note: Input is a set of reference sequences and a query fragment; output is a `data.frame` of alignment matches.

## When to Use
- **Local BLAST Queries**: Running local BLAST queries directly from R using Bioconductor `XStringSet` objects (e.g., `RNAStringSet`, `DNAStringSet`).
- **Custom BLAST Databases**: Creating custom BLAST databases from local FASTA files using `makeblastdb` and querying them locally.
- **NCBI Database Downloads**: Downloading and caching pre-trained NCBI BLAST databases (e.g., 16S rRNA) using `blast_db_get`.

## When NOT to Use
- **Remote NCBI Queries**: For running BLAST queries remotely on NCBI servers without local BLAST+ installation (use `annotate::blastSequences` instead).
- **No Local BLAST+ Installation**: If the BLAST+ command-line tools are not installed on the system or not in the system `PATH`.

## Data Requirements
- Query sequences as `Biostrings::XStringSet` objects (e.g., `RNAStringSet`).
- Reference sequences in FASTA format for database creation.

## Key Parameters
- **db**: Path to the BLAST database in `blast()`.
- **db_name**: Output path and name prefix for the database in `makeblastdb()`.
- **dbtype** ("nucl"): Type of database to create ("nucl" or "prot") in `makeblastdb()`.
- **BLAST_args**: Additional command-line arguments passed to the BLAST executable in `predict()` (e.g., `"-perc_identity 99"`).
- **custom_format**: Custom output format string specifying columns to return in `predict()`.

## Best Practices
- Verify BLAST+ is installed and accessible in R using `has_blast()` or `Sys.which("blastn")`.
- Set the system `PATH` environment variable using `Sys.setenv` if R cannot find the BLAST+ executables.
- Organize custom database files by specifying a directory prefix (e.g., `db/small`) in `makeblastdb`.
- Use `unlink` with `recursive = TRUE` to clean up temporary database directories and FASTA files.

## Common Pitfalls
- **BLAST executable not found**: `Sys.which("blastn")` returns `""`. Fix: Set the `PATH` environment variable to include the BLAST+ installation directory.
- **Database files missing or corrupted**: Occurs if the database path is incorrect. Fix: Ensure the database prefix matches the one specified during `makeblastdb`.

## Alternatives
- **annotate**: Use `blastSequences` for querying the remote NCBI BLAST server.

## Citations
- Altschul, S. F., Gish, W., Miller, W., Myers, E. W., & Lipman, D. J. (1990). Basic local alignment search tool. Journal of Molecular Biology.

## References
- Homepage: bioconductor.org/packages/rblast
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/rblast/inst/doc/rblast.html
