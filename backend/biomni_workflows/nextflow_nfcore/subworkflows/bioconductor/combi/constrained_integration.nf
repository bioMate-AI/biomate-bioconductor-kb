#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: combi — constrained_integration
// Integrate multiple omics views constrained by sample covariates.
// Input: zhangMicrobio, zhangMetabo, zhangMetavars
// Container: quay.io/biocontainers/bioconductor-combi:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: combi
// Visualizations: ordination plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit constrained combi model using combi() with covariates
//  * 2. [Visualization & Output] Print model summary
//  * 3. [Visualization & Output] Plot constrained ordination with sample metadata

nextflow.enable.dsl = 2

process BIOC_COMBI_CONSTRAINED_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("combi")
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
        library(combi)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        
        # Load zhangMicrobio
        if (file.exists("zhangMicrobio.rds")) {
          zhangMicrobio <- readRDS("zhangMicrobio.rds")
        } else if (file.exists("zhangMicrobio.csv")) {
          zhangMicrobio <- as.matrix(read.csv("zhangMicrobio.csv", row.names = 1))
        } else {
          stop("Required input file 'zhangMicrobio' (RDS or CSV) not found in the working directory.")
        }
        
        # Load zhangMetabo
        if (file.exists("zhangMetabo.rds")) {
          zhangMetabo <- readRDS("zhangMetabo.rds")
        } else if (file.exists("zhangMetabo.csv")) {
          zhangMetabo <- as.matrix(read.csv("zhangMetabo.csv", row.names = 1))
        } else {
          stop("Required input file 'zhangMetabo' (RDS or CSV) not found in the working directory.")
        }
        
        # Load zhangMetavars
        if (file.exists("zhangMetavars.rds")) {
          zhangMetavars <- readRDS("zhangMetavars.rds")
        } else if (file.exists("zhangMetavars.csv")) {
          zhangMetavars <- read.csv("zhangMetavars.csv", row.names = 1)
        } else {
          stop("Required input file 'zhangMetavars' (RDS or CSV) not found in the working directory.")
        }
        
        # -----------------------------------------------------------------------------
        # 2. Fit Constrained Combi Model
        # -----------------------------------------------------------------------------
        
        microMetaboIntConstr = combi(
             list("microbiome" = zhangMicrobio, "metabolomics" = zhangMetabo),
             distributions = c("quasi", "gaussian"), compositional = c(TRUE, FALSE),
             logTransformGaussian = FALSE, covariates = zhangMetavars)
        
        # -----------------------------------------------------------------------------
        # 3. Print Model Summary
        # -----------------------------------------------------------------------------
        
        print(microMetaboIntConstr)
        
        # Save model summary text to file
        sink("constrained_model_summary.txt")
        print(microMetaboIntConstr)
        sink()
        
        # -----------------------------------------------------------------------------
        # 4. Plot Constrained Ordination
        # -----------------------------------------------------------------------------
        
        pdf("constrained_ordination_plot.pdf", width = 9, height = 6)
        plot(microMetaboIntConstr, samDf = zhangMetavars, samCol = colnames(zhangMetavars)[1])
        dev.off()
        
        # -----------------------------------------------------------------------------
        # 5. Export Meaningful Results
        # -----------------------------------------------------------------------------
        
        # Save the fitted model object
        saveRDS(microMetaboIntConstr, file = "microMetaboIntConstr.rds")
        
        # Extract and save coordinates for downstream analysis
        tryCatch({
          coords <- extractCoords(microMetaboIntConstr, Dim = c(1, 2))
          for (nm in names(coords)) {
            write.csv(coords[[nm]], file = paste0("constrained_coordinates_", nm, ".csv"), row.names = TRUE)
          }
        }, error = function(e) {
          warning("Could not extract coordinates: ", e\$message)
        })

    writeLines(c(
        '"BIOC_COMBI_CONSTRAINED_INTEGRATION":',
        paste0('    combi: ', as.character(packageVersion('combi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_constrained_integration.csv versions.yml
    """
}

workflow BIOC_COMBI_CONSTRAINED_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zhangMicrobio, zhangMetabo, zhangMetavars ] ]

    main:
    BIOC_COMBI_CONSTRAINED_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_COMBI_CONSTRAINED_INTEGRATION.out.tables
    plots    = BIOC_COMBI_CONSTRAINED_INTEGRATION.out.plots
    objects  = BIOC_COMBI_CONSTRAINED_INTEGRATION.out.objects
    versions = BIOC_COMBI_CONSTRAINED_INTEGRATION.out.versions
}
