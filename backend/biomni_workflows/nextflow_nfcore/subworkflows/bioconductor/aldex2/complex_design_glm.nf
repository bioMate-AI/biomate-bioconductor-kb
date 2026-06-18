#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ALDEx2 — complex_design_glm
// Perform differential abundance analysis for complex experimental designs with multiple covariates using GLMs.
// Input: selex.sub, covariates
// Container: quay.io/biocontainers/bioconductor-aldex2:1.42.0--r45hdfd78af_0
// R packages: ALDEx2
// Bioconductor: 3.20 | R: 4.4
// Requires: ALDEx2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate CLR instances using model matrix in `aldex.clr`
//  * 2. [Core Analysis] Fit GLM using `aldex.glm`
//  * 3. [Core Analysis] Calculate GLM effect sizes using `aldex.glm.effect`
//  * 4. [Visualization & Output] Plot GLM results using `aldex.glm.plot`

nextflow.enable.dsl = 2

process BIOC_ALDEX2_COMPLEX_DESIGN_GLM {
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
    .bm_deps <- c("ALDEx2")
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
            
            # Read selex.sub (count matrix of features by samples)
            if (file.exists("selex.sub")) {
              selex.sub <- tryCatch({
                read.csv("selex.sub", row.names = 1, check.names = FALSE)
              }, error = function(e) {
                read.table("selex.sub", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
              })
            } else {
              stop("Error: 'selex.sub' file not found in the working directory.")
            }
            
            # Read covariates (data frame of covariates)
            if (file.exists("covariates")) {
              covariates <- tryCatch({
                read.csv("covariates", row.names = 1, check.names = FALSE)
              }, error = function(e) {
                read.table("covariates", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
              })
            } else {
              stop("Error: 'covariates' file not found in the working directory.")
            }
            
            # Ensure covariates is a data.frame
            covariates <- as.data.frame(covariates)
            
            # -----------------------------------------------------------------------------
            # 2. Construct Model Matrix and Run ALDEx2 GLM Workflow
            # -----------------------------------------------------------------------------
            
            # Create model matrix using all provided covariates dynamically
            mm <- model.matrix(~ ., data = covariates)
            
            # Stage 1: Generate CLR instances using model matrix in aldex.clr
            x.glm <- aldex.clr(selex.sub, mm, mc.samples=4, denom="all", verbose=T)
            
            # Stage 2: Fit GLM using aldex.glm
            glm.test <- aldex.glm(x.glm, fdr.method='holm')
            
            # Stage 3: Calculate GLM effect sizes using aldex.glm.effect
            glm.eff <- aldex.glm.effect(x.glm)
            
            # -----------------------------------------------------------------------------
            # 3. Save Outputs and Generate Plots
            # -----------------------------------------------------------------------------
            
            # Save GLM test results
            write.csv(glm.test, "glm_test_results.csv", row.names = TRUE)
            
            # Save GLM effect sizes (RDS and individual CSVs if applicable)
            saveRDS(glm.eff, "glm_effect_results.rds")
            if (is.list(glm.eff)) {
              for (name in names(glm.eff)) {
                write.csv(glm.eff[[name]], paste0("glm_effect_", name, ".csv"), row.names = TRUE)
              }
            } else {
              write.csv(glm.eff, "glm_effect_results.csv", row.names = TRUE)
            }
            
            # Stage 4: Plot GLM results using aldex.glm.plot
            pdf("aldex_glm_plot.pdf", width = 7, height = 7)
            contrast_names <- sub(":pval\$", "", grep(":pval\$", colnames(glm.test), value = TRUE))
            contrast_name <- contrast_names[contrast_names != "Intercept"][1]
            aldex.glm.plot(glm.test, eff=glm.eff, contrast=contrast_name, type='MW', test='fdr')
            dev.off()
            
            cat("ALDEx2 GLM pipeline completed successfully. Outputs saved to 'glm_test_results.csv', 'glm_effect_results.rds', and 'aldex_glm_plot.pdf'.\n")

    writeLines(c(
        '"BIOC_ALDEX2_COMPLEX_DESIGN_GLM":',
        paste0('    ALDEx2: ', as.character(packageVersion('ALDEx2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_design_glm.csv versions.yml
    """
}

workflow BIOC_ALDEX2_COMPLEX_DESIGN_GLM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ selex.sub, covariates ] ]

    main:
    BIOC_ALDEX2_COMPLEX_DESIGN_GLM(ch_input)

    emit:
    tables   = BIOC_ALDEX2_COMPLEX_DESIGN_GLM.out.tables
    plots    = BIOC_ALDEX2_COMPLEX_DESIGN_GLM.out.plots
    objects  = BIOC_ALDEX2_COMPLEX_DESIGN_GLM.out.objects
    versions = BIOC_ALDEX2_COMPLEX_DESIGN_GLM.out.versions
}
