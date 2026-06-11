# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DMRcaller", "BSgenome.Hsapiens.UCSC.hg38", "Biostrings", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DMRcaller)
library(BSgenome.Hsapiens.UCSC.hg38)
library(Biostrings) # For writing FASTA files
library(rtracklayer) # For writing GFF files

# 1. Prepare and serialize 'aligned_ont.bam'
# The vignette provides an example BAM file within the DMRcaller package.
# We copy this example file to the expected input filename.
bam_source_path <- system.file("extdata", "scanBamChr1Random5.bam", package="DMRcaller")
file.copy(bam_source_path, "aligned_ont.bam", overwrite = TRUE)

# 2. Prepare and serialize 'hg38_genome.fa'
# The vignette uses BSgenome.Hsapiens.UCSC.hg38 for genomic context,
# specifically referencing "chr1" in the selectCytosine example.
# We extract the sequence for "chr1" and write it to a FASTA file.
genome_obj <- BSgenome.Hsapiens.UCSC.hg38
chr1_sequence <- getSeq(genome_obj, "chr1")
names(chr1_sequence) <- "chr1" # Ensure the FASTA header is correctly set
writeXStringSet(chr1_sequence, "hg38_genome.fa")

# 3. Prepare and serialize 'transcripts.gff'
# The vignette does not explicitly use or generate a GFF file for "transcripts".
# However, it generates a GRanges object 'gr_cpg' representing cytosine positions
# on "chr1" in CG context. This is the only GRanges object derived directly
# from the vignette's code that can be serialized to a GFF file without
# inventing data. We use this object as the content for 'transcripts.gff'.
gr_cpg <- selectCytosine(
    genome = BSgenome.Hsapiens.UCSC.hg38,
    context = "CG",
    chr = "chr1"
)
export.gff3(gr_cpg, "transcripts.gff")