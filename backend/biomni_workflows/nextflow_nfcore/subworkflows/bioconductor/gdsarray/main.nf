#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GDSArray — gdsarray_genomic_processing
// Convert a feature-by-sample CSV matrix into a high-performance Genomic Data Structure (GDS) file, represent it as a GDSArray for memory-efficient delayed operat
// Input: input.csv
// Container: 1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GDSArray, S4Vectors, SummarizedExperiment, gdsfmt
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("gdsfmt", "GDSArray", "S4Vectors", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(gdsfmt)
    library(SummarizedExperiment)
    library(GDSArray)
    library(S4Vectors)
    
    # ==========================================
    # --- Read and Clean Input Defensively ---
    # ==========================================
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found in the working directory.")
    }
    
    # Read CSV defensively
    csv_data <- read.csv("input.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (ncol(csv_data) < 2) {
      stop("Input CSV must have at least a feature ID column and one sample column.")
    }
    
    # Extract row names (features) and sample columns
    if ("feature_id" %in% colnames(csv_data)) {
      row_names <- csv_data\$feature_id
      csv_data\$feature_id <- NULL
    } else {
      row_names <- csv_data[, 1]
      csv_data <- csv_data[, -1, drop = FALSE]
    }
    
    # Convert to numeric matrix
    mat <- as.matrix(csv_data)
    storage.mode(mat) <- "double"
    
    # Handle any missing values by replacing them with 0
    mat[is.na(mat)] <- 0
    
    # ==========================================
    # --- Create GDS File from Matrix ---
    # ==========================================
    gds_path <- "input_data.gds"
    if (file.exists(gds_path)) {
      file.remove(gds_path)
    }
    
    # Initialize GDS file and write nodes
    f <- createfn.gds(gds_path)
    add.gdsn(f, "assay/data", val = mat)
    add.gdsn(f, "row_names", val = as.character(row_names))
    add.gdsn(f, "col_names", val = as.character(colnames(mat)))
    closefn.gds(f)
    
    # ==========================================
    # --- Represent GDS Nodes as GDSArrays ---
    # ==========================================
    # Instantiate GDSArray for the main data matrix
    gds_arr <- GDSArray(gds_path, "assay/data")
    
    # Retrieve row and column names from GDS
    row_names_arr <- as.vector(GDSArray(gds_path, "row_names"))
    col_names_arr <- as.vector(GDSArray(gds_path, "col_names"))
    
    # Assign dimension names to the GDSArray
    dimnames(gds_arr) <- list(row_names_arr, col_names_arr)
    
    # Inspect GDS metadata using GDSArray API
    message("GDS File Path: ", gdsfile(gds_arr))
    message("GDS Seed Details:")
    print(seed(gds_arr))
    
    # Represent the file using GDSFile class for node exploration
    gf <- GDSFile(gds_path)
    gds_nodes <- gdsnodes(gf)
    
    # ==========================================
    # --- Delayed Operations & Filtering ---
    # ==========================================
    # Perform delayed log-transformation (no memory overhead)
    log_arr <- log1p(gds_arr)
    
    # Compute row means using block-processing
    row_means <- rowMeans(log_arr)
    mean_threshold <- mean(row_means, na.rm = TRUE)
    
    # Filter features with expression above the mean
    keep_idx <- which(row_means >= mean_threshold)
    filtered_arr <- log_arr[keep_idx, , drop = FALSE]
    
    # ==========================================
    # --- SummarizedExperiment Integration ---
    # ==========================================
    se <- SummarizedExperiment(
      assays = list(log_counts = filtered_arr),
      rowData = DataFrame(
        feature_id = rownames(filtered_arr),
        mean_log_expr = row_means[keep_idx]
      ),
      colData = DataFrame(
        sample_id = colnames(filtered_arr)
      )
    )
    
    # ==========================================
    # --- Write Outputs ---
    # ==========================================
    # 1. Processed matrix (realize the delayed array to in-memory matrix for writing)
    write.csv(as.matrix(assay(se, "log_counts")), "processed_features.csv", row.names = TRUE)
    
    # 2. Feature metadata
    write.csv(as.data.frame(rowData(se)), "feature_metadata.csv", row.names = FALSE)
    
    # 3. GDS structure report
    gds_report <- data.frame(
      node_name = gds_nodes,
      stringsAsFactors = FALSE
    )
    write.csv(gds_report, "gds_structure.csv", row.names = FALSE)
    
    # ==========================================
    # --- Cleanup and Resource Release ---
    # ==========================================
    tryCatch({
      releaseGDS(gds_path)
    }, error = function(e) {
      warning("Could not release GDS file handle: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING":',
        paste0('    GDSArray: ', as.character(packageVersion('GDSArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdsarray_genomic_processing.csv versions.yml
    """
}

workflow BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING(ch_input)

    emit:
    tables   = BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING.out.tables
    plots    = BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING.out.plots
    objects  = BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING.out.objects
    versions = BIOC_GDSARRAY_GDSARRAY_GENOMIC_PROCESSING.out.versions
}
