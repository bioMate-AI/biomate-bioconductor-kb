#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DropletUtils — remove_swapping_and_chimeric_effects
// Clean up barcode swapping between multiplexed samples and chimeric reads within cells.
// Input: mult.mol.info
// Container: quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0
// R packages: DropletUtils
// Bioconductor: 3.20 | R: 4.4
// Requires: DropletUtils
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the declared user input files from the working
//  * 2. [Core Analysis] Remove barcode swapping across multiplexed samples using
//  * 3. [Core Analysis] Remove chimeric reads within cells using chimericDrops
//  * 4. [Core Analysis] Save meaningful results

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DropletUtils")
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
        library(DropletUtils)
        
        # --- Read the declared user input files from the working ---
        # The user provides molecule information HDF5 files in the working directory.
        mult.mol.info <- sort(list.files(pattern = "\\\\.h5\$", full.names = TRUE))
        
        if (length(mult.mol.info) == 0) {
          stop("Error: No HDF5 (.h5) molecule information files found in the working directory.")
        }
        
        # --- Remove barcode swapping across multiplexed samples using ---
        s.out <- swappedDrops(mult.mol.info, min.frac=0.9)
        
        # --- Remove chimeric reads within cells using chimericDrops ---
        out <- lapply(mult.mol.info, chimericDrops)
        
        # --- Save meaningful results ---
        # Save the full output objects as RDS for downstream analysis
        saveRDS(s.out, "swapped_drops_output.rds")
        saveRDS(out, "chimeric_drops_output.rds")
        
        # Write a text summary of the cleaning results
        sink("cleaning_summary.txt")
        cat("==================================================\n")
        cat("DropletUtils: Swapping and Chimeric Effects Clean Up\n")
        cat("==================================================\n\n")
        
        cat("--- Barcode Swapping (swappedDrops) ---\n")
        cat("Input files processed:\n")
        print(mult.mol.info)
        cat("\nNumber of cleaned matrices returned:", length(s.out\$cleaned), "\n")
        for (i in seq_along(s.out\$cleaned)) {
          cat(sprintf("  Sample %d: %d genes, %d barcodes\n", 
                      i, nrow(s.out\$cleaned[[i]]), ncol(s.out\$cleaned[[i]])))
        }
        
        cat("\n--- Chimeric Reads (chimericDrops) ---\n")
        cat("Input files processed:\n")
        print(mult.mol.info)
        if (is.list(out)) {
          cat("\nNumber of cleaned matrices returned:", length(out), "\n")
          for (i in seq_along(out)) {
            cat(sprintf("  Matrix %d: %d genes, %d barcodes\n", 
                        i, nrow(out[[i]]), ncol(out[[i]])))
          }
        } else {
          cat(sprintf("Cleaned matrix: %d genes, %d barcodes\n", 
                      nrow(out), ncol(out)))
        }
        sink()

    writeLines(c(
        '"BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS":',
        paste0('    DropletUtils: ', as.character(packageVersion('DropletUtils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_remove_swapping_and_chimeric_effects.csv versions.yml
    """
}

workflow BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mult.mol.info ] ]

    main:
    BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS(ch_input)

    emit:
    tables   = BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS.out.tables
    plots    = BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS.out.plots
    objects  = BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS.out.objects
    versions = BIOC_DROPLETUTILS_REMOVE_SWAPPING_AND_CHIMERIC_EFFECTS.out.versions
}
