library(RiboDiPA)
library(Rsamtools)
library(rtracklayer)
library(GenomicRanges)

# Define file names as in the vignette
file_names <- c("WT1.bam", "WT2.bam", "MUT1.bam", "MUT2.bam", "eg.gtf")

# 1. Generate the GTF file (bam_path[5])
# We use "seq1" to match the sequence names in the Rsamtools example BAM file
gr <- GRanges(
    seqnames = "seq1",
    ranges = IRanges(start = c(1, 500), end = c(400, 900)),
    strand = "+",
    type = "exon",
    gene_id = "gene1",
    transcript_id = "tx1"
)
export(gr, "eg.gtf", format = "gtf")

# 2. Generate the BAM files (bam_path[1:4]) using Rsamtools example data
ex_bam <- system.file("extdata", "ex1.bam", package = "Rsamtools")
for (i in 1:4) {
    file.copy(ex_bam, file_names[i], overwrite = TRUE)
    # Create BAM indices as they are often required by alignment processing tools
    indexBam(file_names[i])
}

# 3. Create the bam_path vector as expected by the vignette and workflow
bam_path <- file_names

# 4. Create the classlabel object as in the vignette
classlabel <- data.frame(
    condition = c("mutant", "mutant", "wildtype", "wildtype"),
    comparison = c(2, 2, 1, 1)
)
rownames(classlabel) <- c("mutant1", "mutant2", "wildtype1", "wildtype2")

# Verify files exist
stopifnot(all(file.exists(bam_path)))