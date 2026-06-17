#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaPhOR — multi_deg_metabolic_comparison
// Compare metabolic profiles across multiple conditions or DEG lists using a comparative heatmap.
// Input: BRCA_DEGS.csv, OVCA_Scores.csv, PRAD_Scores.csv
// Container: quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0
// R packages: MetaPhOR
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaPhOR
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Run pathway analysis on each DEG list (or read pre-calculated scores)
//  * 2. [Core Analysis] Combine the scores into a list
//  * 3. [Input & Preparation] Define sample names
//  * 4. [Visualization & Output] Generate a comparative heatmap using metaHeatmap

nextflow.enable.dsl = 2

process BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("MetaPhOR")
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
    
    # Load required library
    library(MetaPhOR)
    
    # Set seed for reproducibility (required by pathwayAnalysis bootstrapping)
    set.seed(1234)
    
    # 1. Run pathway analysis on the BRCA DEG list
    brca <- pathwayAnalysis(DEGpath = "BRCA_DEGS.csv",
                            genename = "X",
                            sampsize = 1095,
                            iters = 50000,
                            headers = c("logFC", "adj.P.Val"))
    
    # Save the calculated BRCA scores to a CSV file
    write.csv(brca, "BRCA_Scores.csv", row.names = TRUE)
    
    # 2. Read pre-calculated scores for OVCA and PRAD from the working directory
    ovca <- read.csv("OVCA_Scores.csv",
                    header = TRUE,
                    row.names = 1)
    
    prad <- read.csv("PRAD_Scores.csv",
                    header = TRUE,
                    row.names = 1)
    
    # 3. Combine the scores into a list and define sample names
    all.scores <- list(brca, ovca, prad)
    names <- c("BRCA", "OVCA", "PRAD")
    
    # Save the combined scores list as an RDS object
    saveRDS(all.scores, "all_scores.rds")
    
    # 4. Generate a comparative heatmap using metaHeatmap and save to a PDF file
    pdf("meta_heatmap.pdf", width = 10, height = 8)
    metaHeatmap(scorelist = all.scores,
                samplenames = names,
                pvalcut = 0.05)
    dev.off()

    writeLines(c(
        '"BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON":',
        paste0('    MetaPhOR: ', as.character(packageVersion('MetaPhOR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_deg_metabolic_comparison.csv versions.yml
    """
}

workflow BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BRCA_DEGS.csv, OVCA_Scores.csv, PRAD_Scores.csv ] ]

    main:
    BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON(ch_input)

    emit:
    tables   = BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON.out.tables
    plots    = BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON.out.plots
    objects  = BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON.out.objects
    versions = BIOC_METAPHOR_MULTI_DEG_METABOLIC_COMPARISON.out.versions
}
