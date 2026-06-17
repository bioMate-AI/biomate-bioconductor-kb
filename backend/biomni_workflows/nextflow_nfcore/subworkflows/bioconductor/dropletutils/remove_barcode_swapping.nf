#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dropletutils — remove_barcode_swapping
// Eliminate barcode swapping effects across multiplexed 10X samples sequenced on the same Illumina run.
// Input: mult.mol.info
// Container: quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0
// R packages: DropletUtils, Matrix
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0"

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
    .bm_deps <- c("DropletUtils", "Matrix")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(DropletUtils)
    library(Matrix)
    
    # Identify the multiplexed molecule information HDF5 files in the working directory
    # The user provides molecule_info.h5 files for the multiplexed samples.
    mult.mol.info <- list.files(pattern = ".*molecule_info\\\\.h5\$|.*\\\\.h5\$", full.names = TRUE)
    
    if (length(mult.mol.info) == 0) {
      stop("Error: No molecule_info.h5 or .h5 files found in the working directory. Please ensure the multiplexed sample files are present.")
    }
    
    # Clean the molecule information files and generate cleaned UMI count matrices
    s.out <- swappedDrops(mult.mol.info, min.frac=0.9)
    
    # Documented validation steps
    cleaned_length <- length(s.out\$cleaned)
    first_matrix_class <- class(s.out\$cleaned[[1]])
    
    # Print validation info to console
    cat("Number of cleaned matrices:", cleaned_length, "\n")
    cat("Class of the first cleaned matrix:", paste(first_matrix_class, collapse = ", "), "\n")
    
    # Save the complete output object
    saveRDS(s.out, file = "swapped_drops_output.rds")
    
    # Save individual cleaned matrices as RDS files and compile summary statistics
    summary_data <- list()
    
    for (i in seq_along(s.out\$cleaned)) {
      matrix_file_name <- paste0("cleaned_matrix_sample_", i, ".rds")
      saveRDS(s.out\$cleaned[[i]], file = matrix_file_name)
      
      # Collect summary statistics for each sample
      summary_data[[i]] <- data.frame(
        Sample_Index = i,
        Source_File = mult.mol.info[i],
        Num_Genes = nrow(s.out\$cleaned[[i]]),
        Num_Barcodes = ncol(s.out\$cleaned[[i]]),
        Total_UMIs = sum(s.out\$cleaned[[i]]),
        stringsAsFactors = FALSE
      )
    }
    
    # Write summary table to CSV
    summary_df <- do.call(rbind, summary_data)
    write.csv(summary_df, file = "barcode_swapping_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING":',
        paste0('        dropletutils: ', as.character(packageVersion("dropletutils")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_remove_barcode_swapping.csv versions.yml
    """
}

workflow BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mult.mol.info ] ]

    main:
    BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING(ch_input)

    emit:
    tables   = BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING.out.tables
    plots    = BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING.out.plots
    objects  = BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING.out.objects
    versions = BIOC_DROPLETUTILS_REMOVE_BARCODE_SWAPPING.out.versions
}
