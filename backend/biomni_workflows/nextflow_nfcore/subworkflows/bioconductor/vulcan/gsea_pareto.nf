#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vulcan — gsea_pareto
// Perform Gene Set Enrichment Analysis (GSEA) with a Pareto tail distribution for p-value estimation.
// Input: reflist.rds, set.rds
// Container: quay.io/biocontainers/bioconductor-vulcan:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: vulcan
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run GSEA using gsea with method="pareto"
//  * 2. [Visualization & Output] Plot GSEA results using plot_gsea

nextflow.enable.dsl = 2

process BIOC_VULCAN_GSEA_PARETO {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(vulcan)
    
    # Check if input files exist
    if (!file.exists("reflist.rds") || !file.exists("set.rds")) {
      stop("Required input files 'reflist.rds' and/or 'set.rds' are missing in the working directory.")
    }
    
    # Read user inputs
    reflist <- readRDS("reflist.rds")
    set <- readRDS("set.rds")
    
    # Run GSEA using gsea with method="pareto"
    obj <- gsea(reflist, set, method = "pareto")
    
    # Save the GSEA object
    saveRDS(obj, file = "gsea_object.rds")
    
    # Save the p-value to a text file
    write.table(data.frame(p_value = obj\$p.value), file = "gsea_p_value.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Plot GSEA results using plot_gsea and save to PDF
    pdf("gsea_plot.pdf", width = 7, height = 7)
    plot_gsea(obj)
    dev.off()

    writeLines(c(
        '"BIOC_VULCAN_GSEA_PARETO":',
        paste0('    vulcan: ', as.character(packageVersion('vulcan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsea_pareto.csv versions.yml
    """
}

workflow BIOC_VULCAN_GSEA_PARETO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reflist.rds, set.rds ] ]

    main:
    BIOC_VULCAN_GSEA_PARETO(ch_input)

    emit:
    tables   = BIOC_VULCAN_GSEA_PARETO.out.tables
    plots    = BIOC_VULCAN_GSEA_PARETO.out.plots
    objects  = BIOC_VULCAN_GSEA_PARETO.out.objects
    versions = BIOC_VULCAN_GSEA_PARETO.out.versions
}
