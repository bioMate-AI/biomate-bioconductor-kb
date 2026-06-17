#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metahdep — custom_meta_analysis
// Perform meta-analysis on custom effect size estimates and covariance matrices (e.g., from literature reviews) using FEMA, REMA, and HBLM.
// Input: Vector of effect sizes, Covariance matrix, Design matrix, List of dependence groups
// Container: quay.io/biocontainers/bioconductor-metahdep:1.64.0--r44h3df3fcb_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metahdep
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the effect size vector theta and covariance matrix V (including off-diagonal elements for sampling dependence)
//  * 2. [Input & Preparation] Construct the design matrix X for covariates
//  * 3. [Input & Preparation] Define hierarchical dependence groups dep.groups
//  * 4. [Core Analysis] Run fixed effects meta-analysis using metahdep.FEMA
//  * 5. [Core Analysis] Run random effects meta-analysis (with or without delta-splitting) using metahdep.REMA
//  * 6. [Core Analysis] Run hierarchical Bayes meta-analysis (with or without delta-splitting) using metahdep.HBLM

nextflow.enable.dsl = 2

process BIOC_METAHDEP_CUSTOM_META_ANALYSIS {
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
    .bm_deps <- c("metahdep")
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
    
    # Load required library
    library(metahdep)
    
    # 1. Read user inputs from the working directory
    if (!file.exists("theta.rds") || !file.exists("V.rds") || !file.exists("X.rds") || !file.exists("dep.groups.rds")) {
      stop("Required input files (theta.rds, V.rds, X.rds, dep.groups.rds) not found in the working directory.")
    }
    
    theta <- readRDS("theta.rds")
    V <- readRDS("V.rds")
    X <- readRDS("X.rds")
    dep.groups <- readRDS("dep.groups.rds")
    
    # 2. Run fixed effects meta-analysis using metahdep.FEMA
    FEMA.indep <- metahdep.FEMA(theta, diag(diag(V)), X, center.X=TRUE)
    FEMA.dep <- metahdep.FEMA(theta, V, X, center.X=TRUE)
    
    # 3. Run random effects meta-analysis using metahdep.REMA
    REMA.indep <- metahdep.REMA(theta, diag(diag(V)), X, center.X=TRUE)
    REMA.dep <- metahdep.REMA(theta, V, X, center.X=TRUE)
    REMA.ds <- metahdep.REMA(theta, V, X, center.X=TRUE, delta.split=TRUE, dep.groups=dep.groups)
    
    # 4. Run hierarchical Bayes meta-analysis using metahdep.HBLM
    HBLM.indep <- metahdep.HBLM(theta, diag(diag(V)), X, center.X=TRUE, two.sided=TRUE)
    HBLM.dep <- metahdep.HBLM(theta, V, X, center.X=TRUE, two.sided=TRUE)
    HBLM.ds <- metahdep.HBLM(theta, V, X, center.X=TRUE, two.sided=TRUE, delta.split=TRUE, dep.groups=dep.groups, n=20, m=20)
    
    # 5. Save RDS objects of the results
    saveRDS(FEMA.indep, "FEMA.indep.rds")
    saveRDS(FEMA.dep, "FEMA.dep.rds")
    saveRDS(REMA.indep, "REMA.indep.rds")
    saveRDS(REMA.dep, "REMA.dep.rds")
    saveRDS(REMA.ds, "REMA.ds.rds")
    saveRDS(HBLM.indep, "HBLM.indep.rds")
    saveRDS(HBLM.dep, "HBLM.dep.rds")
    saveRDS(HBLM.ds, "HBLM.ds.rds")
    
    # 6. Construct and save summary table
    r1 <- round(c(FEMA.indep\$beta.hats[1], FEMA.indep\$beta.hat.p.values[1], NA, NA), 4)
    r2 <- round(c(FEMA.dep\$beta.hats[1], FEMA.dep\$beta.hat.p.values[1], NA, NA), 4)
    r3 <- round(c(REMA.indep\$beta.hats[1], REMA.indep\$beta.hat.p.values[1], REMA.indep\$tau2.hat, NA), 4)
    r4 <- round(c(REMA.dep\$beta.hats[1], REMA.dep\$beta.hat.p.values[1], REMA.dep\$tau2.hat, NA), 4)
    r5 <- round(c(REMA.ds\$beta.hats[1], REMA.ds\$beta.hat.p.values[1], REMA.ds\$tau2.hat, REMA.ds\$varsigma.hat), 4)
    r6 <- round(c(HBLM.indep\$beta.hats[1], HBLM.indep\$beta.hat.p.values[1], HBLM.indep\$tau.var + HBLM.indep\$tau.hat^2, NA), 4)
    r7 <- round(c(HBLM.dep\$beta.hats[1], HBLM.dep\$beta.hat.p.values[1], HBLM.dep\$tau.var + HBLM.dep\$tau.hat^2, NA), 4)
    r8 <- round(c(HBLM.ds\$beta.hats[1], HBLM.ds\$beta.hat.p.values[1], HBLM.ds\$tau.var + HBLM.ds\$tau.hat^2, HBLM.ds\$varsigma.hat), 4)
    
    model <- c(rep('Fixed', 2), rep('Random', 3), rep('Bayes', 3))
    dep_structure <- c('Independent', 'Dependent', rep(c('Independent', 'Dependent', 'Delta-split'), 2))
    Table2 <- as.data.frame(cbind(model, dep_structure, rbind(r1, r2, r3, r4, r5, r6, r7, r8)))
    colnames(Table2) <- c('Model', 'Structure', 'Intercept', 'P', 'tau-square', 'varsigma')
    write.csv(Table2, "meta_analysis_summary.csv", row.names = FALSE)
    
    # 7. Generate and save plot
    pdf("meta_analysis_pvalues.pdf", width = 8, height = 6)
    pvals <- c(
      FEMA.indep = FEMA.indep\$beta.hat.p.values[1],
      FEMA.dep = FEMA.dep\$beta.hat.p.values[1],
      REMA.indep = REMA.indep\$beta.hat.p.values[1],
      REMA.dep = REMA.dep\$beta.hat.p.values[1],
      REMA.ds = REMA.ds\$beta.hat.p.values[1],
      HBLM.indep = HBLM.indep\$beta.hat.p.values[1],
      HBLM.dep = HBLM.dep\$beta.hat.p.values[1],
      HBLM.ds = HBLM.ds\$beta.hat.p.values[1]
    )
    par(mar = c(8, 4, 4, 2) + 0.1)
    barplot(pvals, las = 2, main = "Intercept P-values by Model Structure", col = "skyblue", ylab = "P-value")
    dev.off()

    writeLines(c(
        '"BIOC_METAHDEP_CUSTOM_META_ANALYSIS":',
        paste0('    metahdep: ', as.character(packageVersion('metahdep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_meta_analysis.csv versions.yml
    """
}

workflow BIOC_METAHDEP_CUSTOM_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Vector of effect sizes, Covariance matrix, Design matrix, List of dependence groups ] ]

    main:
    BIOC_METAHDEP_CUSTOM_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METAHDEP_CUSTOM_META_ANALYSIS.out.tables
    plots    = BIOC_METAHDEP_CUSTOM_META_ANALYSIS.out.plots
    objects  = BIOC_METAHDEP_CUSTOM_META_ANALYSIS.out.objects
    versions = BIOC_METAHDEP_CUSTOM_META_ANALYSIS.out.versions
}
