library(Rbec)

log_files <- list.files(
    system.file("extdata/contamination_test", package = "Rbec"),
    recursive = TRUE,
    full.names = TRUE
)

writeLines(log_files, "log_path")