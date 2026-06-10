#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: singscore — score_landscape_projection
// Plot scores of samples against two different gene signatures in a landscape and project new data points onto it.
// Input: scoredf_ccle_epi, scoredf_ccle_mes, scoredf_tcga_epi, scoredf_tcga_mes
// Container: quay.io/biocontainers/bioconductor-singscore:1.30.0--r45hdfd78af_0
// R packages: ggplot2, singscore
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, singscore
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot score landscape using plotScoreLandscape
//  * 2. [Core Analysis] Project new samples onto the landscape using projectScoreLandscape

nextflow.enable.dsl = 2

process BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION {
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
    .bm_deps <- c("ggplot2", "singscore")
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
    library(singscore)
    library(ggplot2)
    
    # Helper function to robustly load user input files from the working directory
    load_input <- function(name) {
      rds_path <- paste0(name, ".rds")
      csv_path <- paste0(name, ".csv")
      tsv_path <- paste0(name, ".tsv")
      txt_path <- paste0(name, ".txt")
      
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        return(read.csv(csv_path, row.names = 1, check.names = FALSE))
      } else if (file.exists(tsv_path)) {
        return(read.delim(tsv_path, row.names = 1, check.names = FALSE))
      } else if (file.exists(txt_path)) {
        return(read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE))
      } else {
        stop(paste("Required input file not found in working directory:", name))
      }
    }
    
    # 1. Load the pre-computed score data frames
    scoredf_ccle_epi <- load_input("scoredf_ccle_epi")
    scoredf_ccle_mes <- load_input("scoredf_ccle_mes")
    scoredf_tcga_epi <- load_input("scoredf_tcga_epi")
    scoredf_tcga_mes <- load_input("scoredf_tcga_mes")
    
    # 2. Plot CCLE Score Landscape
    pdf("ccle_score_landscape.pdf", width = 8, height = 6)
    ccle_plot <- plotScoreLandscape(scoredf_ccle_epi, scoredf_ccle_mes, 
                                    scorenames = c('ccle-EPI','ccle-MES'), hexMin = 10)
    print(ccle_plot)
    dev.off()
    
    # 3. Plot TCGA Score Landscape
    pdf("tcga_score_landscape.pdf", width = 8, height = 6)
    tcgaLandscape <- plotScoreLandscape(scoredf_tcga_epi, scoredf_tcga_mes, 
                                         scorenames = c('tcga_EPI','tcga_MES'), isInteractive = FALSE)
    print(tcgaLandscape)
    dev.off()
    
    # Save the TCGA landscape object
    saveRDS(tcgaLandscape, "tcga_landscape_object.rds")
    
    # 4. Project CCLE samples onto the TCGA landscape
    pdf("projected_score_landscape.pdf", width = 8, height = 6)
    projected_plot <- projectScoreLandscape(plotObj = tcgaLandscape, scoredf_ccle_epi, 
                                            scoredf_ccle_mes,
                                            subSamples = rownames(scoredf_ccle_epi)[c(1,4,5)],
                                            annot = rownames(scoredf_ccle_epi)[c(1,4,5)], 
                                            sampleLabels = NULL,
                                            isInteractive = FALSE)
    print(projected_plot)
    dev.off()
    
    # Save the projected plot object
    saveRDS(projected_plot, "projected_landscape_object.rds")
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION":',
        paste0('    singscore: ', as.character(packageVersion('singscore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_score_landscape_projection.csv versions.yml
    """
}

workflow BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scoredf_ccle_epi, scoredf_ccle_mes, scoredf_tcga_epi, scoredf_tcga_mes ] ]

    main:
    BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION(ch_input)

    emit:
    tables   = BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION.out.tables
    plots    = BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION.out.plots
    objects  = BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION.out.objects
    versions = BIOC_SINGSCORE_SCORE_LANDSCAPE_PROJECTION.out.versions
}
