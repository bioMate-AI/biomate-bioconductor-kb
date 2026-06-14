#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AIMS — absolute_breast_cancer_subtyping
// Assign absolute breast cancer intrinsic molecular subtypes to a gene expression dataset or a single sample using Entrez IDs.
// Input: expression_matrix.csv, gene_annotations.csv
// Container: quay.io/biocontainers/bioconductor-aims:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AIMS, Biobase
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the AIMS package and the expression dataset
//  * 2. [Core Analysis] Convert the expression matrix to an ExpressionSet if necessary
//  * 3. [Core Analysis] Run applyAIMS using the expression data and Entrez IDs
//  * 4. [Core Analysis] Retrieve the assigned subtypes and posterior probabilities

nextflow.enable.dsl = 2

process BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING {
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
    .bm_deps <- c("AIMS", "Biobase")
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
    library(AIMS)
    library(Biobase)
    
    # 1. Load the expression dataset and gene annotations from user input files
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    expr_mat <- as.matrix(expr_df)
    
    gene_ann <- read.csv("gene_annotations.csv", stringsAsFactors = FALSE)
    
    # Identify the Entrez ID column and Feature ID column in the annotations
    entrez_col <- grep("entrez", colnames(gene_ann), ignore.case = TRUE, value = TRUE)
    if (length(entrez_col) == 0) {
      entrez_col <- colnames(gene_ann)[2]
    } else {
      entrez_col <- entrez_col[1]
    }
    
    feature_col <- grep("feature|probe|symbol|id", colnames(gene_ann), ignore.case = TRUE, value = TRUE)
    if (length(feature_col) == 0) {
      feature_col <- colnames(gene_ann)[1]
    } else {
      feature_col <- feature_col[1]
    }
    
    # Map the row names of the expression matrix to Entrez IDs
    mapping <- gene_ann[[entrez_col]]
    names(mapping) <- gene_ann[[feature_col]]
    
    entrez_ids <- as.character(mapping[rownames(expr_mat)])
    entrez_ids[is.na(entrez_ids)] <- ""
    
    # Construct the mcgillExample list structure to match the documented code
    mcgillExample <- list(
      D = expr_mat,
      EntrezID = entrez_ids
    )
    
    # 2. Convert the expression matrix to an ExpressionSet
    mcgillExample\$D <- ExpressionSet(assayData=mcgillExample\$D)
    
    # 3. Run applyAIMS using the expression data and Entrez IDs
    mcgill.subtypes <- applyAIMS(mcgillExample\$D,
                                 mcgillExample\$EntrezID)
    
    # 4. Retrieve and display the assigned subtypes and posterior probabilities
    names(mcgill.subtypes)
    head(mcgill.subtypes\$cl)
    head(mcgill.subtypes\$prob)
    table(mcgill.subtypes\$cl)
    
    # Save the meaningful results to output files
    results_df <- data.frame(
      Sample = names(mcgill.subtypes\$cl),
      Subtype = as.character(mcgill.subtypes\$cl),
      Probability = as.numeric(mcgill.subtypes\$prob),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "aims_subtypes.csv", row.names = FALSE)
    
    saveRDS(mcgill.subtypes, "aims_results.rds")
    
    # Generate and save a frequency plot of the assigned subtypes
    pdf("subtype_frequencies.pdf", width = 7, height = 5)
    barplot(table(mcgill.subtypes\$cl),
            main = "AIMS Breast Cancer Subtype Frequencies",
            xlab = "Subtype",
            ylab = "Frequency",
            col = "skyblue",
            las = 1)
    dev.off()

    writeLines(c(
        '"BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING":',
        paste0('    AIMS: ', as.character(packageVersion('AIMS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_absolute_breast_cancer_subtyping.csv versions.yml
    """
}

workflow BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, gene_annotations.csv ] ]

    main:
    BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING(ch_input)

    emit:
    tables   = BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING.out.tables
    plots    = BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING.out.plots
    objects  = BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING.out.objects
    versions = BIOC_AIMS_ABSOLUTE_BREAST_CANCER_SUBTYPING.out.versions
}
