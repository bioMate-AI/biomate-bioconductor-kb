#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MICSQTL — multi_omic_csqtl_pipeline
// Perform joint deconvolution of bulk proteomes using matched transcriptomes, visualize joint variation, filter features, and map cell-type-specific quantitative 
// Input: your_protein_data, your_anno_protein, your_gene_data, prop_gene, ref_gene, SNP_data, anno_SNP, meta
// Container: quay.io/biocontainers/bioconductor-micsqtl:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MICSQTL, SummarizedExperiment, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize the SummarizedExperiment object with bulk protein data, protein annotations, and gene expression data
//  * 2. [Core Analysis] Perform AJIVE decomposition to extract joint variation and select features
//  * 3. [Core Analysis] Deconvolve cell-type proportions using Joint Non-negative Matrix Factorization (JNMF)
//  * 4. [Visualization & Output] Visualize joint variation using common normalized scores from AJIVE
//  * 5. [Core Analysis] Filter features (proteins/genes and SNPs) based on allele frequency, genotype group size, and genomic distance
//  * 6. [Core Analysis] Perform cell-type-specific QTL (csQTL) mapping using the TOAST method

nextflow.enable.dsl = 2

process BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE {
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
    .bm_deps <- c("MICSQTL", "ggplot2")
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
        library(MICSQTL)
        library(ggplot2)
        
        # Helper function to load input files robustly
        load_input <- function(name, as_matrix = FALSE) {
          exts <- c(".rds", ".csv", ".tsv", ".txt", "")
          file_found <- NULL
          for (ext in exts) {
            path <- paste0(name, ext)
            if (file.exists(path)) {
              file_found <- path
              break
            }
          }
          if (is.null(file_found)) {
            stop(paste("Error: Required file not found in working directory:", name))
          }
          
          message(paste("Loading file:", file_found))
          if (grepl("\\\\.rds\$", file_found)) {
            obj <- readRDS(file_found)
            if (as_matrix) {
              return(as.matrix(obj))
            } else {
              return(obj)
            }
          } else {
            df <- tryCatch({
              read.csv(file_found, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
            }, error = function(e) {
              read.csv(file_found, check.names = FALSE, stringsAsFactors = FALSE)
            })
            if (as_matrix) {
              return(as.matrix(df))
            } else {
              return(as.data.frame(df))
            }
          }
        }
        
        # 1. Read user input files
        your_protein_data <- load_input("your_protein_data", as_matrix = TRUE)
        your_anno_protein <- load_input("your_anno_protein", as_matrix = FALSE)
        your_gene_data    <- load_input("your_gene_data", as_matrix = FALSE)
        prop_gene         <- load_input("prop_gene", as_matrix = TRUE)
        ref_gene          <- load_input("ref_gene", as_matrix = TRUE)
        SNP_data          <- load_input("SNP_data", as_matrix = TRUE)
        anno_SNP          <- load_input("anno_SNP", as_matrix = FALSE)
        meta              <- load_input("meta", as_matrix = FALSE)
        
        # 2. Initialize the SummarizedExperiment object
        se <- SummarizedExperiment(
            assays = list(protein = your_protein_data),
            rowData = your_anno_protein
        )
        metadata(se) <- list(
            gene_data = your_gene_data
        )
        
        # Populate additional metadata required for downstream analysis
        metadata(se)\$prop_gene <- prop_gene
        metadata(se)\$ref_gene  <- ref_gene
        metadata(se)\$SNP_data  <- SNP_data
        metadata(se)\$anno_SNP  <- anno_SNP
        metadata(se)\$meta      <- meta
        
        # 3. Perform AJIVE decomposition to extract joint variation and select features
        message("Performing initial AJIVE decomposition...")
        se <- ajive_decomp(se, use_marker = FALSE, refactor_loading = TRUE)
        
        # 4. Deconvolve cell-type proportions using Joint Non-negative Matrix Factorization (JNMF)
        message("Deconvolving cell-type proportions using JNMF...")
        se <- deconv(se, source = "cross", method = "JNMF",
                     Step = c(10^(-9), 10^(-7)),
                     use_refactor = 1000,
                     pinit = se@metadata\$prop_gene,
                     ref_pnl = se@metadata\$ref_gene)
        
        # 5. Visualize joint variation using common normalized scores from AJIVE
        message("Performing AJIVE decomposition with plotting...")
        group_var_name <- colnames(metadata(se)\$meta)[1]
        se <- ajive_decomp(se, plot = TRUE,
                           group_var = group_var_name,
                           scatter = TRUE, scatter_x = "cns_1", scatter_y = "cns_2")
        
        # Save the AJIVE plot if generated
        if (!is.null(metadata(se)\$cns_plot)) {
          message("Saving AJIVE plot...")
          ggplot2::ggsave("ajive_cns_plot.pdf", plot = metadata(se)\$cns_plot, width = 8, height = 6)
        }
        
        # 6. Filter features (proteins/genes and SNPs)
        message("Filtering features...")
        target_protein <- rowData(se)[seq_len(min(3, nrow(rowData(se)))), "Symbol"]
        target_protein <- target_protein[!is.na(target_protein)] # Ensure no NA values
        
        se <- feature_filter(se,
            target_protein = target_protein,
            filter_method = c("allele", "distance"),
            filter_allele = 0.15,
            filter_geno = 0.05,
            ref_position = "TSS"
        )
        
        # 7. Perform cell-type-specific QTL (csQTL) mapping using the TOAST method
        message("Running csQTL mapping...")
        system.time(se <- csQTL(se))
        
        # Save the final SummarizedExperiment object
        message("Saving final SummarizedExperiment object...")
        saveRDS(se, "MICSQTL_output_se.rds")
        
        # Extract and save results
        if (!is.null(metadata(se)\$TOAST_output)) {
          message("Saving csQTL results...")
          saveRDS(metadata(se)\$TOAST_output, "csQTL_TOAST_output.rds")
          
          if (length(metadata(se)\$TOAST_output) >= 2) {
            res <- metadata(se)\$TOAST_output[[2]]
            sorted_res <- res[order(apply(res, 1, min)), ]
            write.csv(sorted_res, "csQTL_top_results_protein2.csv")
            message("Top results for the second target protein:")
            print(head(sorted_res))
          }
        }
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE":',
        paste0('    MICSQTL: ', as.character(packageVersion('MICSQTL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omic_csqtl_pipeline.csv versions.yml
    """
}

workflow BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ your_protein_data, your_anno_protein, your_gene_data, prop_gene, ref_gene, SNP_data, anno_SNP, meta ] ]

    main:
    BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE.out.tables
    plots    = BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE.out.plots
    objects  = BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE.out.objects
    versions = BIOC_MICSQTL_MULTI_OMIC_CSQTL_PIPELINE.out.versions
}
