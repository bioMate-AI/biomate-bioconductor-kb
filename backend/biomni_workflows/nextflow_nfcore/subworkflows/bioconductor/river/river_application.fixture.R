suppressPackageStartupMessages(library(RIVER))

src_file <- system.file("extdata", "simulation_RIVER.gz", package="RIVER")

if (src_file != "" && file.exists(src_file)) {
    file.copy(src_file, "simulation_RIVER.gz", overwrite = TRUE)
} else {
    # Fallback: construct a synthetic file matching the expected format
    set.seed(123)
    n_samples <- 100
    
    df <- data.frame(
        Subject = paste0("indiv", 1:n_samples),
        Gene = paste0("gene", 1:n_samples)
    )
    
    # Add 18 genomic features
    for(i in 1:18) {
        df[[paste0("Feature", i)]] <- rnorm(n_samples)
    }
    
    # Add expression Z-scores and N2 pair identifiers
    df$Zscore <- rnorm(n_samples)
    df$N2pair <- rep(1:(n_samples/2), each=2)
    
    gz <- gzfile("simulation_RIVER.gz", "w")
    write.table(df, gz, sep="\t", quote=FALSE, row.names=FALSE)
    close(gz)
}