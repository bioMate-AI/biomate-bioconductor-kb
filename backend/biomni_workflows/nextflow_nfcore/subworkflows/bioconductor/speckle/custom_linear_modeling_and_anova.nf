#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: speckle — custom_linear_modeling_and_anova
// Extract transformed proportions to perform custom linear modeling, ANOVA, pairwise t-tests, continuous trend fitting, or random effects modeling.
// Input: sce_all
// Container: quay.io/biocontainers/bioconductor-speckle:1.10.0--r45hdfd78af_0
// R packages: SingleCellExperiment, edgeR, ggplot2, limma, patchwork, scater, speckle, statmod
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, edgeR, ggplot2, limma, patchwork, scater, speckle, statmod
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Extract counts, proportions, and transformed proportions. 2. Set up a design matrix for group and pairing covariates. 3. Perform a

nextflow.enable.dsl = 2

process BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA {
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
    .bm_deps <- c("SingleCellExperiment", "edgeR", "ggplot2", "limma", "patchwork", "scater", "speckle", "statmod")
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
    library(speckle)
    library(limma)
    library(ggplot2)
    library(scater)
    library(patchwork)
    library(edgeR)
    library(statmod)
    
    # 1. Read the input SingleCellExperiment object
    if (file.exists("sce_all.rds")) {
      sce_all <- readRDS("sce_all.rds")
    } else if (file.exists("sce_all")) {
      sce_all <- readRDS("sce_all")
    } else {
      stop("Error: Could not find 'sce_all' or 'sce_all.rds' in the working directory.")
    }
    
    # 2. Extract counts, proportions, and transformed proportions
    props <- getTransformedProps(sce_all\$cluster, sce_all\$sample, transform="logit")
    
    samples_in_props <- colnames(props\$TransformedProps)
    
    # Extract unique sample-to-group mapping from sce_all
    sample_group_map <- unique(data.frame(
      sample = sce_all\$sample,
      group = sce_all\$group
    ))
    
    # Extract pair and dose covariates only if they actually exist in the experimental design
    if (!is.null(sce_all\$pair)) {
      sample_group_map\$pair <- sce_all\$pair[match(sample_group_map\$sample, sce_all\$sample)]
    }
    if (!is.null(sce_all\$dose)) {
      sample_group_map\$dose <- sce_all\$dose[match(sample_group_map\$sample, sce_all\$sample)]
    }
    
    sample_group_map <- sample_group_map[match(samples_in_props, sample_group_map\$sample), ]
    
    # Use the actual groups from the user's data
    group <- factor(sample_group_map\$group)
    
    # 3. Set up a design matrix for group and pairing covariates
    if ("pair" %in% colnames(sample_group_map)) {
      pair <- factor(sample_group_map\$pair)
      design <- model.matrix(~ 0 + group + pair)
    } else {
      design <- model.matrix(~ 0 + group)
    }
    
    # 4. Perform an ANOVA test across multiple groups using propeller.anova
    group_coefs <- 1:length(levels(group))
    anova_res <- propeller.anova(prop.list=props, design=design, coef = group_coefs, robust=TRUE, trend=FALSE, sort=TRUE)
    write.csv(anova_res, "propeller_anova_results.csv", row.names=TRUE)
    
    # 5. Perform a pairwise t-test using propeller.ttest with contrasts
    if (length(levels(group)) >= 2) {
      # Dynamically create a contrast between the first two groups, using backticks to safely handle any special characters
      contr_str <- paste0("`", colnames(design)[1], "` - `", colnames(design)[2], "`")
      mycontr <- makeContrasts(contrasts = contr_str, levels=design)
      ttest_res <- propeller.ttest(props, design, contrasts = mycontr, robust=TRUE, trend=FALSE, sort=TRUE)
      write.csv(ttest_res, "propeller_ttest_results.csv", row.names=TRUE)
    }
    
    # 6. Fit a continuous variable (dose/trend) directly using limma
    if ("dose" %in% colnames(sample_group_map)) {
      dose <- sample_group_map\$dose
      des.dose <- model.matrix(~dose)
      fit <- lmFit(props\$TransformedProps, des.dose)
      fit <- eBayes(fit, robust=TRUE)
      top_dose <- topTable(fit)
      write.csv(top_dose, "limma_continuous_dose_results.csv", row.names=TRUE)
    }
    
    # 7. Fit a linear model accounting for random effects using duplicateCorrelation
    if ("pair" %in% colnames(sample_group_map)) {
      des.tech <- model.matrix(~group)
      dupcor <- duplicateCorrelation(props\$TransformedProps, design=des.tech, block=pair)
      fit1 <- lmFit(props\$TransformedProps, design=des.tech, block=pair, correlation=dupcor\$consensus)
      fit1 <- eBayes(fit1)
      top_tech <- topTable(fit1, coef=2)
      write.csv(top_tech, "limma_random_effects_results.csv", row.names=TRUE)
    }
    
    # 8. Generate and save diagnostic plots
    pdf("speckle_diagnostic_plots.pdf", width=10, height=8)
    try({
      print(plotCellTypeProps(sce_all))
    })
    try({
      par(mfrow=c(1,2))
      plotCellTypeMeanVar(props\$Counts)
      plotCellTypePropsMeanVar(props\$Counts)
    })
    dev.off()

    writeLines(c(
        '"BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA":',
        paste0('    speckle: ', as.character(packageVersion('speckle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_linear_modeling_and_anova.csv versions.yml
    """
}

workflow BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_all ] ]

    main:
    BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA(ch_input)

    emit:
    tables   = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.tables
    plots    = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.plots
    objects  = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.objects
    versions = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.versions
}
