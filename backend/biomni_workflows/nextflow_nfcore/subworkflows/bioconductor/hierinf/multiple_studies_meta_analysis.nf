#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hierinf — multiple_studies_meta_analysis
// Jointly analyze multiple GWAS datasets by estimating a single hierarchical tree and aggregating p-values across studies.
// Input: genotype_matrices_list.rds, phenotype_vectors_list.rds, control_variables_list.rds
// Container: quay.io/biocontainers/bioconductor-hierinf:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: hierinf
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the second level of the tree structure (blocks/chromosomes)
//  * 2. [Core Analysis] Cluster the SNPs across datasets using cluster_var or cluster_position
//  * 3. [Core Analysis] Perform hierarchical testing and aggregate p-values using test_hierarchy with an aggregation method
//  * 4. [Core Analysis] Print results

nextflow.enable.dsl = 2

process BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS {
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
    
    # Load the required package
    library(hierinf)
    
    # Set random number generator for reproducibility (especially for parallel computing)
    RNGkind("L'Ecuyer-CMRG")
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    sim.geno.2dat  <- readRDS("genotype_matrices_list.rds")
    sim.pheno.2dat <- readRDS("phenotype_vectors_list.rds")
    sim.clvar.2dat <- readRDS("control_variables_list.rds")
    
    # Ensure the genotype matrices have column names
    all_cols <- unique(unlist(lapply(sim.geno.2dat, colnames)))
    if (is.null(all_cols)) {
      num_snps <- ncol(sim.geno.2dat[[1]])
      all_cols <- paste0("SNP.", seq_len(num_snps))
      for (i in seq_along(sim.geno.2dat)) {
        colnames(sim.geno.2dat[[i]]) <- all_cols
      }
    }
    
    # ==========================================
    # 2. Define the Second Level of the Tree Structure
    # ==========================================
    # Dynamically split the SNPs into two blocks (representing chromosomes)
    n_snps <- length(all_cols)
    half <- ceiling(n_snps / 2)
    block <- data.frame(
      "colname" = all_cols,
      "block" = c(rep("chrom 1", half), rep("chrom 2", n_snps - half))[1:n_snps],
      stringsAsFactors = FALSE
    )
    
    # ==========================================
    # 3. Cluster the SNPs Across Datasets
    # ==========================================
    dendr <- cluster_var(x = sim.geno.2dat,
                         block = block)
    
    # Save the estimated hierarchical tree
    saveRDS(dendr, "hierinf_dendrogram.rds")
    
    # ==========================================
    # 4. Perform Hierarchical Testing
    # ==========================================
    # Determine model family dynamically based on phenotype values
    all_pheno_vals <- unlist(sim.pheno.2dat)
    unique_vals <- unique(all_pheno_vals)
    if (length(unique_vals) <= 2) {
      family_val <- "binomial"
    } else {
      family_val <- "gaussian"
    }
    
    set.seed(1234)
    result <- test_hierarchy(x = sim.geno.2dat,
                             y = sim.pheno.2dat,
                             clvar = sim.clvar.2dat,
                             dendr = dendr,
                             family = family_val)
    
    # ==========================================
    # 5. Print and Save Results
    # ==========================================
    print(result, n.terms = 4)
    
    # Save the complete result object
    saveRDS(result, "hierinf_meta_analysis_results.rds")
    
    # Export the hierarchical testing results to a CSV table
    res_df <- result\$res.hierarchy
    # Collapse the list of significant clusters into a semicolon-separated string for CSV compatibility
    res_df\$significant.cluster <- sapply(res_df\$significant.cluster, function(x) {
      if (all(is.na(x))) {
        return(NA)
      } else {
        return(paste(x, collapse = "; "))
      }
    })
    write.csv(res_df, "hierinf_meta_analysis_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS":',
        paste0('    hierinf: ', as.character(packageVersion('hierinf')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_studies_meta_analysis.csv versions.yml
    """
}

workflow BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotype_matrices_list.rds, phenotype_vectors_list.rds, control_variables_list.rds ] ]

    main:
    BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS.out.tables
    plots    = BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS.out.plots
    objects  = BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS.out.objects
    versions = BIOC_HIERINF_MULTIPLE_STUDIES_META_ANALYSIS.out.versions
}
