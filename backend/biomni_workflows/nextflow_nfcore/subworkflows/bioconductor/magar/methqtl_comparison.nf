#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAGAR — methqtl_comparison
// Compare and overlap methQTL results from multiple datasets or analyses.
// Input: reduced_methQTL, MethQTLResult_chr18
// Container: quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0
// R packages: MAGAR
// Bioconductor: 3.20 | R: 4.4
// Requires: MAGAR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load multiple methQTL result objects
//  * 2. [Visualization & Output] Generate Venn and UpSet plots to compare overlapping QTLs
//  * 3. [Visualization & Output] Identify dataset-specific QTLs using getSpecificQTL

nextflow.enable.dsl = 2

process BIOC_MAGAR_METHQTL_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("MAGAR")
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
    library(MAGAR)
    
    # --- Load multiple methQTL result objects ---
    # Load the first methQTL input dataset from the working directory
    imp.data <- loadMethQTLInput("reduced_methQTL")
    
    # Set options for methQTL calling
    qtlSetOption(standard.deviation.gauss = 100, cluster.cor.threshold = 0.75)
    
    # Compute the first methQTL result
    meth.qtl.res <- doMethQTL(imp.data, default.options = FALSE, p.val.cutoff = 0.05)
    
    # Load the second pre-computed methQTL result from the working directory
    meth.qtl.res.2 <- loadMethQTLResult("MethQTLResult_chr18")
    
    # Combine the results into a list
    meth.qtl.list <- list(First = meth.qtl.res, Second = meth.qtl.res.2)
    
    # --- Generate Venn and UpSet plots to compare overlapping QTLs ---
    # Generate Venn plot (saves files directly to the output folder)
    qtlVennPlot(meth.qtl.list, out.folder = getwd())
    
    # Generate and save UpSet plot
    pdf("qtl_upset_plot.pdf", width = 8, height = 6)
    print(qtlUpsetPlot(meth.qtl.list, type = "cor.block"))
    dev.off()
    
    # --- Identify dataset-specific QTLs using getSpecificQTL ---
    spec.first <- getSpecificQTL(meth.qtl.list\$First, meth.qtl.list[-1])
    
    # Save meaningful results to output files
    saveRDS(meth.qtl.res, "meth_qtl_res_first.rds")
    saveRDS(meth.qtl.list, "meth_qtl_list.rds")
    saveRDS(spec.first, "specific_qtl_first.rds")
    
    # Attempt to export specific QTLs as a CSV table for convenience
    tryCatch({
      spec.table <- getResult(spec.first)
      write.csv(spec.table, "specific_qtl_first.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not export specific QTL table to CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MAGAR_METHQTL_COMPARISON":',
        paste0('    MAGAR: ', as.character(packageVersion('MAGAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methqtl_comparison.csv versions.yml
    """
}

workflow BIOC_MAGAR_METHQTL_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reduced_methQTL, MethQTLResult_chr18 ] ]

    main:
    BIOC_MAGAR_METHQTL_COMPARISON(ch_input)

    emit:
    tables   = BIOC_MAGAR_METHQTL_COMPARISON.out.tables
    plots    = BIOC_MAGAR_METHQTL_COMPARISON.out.plots
    objects  = BIOC_MAGAR_METHQTL_COMPARISON.out.objects
    versions = BIOC_MAGAR_METHQTL_COMPARISON.out.versions
}
