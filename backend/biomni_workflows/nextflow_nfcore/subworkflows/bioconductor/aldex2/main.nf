#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ALDEx2 — two_group_comparison
// Perform differential abundance testing between two groups using Welch's t-test, Wilcoxon rank test, and effect size estimation.
// Input: selex.sub, conds
// Container: quay.io/biocontainers/bioconductor-aldex2:1.42.0--r45hdfd78af_0
// R packages: ALDEx2, cowplot, ggpattern, ggplot2, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: ALDEx2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate Dirichlet Monte Carlo instances using `aldex.clr`
//  * 2. [Core Analysis] Perform t-tests using `aldex.ttest`
//  * 3. [Core Analysis] Calculate effect sizes using `aldex.effect`
//  * 4. [Visualization & Output] Merge and plot results using `aldex.plot` and `aldex.plotFeature`

nextflow.enable.dsl = 2

process BIOC_ALDEX2_TWO_GROUP_COMPARISON {
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
    .bm_deps <- c("ALDEx2", "cowplot", "ggpattern", "ggplot2", "tidyverse")
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
    library(ALDEx2)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    if (!file.exists("selex.sub")) {
      stop("Error: Required input file 'selex.sub' not found in the working directory.")
    }
    
    if (!file.exists("conds")) {
      stop("Error: Required input file 'conds' not found in the working directory.")
    }
    
    # Read count matrix (features by samples)
    selex.sub <- tryCatch({
      read.csv("selex.sub", row.names = 1, check.names = FALSE)
    }, error = function(e) {
      read.table("selex.sub", header = TRUE, row.names = 1, sep = "", check.names = FALSE)
    })
    
    # Read conditions vector
    conds <- scan("conds", what = character(), quiet = TRUE)
    conds <- conds[conds != ""]
    
    # -----------------------------------------------------------------------------
    # 2. Run ALDEx2 Pipeline
    # -----------------------------------------------------------------------------
    # Generate Dirichlet Monte Carlo instances
    x <- aldex.clr(selex.sub, conds, mc.samples=16, denom="all", verbose=F, gamma=1e-3)
    
    # Perform Welch's t-test and Wilcoxon rank test
    x.tt <- aldex.ttest(x, hist.plot=F, paired.test=FALSE, verbose=FALSE)
    
    # Calculate effect sizes
    x.effect <- aldex.effect(x, CI=T, verbose=F, include.sample.summary=F,
      paired.test=FALSE, glm.conds=NULL, useMC=F)
    
    # Merge results
    x.all <- data.frame(x.tt, x.effect)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs and Generate Plots
    # -----------------------------------------------------------------------------
    # Save tabular results
    write.csv(x.all, "aldex_results.csv", row.names = TRUE)
    saveRDS(x, "aldex_clr_object.rds")
    
    # Generate MA and MW plots
    pdf("aldex_plots.pdf", width = 10, height = 5)
    par(mfrow=c(1,2))
    aldex.plot(x.all, type="MA", test="welch")
    aldex.plot(x.all, type="MW", test="welch")
    dev.off()
    
    # Generate feature plot
    pdf("aldex_feature_plot.pdf", width = 7, height = 7)
    tryCatch({
      # Attempt to plot the documented feature 'S:E:G:D'
      aldex.plotFeature(x, 'S:E:G:D')
    }, error = function(e) {
      # Fallback to the first available feature if 'S:E:G:D' is not in the user's dataset
      if (nrow(selex.sub) > 0) {
        fallback_feature <- rownames(selex.sub)[1]
        aldex.plotFeature(x, fallback_feature)
      }
    })
    dev.off()

    writeLines(c(
        '"BIOC_ALDEX2_TWO_GROUP_COMPARISON":',
        paste0('    ALDEx2: ', as.character(packageVersion('ALDEx2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_comparison.csv versions.yml
    """
}

workflow BIOC_ALDEX2_TWO_GROUP_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ selex.sub, conds ] ]

    main:
    BIOC_ALDEX2_TWO_GROUP_COMPARISON(ch_input)

    emit:
    tables   = BIOC_ALDEX2_TWO_GROUP_COMPARISON.out.tables
    plots    = BIOC_ALDEX2_TWO_GROUP_COMPARISON.out.plots
    objects  = BIOC_ALDEX2_TWO_GROUP_COMPARISON.out.objects
    versions = BIOC_ALDEX2_TWO_GROUP_COMPARISON.out.versions
}
