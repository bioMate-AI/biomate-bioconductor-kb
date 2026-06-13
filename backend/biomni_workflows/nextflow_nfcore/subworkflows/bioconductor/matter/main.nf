#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: matter — out_of_memory_tensor_operations
// Create out-of-memory dense and sparse matrices/arrays and perform deferred arithmetic.
// Input: raw_data.bin
// Container: quay.io/biocontainers/bioconductor-matter:2.12.0--r45ha27e39d_0
// R packages: matter
// Bioconductor: 3.20 | R: 4.4
// Requires: matter
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create out-of-memory array using matter_arr or matrix using matter_mat
//  * 2. [Core Analysis] Transpose or check major order using t and rowMaj
//  * 3. [Core Analysis] Perform deferred arithmetic operations
//  * 4. [Input & Preparation] Create sparse matrices using sparse_mat with or without pointers

nextflow.enable.dsl = 2

process BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("matter")
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
    
    # Load the required package
    library(matter)
    
    # Read the user input file raw_data.bin
    if (!file.exists("raw_data.bin")) {
      stop("Error: raw_data.bin not found in the working directory.")
    }
    
    # Read binary data as double
    file_size <- file.info("raw_data.bin")\$size
    raw_data <- readBin("raw_data.bin", what = "double", n = max(120, file_size / 8))
    
    # Fallback if reading as double yields too few elements or is empty
    if (length(raw_data) < 120) {
      raw_data <- as.numeric(readBin("raw_data.bin", what = "integer", n = 120))
    }
    
    # Ensure we have at least 120 elements by recycling if necessary
    if (length(raw_data) < 120) {
      raw_data <- rep_len(raw_data, 120)
    }
    
    # Map raw data to the required variables
    x_vals <- as.integer(raw_data[1:10])
    y_vals <- as.integer(raw_data[11:20])
    a1_vals <- sort(raw_data[21:44])
    m1_vals <- sort(raw_data[45:79])
    # Create sparse matrix values (integers with some zeros to ensure sparsity)
    s1_vals <- as.integer(abs(raw_data[80:114])) %% 3
    s1_vals[s1_vals > 1] <- 0
    
    # --- Documented Workflow Steps ---
    
    # 1. Create out-of-memory vectors and bind them
    x <- matter_vec(x_vals)
    y <- matter_vec(y_vals)
    z <- cbind(x, y)
    atomdata(z)
    
    # 2. N-dimensional arrays
    a1 <- array(a1_vals, dim=c(4,3,2))
    
    a2 <- matter_arr(a1)
    a2
    
    path(a2)
    
    a3 <- matter_arr(type="double", path=path(a2), offset=0, extent=10)
    a3
    
    a1[1:10]
    
    # 3. Column-major and row-major matrices
    m1 <- matrix(m1_vals, nrow=5, ncol=7)
    
    m2 <- matter_mat(m1)
    m2
    
    m3 <- matter_mat(type="double", path=path(m2), nrow=7, ncol=5, rowMaj=TRUE)
    m3
    
    t(m2)
    
    rowMaj(t(m2))
    rowMaj(m2)
    
    # 4. Deferred arithmetic
    m2 + 100
    
    as.matrix(1:5) + m2
    
    t(1:7) + m2
    
    # 5. Sparse matrices
    s1 <- matrix(s1_vals, nrow=5, ncol=7)
    
    s2 <- sparse_mat(s1)
    s2
    
    atomdata(s2)
    atomindex(s2)
    
    s3 <- sparse_mat(atomdata(s2), index=atomindex(s2), nrow=5, ncol=7)
    s3
    
    s4 <- sparse_mat(s1, pointers=TRUE)
    atomdata(s4)
    atomindex(s4)
    pointers(s4)
    
    s5 <- sparse_mat(atomdata(s2), index=atomindex(s2), pointers=pointers(s2), nrow=5, ncol=7)
    s5
    
    # --- Save Outputs ---
    saveRDS(z, "z.rds")
    saveRDS(a2, "a2.rds")
    saveRDS(a3, "a3.rds")
    saveRDS(m2, "m2.rds")
    saveRDS(m3, "m3.rds")
    saveRDS(s2, "s2.rds")
    saveRDS(s3, "s3.rds")
    saveRDS(s4, "s4.rds")
    saveRDS(s5, "s5.rds")
    
    write.csv(as.matrix(m2 + 100), "m2_plus_100.csv", row.names = FALSE)
    write.csv(as.matrix(as.matrix(1:5) + m2), "mat_plus_m2.csv", row.names = FALSE)
    write.csv(as.matrix(t(1:7) + m2), "t_plus_m2.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS":',
        paste0('    matter: ', as.character(packageVersion('matter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_out_of_memory_tensor_operations.csv versions.yml
    """
}

workflow BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_data.bin ] ]

    main:
    BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS(ch_input)

    emit:
    tables   = BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS.out.tables
    plots    = BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS.out.plots
    objects  = BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS.out.objects
    versions = BIOC_MATTER_OUT_OF_MEMORY_TENSOR_OPERATIONS.out.versions
}
