#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: viper — single_sample_viper
// Transform a gene expression matrix into a single-sample protein activity matrix and perform sample similarity clustering.
// Input: dset, regulon
// Container: quay.io/biocontainers/bioconductor-viper:1.44.0--r45hdfd78af_0
// R packages: Biobase, viper
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, viper
// Visualizations: heatmap, dendrogram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run VIPER directly on the expression dataset
//  * 2. [Core Analysis] Run VIPER with a permutation-based null model using reference samples
//  * 3. [Core Analysis] Compute sample similarity using the aREA-based viperSimilarity algorithm
//  * 4. [Core Analysis] Perform hierarchical clustering on the similarity matrix

nextflow.enable.dsl = 2

process BIOC_VIPER_SINGLE_SAMPLE_VIPER {
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
    .bm_deps <- c("Biobase", "viper")
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
        library(viper)
        library(Biobase)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        # The pipeline expects 'dset.rds' (ExpressionSet) and 'regulon.rds' (regulon object)
        # to be present in the working directory.
        
        if (file.exists("dset.rds")) {
          dset <- readRDS("dset.rds")
        } else if (file.exists("dset.RData")) {
          env <- new.env()
          load("dset.RData", envir = env)
          if ("dset" %in% names(env)) {
            dset <- env\$dset
          } else {
            stop("dset.RData loaded but 'dset' object not found.")
          }
        } else {
          stop("Error: Input gene expression dataset (dset.rds or dset.RData) not found in the working directory.")
        }
        
        if (file.exists("regulon.rds")) {
          regulon <- readRDS("regulon.rds")
        } else if (file.exists("regulon.RData")) {
          env <- new.env()
          load("regulon.RData", envir = env)
          if ("regulon" %in% names(env)) {
            regulon <- env\$regulon
          } else {
            stop("regulon.RData loaded but 'regulon' object not found.")
          }
        } else {
          stop("Error: Input regulon object (regulon.rds or regulon.RData) not found in the working directory.")
        }
        
        # Ensure dset is an ExpressionSet and contains the required phenoData
        if (!is(dset, "ExpressionSet")) {
          stop("Error: 'dset' must be an ExpressionSet object.")
        }
        
        # Dynamically extract phenotype column and labels
        pheno_cols <- colnames(pData(dset))
        if (length(pheno_cols) == 0) {
          stop("Error: 'dset' phenoData must contain at least one column.")
        }
        
        pheno_col <- pheno_cols[1]
        pheno_labels <- unique(as.character(pData(dset)[[pheno_col]]))
        
        if (length(pheno_labels) < 2) {
          stop("Error: The phenotype column must contain at least two distinct groups.")
        }
        
        ref_group <- pheno_labels[1]
        test_groups <- pheno_labels[-1]
        
        # ==========================================
        # 2. Run VIPER Directly on Expression Dataset
        # ==========================================
        vpres_direct <- viper(dset, regulon, verbose = FALSE)
        saveRDS(vpres_direct, "vpres_direct.rds")
        
        # Print dimensions of the direct VIPER results
        print("Dimensions of direct VIPER results:")
        print(dim(vpres_direct))
        
        # Perform row-wise t-test on direct VIPER results
        tmp <- rowTtest(vpres_direct, pheno_col, test_groups, ref_group)
        top_table <- data.frame(
          Gene = rownames(tmp\$p.value), 
          t = round(tmp\$statistic, 2),
          "p-value" = signif(tmp\$p.value, 3),
          check.names = FALSE
        )[order(tmp\$p.value)[1:10], ]
        
        # Save the top differential proteins table
        write.csv(top_table, "top_differential_proteins.csv", row.names = FALSE)
        print("Top 10 differential proteins saved to 'top_differential_proteins.csv'.")
        
        # ==========================================
        # 3. Run VIPER with Permutation-Based Null Model
        # ==========================================
        vpsig <- viperSignature(dset, pheno_col, ref_group, verbose = FALSE)
        vpres <- viper(vpsig, regulon, verbose = FALSE)
        saveRDS(vpres, "vpres_null.rds")
        
        # ==========================================
        # 4. Sample Similarity and Clustering
        # ==========================================
        pos <- pData(vpres)[[pheno_col]] %in% pheno_labels
        d1 <- exprs(vpres)[, pos]
        colnames(d1) <- pData(vpres)[[pheno_col]][pos]
        
        # Euclidean distance clustering
        dd <- dist(t(d1), method = "euclidean")
        
        pdf("euclidean_distance_heatmap.pdf")
        heatmap(as.matrix(dd), Rowv = as.dendrogram(hclust(dd, method = "average")), symm = TRUE)
        dev.off()
        print("Euclidean distance heatmap saved to 'euclidean_distance_heatmap.pdf'.")
        
        # aREA-based viperSimilarity clustering
        dd <- viperSimilarity(d1)
        
        pdf("viper_similarity_heatmap.pdf")
        heatmap(as.matrix(as.dist(dd)), Rowv = as.dendrogram(hclust(as.dist(dd), method = "average")), symm = TRUE)
        dev.off()
        print("VIPER similarity heatmap saved to 'viper_similarity_heatmap.pdf'.")
        
        print("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_VIPER_SINGLE_SAMPLE_VIPER":',
        paste0('    viper: ', as.character(packageVersion('viper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_viper.csv versions.yml
    """
}

workflow BIOC_VIPER_SINGLE_SAMPLE_VIPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dset, regulon ] ]

    main:
    BIOC_VIPER_SINGLE_SAMPLE_VIPER(ch_input)

    emit:
    tables   = BIOC_VIPER_SINGLE_SAMPLE_VIPER.out.tables
    plots    = BIOC_VIPER_SINGLE_SAMPLE_VIPER.out.plots
    objects  = BIOC_VIPER_SINGLE_SAMPLE_VIPER.out.objects
    versions = BIOC_VIPER_SINGLE_SAMPLE_VIPER.out.versions
}
