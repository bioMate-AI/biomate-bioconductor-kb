library(celaref)

# Helper function to copy package example files or generate synthetic fallbacks
setup_input_file <- function(filename, is_counts, is_query) {
    # Attempt to find the file in the package's extdata
    pkg_file <- system.file("extdata", filename, package = "celaref")
    
    if (pkg_file != "" && file.exists(pkg_file)) {
        file.copy(pkg_file, filename, overwrite = TRUE)
    } else {
        # Fallback: Construct a small synthetic file matching the exact expected format
        set.seed(123)
        prefix <- if (is_query) "CellQ" else "CellR"
        clusters <- if (is_query) c("cluster1", "cluster2") else c("astrocytes", "microglia")
        
        if (is_counts) {
            # Tab-delimited counts matrix (genes x cells)
            counts <- matrix(rpois(100 * 20, lambda = 5), nrow = 100, ncol = 20)
            rownames(counts) <- paste0("Gene", 1:100)
            colnames(counts) <- paste0(prefix, 1:20)
            # col.names = NA ensures the header is properly shifted for row names
            write.table(counts, file = filename, sep = "\t", quote = FALSE, col.names = NA)
        } else {
            # Tab-delimited cell metadata with cluster assignments
            cell_info <- data.frame(
                CellId = paste0(prefix, 1:20),
                Cluster = rep(clusters, each = 10)
            )
            write.table(cell_info, file = filename, sep = "\t", quote = FALSE, row.names = FALSE)
        }
    }
}

# Generate the 4 required input files in the working directory
setup_input_file("sim_query_counts.tab", is_counts = TRUE, is_query = TRUE)
setup_input_file("sim_query_cell_info.tab", is_counts = FALSE, is_query = TRUE)
setup_input_file("sim_ref_counts.tab", is_counts = TRUE, is_query = FALSE)
setup_input_file("sim_ref_cell_info.tab", is_counts = FALSE, is_query = FALSE)

# Verify files exist
stopifnot(
    file.exists("sim_query_counts.tab"),
    file.exists("sim_query_cell_info.tab"),
    file.exists("sim_ref_counts.tab"),
    file.exists("sim_ref_cell_info.tab")
)