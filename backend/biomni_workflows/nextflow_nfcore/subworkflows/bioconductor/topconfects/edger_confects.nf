#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: topconfects — edger_confects
// Rank genes by confident fold change from an edgeR quasi-likelihood fit.
// Input: y, design
// Container: quay.io/biocontainers/bioconductor-topconfects:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, ggplot2, topconfects
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate dispersions and fit QL model
//  * 2. [Core Analysis] Calculate confident effect sizes using edger_confects
//  * 3. [Visualization & Output] Visualize results using confects_plot and confects_plot_me2

nextflow.enable.dsl = 2

process BIOC_TOPCONFECTS_EDGER_CONFECTS {
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
            
            # Load required libraries
            library(edgeR)
            library(topconfects)
            library(ggplot2)
            
            # ==========================================
            # 1. Read User Input Files
            # ==========================================
            # The pipeline expects 'y.rds' (a DGEList object with normalization factors)
            # and 'design.rds' (the model matrix) in the working directory.
            if (!file.exists("y.rds") || !file.exists("design.rds")) {
              stop("Required input files 'y.rds' and/or 'design.rds' are missing from the working directory.")
            }
            
            y <- readRDS("y.rds")
            design <- readRDS("design.rds")
            
            # ==========================================
            # 2. Estimate Dispersions and Fit QL Model
            # ==========================================
            y <- estimateDisp(y, design, robust=TRUE)
            efit <- glmQLFit(y, design, robust=TRUE)
            
            # ==========================================
            # 3. Calculate Confident Effect Sizes
            # ==========================================
            # Note: coef=ncol(design) is used to test the last coefficient in the design matrix
            # by default, making it compatible with generic user-provided data.
            econfects <- edger_confects(efit, coef=ncol(design), fdr=0.05, step=0.01)
            
            # Save the resulting confects object and table
            saveRDS(econfects, "econfects.rds")
            write.csv(econfects\$table, "econfects_table.csv", row.names=FALSE)
            
            # ==========================================
            # 4. Visualize Results
            # ==========================================
            pdf("confects_plots.pdf", width=8, height=6)
            
            # Plot 1: Confident effect sizes of top genes
            p1 <- confects_plot(econfects)
            print(p1)
            
            # Plot 2: Mean-Difference Plot with colored confident effect size thresholds
            p2 <- confects_plot_me2(econfects, breaks=c(0,1,2))
            print(p2)
            
            dev.off()

    writeLines(c(
        '"BIOC_TOPCONFECTS_EDGER_CONFECTS":',
        paste0('    topconfects: ', as.character(packageVersion('topconfects')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edger_confects.csv versions.yml
    """
}

workflow BIOC_TOPCONFECTS_EDGER_CONFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y, design ] ]

    main:
    BIOC_TOPCONFECTS_EDGER_CONFECTS(ch_input)

    emit:
    tables   = BIOC_TOPCONFECTS_EDGER_CONFECTS.out.tables
    plots    = BIOC_TOPCONFECTS_EDGER_CONFECTS.out.plots
    objects  = BIOC_TOPCONFECTS_EDGER_CONFECTS.out.objects
    versions = BIOC_TOPCONFECTS_EDGER_CONFECTS.out.versions
}
