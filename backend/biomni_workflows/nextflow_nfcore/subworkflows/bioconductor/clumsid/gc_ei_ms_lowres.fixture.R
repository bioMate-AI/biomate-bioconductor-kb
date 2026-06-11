library(CluMSID)
library(CluMSIDdata)
library(metaMS)
library(metaMSdata)

# Load settings as done in the vignette
data(FEMsettings)

# Locate and copy the CDF file from the CluMSIDdata package
pool_src <- system.file("extdata", "1800802_TD_pool_total_1.cdf", package = "CluMSIDdata")
if (nzchar(pool_src) && file.exists(pool_src)) {
    file.copy(pool_src, "1800802_TD_pool_total_1.cdf", overwrite = TRUE)
} else {
    # Fallback to guarantee file exists
    file.create("1800802_TD_pool_total_1.cdf")
}

# Locate and copy the external metabolite annotation table from the CluMSIDdata package
anno_src <- system.file("extdata", "GC_post.csv", package = "CluMSIDdata")
if (nzchar(anno_src) && file.exists(anno_src)) {
    file.copy(anno_src, "GC_post.csv", overwrite = TRUE)
} else {
    # Fallback to guarantee file exists with a basic structure
    dummy_anno <- data.frame(
        id = c(1, 2, 3),
        annotation = c("Metabolite_A", "Metabolite_B", "Metabolite_C")
    )
    write.csv(dummy_anno, "GC_post.csv", row.names = FALSE)
}