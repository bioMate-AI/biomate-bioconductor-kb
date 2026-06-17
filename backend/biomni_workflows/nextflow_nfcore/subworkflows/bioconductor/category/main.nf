#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Category — pathway_category_analysis
// Perform pathway-based category analysis using t-statistics, permutation testing, and custom category functions.
// Input: esetA.RData
// Container: quay.io/biocontainers/bioconductor-category:2.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Category, annotate, genefilter, hgu95av2.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter and preprocess the ExpressionSet to remove duplicate Entrez ID mappings
//  * 2. [Core Analysis] Compute per-gene t-statistics using rowttests
//  * 3. [Input & Preparation] Map genes to pathways and build the category incidence matrix
//  * 4. [Core Analysis] Compute observed category-level statistics
//  * 5. [Core Analysis] Generate a permutation distribution using ttperm to calculate empirical p-values
//  * 6. [Core Analysis] Apply custom functions across categories using applyByCategory

nextflow.enable.dsl = 2

process BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS {
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
    .bm_deps <- c("Biobase", "annotate", "hgu95av2.db", "genefilter", "Category")
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
    suppressPackageStartupMessages({
      library("Biobase")
      library("annotate")
      library("hgu95av2.db")
      library("genefilter")
      library("Category")
    })
    
    # 1. Load User Input
    if (!file.exists("esetA.RData")) {
      stop("Error: 'esetA.RData' is required but was not found in the working directory.")
    }
    
    load("esetA.RData")
    
    if (!exists("esetA")) {
      stop("Error: Loaded 'esetA.RData' does not contain an object named 'esetA'.")
    }
    
    # Filter and preprocess the ExpressionSet to remove duplicate Entrez ID mappings
    esetA@annotation = "hgu95av2"
    esetA\$mol.biol = factor(esetA\$mol.biol)
    esetASub = nsFilter(esetA, var.cutoff=0.5)\$eset
    
    # 2. Compute per-gene t-statistics using rowttests
    ttests = rowttests(esetASub, "mol.biol")
    
    # Find the probes that we are going to use
    fL = findLargest(featureNames(esetASub), abs(ttests\$statistic), "hgu95av2")
    fL2 = probes2Path(fL, "hgu95av2")
    inBoth = fL %in% names(fL2)
    fL = fL[inBoth]
    
    # Reorder and compute t-tests
    eS = esetASub[match(names(fL2), featureNames(esetASub)),]
    tobs = rowttests(eS, "mol.biol")
    
    # 3. Map genes to pathways and build the category incidence matrix
    Amat = t(PWAmat("hgu95av2"))
    AmER = Amat[,names(fL)]
    
    rs = rowSums(AmER)
    AmER2 = AmER[rs>5,]
    rs2   = rs[rs>5]
    nCats = length(rs2)
    
    # 4. Compute observed category-level statistics
    tA = AmER2 %*% tobs\$statistic
    tA = tA/sqrt(rs2)
    names(tA) = row.names(AmER2)
    
    # Save QQ-plot of category statistics
    pdf("category_stats_qqplot.pdf")
    qqnorm(tA)
    qqline(tA)
    dev.off()
    
    # 5. Generate a permutation distribution using ttperm to calculate empirical p-values
    NPERM = 500
    set.seed(444)
    
    v1 = ttperm(exprs(eS), eS\$mol.biol, B=NPERM)
    
    permDm <- matrix(0.0, nrow=length(v1\$perms[[1]]\$statistic),
                     ncol=length(v1\$perms))
    for (j in 1:ncol(permDm)) {
        permDm[ , j] <- v1\$perms[[j]]\$statistic
    }
    
    permD = AmER2 %*% permDm
    permD2 = sweep(permD, 1, sqrt(rs2), "/")
    
    pvals = matrix(NA, nr=nCats, ncol=2)
    dimnames(pvals) = list(row.names(AmER2), c("Lower", "Upper"))
    
    for(i in 1:nCats) {
        pvals[i,1] = sum(permD2[i,] < tA[i])/NPERM
        pvals[i,2] = sum(permD2[i,] > tA[i])/NPERM
    }
    
    # 6. Apply custom functions across categories using applyByCategory
    med = applyByCategory(tobs\$statistic, AmER2, FUN=median)
    wt  = applyByCategory(tobs\$statistic, AmER2, 
      FUN = function(x) with(wilcox.test(x), c(statistic, p=p.value)))
    
    # Save outputs to files
    cat_stats_df <- data.frame(
      Category = names(tA),
      Observed_T = as.vector(tA),
      Size = rs2,
      stringsAsFactors = FALSE
    )
    write.csv(cat_stats_df, "category_observed_statistics.csv", row.names = FALSE)
    
    pvals_df <- data.frame(
      Category = row.names(pvals),
      P_Lower = pvals[, "Lower"],
      P_Upper = pvals[, "Upper"],
      stringsAsFactors = FALSE
    )
    write.csv(pvals_df, "category_permutation_pvalues.csv", row.names = FALSE)
    
    med_df <- data.frame(
      Category = names(med),
      Median_T = as.vector(med),
      stringsAsFactors = FALSE
    )
    write.csv(med_df, "category_median_statistics.csv", row.names = FALSE)
    
    write.csv(as.data.frame(t(wt)), "category_wilcoxon_test.csv", row.names = TRUE)
    
    saveRDS(tA, "category_tA.rds")
    saveRDS(pvals, "category_pvals.rds")
    saveRDS(med, "category_med.rds")
    saveRDS(wt, "category_wt.rds")

    writeLines(c(
        '"BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS":',
        paste0('    Category: ', as.character(packageVersion('Category')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_category_analysis.csv versions.yml
    """
}

workflow BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ esetA.RData ] ]

    main:
    BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS.out.tables
    plots    = BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS.out.plots
    objects  = BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS.out.objects
    versions = BIOC_CATEGORY_PATHWAY_CATEGORY_ANALYSIS.out.versions
}
