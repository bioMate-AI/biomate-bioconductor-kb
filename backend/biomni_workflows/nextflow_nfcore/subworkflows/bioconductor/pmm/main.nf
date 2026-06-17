#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pmm — parallel_mixed_model_analysis
// Fit the Parallel Mixed Model to parallel RNAi screen data to estimate gene effects and local FDRs, calculate sharedness scores, and visualize the hits.
// Input: screen_data.csv
// Container: quay.io/biocontainers/bioconductor-pmm:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pmm
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the Parallel Mixed Model using pmm
//  * 2. [Core Analysis] Calculate the sharedness score using sharedness
//  * 3. [Visualization & Output] Visualize the results using hitheatmap

nextflow.enable.dsl = 2

process BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS {
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
    .bm_deps <- c("pmm")
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
        
    library(pmm)
    
    # Read the user input file
    kinome <- read.csv("screen_data.csv", stringsAsFactors = FALSE)
    
    # Extract column names dynamically assuming the order: gene, condition, readout
    gene_col <- colnames(kinome)[1]
    condition_col <- colnames(kinome)[2]
    readout_col <- colnames(kinome)[3]
    
    # Fit the Parallel Mixed Model (single, clean analysis)
    fit2 <- pmm(kinome, readout_col, gene.col = gene_col,
                condition.col = condition_col, simplify = FALSE)
    
    # Extract simplified output
    fit1 <- fit2[[1]]
    
    head(fit1)
    class(fit2)
    names(fit2)
    
    # Visualize the results using hitheatmap and save to PDF
    pdf("hitheatmap_threshold_0.2.pdf", width = 10, height = 8)
    hitheatmap(fit1, threshold = 0.2)
    dev.off()
    
    pdf("hitheatmap_modified.pdf", width = 12, height = 10)
    hitheatmap(fit1, threshold = 0.4, cex.main = 2,
               main = "My modified plot", col.main = "white",
               col.axis = "white", cex.axis = 0.8, bg = "black", mar = c(6, 8, 4, 6))
    dev.off()
    
    # Calculate the sharedness score
    sh <- sharedness(fit1, threshold = 0.2)
    sh_ordered <- sh[order(sh\$Sharedness), ]
    
    # Visualize the results with the sharedness score added
    pdf("hitheatmap_sharedness.pdf", width = 10, height = 8)
    hitheatmap(fit1, sharedness.score = TRUE, main = "My hits found by PMM")
    dev.off()
    
    # Write meaningful results to output files
    write.csv(fit1, "pmm_fit_simplified.csv", row.names = TRUE)
    saveRDS(fit2, "pmm_fit_list.rds")
    write.csv(sh_ordered, "sharedness_scores.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS":',
        paste0('    pmm: ', as.character(packageVersion('pmm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parallel_mixed_model_analysis.csv versions.yml
    """
}

workflow BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ screen_data.csv ] ]

    main:
    BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS.out.tables
    plots    = BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS.out.plots
    objects  = BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS.out.objects
    versions = BIOC_PMM_PARALLEL_MIXED_MODEL_ANALYSIS.out.versions
}
