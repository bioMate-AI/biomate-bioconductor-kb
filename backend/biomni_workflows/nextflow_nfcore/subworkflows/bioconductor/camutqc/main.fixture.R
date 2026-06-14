# [biomate] structured fixture (rule: package_example_data) — deterministic, no LLM
# The CaMutQC package ships the exact vignette example files this workflow reads:
#   WES_EA_T_1_mutect2.vep.vcf  (VEP-annotated MuTect2 VCF — has the CSQ/Format header
#                                that vcfToMAF requires)
#   PON_test.txt                (panel-of-normals table)
#   Pan-cancer-hg38.rds         (bed/regions object passed as bedFile= to mutFilterCom)
# Copy them by their real names so the input contract is satisfied with real, valid data
# (sourcing a generic VCF from VariantAnnotation lacks the CSQ annotation and breaks vcfToMAF).
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
if (!requireNamespace("CaMutQC", quietly=TRUE)) tryCatch(BiocManager::install("CaMutQC", update=FALSE, ask=FALSE), error=function(e) NULL)

.ext <- system.file("extdata", package="CaMutQC")
stopifnot("CaMutQC extdata not found"=nzchar(.ext))

.copy_named <- function(fname) {
  cand <- list.files(.ext, pattern=paste0("^", gsub("([.\\^$*+?()\\[\\]{}|])", "\\\\\\1", fname), "$"),
                     recursive=TRUE, full.names=TRUE)
  if (!length(cand)) cand <- list.files(.ext, pattern=fname, recursive=TRUE, full.names=TRUE)
  if (!length(cand)) stop(paste0("CaMutQC example not found: ", fname))
  file.copy(cand[[1]], fname, overwrite=TRUE)
}

.copy_named("WES_EA_T_1_mutect2.vep.vcf")
.copy_named("PON_test.txt")
.copy_named("Pan-cancer-hg38.rds")
