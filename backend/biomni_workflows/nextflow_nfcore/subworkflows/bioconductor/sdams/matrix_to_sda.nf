#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sdams — matrix_to_sda
// Create a SummarizedExperiment object from in-memory feature and covariate matrices and perform semi-parametric differential expression analysis.
// Input: featureInfo, groupInfo
// Container: quay.io/biocontainers/bioconductor-sdams:1.30.0--r45hdfd78af_0
// R packages: SDAMS, SummarizedExperiment
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SDAMS_MATRIX_TO_SDA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sdams:1.30.0--r45hdfd78af_0"

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
    .bm_deps <- c("SDAMS", "SummarizedExperiment")
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
    library(SDAMS)
    library(SummarizedExperiment)
    
    # Helper function to find input files with or without extensions
    find_file <- function(base_name) {
      extensions <- c("", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        path <- paste0(base_name, ext)
        if (file.exists(path)) {
          return(path)
        }
      }
      stop(paste("Required input file not found:", base_name))
    }
    
    # Locate the input files
    feature_path <- find_file("featureInfo")
    group_path <- find_file("groupInfo")
    
    # Read featureInfo (matrix of non-negative expression values)
    featureInfo_df <- tryCatch({
      read.csv(feature_path, row.names = 1, check.names = FALSE)
    }, error = function(e) {
      read.delim(feature_path, row.names = 1, check.names = FALSE)
    })
    featureInfo <- as.matrix(featureInfo_df)
    
    # Read groupInfo (data frame of grouping/covariate information)
    groupInfo <- tryCatch({
      read.csv(group_path, row.names = 1, check.names = FALSE)
    }, error = function(e) {
      read.delim(group_path, row.names = 1, check.names = FALSE)
    })
    
    # Ensure rownames of groupInfo match colnames of featureInfo
    if (!all(rownames(groupInfo) == colnames(featureInfo))) {
      common_samples <- intersect(rownames(groupInfo), colnames(featureInfo))
      if (length(common_samples) == 0) {
        stop("Rownames of groupInfo do not match colnames of featureInfo.")
      }
      featureInfo <- featureInfo[, common_samples, drop = FALSE]
      groupInfo <- groupInfo[common_samples, , drop = FALSE]
    }
    
    # 1. Create a SummarizedExperiment object from the feature matrix and covariate data frame
    exampleSE2 <- createSEFromMatrix(feature = featureInfo, colData = groupInfo)
    
    # 2. Perform differential expression analysis using SDA
    results_SC <- SDA(exampleSE2)
    
    # 3. Extract results for gamma, beta, and the two-part test (as documented)
    print("Head of pv_gamma:")
    print(head(results_SC\$pv_gamma[,1]))
    
    print("Head of qv_gamma:")
    print(head(results_SC\$qv_gamma[,1]))
    
    print("Head of pv_beta:")
    print(head(results_SC\$pv_beta[,1]))
    
    print("Head of qv_beta:")
    print(head(results_SC\$qv_beta[,1]))
    
    print("Head of pv_2part:")
    print(head(results_SC\$pv_2part[,1]))
    
    print("Head of qv_2part:")
    print(head(results_SC\$qv_2part[,1]))
    
    print("Head of feat.names:")
    print(head(results_SC\$feat.names))
    
    # Helper to extract first column safely
    get_col1 <- function(x) {
      if (is.null(x)) return(NULL)
      if (is.matrix(x) || is.data.frame(x)) {
        return(x[, 1])
      }
      return(x)
    }
    
    # Construct a comprehensive results data frame
    feat_names <- results_SC\$feat.names
    if (is.null(feat_names)) {
      feat_names <- rownames(featureInfo)
    }
    
    results_df <- data.frame(
      Feature = feat_names,
      gamma = if (!is.null(results_SC\$gamma)) get_col1(results_SC\$gamma) else NA,
      pv_gamma = if (!is.null(results_SC\$pv_gamma)) get_col1(results_SC\$pv_gamma) else NA,
      qv_gamma = if (!is.null(results_SC\$qv_gamma)) get_col1(results_SC\$qv_gamma) else NA,
      beta = if (!is.null(results_SC\$beta)) get_col1(results_SC\$beta) else NA,
      pv_beta = if (!is.null(results_SC\$pv_beta)) get_col1(results_SC\$pv_beta) else NA,
      qv_beta = if (!is.null(results_SC\$qv_beta)) get_col1(results_SC\$qv_beta) else NA,
      pv_2part = if (!is.null(results_SC\$pv_2part)) get_col1(results_SC\$pv_2part) else NA,
      qv_2part = if (!is.null(results_SC\$qv_2part)) get_col1(results_SC\$qv_2part) else NA,
      stringsAsFactors = FALSE
    )
    
    # Write outputs
    write.csv(results_df, "sda_results.csv", row.names = FALSE)
    saveRDS(results_SC, "sda_results.rds")
    
    # Generate plots
    pdf("sda_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2))
    
    if (!is.null(results_SC\$pv_gamma)) {
      hist(get_col1(results_SC\$pv_gamma), main = "P-values (Gamma)", xlab = "p-value", col = "skyblue", breaks = 20)
    }
    if (!is.null(results_SC\$pv_beta)) {
      hist(get_col1(results_SC\$pv_beta), main = "P-values (Beta)", xlab = "p-value", col = "lightgreen", breaks = 20)
    }
    if (!is.null(results_SC\$pv_2part)) {
      hist(get_col1(results_SC\$pv_2part), main = "P-values (2-part)", xlab = "p-value", col = "salmon", breaks = 20)
    }
    if (!is.null(results_SC\$beta) && !is.null(results_SC\$pv_2part)) {
      plot(get_col1(results_SC\$beta), -log10(get_col1(results_SC\$pv_2part)),
           main = "Volcano Plot (2-part)",
           xlab = "Beta (log fold change)",
           ylab = "-log10(p-value)",
           pch = 20, col = "darkgray")
      sig <- which(get_col1(results_SC\$qv_2part) < 0.05)
      if (length(sig) > 0) {
        points(get_col1(results_SC\$beta)[sig], -log10(get_col1(results_SC\$pv_2part))[sig], col = "red", pch = 20)
      }
    }
    dev.off()

    writeLines(c(
        '"BIOC_SDAMS_MATRIX_TO_SDA":',
        paste0('        sdams: ', as.character(packageVersion("sdams")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_to_sda.csv versions.yml
    """
}

workflow BIOC_SDAMS_MATRIX_TO_SDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ featureInfo, groupInfo ] ]

    main:
    BIOC_SDAMS_MATRIX_TO_SDA(ch_input)

    emit:
    tables   = BIOC_SDAMS_MATRIX_TO_SDA.out.tables
    plots    = BIOC_SDAMS_MATRIX_TO_SDA.out.plots
    objects  = BIOC_SDAMS_MATRIX_TO_SDA.out.objects
    versions = BIOC_SDAMS_MATRIX_TO_SDA.out.versions
}
