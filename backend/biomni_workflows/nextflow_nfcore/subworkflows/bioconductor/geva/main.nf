#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geva — detailed_geva_pipeline
// Perform a detailed, step-by-step Gene Expression Variation Analysis (GEVA) from input files to final gene classification, allowing fine-tuning of each intermedi
// Input: cond_A_2h.txt, cond_B_2h.txt, cond_C_2h.txt, cond_A_4h.txt, cond_B_4h.txt, cond_C_4h.txt
// Container: quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0
// R packages: geva
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: cluster plot

nextflow.enable.dsl = 2

process BIOC_GEVA_DETAILED_GEVA_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("geva")
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
    
    # Load the required Bioconductor package
    library(geva)
    
    # --- Read input files ---
    filenms <- c("cond_A_2h.txt", "cond_B_2h.txt", "cond_C_2h.txt",
                 "cond_A_4h.txt", "cond_B_4h.txt", "cond_C_4h.txt")
    ginput <- geva.read.tables(filenms)
    
    # --- Correct numeric tables ---
    ginput <- geva.input.correct(ginput)
    
    # --- Filter out insignificant rows ---
    ginput <- geva.input.filter(ginput, p.value.cutoff = 0.05)
    
    # --- Rename row names and resolve duplicates ---
    ginput <- geva.input.rename.rows(ginput,
                                     attr.column = "Symbol")
    
    # --- Summarize logFC and variation ---
    gsummary <- geva.summarize(ginput)
    
    # Save GEVASummary plot
    pdf("gsummary_plot.pdf", width = 9, height = 6)
    plot(gsummary)
    dev.off()
    
    # --- Calculate SV-space quantiles ---
    gquants <- geva.quantiles(gsummary)
    
    # Save GEVAQuantiles plot
    pdf("gquants_plot.pdf", width = 9, height = 6)
    plot(gquants)
    dev.off()
    
    # --- Perform cluster analysis ---
    gcluster <- geva.cluster(gsummary,
                             cluster.method="hierarchical",
                             resolution=0.3)
    
    # Save GEVACluster plot
    pdf("gcluster_plot.pdf", width = 9, height = 6)
    plot(gcluster)
    dev.off()
    
    # --- Combine intermediate results ---
    ggroupedsummary <- gsummary
    groupsets(ggroupedsummary) <- gquants
    groupsets(ggroupedsummary) <- gcluster
    
    # Save GEVAGroupedSummary plot
    pdf("ggroupedsummary_plot.pdf", width = 9, height = 6)
    plot(ggroupedsummary)
    dev.off()
    
    # --- Finalize classifications ---
    gresults <- geva.finalize(ggroupedsummary)
    
    # Save GEVAResults plot
    pdf("gresults_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()
    
    # Extract and save the final classifications table
    res_table <- results.table(gresults)
    write.csv(res_table, "geva_results_table.csv", row.names = TRUE)
    
    # Print the last 10 rows of the results table to console
    print(tail(res_table, 10))
    
    # --- Extract top relevant genes ---
    dtgens <- top.genes(gresults, add.cols = "Symbol")
    write.csv(dtgens, "geva_top_genes.csv", row.names = TRUE)
    
    # Save the final results object as an RDS file
    saveRDS(gresults, "geva_results.rds")

    writeLines(c(
        '"BIOC_GEVA_DETAILED_GEVA_PIPELINE":',
        paste0('        geva: ', as.character(packageVersion("geva")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detailed_geva_pipeline.csv versions.yml
    """
}

workflow BIOC_GEVA_DETAILED_GEVA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cond_A_2h.txt, cond_B_2h.txt, cond_C_2h.txt, cond_A_4h.txt, cond_B_4h.txt, cond_C_4h.txt ] ]

    main:
    BIOC_GEVA_DETAILED_GEVA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.tables
    plots    = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.plots
    objects  = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.objects
    versions = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.versions
}
