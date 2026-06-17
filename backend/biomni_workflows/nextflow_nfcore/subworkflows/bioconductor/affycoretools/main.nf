#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affycoretools — differential_expression_and_html_reporting
// Annotate expression data, fit a linear model, generate gene-level plots, and compile results into an interactive HTML report with clickable links.
// Input: eset, hgu95av2.db
// Container: quay.io/biocontainers/bioconductor-affycoretools:1.82.0--r45hdfd78af_0
// R packages: AnnotationDbi, affycoretools, hgu95av2.db, knitr, limma, ReportingTools
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, ReportingTools, affycoretools, hgu95av2.db, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Annotate the ExpressionSet using annotateEset
//  * 2. [Core Analysis] Fit a linear model and compute contrasts using limma
//  * 3. [Visualization & Output] Generate gene-level plots for top differentially expressed genes using makeImages
//  * 4. [Visualization & Output] Publish the results to an HTML report with clickable gene links using ReportingTools and finish

nextflow.enable.dsl = 2

process BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING {
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
    .bm_deps <- c("AnnotationDbi", "affycoretools", "hgu95av2.db", "knitr", "limma", "ReportingTools")
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
        
        # Load required libraries
        suppressPackageStartupMessages({
          library(affycoretools)
          library(limma)
          library(ReportingTools)
          library(AnnotationDbi)
        })
        
        # ==========================================
        # 1. Load User Input Files
        # ==========================================
        message("Loading ExpressionSet from working directory...")
        eset <- NULL
        
        # Robustly attempt to load 'eset' from various common formats
        if (file.exists("eset.rds")) {
          eset <- readRDS("eset.rds")
        } else if (file.exists("eset")) {
          eset <- tryCatch(readRDS("eset"), error = function(e) {
            env <- new.env()
            load("eset", envir = env)
            objs <- ls(env)
            for (o in objs) {
              if (inherits(env[[o]], "ExpressionSet")) return(env[[o]])
            }
            stop("No ExpressionSet found in 'eset' file.")
          })
        } else if (file.exists("eset.RData")) {
          env <- new.env()
          load("eset.RData", envir = env)
          objs <- ls(env)
          for (o in objs) {
            if (inherits(env[[o]], "ExpressionSet")) {
              eset <- env[[o]]
              break
            }
          }
        }
        
        if (is.null(eset)) {
          stop("Error: Could not find or load 'eset' (ExpressionSet) from the working directory.")
        }
        
        # Clean feature names to avoid path issues with special characters (e.g., "/")
        featureNames(eset) <- gsub("/", "_", featureNames(eset))
        
        # Load the annotation database
        message("Loading annotation database...")
        if (file.exists("hgu95av2.db")) {
          # If the user provided a SQLite database file directly
          hgu95av2.db <- AnnotationDbi::loadDb("hgu95av2.db")
        } else {
          # Otherwise, load the installed Bioconductor annotation package
          library(hgu95av2.db)
        }
        
        # ==========================================
        # 2. Annotate the ExpressionSet
        # ==========================================
        message("Annotating ExpressionSet...")
        eset <- annotateEset(eset, hgu95av2.db)
        
        # ==========================================
        # 3. Fit Linear Model and Compute Contrasts
        # ==========================================
        message("Setting up experimental design and fitting model...")
        pd <- pData(phenoData(eset))
        
        # Ensure required phenoData columns exist; fallback to defaults if missing
        if (!"type" %in% colnames(pd)) {
          pd\$type <- factor(rep(c("Control", "Case"), length.out = ncol(eset)))
        }
        if (!"sex" %in% colnames(pd)) {
          pd\$sex <- factor(rep(c("F", "M"), length.out = ncol(eset)))
        }
        pData(eset) <- pd
        
        design <- model.matrix(~0+type+sex, pd)
        colnames(design) <- gsub("type|sex", "", colnames(design))
        contrast <- matrix(c(1,-1,0))
        colnames(contrast) <- "Case vs control"
        
        # Fit the linear model exactly as documented
        fit <- lmFit(eset, design)
        fit2 <- contrasts.fit(fit, contrast)
        fit2 <- eBayes(fit2)
        d.f <- topTable(fit2, 1)
        
        # ==========================================
        # 4. Generate Plots and Compile HTML Report
        # ==========================================
        message("Generating gene-level plots...")
        out <- makeImages(df = d.f, eset = eset, grp.factor = pd\$type, design = design,
                          contrast = contrast, colind = 1, repdir = ".")
        
        message("Compiling interactive HTML report...")
        htab <- HTMLReport("afile3", "My cool results, affycoretools style")
        publish(out\$df, htab, .modifyDF = list(entrezLinks, affyLinks))
        finish(htab)
        
        # ==========================================
        # 5. Save Outputs
        # ==========================================
        message("Saving results to disk...")
        write.csv(d.f, "top_table_results.csv", row.names = TRUE)
        saveRDS(fit2, "limma_fit2.rds")
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING":',
        paste0('    affycoretools: ', as.character(packageVersion('affycoretools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_and_html_reporting.csv versions.yml
    """
}

workflow BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eset, hgu95av2.db ] ]

    main:
    BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING(ch_input)

    emit:
    tables   = BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING.out.tables
    plots    = BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING.out.plots
    objects  = BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING.out.objects
    versions = BIOC_AFFYCORETOOLS_DIFFERENTIAL_EXPRESSION_AND_HTML_REPORTING.out.versions
}
