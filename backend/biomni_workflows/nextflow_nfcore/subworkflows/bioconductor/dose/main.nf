#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DOSE — disease_ontology_enrichment
// Perform over-representation analysis of disease ontology terms on a list of Entrez gene IDs.
// Input: gene_list.txt
// Container: quay.io/biocontainers/bioconductor-dose:4.4.0--r45hdfd78af_0
// R packages: DOSE, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: DOSE, ggplot2
// Visualizations: bar plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the DOSE package
//  * 2. [Core Analysis] Run enrichment analysis using enrichDO, enrichDGN, or enrichNCG
//  * 3. [Visualization & Output] Visualize results using simplot or theme_dose

nextflow.enable.dsl = 2

process BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("DOSE", "ggplot2")
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
    
    # 1. Load the DOSE package and ggplot2 for visualization
    library(DOSE)
    library(ggplot2)
    
    # 2. Read the user input file
    if (!file.exists("gene_list.txt")) {
      stop("Error: 'gene_list.txt' not found in the working directory.")
    }
    
    gene_ids <- readLines("gene_list.txt")
    gene_ids <- trimws(gene_ids)
    gene_ids <- gene_ids[gene_ids != ""]
    
    if (length(gene_ids) == 0) {
      stop("Error: 'gene_list.txt' is empty.")
    }
    
    # 3. Run enrichment analysis using enrichDO
    edo <- enrichDO(
      gene          = gene_ids,
      ont           = "DO",
      pvalueCutoff  = 0.05,
      pAdjustMethod = "BH",
      qvalueCutoff  = 0.2,
      readable      = FALSE
    )
    
    # 4. Save the meaningful results
    # Save RDS object
    saveRDS(edo, "enrichment_results.rds")
    
    # Save CSV table
    results_df <- as.data.frame(edo)
    write.csv(results_df, "enrichment_results.csv", row.names = FALSE)
    
    # 5. Visualize results using theme_dose
    if (!is.null(edo) && nrow(results_df) > 0) {
      # Generate barplot and apply theme_dose
      p <- barplot(edo, showCategory = 20) + theme_dose()
      ggsave("enrichment_barplot.pdf", plot = p, width = 10, height = 8)
    } else {
      message("No significant enrichment found. Plot was not generated.")
    }

    writeLines(c(
        '"BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT":',
        paste0('    DOSE: ', as.character(packageVersion('DOSE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_disease_ontology_enrichment.csv versions.yml
    """
}

workflow BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.txt ] ]

    main:
    BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT.out.tables
    plots    = BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT.out.plots
    objects  = BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT.out.objects
    versions = BIOC_DOSE_DISEASE_ONTOLOGY_ENRICHMENT.out.versions
}
