library(deltaGseg)

extdata_dir <- system.file("extdata", package="deltaGseg")
files_to_copy <- c("D_GBTOT1", "D_GBTOT2", "D_GBTOT3")

for (f in files_to_copy) {
    src <- file.path(extdata_dir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        timepoints <- 1:5000
        measurements <- rnorm(5000, mean = -30, sd = 5)
        if (f == "D_GBTOT3") {
            measurements[2501:5000] <- measurements[2501:5000] + 10
        }
        df <- data.frame(timepoints, measurements)
        write.table(df, file = f, sep = " ", row.names = FALSE, col.names = FALSE, quote = FALSE)
    }
}