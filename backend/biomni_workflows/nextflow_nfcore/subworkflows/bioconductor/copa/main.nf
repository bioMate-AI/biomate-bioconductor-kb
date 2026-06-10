#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: copa — cancer_outlier_profile_analysis
// Identify, visualize, and statistically validate mutually exclusive outlier gene pairs representing potential gene fusions from microarray expression data.
// Input: expression_set.RData
// Container: quay.io/biocontainers/bioconductor-copa:1.78.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: copa
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and data
//  * 2. [Core Analysis] Run COPA analysis to find outlier gene pairs
//  * 3. [Visualization & Output] Plot the top outlier gene pair
//  * 4. [Core Analysis] Tabulate the number of gene pairs with given outlier counts
//  * 5. [Visualization & Output] Summarize the specific gene pairs meeting the outlier threshold
//  * 6. [Core Analysis] Run permutation testing to assess the statistical significance of the observed outlier pairs

nextflow.enable.dsl = 2

process BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS {
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
        
    # 1. Load package and data
    library(copa)
    
    if (!file.exists("expression_set.RData")) {
      stop("Error: expression_set.RData not found in the working directory.")
    }
    
    # Load the ExpressionSet from the user-provided RData file
    env <- new.env()
    load("expression_set.RData", envir = env)
    obj_names <- ls(env)
    eset_idx <- sapply(obj_names, function(x) inherits(env[[x]], "ExpressionSet"))
    
    if (!any(eset_idx)) {
      stop("Error: No ExpressionSet object found in expression_set.RData")
    }
    
    # Assign the loaded ExpressionSet to 'colonCA' to match the documented code
    colonCA <- env[[obj_names[eset_idx][1]]]
    
    # Display the first 10 rows of phenotypic data
    head(pData(colonCA), 10)
    
    # Dynamically determine the class label column (look for a binary column)
    pd <- pData(colonCA)
    valid_cols <- which(sapply(pd, function(x) length(unique(na.omit(x))) == 2))
    if (length(valid_cols) > 0) {
      cl <- as.numeric(as.factor(pd[[valid_cols[1]]]))
    } else {
      cl <- as.numeric(as.factor(pd[[ncol(pd)]]))
    }
    
    # 2. Run COPA analysis to find outlier gene pairs
    rslt <- copa(colonCA, cl)
    
    # 3. Plot the top outlier gene pair
    pdf("copa_plot.pdf")
    plotCopa(rslt, idx = 1, col = c("lightgreen","salmon"))
    dev.off()
    
    # 4. Tabulate the number of gene pairs with given outlier counts
    tbl <- tableCopa(rslt)
    write.csv(as.data.frame(tbl), "copa_table.csv", row.names = TRUE)
    
    # Determine the maximum number of outliers and the corresponding number of pairs
    outlier_counts <- as.numeric(names(tbl))
    max_outliers <- max(outlier_counts)
    num_pairs <- as.numeric(tbl[as.character(max_outliers)])
    
    # 5. Summarize the specific gene pairs meeting the outlier threshold
    smry <- summaryCopa(rslt, max_outliers)
    write.csv(smry, "copa_summary.csv", row.names = FALSE)
    
    # 6. Run permutation testing to assess statistical significance
    prm <- copaPerm(colonCA, rslt, max_outliers, num_pairs)
    perm_sum <- sum(prm >= max_outliers)
    
    # Save permutation results
    saveRDS(prm, "copa_perm.rds")
    writeLines(paste("Number of permutations >=", max_outliers, ":", perm_sum), "copa_perm_sum.txt")

    writeLines(c(
        '"BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS":',
        paste0('    copa: ', as.character(packageVersion('copa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancer_outlier_profile_analysis.csv versions.yml
    """
}

workflow BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData ] ]

    main:
    BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS.out.tables
    plots    = BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS.out.plots
    objects  = BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS.out.objects
    versions = BIOC_COPA_CANCER_OUTLIER_PROFILE_ANALYSIS.out.versions
}
