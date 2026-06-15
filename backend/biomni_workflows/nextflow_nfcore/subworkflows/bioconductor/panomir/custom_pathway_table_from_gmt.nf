#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: panomir — custom_pathway_table_from_gmt
// Create a customized pathway-gene association table from an external GMT file or GeneSetCollection.
// Input: pathways.gmt
// Container: quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0
// R packages: GSEABase, PanomiR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("GSEABase", "PanomiR")
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
    library(GSEABase)
    library(PanomiR)
    
    # Define input file path
    gmt_file <- "pathways.gmt"
    
    # Check if input file exists
    if (!file.exists(gmt_file)) {
      stop(paste("Required input file", gmt_file, "does not exist in the working directory."))
    }
    
    # --- Read GMT file into a GeneSetCollection using ---
    yourGeneSetCollection <- getGmt(gmt_file)
    
    # --- Convert the GeneSetCollection to a pathway-gene ---
    newPathGeneTable      <- tableFromGSC(yourGeneSetCollection)
    
    # Write the meaningful results to output files
    write.csv(newPathGeneTable, "newPathGeneTable.csv", row.names = FALSE)
    saveRDS(newPathGeneTable, "newPathGeneTable.rds")

    writeLines(c(
        '"BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT":',
        paste0('        panomir: ', as.character(packageVersion("panomir")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_pathway_table_from_gmt.csv versions.yml
    """
}

workflow BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pathways.gmt ] ]

    main:
    BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT(ch_input)

    emit:
    tables   = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.tables
    plots    = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.plots
    objects  = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.objects
    versions = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.versions
}
