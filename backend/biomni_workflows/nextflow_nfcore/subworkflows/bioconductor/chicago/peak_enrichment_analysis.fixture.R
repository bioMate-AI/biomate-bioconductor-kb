library(Chicago)
library(PCHiCdata)

# 1. cd (Processed chicagoData object)
cd_shipped <- list.files(system.file("extdata", package="Chicago"), pattern="^cd$", recursive=TRUE, full.names=TRUE)
if (length(cd_shipped) > 0) {
    file.copy(cd_shipped[1], "cd")
} else {
    env <- new.env()
    data_loaded <- try(data("cd", package="Chicago", envir=env), silent=TRUE)
    if (!inherits(data_loaded, "try-error") && "cd" %in% ls(env)) {
        saveRDS(env$cd, "cd")
    } else {
        dataPath <- system.file("extdata", package="PCHiCdata")
        testDesignDir <- file.path(dataPath, "hg19TestDesign")
        testDataPath <- file.path(dataPath, "GMchinputFiles")
        files <- c(
          file.path(testDataPath, "GM_rep1.chinput"),
          file.path(testDataPath, "GM_rep2.chinput"),
          file.path(testDataPath, "GM_rep3.chinput")
        )
        settingsFile <- file.path(system.file("extdata", package="PCHiCdata"), "sGM12878Settings", "sGM12878.settingsFile")

        cd_obj <- setExperiment(designDir = testDesignDir, settingsFile = settingsFile)
        cd_obj <- readAndMerge(files=files, cd=cd_obj)
        cd_obj <- chicagoPipeline(cd_obj)
        saveRDS(cd_obj, "cd")
    }
}

# 2. featuresGM.txt (Tab-delimited table mapping feature names to bed/narrowPeak files)
features_shipped <- list.files(system.file("extdata", package="Chicago"), pattern="featuresGM.txt", recursive=TRUE, full.names=TRUE)
if (length(features_shipped) > 0) {
    file.copy(features_shipped[1], "featuresGM.txt")
} else {
    write.table(
        data.frame(V1="CTCF", V2="spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak"),
        "featuresGM.txt", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE
    )
}

# 3. spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak (Genomic feature interval file)
peak_shipped <- list.files(system.file("extdata", package="Chicago"), pattern="spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak", recursive=TRUE, full.names=TRUE)
if (length(peak_shipped) > 0) {
    file.copy(peak_shipped[1], "spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak")
} else {
    write.table(
        data.frame(chr="chr20", start=119103, end=138049, name="peak1", score=1000, strand=".", signalValue=10, pValue=5, qValue=5, peak=250),
        "spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE
    )
}