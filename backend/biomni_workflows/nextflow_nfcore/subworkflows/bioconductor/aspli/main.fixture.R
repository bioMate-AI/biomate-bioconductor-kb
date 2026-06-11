# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ASpli")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ASpli)

# 1. Genome annotation file (genes.gtf)
gtfFileName <- aspliExampleGTF()
file.copy(gtfFileName, "genes.gtf", overwrite = TRUE)

# 2. Directory containing BAM and BAI files for each sample (sample_bams/)
dir.create("sample_bams", showWarnings = FALSE)
bam_files <- aspliExampleBamList()

for (bam in bam_files) {
    file.copy(bam, file.path("sample_bams", basename(bam)), overwrite = TRUE)
    bai <- paste0(bam, ".bai")
    if (file.exists(bai)) {
        file.copy(bai, file.path("sample_bams", basename(bai)), overwrite = TRUE)
    }
}

# 3. Directory containing replicate-merged BAM and BAI files for each condition (merged_bams/)
dir.create("merged_bams", showWarnings = FALSE)
merged_bams_original <- unique(sub("_[012]", "", bam_files))

for (mbam in merged_bams_original) {
    if (file.exists(mbam)) {
        # If the package ships the merged BAMs directly, copy them
        file.copy(mbam, file.path("merged_bams", basename(mbam)), overwrite = TRUE)
        mbai <- paste0(mbam, ".bai")
        if (file.exists(mbai)) {
            file.copy(mbai, file.path("merged_bams", basename(mbai)), overwrite = TRUE)
        }
    } else {
        # Fallback: copy the first corresponding sample BAM and rename it to act as the merged BAM
        match_idx <- which(sub("_[012]", "", bam_files) == mbam)[1]
        sbam <- bam_files[match_idx]
        file.copy(sbam, file.path("merged_bams", basename(mbam)), overwrite = TRUE)
        sbai <- paste0(sbam, ".bai")
        if (file.exists(sbai)) {
            file.copy(sbai, file.path("merged_bams", paste0(basename(mbam), ".bai")), overwrite = TRUE)
        }
    }
}