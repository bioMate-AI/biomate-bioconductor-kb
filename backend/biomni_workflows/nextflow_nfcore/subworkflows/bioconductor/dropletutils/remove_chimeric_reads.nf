#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dropletutils — remove_chimeric_reads
// Remove chimeric molecules generated during library preparation within cells.
// Input: mult.mol.info[1]
// Container: quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0
// R packages: DropletUtils, Matrix
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS {
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
    library(Matrix)
    
    # Define the input file path as specified by the user
    # The pipeline expects "molecule_info.h5" in the working directory
    mult.mol.info <- c("molecule_info.h5")
    
    # Verify input file existence
    if (!file.exists(mult.mol.info[1])) {
      stop(paste("Required input file missing:", mult.mol.info[1]))
    }
    
    # 1. Remove molecules in the same cell with the same UMI sequence using chimericDrops
    out <- chimericDrops(mult.mol.info[1])
    class(out)
    
    # Save the complete output list to an RDS file
    saveRDS(out, file = "chimeric_drops_output.rds")
    
    # If the output contains the cleaned matrix, save it separately as well
    if (is.list(out) && "cleaned" %in% names(out)) {
      saveRDS(out\$cleaned, file = "cleaned_umi_matrix.rds")
      
      # Write a summary of the cleaned matrix
      summary_stats <- data.frame(
        Metric = c("Number of Genes", "Number of Cells", "Total UMI Count"),
        Value = c(nrow(out\$cleaned), ncol(out\$cleaned), sum(out\$cleaned))
      )
      write.csv(summary_stats, file = "cleaned_matrix_summary.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS":',
        paste0('        dropletutils: ', as.character(packageVersion("dropletutils")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_remove_chimeric_reads.csv versions.yml
    """
}

workflow BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mult.mol.info[1] ] ]

    main:
    BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS(ch_input)

    emit:
    tables   = BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS.out.tables
    plots    = BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS.out.plots
    objects  = BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS.out.objects
    versions = BIOC_DROPLETUTILS_REMOVE_CHIMERIC_READS.out.versions
}
