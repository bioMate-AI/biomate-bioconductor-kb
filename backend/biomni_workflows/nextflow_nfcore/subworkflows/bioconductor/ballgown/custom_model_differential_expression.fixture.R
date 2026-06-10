library(ballgown)

data_dir <- system.file("extdata", "sample01", package="ballgown")
files_to_copy <- c("e_data.ctab", "i_data.ctab", "t_data.ctab", "e2t.ctab", "i2t.ctab")

for (f in files_to_copy) {
    src <- file.path(data_dir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        stop(paste("Source file not found:", src))
    }
}