library(NoRCE)

# 1. Generate or load brain_mirna
has_brain_mirna <- FALSE
try({
    data("brain_mirna", package = "NoRCE", envir = environment())
    if (exists("brain_mirna")) {
        writeLines(as.character(brain_mirna), "brain_mirna")
        has_brain_mirna <- TRUE
    }
}, silent = TRUE)

if (!has_brain_mirna) {
    # Fallback to synthetic miRBase names if dataset is not available
    writeLines(c("hsa-let-7a-5p", "hsa-let-7b-5p", "hsa-mir-124-3p"), "brain_mirna")
}

# 2. Generate or load brain_disorder_ncRNA
has_brain_disorder <- FALSE
try({
    data("brain_disorder_ncRNA", package = "NoRCE", envir = environment())
    if (exists("brain_disorder_ncRNA")) {
        writeLines(as.character(brain_disorder_ncRNA), "brain_disorder_ncRNA")
        has_brain_disorder <- TRUE
    }
}, silent = TRUE)

if (!has_brain_disorder) {
    # Fallback to synthetic Ensembl gene IDs if dataset is not available
    writeLines(c("ENSG00000228630", "ENSG00000230021", "ENSG00000237973"), "brain_disorder_ncRNA")
}

# 3. Generate custom.gmt
# GMT format: Pathway Name \t Description \t Gene1 \t Gene2 ...
# The vignette states GMT supports ENTREZ ID or Symbol.
gmt_content <- c(
    "Custom_Pathway_1\tSynthetic_Description_1\t100\t200\tTP53\tBRCA1",
    "Custom_Pathway_2\tSynthetic_Description_2\t300\t400\tEGFR\tMYC"
)
writeLines(gmt_content, "custom.gmt")