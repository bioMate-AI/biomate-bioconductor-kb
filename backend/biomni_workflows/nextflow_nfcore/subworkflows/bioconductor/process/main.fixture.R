library(PROcess)

testdir <- "testdir"
dir.create(testdir, showWarnings = FALSE, recursive = TRUE)

fdat <- system.file("Test", package="PROcess")
fs <- list.files(fdat, pattern="csv", full.names=TRUE, ignore.case=TRUE)

if (length(fs) > 0) {
    file.copy(fs, testdir)
} else {
    # Fallback: create synthetic CSV files if the package data is missing
    mz_vals <- seq(1000, 20000, by=10)
    dummy_data1 <- data.frame(mz = mz_vals, intensity = abs(rnorm(length(mz_vals), 50, 10)))
    dummy_data2 <- data.frame(mz = mz_vals, intensity = abs(rnorm(length(mz_vals), 50, 10)))
    
    write.table(dummy_data1, file.path(testdir, "sample1.csv"), sep=",", row.names=FALSE, col.names=FALSE)
    write.table(dummy_data2, file.path(testdir, "sample2.csv"), sep=",", row.names=FALSE, col.names=FALSE)
}