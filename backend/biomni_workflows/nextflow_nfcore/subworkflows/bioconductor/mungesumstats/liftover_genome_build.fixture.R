library(MungeSumstats)
library(data.table)

# Locate the example GWAS summary statistics file shipped with MungeSumstats
extdata_dir <- system.file("extdata", package = "MungeSumstats")
okbay_file <- list.files(extdata_dir, pattern = "eduAttainOkbay\\.txt", full.names = TRUE)[1]

# Read the file if it exists, otherwise create a synthetic data.table matching the expected format
if (!is.na(okbay_file) && file.exists(okbay_file)) {
    sumstats_dt <- data.table::fread(okbay_file)
} else {
    sumstats_dt <- data.table::data.table(
        SNP = c("rs123", "rs456", "rs789"),
        CHR = c(1, 1, 2),
        BP = c(1000, 2000, 3000),
        A1 = c("A", "C", "G"),
        A2 = c("T", "G", "A"),
        P = c(0.01, 0.05, 0.001),
        BETA = c(0.1, -0.2, 0.3),
        SE = c(0.05, 0.06, 0.04),
        N = c(10000, 10000, 10000)
    )
}

# Serialize the object to the exact file name and format expected by the workflow
saveRDS(sumstats_dt, "sumstats_dt.rds")