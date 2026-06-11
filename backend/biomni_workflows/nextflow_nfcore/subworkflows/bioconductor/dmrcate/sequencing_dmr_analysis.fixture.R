# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DMRcate", "bsseq", "GenomicRanges", "edgeR", "limma", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DMRcate)
library(bsseq)
library(GenomicRanges)
library(edgeR)
library(limma)
library(SummarizedExperiment)

# 1. Construct a mock BSseq object to replace the offline-incompatible ExperimentHub fetch
sample_names <- c("Lymph_N-Treg-1", "Lymph_N-Treg-2", 
                  "Lymph_N-Tcon-1", "Lymph_N-Tcon-2",
                  "Fat-Treg-1", "Fat-Treg-2",
                  "Skin-Treg-1", "Skin-Treg-2",
                  "Liver-Treg-1", "Liver-Treg-2")

num_cpgs <- 1000
set.seed(123)
M <- matrix(rbinom(num_cpgs * length(sample_names), 50, 0.5), ncol = length(sample_names))
Cov <- matrix(rpois(num_cpgs * length(sample_names), 50), ncol = length(sample_names))
Cov <- Cov + M # Cov must be >= M

colnames(M) <- sample_names
colnames(Cov) <- sample_names

gr <- GRanges(seqnames = "chr19", ranges = IRanges(start = 1:num_cpgs * 100, width = 1))

bis_1072 <- BSseq(M = M, Cov = Cov, pos = start(gr), chr = as.character(seqnames(gr)), sampleNames = sample_names)

# Apply the vignette's exact pData logic
bsseq::pData(bis_1072) <- data.frame(replicate=gsub(".*-", "", colnames(bis_1072)),
                              tissue=substr(colnames(bis_1072), 1, 
                                            nchar(colnames(bis_1072))-3), 
                              row.names=colnames(bis_1072))
colData(bis_1072)$tissue <- gsub("-", "_", colData(bis_1072)$tissue)

# 2. Create the methylation design matrix
tissue <- factor(pData(bis_1072)$tissue)
tissue <- relevel(tissue, "Liver_Treg")

design <- model.matrix(~tissue)
colnames(design) <- gsub("tissue", "", colnames(design))
colnames(design)[1] <- "Intercept"
rownames(design) <- colnames(bis_1072)

methdesign <- edgeR::modelMatrixMeth(design)

# 3. Create the contrast matrix
cont.mat <- limma::makeContrasts(treg_vs_tcon=Lymph_N_Treg-Lymph_N_Tcon,
                                 fat_vs_ln=Fat_Treg-Lymph_N_Treg,
                                 skin_vs_ln=Skin_Treg-Lymph_N_Treg,
                                 fat_vs_skin=Fat_Treg-Skin_Treg,
                                 levels=methdesign)

# 4. Serialize to the declared input files
saveRDS(bis_1072, "bis_1072")
saveRDS(methdesign, "methdesign")
saveRDS(cont.mat, "cont.mat")