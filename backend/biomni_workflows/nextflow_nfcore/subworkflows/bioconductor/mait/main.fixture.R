library(MAIT)
library(faahKO)

# Locate the raw CDF files from the faahKO package
cdfFiles <- system.file("cdf", package="faahKO", mustWork=TRUE)

# Run the MAIT processing steps as described in the vignette
MAIT_obj <- sampleProcessing(dataDir = cdfFiles, project = "MAIT_Demo", snThres=2, rtStep=0.03)
MAIT_obj <- peakAnnotation(MAIT.object = MAIT_obj, corrWithSamp = 0.7, corrBetSamp = 0.75, perfwhm = 0.6)
MAIT_obj <- spectralSigFeatures(MAIT.object = MAIT_obj, pvalue=0.05, p.adj="none", scale=FALSE)

# Extract the required data components
peaks <- scores(MAIT_obj)
masses <- getPeaklist(MAIT_obj)$mz
rt <- getPeaklist(MAIT_obj)$rt/60

# Save the extracted components to the expected input files
saveRDS(as.matrix(peaks), "peaks_matrix.rds")
saveRDS(as.numeric(masses), "masses_vector.rds")
saveRDS(as.numeric(rt), "rt_vector.rds")