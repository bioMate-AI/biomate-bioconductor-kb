library(factR)
library(rtracklayer)
library(BSgenome.Mmusculus.UCSC.mm10)

# 1. custom_assembled_transcriptome.gtf
custom_gtf_src <- system.file("extdata", "sc_merged_sample.gtf.gz", package = "factR")
if (file.exists(custom_gtf_src)) {
    gr_custom <- import(custom_gtf_src, format = "gtf")
    export(gr_custom, "custom_assembled_transcriptome.gtf", format = "gtf")
} else {
    # Fallback synthetic data if the file is missing
    gr_custom <- GRanges("chr15", IRanges(3180731, 3180944), strand = "*")
    gr_custom$type <- "transcript"
    gr_custom$gene_id <- "MSTRG.14523"
    gr_custom$transcript_id <- "MSTRG.14523.1"
    export(gr_custom, "custom_assembled_transcriptome.gtf", format = "gtf")
}

# 2. reference_transcriptome.gtf
ref_gtf_src <- list.files(system.file("extdata", package = "factR"), pattern = "gencode.*\\.gtf\\.gz$", full.names = TRUE)
if (length(ref_gtf_src) > 0) {
    gr_ref <- import(ref_gtf_src[1], format = "gtf")
    export(gr_ref, "reference_transcriptome.gtf", format = "gtf")
} else {
    # Fallback to using the custom GTF as the reference if the specific gencode file is not shipped
    export(gr_custom, "reference_transcriptome.gtf", format = "gtf")
}

# 3. genome_sequence
# The workflow can read a serialized BSgenome object via readRDS
saveRDS(BSgenome.Mmusculus.UCSC.mm10, "genome_sequence")