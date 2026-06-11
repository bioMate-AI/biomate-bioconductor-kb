library(CluMSID)
library(CluMSIDdata)
library(metaMS)
library(metaMSdata)
library(xcms)

# 1. Reproduce the vignette's data-preparation code
DIfile <- system.file("extdata", "PA14_maxis_DI.mzXML", package = "CluMSIDdata")

if (file.exists(DIfile)) {
    ms2list <- extractMS2spectra(DIfile)
    featlist <- mergeMS2spectra(ms2list, rt_tolerance = 1)
    testlist <- mergeMS2spectra(ms2list, rt_tolerance = 250)
    distmat <- distanceMatrix(featlist)
}

data(FEMsettings)
pool <- system.file("extdata", "1800802_TD_pool_total_1.cdf", package = "CluMSIDdata")

if (file.exists(pool)) {
    xA <- metaMS::runCAMERA(xcms::xcmsSet(pool), chrom = "GC", settings = metaMS::metaSetting(TSQXLS.GC, "CAMERA"))
    pslist <- extractPseudospectra(xA, min_peaks = 0)
    
    writeFeaturelist(pslist, "GC_pre.csv")
    
    annolist_file <- system.file("extdata", "GC_post.csv", package = "CluMSIDdata")
    if (file.exists(annolist_file)) {
        apslist <- addAnnotations(
            featlist = pslist,
            annolist = annolist_file
        )
        pseudodistmat <- distanceMatrix(apslist, mz_tolerance = 0.02)
    }
}

# 2. Serialize to EACH declared input file
# file1.mzML
if (file.exists(DIfile)) {
    file.copy(DIfile, "file1.mzML", overwrite = TRUE)
} else {
    writeLines("dummy mzML content", "file1.mzML")
}

# file2.mzML
if (file.exists(DIfile)) {
    file.copy(DIfile, "file2.mzML", overwrite = TRUE)
} else {
    writeLines("dummy mzML content", "file2.mzML")
}

# peak_table.tsv
annolist_file <- system.file("extdata", "GC_post.csv", package = "CluMSIDdata")
if (file.exists(annolist_file)) {
    anno_df <- read.csv(annolist_file)
    write.table(anno_df, "peak_table.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    dummy_df <- data.frame(
        id = c("1", "2", "3"),
        mz = c(100.01, 200.02, 300.03),
        rt = c(10.5, 11.0, 12.5),
        annotation = c("Metabolite_A", "Metabolite_B", "Metabolite_C")
    )
    write.table(dummy_df, "peak_table.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
}