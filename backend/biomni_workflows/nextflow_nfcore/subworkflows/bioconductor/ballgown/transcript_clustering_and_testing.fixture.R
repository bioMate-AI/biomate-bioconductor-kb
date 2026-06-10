library(ballgown)

files_to_copy <- c("e_data.ctab", "i_data.ctab", "t_data.ctab", "e2t.ctab", "i2t.ctab")

for (f in files_to_copy) {
    src <- file.path(system.file("extdata", "sample01", package="ballgown"), f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        all_files <- list.files(system.file("extdata", package="ballgown"), 
                                pattern=paste0("^", f, "$"), 
                                recursive=TRUE, 
                                full.names=TRUE)
        if (length(all_files) > 0) {
            file.copy(all_files[1], f, overwrite = TRUE)
        } else {
            stop(paste("Could not find", f, "in ballgown extdata"))
        }
    }
}