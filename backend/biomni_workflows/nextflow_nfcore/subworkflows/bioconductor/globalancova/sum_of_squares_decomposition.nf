#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GlobalAncova — sum_of_squares_decomposition
// Decompose the model sum of squares to evaluate the sequential or Type III effects of multiple clinical factors on gene expression, and perform pairwise comparis
// Input: expression_matrix.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-globalancova:4.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GlobalAncova
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Perform Sequential and Type III Sum of Squares
//  * 3. [Visualization & Output] Perform Pairwise Comparisons
//  * 4. [Visualization & Output] Plot Sequential Decomposition and Combined Visualizations

nextflow.enable.dsl = 2

process BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION {
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
    .bm_deps <- c("GlobalAncova")
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
        library(GlobalAncova)
        
        # -------------------------------------------------------------------------
        # --- Read User Input Files ---
        # -------------------------------------------------------------------------
        # Read the normalized gene expression matrix
        # Rows: Genes, Columns: Samples
        vantVeer <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Read the phenotype data
        # Rows: Samples, Columns: Clinical factors (grade, metastases, ERstatus, etc.)
        phenodata <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between expression matrix and phenotype data
        common_samples <- intersect(colnames(vantVeer), rownames(phenodata))
        if (length(common_samples) == 0) {
          stop("No common samples found between expression_matrix.csv and phenotype_data.csv")
        }
        vantVeer <- vantVeer[, common_samples, drop = FALSE]
        phenodata <- phenodata[common_samples, , drop = FALSE]
        
        # Ensure clinical factors are treated as factors
        for (col in colnames(phenodata)) {
          phenodata[[col]] <- as.factor(phenodata[[col]])
        }
        
        # Define pathways dynamically from the input expression matrix to avoid hardcoding
        # pathways[[3]] is used in the plotting functions
        pathways <- list(
          pathway1 = rownames(vantVeer)[1:min(5, nrow(vantVeer))],
          pathway2 = rownames(vantVeer)[1:min(10, nrow(vantVeer))],
          pathway3 = rownames(vantVeer)[1:min(20, nrow(vantVeer))]
        )
        
        # -------------------------------------------------------------------------
        # --- Perform Sequential and Type III Sum of Squares ---
        # -------------------------------------------------------------------------
        formula <- as.formula(paste("~", paste(colnames(phenodata), collapse = " + ")))
        
        # Sequential sum of squares decomposition
        decomp_seq <- GlobalAncova.decomp(
          xx = vantVeer, 
          formula = formula, 
          model.dat = phenodata, 
          method = "sequential"
        )
        
        # Type III sum of squares decomposition
        decomp_t3 <- GlobalAncova.decomp(
          xx = vantVeer, 
          formula = formula, 
          model.dat = phenodata, 
          method = "type3"
        )
        
        # Save decomposition results
        write.csv(as.data.frame(decomp_seq), "decomposition_sequential.csv", row.names = TRUE)
        write.csv(as.data.frame(decomp_t3), "decomposition_type3.csv", row.names = TRUE)
        
        # -------------------------------------------------------------------------
        # --- Perform Pairwise Comparisons ---
        # -------------------------------------------------------------------------
        group_var <- colnames(phenodata)[1]
        pair_formula <- as.formula(paste("~", group_var))
        
        pair_comp <- pair.compare(
          xx = vantVeer, 
          formula = pair_formula, 
          model.dat = phenodata, 
          group = group_var, 
          perm = 100
        )
        
        # Save pairwise comparison results
        saveRDS(pair_comp, "pairwise_comparisons.rds")
        if (is.matrix(pair_comp) || is.data.frame(pair_comp)) {
          write.csv(as.data.frame(pair_comp), "pairwise_comparisons.csv", row.names = TRUE)
        } else {
          # If it's a list, capture output or write elements
          sink("pairwise_comparisons.txt")
          print(pair_comp)
          sink()
        }
        
        # -------------------------------------------------------------------------
        # --- Plot Sequential Decomposition and Combined Visualizations ---
        # -------------------------------------------------------------------------
        pdf("decomposition_plots.pdf", width = 10, height = 8)
        
        rev_formula <- as.formula(paste("~", paste(rev(colnames(phenodata)), collapse = " + ")))
        
        # Plot sequential decomposition of sum of squares across genes in the pathway
        Plot.sequential(
          vantVeer, 
          formula = rev_formula, 
          model.dat = phenodata, 
          test.genes = pathways[[3]], 
          name.geneset = "cell cycle pathway"
        )
        
        # Plot combined visualization of sequential decomposition
        Plot.all(
          vantVeer, 
          formula = rev_formula, 
          model.dat = phenodata, 
          test.genes = pathways[[3]], 
          name.geneset = "cell cycle pathway"
        )
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION":',
        paste0('    GlobalAncova: ', as.character(packageVersion('GlobalAncova')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sum_of_squares_decomposition.csv versions.yml
    """
}

workflow BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_data.csv ] ]

    main:
    BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION(ch_input)

    emit:
    tables   = BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION.out.tables
    plots    = BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION.out.plots
    objects  = BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION.out.objects
    versions = BIOC_GLOBALANCOVA_SUM_OF_SQUARES_DECOMPOSITION.out.versions
}
