# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BindingSiteFinder", "rtracklayer", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BindingSiteFinder)
library(rtracklayer)
library(GenomicRanges)

# 1. PureCLIP_crosslink_sites_examples.bed
csFile <- system.file("extdata", "PureCLIP_crosslink_sites_examples.bed", package="BindingSiteFinder")
if (file.exists(csFile) && csFile != "") {
    file.copy(csFile, "PureCLIP_crosslink_sites_examples.bed", overwrite = TRUE)
} else {
    bed_data <- data.frame(
        chrom = "chr1",
        chromStart = 629905,
        chromEnd = 629906,
        name = "3",
        score = 27.3,
        strand = "+"
    )
    write.table(bed_data, "PureCLIP_crosslink_sites_examples.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}

# 2. plus.bw
plus_files <- list.files(system.file("extdata", package="BindingSiteFinder"), pattern = "plus\\.bw$", full.names = TRUE)
if (length(plus_files) > 0) {
    file.copy(plus_files[1], "plus.bw", overwrite = TRUE)
} else {
    gr_plus <- GRanges("chr1", IRanges(629905, 629906), strand="+", score=1)
    seqlengths(gr_plus) <- c(chr1=1000000)
    export.bw(gr_plus, "plus.bw")
}

# 3. minus.bw
minus_files <- list.files(system.file("extdata", package="BindingSiteFinder"), pattern = "minus\\.bw$", full.names = TRUE)
if (length(minus_files) > 0) {
    file.copy(minus_files[1], "minus.bw", overwrite = TRUE)
} else {
    gr_minus <- GRanges("chr1", IRanges(629905, 629906), strand="-", score=1)
    seqlengths(gr_minus) <- c(chr1=1000000)
    export.bw(gr_minus, "minus.bw")
}

# 4. gencode_v37_annotation.gff3
gff_file <- list.files(system.file("extdata", package="BindingSiteFinder"), pattern = "gencode.*\\.gff3$", full.names = TRUE)
if (length(gff_file) > 0) {
    file.copy(gff_file[1], "gencode_v37_annotation.gff3", overwrite = TRUE)
} else {
    gff_lines <- c(
        "##gff-version 3",
        "##sequence-region chr22 1 50818468",
        "chr22\tHAVANA\tgene\t15528192\t15529139\t.\t+\t.\tID=ENSG00000008735.14;gene_id=ENSG00000008735.14;gene_type=protein_coding;gene_name=MAPK8IP2",
        "chr22\tHAVANA\ttranscript\t15528192\t15529139\t.\t+\t.\tID=ENST00000008735.14;Parent=ENSG00000008735.14;gene_id=ENSG00000008735.14;transcript_id=ENST00000008735.14;gene_type=protein_coding;gene_name=MAPK8IP2",
        "chr22\tHAVANA\texon\t15528192\t15529139\t.\t+\t.\tID=exon1;Parent=ENST00000008735.14;gene_id=ENSG00000008735.14;transcript_id=ENST00000008735.14;gene_type=protein_coding;gene_name=MAPK8IP2"
    )
    writeLines(gff_lines, "gencode_v37_annotation.gff3")
}