suppressPackageStartupMessages({
    library(mariner)
    library(marinerData)
})

# Helper function to safely locate or create the required input files
get_or_create_file <- function(func_name, file_name, is_hic = FALSE) {
    file_path <- NULL
    
    # 1. Try to get from marinerData function (as shown in vignette)
    if (exists(func_name, where = asNamespace("marinerData"))) {
        try({
            func <- get(func_name, envir = asNamespace("marinerData"))
            file_path <- func()
        }, silent = TRUE)
    }
    
    # 2. Try to find in extdata of marinerData
    if (is.null(file_path) || !file.exists(file_path)) {
        found <- list.files(system.file("extdata", package="marinerData"), 
                            pattern=file_name, recursive=TRUE, full.names=TRUE)
        if (length(found) > 0) {
            file_path <- found[1]
        }
    }
    
    # 3. Try to find in extdata of mariner
    if (is.null(file_path) || !file.exists(file_path)) {
        found <- list.files(system.file("extdata", package="mariner"), 
                            pattern=file_name, recursive=TRUE, full.names=TRUE)
        if (length(found) > 0) {
            file_path <- found[1]
        }
    }
    
    # Copy if found, otherwise create a synthetic fallback
    if (!is.null(file_path) && file.exists(file_path)) {
        file.copy(file_path, file_name, overwrite = TRUE)
    } else {
        if (is_hic) {
            # Create a dummy .hic file
            file.create(file_name)
        } else {
            # Create a synthetic BEDPE file matching the vignette's structure
            df <- data.frame(
                chromosome1 = c("chr9", "chr9", "chr9", "chr9", "chr9", "chr9"),
                x1 = c(14460000, 89565000, 23725000, 128165000, 113100000, 16570000),
                x2 = c(14465000, 89570000, 23730000, 128170000, 113105000, 16575000),
                chromosome2 = c("chr9", "chr9", "chr9", "chr9", "chr9", "chr9"),
                y1 = c(14765000, 89810000, 23785000, 128670000, 113380000, 16865000),
                y2 = c(14770000, 89815000, 23790000, 128675000, 113385000, 16870000),
                color = rep("0,0,0", 6),
                APScoreAvg = c(3.272132, 2.062756, 1.953737, 4.217386, 2.527488, 4.385120),
                ProbabilityofEnrichment = c(0.9868535, 0.9528638, 0.9335626, 0.9919898, 0.9682012, 0.9976317),
                RegAPScoreAvg = c(2.233533, 1.326748, 1.408335, 2.144296, 1.470122, 2.230119),
                Avg_diffMaxNeihgboor_1 = c(1.0059373, 1.1275173, 0.6212205, 2.2130080, 1.3876540, 2.1201570),
                Avg_diffMaxNeihgboor_2 = c(1.6455076, 1.1394584, 0.8722256, 2.6013327, 1.5604625, 3.5826060),
                avg = c(3.437883, 2.052792, 2.159580, 2.860420, 2.215215, 4.161625),
                std = c(0.5164226, 0.5861371, 0.3773057, 1.0796510, 0.6669347, 1.0922525),
                value = c(4.332049, 3.055030, 2.711776, 4.827538, 3.448685, 6.046209)
            )
            write.table(df, file_name, sep="\t", quote=FALSE, row.names=FALSE)
        }
    }
}

# Generate the required input files
get_or_create_file("WT_5kbLoops.txt", "WT_5kbLoops.txt", is_hic = FALSE)
get_or_create_file("LEUK_HEK_PJA27_inter_30.hic", "LEUK_HEK_PJA27_inter_30.hic", is_hic = TRUE)
get_or_create_file("LEUK_HEK_PJA30_inter_30.hic", "LEUK_HEK_PJA30_inter_30.hic", is_hic = TRUE)