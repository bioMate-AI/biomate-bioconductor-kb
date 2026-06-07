---
name: bioconductor-shortread
description: This package implements sampling, iteration, and input of FASTQ files. The package includes functions for filtering and trimming reads, and for generating a quality assessment report. Data are represented as DNAStringSet-derived objects, an
when_to_use: Use when: Iterative FASTQ Processing: Processing massive FASTQ files in memory-efficient chunks using FastqStreamer() and yield().; Random Subsampling: Drawing a random sample of reads from a FASTQ file using FastqSampler() for quick inspection.; Quality Assessment: Generating HTML quality assessment reports across multiple FASTQ files using qa() and report().; Filtering and Trimming: Removing low-quality r. Not for: For whole-genome alignments or flexible pairwise alignment, use Biostrings or pwalign instead because ShortRead is designed for basic input, QA, and filtering rather than complex alignments.
user-invocable: false
---

# ShortRead

## When to Use
- **Iterative FASTQ Processing**: Processing massive FASTQ files in memory-efficient chunks using `FastqStreamer()` and `yield()`.
- **Random Subsampling**: Drawing a random sample of reads from a FASTQ file using `FastqSampler()` for quick inspection.
- **Quality Assessment**: Generating HTML quality assessment reports across multiple FASTQ files using `qa()` and `report()`.
- **Filtering and Trimming**: Removing low-quality reads or trimming tails using `nFilter()` and `trimTailw()` before writing back to disk with `writeFastq()`.

## When NOT to Use
- For whole-genome alignments or flexible pairwise alignment, use **Biostrings** or **pwalign** instead because `ShortRead` is designed for basic input, QA, and filtering rather than complex alignments.

## Data Requirements
- **Input**: FASTQ files (e.g., `.fastq`, `.fastq.gz`) or legacy Solexa export files (`s_N_export.txt`).
- **Output**: Filtered FASTQ files, `ShortReadQ` objects, or HTML QA reports.
- **Data Structures**: Reads are represented as `DNAStringSet` objects and quality scores as `FastqQuality` or `BStringSet` objects.

## Key Parameters
- **fl**: The file path to the FASTQ file being read or streamed.
- **destination**: The output file path used in `writeFastq()`.
- **type**: The format type specified in `qa()` (e.g., `type="fastq"`).
- **dirPath**: The directory path used in `readXStringColumns()` to locate files.
- **pattern**: The regular expression pattern used to match files in `readXStringColumns()`.
- **colClasses**: A list specifying the class of each column to be read in `readXStringColumns()`.

## Best Practices
- Use `FastqStreamer()` in a `repeat` loop to process large FASTQ files in chunks, preventing memory exhaustion.
- Use `FastqSampler()` to draw a representative subset (e.g., 1M reads) for rapid quality assessment.
- Generate a QA report using `qa()` and view it in a browser using `browseURL(report())` before starting downstream analysis.
- Check the quality score encoding of your FASTQ files using `encoding(quality())` to ensure accurate quality filtering.

## Common Pitfalls
- **Out of Memory Errors**: Attempting to load an entire massive FASTQ file into memory with `readFastq()`. *Fix*: Use `FastqStreamer()` to iterate through the file in manageable chunks.
- **Incorrect Quality Trimming**: Applying the wrong Phred score threshold because of unknown encoding. *Fix*: Verify the encoding using `encoding(quality(fq))` before using `trimTailw()`.
- **Slow Text Parsing**: Using base R functions to read specific columns of sequence text files. *Fix*: Use `readXStringColumns()` to quickly parse columns directly into `DNAStringSet` and `BStringSet` objects.

## Alternatives
- **Biostrings**: For general sequence manipulation, pattern matching (`matchPDict`), and whole-genome alignments.
- **pwalign**: For flexible pairwise sequence alignment.

## Citations
- Morgan M, et al. (2009) "ShortRead: a bioconductor package for input, quality assessment and exploration of high-throughput sequence data." Bioinformatics.

## References
- Homepage: https://bioconductor.org/packages/ShortRead
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ShortRead/inst/doc/Overview.pdf
