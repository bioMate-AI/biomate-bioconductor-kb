library(comapr)
library(GenomicRanges)
library(Matrix)

# 1. Reproduce the vignette's data preparation
data(snp_geno_gr)
data(parents_geno)

corrected_geno <- correctGT(gt_matrix = mcols(snp_geno_gr), 
                            ref = parents_geno$ref, 
                            alt = parents_geno$alt, 
                            fail = "Fail", 
                            wrong_label = "Homo_ref")
mcols(snp_geno_gr) <- corrected_geno

# 2. Construct the required input files for readHapState
# The workflow reads sscocaller output files: barcodes, vi.mtx, snpAnnot, viSegInfo
# We will try to find them in comapr's extdata, otherwise generate synthetic ones.

extdata_dir <- system.file("extdata", package="comapr")
mtx_files <- list.files(extdata_dir, pattern="vi\\.mtx$", recursive=TRUE, full.names=TRUE)

if (length(mtx_files) > 0) {
  mtx_file <- mtx_files[1]
  dir_path <- dirname(mtx_file)
  
  barcode_file <- list.files(dir_path, pattern="barcodes\\.txt$", full.names=TRUE)[1]
  snp_file <- list.files(dir_path, pattern="snpAnnot\\.txt$", full.names=TRUE)[1]
  seg_file <- list.files(dir_path, pattern="viSegInfo\\.txt$", full