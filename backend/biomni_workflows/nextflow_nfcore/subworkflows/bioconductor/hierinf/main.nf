#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hierinf — single_study_hierarchical_inference
// Perform hierarchical testing on a single GWAS dataset using either correlation-based or position-based clustering.
// Input: genotype_matrix.csv, phenotype_vector.csv, control_variables.csv
// Container: quay.io/biocontainers/bioconductor-hierinf:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: hierinf
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the second level of the tree structure (blocks/chromosomes)
//  * 2. [Core Analysis] Cluster the SNPs using cluster_var (correlation-based) or cluster_position (position-based)
//  * 3. [Core Analysis] Perform hierarchical testing using test_hierarchy
//  * 4. [Core Analysis] Print results and optionally compute R2 for significant clusters using compute_r2

nextflow.enable.dsl = 2

process BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("hierinf")
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
    
    # Load the package
    library(hierinf)
    
    # Random number generator (for parallel computing and reproducibility)
    RNGkind("L'Ecuyer-CMRG")
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read genotype matrix (must be complete with no missing values)
    geno_df <- read.csv("genotype_matrix.csv", check.names = FALSE)
    if (is.character(geno_df[[1]]) || (any(duplicated(geno_df[[1]])) == FALSE && !is.numeric(geno_df[[1]]))) {
      sim.geno <- as.matrix(geno_df[, -1])
      rownames(sim.geno) <- geno_df[[1]]
    } else {
      sim.geno <- as.matrix(geno_df)
    }
    
    # Read phenotype vector
    pheno_df <- read.csv("phenotype_vector.csv", header = FALSE)
    sim.pheno <- pheno_df[[1]]
    if (is.character(sim.pheno[1])) {
      # If the first row was treated as header, re-read with header = TRUE
      pheno_df <- read.csv("phenotype_vector.csv", header = TRUE)
      sim.pheno <- pheno_df[[1]]
    }
    
    # Read control variables matrix
    clvar_df <- read.csv("control_variables.csv", check.names = FALSE)
    if (ncol(clvar_df) == 0 || nrow(clvar_df) == 0) {
      sim.clvar <- NULL
    } else {
      if (is.character(clvar_df[[1]]) || (any(duplicated(clvar_df[[1]])) == FALSE && !is.numeric(clvar_df[[1]]))) {
        sim.clvar <- as.matrix(clvar_df[, -1])
        rownames(sim.clvar) <- clvar_df[[1]]
      } else {
        sim.clvar <- as.matrix(clvar_df)
      }
    }
    
    # Determine model family dynamically based on phenotype
    unique_y <- unique(sim.pheno)
    if (length(unique_y) == 2) {
      fam <- "binomial"
    } else {
      fam <- "gaussian"
    }
    
    # ==========================================
    # 2. DEFINE TREE STRUCTURE & CLUSTER SNPs
    # ==========================================
    
    # Define the second level of the tree structure dynamically based on input SNPs
    num_snps <- ncol(sim.geno)
    snp_names <- colnames(sim.geno)
    if (is.null(snp_names)) {
      snp_names <- paste0("SNP.", seq_len(num_snps))
      colnames(sim.geno) <- snp_names
    }
    
    half_snps <- ceiling(num_snps / 2)
    block <- data.frame("colname" = snp_names,
                        "block" = c(rep("chrom 1", half_snps), rep("chrom 2", num_snps - half_snps)),
                        stringsAsFactors = FALSE)
    
    # Cluster the SNPs (correlation-based)
    dendr <- cluster_var(x = sim.geno,
                         block = block)
    
    # Store the positions of the SNPs dynamically
    position <- data.frame("colnames" = snp_names,
                           "position" = seq_len(num_snps),
                           stringsAsFactors = FALSE)
    
    # Build the hierarchical tree based on the position
    dendr.pos <- cluster_position(position = position,
                                  block = block)
    
    # ==========================================
    # 3. PERFORM HIERARCHICAL TESTING
    # ==========================================
    
    # Test the hierarchy using multi sample split
    set.seed(1234)
    result <- test_hierarchy(x = sim.geno,
                             y = sim.pheno,
                             clvar = sim.clvar,
                             dendr = dendr,
                             family = fam)
    
    # Print results to console
    print(result, n.terms = 4)
    
    # ==========================================
    # 4. COMPUTE R2 FOR SIGNIFICANT CLUSTERS
    # ==========================================
    
    # Safely extract the significant cluster from the hierarchy results
    coln.cluster <- NULL
    if (!is.null(result\$res.hierarchy) && nrow(result\$res.hierarchy) >= 2) {
      coln.cluster <- result\$res.hierarchy[[2, "significant.cluster"]]
    } else if (!is.null(result\$res.hierarchy) && nrow(result\$res.hierarchy) >= 1) {
      coln.cluster <- result\$res.hierarchy[[1, "significant.cluster"]]
    }
    
    # Compute R2 and save outputs
    if (!is.null(coln.cluster) && !any(is.na(coln.cluster)) && length(coln.cluster) > 0) {
      r2_val <- compute_r2(x = sim.geno, y = sim.pheno, clvar = sim.clvar,
                           res.test.hierarchy = result, family = fam,
                           colnames.cluster = coln.cluster)
      writeLines(as.character(r2_val), "r2_value_significant_cluster.txt")
    } else {
      # Fallback: compute R2 for the whole dataset if no specific significant cluster is found
      r2_val <- compute_r2(x = sim.geno, y = sim.pheno, clvar = sim.clvar,
                           res.test.hierarchy = result, family = fam)
      writeLines(as.character(r2_val), "r2_value_whole_dataset.txt")
    }
    
    # ==========================================
    # 5. WRITE OUTPUT FILES
    # ==========================================
    
    # Save the hierarchical testing results table
    res_df <- result\$res.hierarchy
    if (!is.null(res_df)) {
      # Convert list column to comma-separated string for standard CSV compatibility
      res_df\$significant.cluster <- sapply(res_df\$significant.cluster, function(x) {
        if (all(is.na(x))) return(NA)
        paste(x, collapse = ", ")
      })
      write.csv(res_df, "hierarchical_testing_results.csv", row.names = FALSE)
    }
    
    # Save R objects for downstream analysis
    saveRDS(result, "hierinf_result.rds")
    saveRDS(dendr, "dendr_var.rds")
    saveRDS(dendr.pos, "dendr_pos.rds")
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE":',
        paste0('    hierinf: ', as.character(packageVersion('hierinf')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_study_hierarchical_inference.csv versions.yml
    """
}

workflow BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotype_matrix.csv, phenotype_vector.csv, control_variables.csv ] ]

    main:
    BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE(ch_input)

    emit:
    tables   = BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE.out.tables
    plots    = BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE.out.plots
    objects  = BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE.out.objects
    versions = BIOC_HIERINF_SINGLE_STUDY_HIERARCHICAL_INFERENCE.out.versions
}
