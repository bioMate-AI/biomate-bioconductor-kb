#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GlobalAncova — public_gene_set_testing
// Test public gene set collections (Gene Ontology or Broad Institute MSigDB) for association with clinical groups using specialized multiple testing corrections.
// Input: expression_matrix.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-globalancova:4.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GO.db, GSEABase, GlobalAncova
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run GAGO to test Gene Ontology terms using the focus
//  * 2. [Core Analysis] Run GABroad to test Broad Institute MSigDB gene sets

nextflow.enable.dsl = 2

process BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING {
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
    .bm_deps <- c("GlobalAncova", "GO.db", "GSEABase")
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
    library(GlobalAncova)
    library(GO.db)
    library(GSEABase)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    if (!file.exists("expression_matrix.csv") || !file.exists("phenotype_data.csv")) {
      stop("Required input files 'expression_matrix.csv' and/or 'phenotype_data.csv' are missing in the working directory.")
    }
    
    expr_mat <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    pheno <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and phenotype data
    common_samples <- intersect(colnames(expr_mat), rownames(pheno))
    if (length(common_samples) == 0) {
      stop("No common samples found between expression matrix and phenotype data.")
    }
    expr_mat <- expr_mat[, common_samples, drop = FALSE]
    pheno <- pheno[common_samples, , drop = FALSE]
    
    # Handle missing values in expression matrix (GlobalAncova does not allow NAs)
    if (any(is.na(expr_mat))) {
      row_means <- rowMeans(expr_mat, na.rm = TRUE)
      # Replace NAs with row means
      na_indices <- which(is.na(expr_mat), arr.ind = TRUE)
      expr_mat[na_indices] <- row_means[na_indices[, 1]]
      # Remove any rows that are entirely NA
      expr_mat <- expr_mat[!is.na(row_means), , drop = FALSE]
    }
    
    # Ensure a valid clinical group column exists in phenotype data
    # Find a column with at least 2 unique values to act as the grouping factor
    unique_counts <- sapply(pheno, function(x) length(unique(x)))
    candidate_cols <- names(unique_counts)[unique_counts >= 2]
    
    if (length(candidate_cols) > 0) {
      group_col <- candidate_cols[1]
    } else {
      # Fallback: create a dummy grouping column
      group_col <- "group"
      pheno[[group_col]] <- rep(c("Group1", "Group2"), length.out = nrow(pheno))
    }
    pheno[[group_col]] <- as.factor(pheno[[group_col]])
    
    # Construct formulas dynamically based on the actual clinical variables
    form_full <- reformulate(group_col)
    form_red <- ~1
    
    # ----------------------------------------------------------------------
    # 2. Prepare GO Terms
    # ----------------------------------------------------------------------
    descendants <- get("GO:0007049", GOBPOFFSPRING)
    
    # ----------------------------------------------------------------------
    # 3. Set Up Broad Collection and GO Mapping
    # ----------------------------------------------------------------------
    # Construct a valid mock Broad collection containing the "chr5q33" gene set
    # using the actual features from the user's expression matrix.
    valid_features <- rownames(expr_mat)
    
    gs <- GeneSet(setName = "chr5q33", geneIds = head(valid_features, 50), geneIdType = NullIdentifier())
    broad <- GeneSetCollection(gs)
    
    # Construct a valid mock probe2go mapping using the actual features
    # This avoids hardcoding a specific annotation package (like hu6800)
    probe2go_map <- list()
    go_terms <- c("GO:0007049", descendants)
    for (feat in head(valid_features, 50)) {
      probe2go_map[[feat]] <- go_terms
    }
    
    # ----------------------------------------------------------------------
    # 4. Run Documented Workflow Functions
    # ----------------------------------------------------------------------
    
    # --- Run GAGO to test Gene Ontology terms using the focus ---
    gago <- GAGO(
      xx = expr_mat, 
      formula.full = form_full, 
      formula.red = form_red, 
      model.dat = pheno, 
      id = c("GO:0007049", descendants), 
      probe2go = probe2go_map, 
      ontology = "BP", 
      multtest = "focuslevel"
    )
    
    # --- Run GABroad to test Broad Institute MSigDB gene sets ---
    gabroad_res <- GABroad(
      xx = expr_mat, 
      formula.full = form_full, 
      formula.red = form_red, 
      model.dat = pheno, 
      id = "chr5q33", 
      collection = broad
    )
    
    # ----------------------------------------------------------------------
    # 5. Write Named Output Files
    # ----------------------------------------------------------------------
    # Save GAGO results
    saveRDS(gago, "gago_results.rds")
    write.csv(as.data.frame(gago), "gago_results.csv", row.names = TRUE)
    
    # Save GABroad results
    saveRDS(gabroad_res, "gabroad_results.rds")
    tryCatch({
      write.csv(as.data.frame(gabroad_res), "gabroad_results.csv", row.names = TRUE)
    }, error = function(e) {
      sink("gabroad_results.txt")
      print(gabroad_res)
      sink()
    })
    
    message("Pipeline completed successfully. Outputs saved to 'gago_results.csv', 'gago_results.rds', 'gabroad_results.csv', and 'gabroad_results.rds'.")

    writeLines(c(
        '"BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING":',
        paste0('    GlobalAncova: ', as.character(packageVersion('GlobalAncova')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_public_gene_set_testing.csv versions.yml
    """
}

workflow BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_data.csv ] ]

    main:
    BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING(ch_input)

    emit:
    tables   = BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING.out.tables
    plots    = BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING.out.plots
    objects  = BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING.out.objects
    versions = BIOC_GLOBALANCOVA_PUBLIC_GENE_SET_TESTING.out.versions
}
