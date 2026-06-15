#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneGeneInteR — gene_gene_interaction_testing
// Test for statistical interaction between two genes represented by sets of SNPs in a case-control study.
// Input: gene1_snps.csv, gene2_snps.csv, phenotype.csv
// Container: quay.io/biocontainers/bioconductor-genegeneinter:1.32.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneGeneInteR, snpStats
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the genotype data and phenotype vector
//  * 2. [Core Analysis] Run the gene-gene interaction test using the GGI function
//  * 3. [Visualization & Output] Print and plot the interaction results

nextflow.enable.dsl = 2

process BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GeneGeneInteR", "snpStats")
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
    library(GeneGeneInteR)
    library(snpStats)
    
    # ==========================================
    # Stage 1: Load genotype data and phenotype
    # ==========================================
    
    # Read the user input files
    gene1_raw <- read.csv("gene1_snps.csv", stringsAsFactors = FALSE)
    gene2_raw <- read.csv("gene2_snps.csv", stringsAsFactors = FALSE)
    phenotype_raw <- read.csv("phenotype.csv", stringsAsFactors = FALSE)
    
    # Process phenotype to extract the response vector
    if ("phenotype" %in% colnames(phenotype_raw)) {
      response <- phenotype_raw\$phenotype
    } else if ("Y" %in% colnames(phenotype_raw)) {
      response <- phenotype_raw\$Y
    } else {
      response <- phenotype_raw[[ncol(phenotype_raw)]]
    }
    
    # Ensure response is numeric (typically 0/1 for case-control) or factor
    response <- as.numeric(response)
    
    # Process Gene 1 SNPs: handle potential sample ID column
    if (!is.numeric(gene1_raw[[1]])) {
      gene1 <- gene1_raw[, -1, drop = FALSE]
      rownames(gene1) <- gene1_raw[[1]]
    } else {
      gene1 <- gene1_raw
    }
    
    # Process Gene 2 SNPs: handle potential sample ID column
    if (!is.numeric(gene2_raw[[1]])) {
      gene2 <- gene2_raw[, -1, drop = FALSE]
      rownames(gene2) <- gene2_raw[[1]]
    } else {
      gene2 <- gene2_raw
    }
    
    # Ensure data frames contain numeric genotype values (0, 1, 2)
    gene1[] <- lapply(gene1, as.numeric)
    gene2[] <- lapply(gene2, as.numeric)
    
    # ==========================================
    # Stage 2: Run the gene-gene interaction test
    # ==========================================
    
    # Combine SNPs into a single matrix
    combined_snps <- cbind(gene1, gene2)
    
    # Convert to SnpMatrix object
    # Add 1 to 0/1/2 genotypes so they become 1/2/3 (0 is reserved for missing in SnpMatrix)
    mat <- as.matrix(combined_snps)
    mat <- mat + 1
    mat[is.na(mat)] <- 0
    snpX <- as(mat, "SnpMatrix")
    
    # Create genes.info data frame mapping each SNP to its corresponding gene
    genes.info <- data.frame(
      SNP = c(colnames(gene1), colnames(gene2)),
      Gene = c(rep("Gene1", ncol(gene1)), rep("Gene2", ncol(gene2))),
      stringsAsFactors = FALSE
    )
    
    # Run the GGI function exactly as documented
    result <- GGI(Y = response, snpX = snpX, genes.info = genes.info, method = "CCA")
    
    # ==========================================
    # Stage 3: Print, plot, and save results
    # ==========================================
    
    # Print the result to console
    print(result)
    
    # Save the result object to an RDS file
    saveRDS(result, file = "ggi_result.rds")
    
    # Save a text summary of the result
    sink("ggi_summary.txt")
    cat("=== GeneGeneInteR Analysis Summary ===\n")
    print(result)
    sink()
    
    # Attempt to plot the interaction results and save to PDF
    pdf("ggi_plot.pdf")
    tryCatch({
      plot(result)
    }, error = function(e) {
      message("Plotting not supported for this result type or failed: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING":',
        paste0('    GeneGeneInteR: ', as.character(packageVersion('GeneGeneInteR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_gene_interaction_testing.csv versions.yml
    """
}

workflow BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene1_snps.csv, gene2_snps.csv, phenotype.csv ] ]

    main:
    BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING(ch_input)

    emit:
    tables   = BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING.out.tables
    plots    = BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING.out.plots
    objects  = BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING.out.objects
    versions = BIOC_GENEGENEINTER_GENE_GENE_INTERACTION_TESTING.out.versions
}
