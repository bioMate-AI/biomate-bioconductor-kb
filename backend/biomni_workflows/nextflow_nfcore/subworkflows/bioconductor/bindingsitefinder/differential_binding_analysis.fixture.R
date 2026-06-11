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

extdata_dir <- system.file("extdata", package="BindingSiteFinder")

# 1. BED files (PureCLIP crosslink sites)
csFile <- file.path(extdata_dir, "PureCLIP_crosslink_sites_examples.bed")
if (file.exists(csFile)) {
    file.copy(csFile, "wt_pureclip.bed", overwrite = TRUE)
    file.copy(csFile, "ko_pureclip.bed", overwrite = TRUE)
} else {
    gr_bed <- GRanges("chr1", IRanges(629906, width=1), strand="+", name="3", score=27.3)
    export(gr_bed, "wt_pureclip.bed", format="BED")
    export(gr_bed, "ko_pureclip.bed", format="BED")
}

# 2. BigWig files (Coverage)
clipFilesP <- list.files(extdata_dir, pattern = "plus.bw$", full.names = TRUE)
clipFilesM <- list.files(extdata_dir, pattern = "minus.bw$", full.names = TRUE)

if (length(clipFilesP) > 0) {
    file.copy(clipFilesP[1], "wt_plus.bw", overwrite = TRUE)
    file.copy(clipFilesP[1], "ko_plus.bw", overwrite = TRUE)
} else {
    gr_bw <- GRanges("chr1", IRanges(1, 100), score=1)
    seqlengths(gr_bw) <- c(chr1=1000)
    export(gr_bw, "wt_plus.bw", format="BigWig")
    export(gr_bw, "ko_plus.bw", format="BigWig")
}

if (length(clipFilesM) > 0) {
    file.copy(clipFilesM[1], "wt_minus.bw", overwrite = TRUE)
    file.copy(clipFilesM[1], "ko_minus.bw", overwrite = TRUE)
} else {
    gr_bw <- GRanges("chr1", IRanges(1, 100), score=1)
    seqlengths(gr_bw) <- c(chr1=1000)
    export(gr_bw, "wt_minus.bw", format="BigWig")
    export(gr_bw, "ko_minus.bw", format="BigWig")
}

# 3. GFF3 file (GENCODE gene annotation)
# Construct a synthetic GFF3 file that matches the expected format for txdbmaker::makeTxDbFromGFF
gr_gene <- GRanges("chr1", IRanges(629000, 630000), strand="+", type="gene", 
                   ID="gene1", gene_id="gene1", gene_name="gene1", gene_type="protein_coding")
gr_tx <- GRanges("chr1", IRanges(629000, 630000), strand="+", type="transcript", 
                 ID="tx1", Parent="gene1", transcript_id="tx1")
gr_exon <- GRanges("chr1", IRanges(629000, 630000), strand="+", type="exon", 
                   ID="exon1", Parent="tx1", exon_id="exon1")
gr_cds <- GRanges("chr1", IRanges(629000, 630000), strand="+", type="CDS", 
                  ID="cds1", Parent="tx1", protein_id="prot1")

gr_all <- c(gr_gene, gr_tx, gr_exon, gr_cds)
export(gr_all, "gencode_v37_annotation.gff3", format="gff3")