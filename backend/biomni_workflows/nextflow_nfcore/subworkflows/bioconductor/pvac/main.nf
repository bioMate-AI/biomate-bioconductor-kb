#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pvac — pvac_microarray_filtering
// Perform PCA-based gene filtering on Affymetrix microarray data to remove non-informative probesets before differential expression testing.
// Input: celfiles
// Container: quay.io/biocontainers/bioconductor-pvac:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, pvac
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw CEL files into an AffyBatch object
//  * 2. [Visualization & Output] Summarize probe-level data to probeset-level expression using RMA
//  * 3. [Core Analysis] Calculate PVAC scores and identify passing probesets
//  * 4. [Visualization & Output] Subset the summarized ExpressionSet to keep only the filtered probesets

nextflow.enable.dsl = 2

process BIOC_PVAC_PVAC_MICROARRAY_FILTERING {
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
    .bm_deps <- c("affy", "pvac")
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
    
    # Check if input directory exists
    if (!dir.exists("celfiles")) {
      stop("Error: 'celfiles' directory not found in the working directory.")
    }
    
    # Check if there are CEL files in the directory
    cel_files <- list.files("celfiles", pattern = "\\\\.[cC][eE][lL](\\\\.gz)?\$", full.names = TRUE)
    if (length(cel_files) == 0) {
      stop("Error: No CEL files found in 'celfiles' directory.")
    }
    
    if (length(cel_files) < 6) {
      warning("PVAC filtering is most effective with at least 6 samples. Found: ", length(cel_files))
    }
    
    library(affy)
    library(pvac)
    
    # 1. Read raw CEL files into an AffyBatch object
    # We name the object MLL.A to match the documented code exactly
    MLL.A <- ReadAffy(celfile.path = "celfiles")
    
    # 2. Summarize probe-level data to probeset-level expression using RMA
    myeset <- rma(MLL.A)
    
    # 3. Calculate PVAC scores and identify passing probesets
    ft <- pvacFilter(MLL.A)
    
    # 4. Subset the summarized ExpressionSet to keep only the filtered probesets
    myeset.filtered <- myeset[ft\$aset,]
    
    # Generate and save the density plot
    pdf("pvac_density_plot.pdf", width = 7, height = 7)
    plot(density(ft\$pvac[ft\$nullset]), xlab = "PVAC score", main = "",
         col = "gray", cex.lab = 0.5, xlim = c(0, 1))
    lines(density(ft\$pvac), col = 1)
    abline(v = ft\$cutoff, lty = 2, col = "gray")
    dev.off()
    
    # Save outputs
    saveRDS(myeset.filtered, "myeset_filtered.rds")
    saveRDS(ft, "pvac_filter_results.rds")
    write.csv(exprs(myeset.filtered), "filtered_expression_matrix.csv", row.names = TRUE)
    
    # Write a summary text file
    summary_conn <- file("pvac_filter_summary.txt")
    writeLines(c(
      paste("Total probesets before filtering:", nrow(myeset)),
      paste("Probesets passing filter:", length(ft\$aset)),
      paste("Probesets filtered out:", nrow(myeset) - length(ft\$aset)),
      paste("PVAC cutoff score:", ft\$cutoff)
    ), summary_conn)
    close(summary_conn)

    writeLines(c(
        '"BIOC_PVAC_PVAC_MICROARRAY_FILTERING":',
        paste0('    pvac: ', as.character(packageVersion('pvac')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pvac_microarray_filtering.csv versions.yml
    """
}

workflow BIOC_PVAC_PVAC_MICROARRAY_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celfiles ] ]

    main:
    BIOC_PVAC_PVAC_MICROARRAY_FILTERING(ch_input)

    emit:
    tables   = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.tables
    plots    = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.plots
    objects  = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.objects
    versions = BIOC_PVAC_PVAC_MICROARRAY_FILTERING.out.versions
}
