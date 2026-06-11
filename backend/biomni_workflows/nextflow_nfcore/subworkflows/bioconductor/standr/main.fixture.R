library(standR)
library(SpatialExperiment)

# 1. Generate synthetic count data
# The vignette uses ExperimentHub to load data.frames, but the workflow reads from files.
# We construct a synthetic dataset that matches the expected GeoMx DSP format and 
# contains the specific columns referenced in the vignette's downstream analysis.
set.seed(123)
genes <- paste0("Gene", 1:600)
neg_probes <- paste0("NegProbe", 1:5)
targets <- c(genes, neg_probes)
samples <- paste0("Sample", 1:12)

# Generate counts with a high enough lambda so that lib_size > 50000 (as required by the vignette's filtering step)
counts_mat <- matrix(rpois(605 * 12, lambda = 2000), nrow = 605, ncol = 12)
counts <- data.frame(TargetName = targets, counts_mat)
colnames(counts)[2:13] <- samples

# 2. Generate synthetic sample annotation
# Must include columns: SlideName, disease_status, region, SegmentLabel, pathology
sample_anno <- data.frame(
  Sample_ID = samples,
  SlideName = rep(c("disease1B", "healthy1", "disease2"), each = 4),
  disease_status = rep(c("disease", "healthy", "disease"), each = 4),
  region = rep(c("glomerulus", "tubule"), times = 6),
  SegmentLabel = rep("Geometric Segment", 12),
  pathology = rep(c("abnormal", "neg"), times = 6)
)

# 3. Generate synthetic feature annotation
# Must include TargetName and a column to identify negative probes (CodeClass)
feature_anno <- data.frame(
  TargetName = targets,
  CodeClass = c(rep("Endogenous", 600), rep("Negative", 5))
)

# 4. Write to the exact filenames expected by the workflow
# readGeoMx uses read.delim for character inputs, so we use tab separation.
write.table(counts, "countFile", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(sample_anno, "sampleAnnoFile", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(feature_anno, "featureAnnoFile", sep = "\t", row.names = FALSE, quote = FALSE)