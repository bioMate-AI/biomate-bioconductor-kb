library(Chicago)
library(PCHiCdata)
library(GenomicRanges)

# 1. Reproduce the vignette's data-preparation code for the chicagoData object
dataPath <- system.file("extdata", package="PCHiCdata")
testDesignDir <- file.path(dataPath, "hg19TestDesign")
testDataPath <- file.path(dataPath, "GMchinputFiles")

files <- c(
  file.path(testDataPath, "GM_rep1.chinput"),
  file.path(testDataPath, "GM_rep2.chinput"),
  file.path(testDataPath, "GM_rep3.chinput")
)

settingsFile <- file.path(system.file("extdata", package="PCHiCdata"), 
                          "sGM12878Settings", "sGM12878.settingsFile")

cd <- setExperiment(designDir = testDesignDir, settingsFile = settingsFile)
cd <- readAndMerge(files=files, cd=cd)

# Run the pipeline (suppressing plot outputs to avoid Rplots.pdf creation)
pdf(file = NULL)
cd <- chicagoPipeline(cd)
dev.off()

# 2. Serialize the processed chicagoData object
saveRDS(cd, "cd.rds")

# 3. Construct a synthetic GRanges object for the enhancerTrack (since AnnotationHub is offline)
enhancerTrack <- GRanges(
    seqnames = c("20", "20", "21"),
    ranges = IRanges(start = c(119000, 233000, 1000000), width = 1000),
    feature = c("H3K4me1", "H3K4me1", "H3K27ac")
)

# 4. Serialize the enhancerTrack object
saveRDS(enhancerTrack, "enhancerTrack.rds")