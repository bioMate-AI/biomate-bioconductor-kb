#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dearseq — gene_wise_analysis
// Identify differentially expressed genes from RNA-seq data using the variance component score test.
// Input: expression_matrix.xlsx, metadata.csv
// Container: quay.io/biocontainers/bioconductor-dearseq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dearseq, edgeR, readxl
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare expression data and metadata in a SummarizedExperiment object
//  * 2. [Core Analysis] Filter out lowly expressed genes (if starting from raw counts)
//  * 3. [Core Analysis] Run gene-wise differential analysis using dear_seq()
//  * 4. [Visualization & Output] Summarize and plot results using summary() and plot()

nextflow.enable.dsl = 2

process BIOC_DEARSEQ_GENE_WISE_ANALYSIS {
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
    .bm_deps <- c("dearseq", "readxl", "edgeR", "SummarizedExperiment")
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
         library(SummarizedExperiment)
       library(dearseq)
        library(readxl)
        library(edgeR)
        
        # 1. Prepare expression data and metadata in a SummarizedExperiment object
        # Read metadata from the user-provided CSV file
        infos_df <- read.csv("metadata.csv", stringsAsFactors = TRUE)
        
        # Construct col_data and handle factor levels robustly
        # Assuming first column is Sample ID and second column is the condition of interest
        col_data <- data.frame("Condition" = infos_df[[2]])
        if ("Control" %in% col_data\$Condition) {
          col_data\$Condition <- stats::relevel(factor(col_data\$Condition), ref="Control")
        } else {
          col_data\$Condition <- factor(col_data\$Condition)
        }
        rownames(col_data) <- as.character(infos_df[[1]])
        
        # Read expression matrix from the user-provided Excel file
        London_raw <- readxl::read_excel("expression_matrix.xlsx")
        
        # Identify the gene identifier column and numeric expression columns
        if ("Genes" %in% colnames(London_raw)) {
          genes_raw <- London_raw\$Genes
        } else {
          genes_raw <- London_raw[[1]]
        }
        
        num_cols <- sapply(London_raw, is.numeric)
        London_raw_mat <- as.matrix(London_raw[, num_cols])
        rownames(London_raw_mat) <- genes_raw
        
        # Create SummarizedExperiment object
        se_raw <- SummarizedExperiment(assays = London_raw_mat, 
                                       colData = col_data)
        
        # 2. Filter out lowly expressed genes (if starting from raw counts)
        group <- se_raw\$Condition
        
        dgList <- DGEList(counts = London_raw_mat, group = group)
        cpm <- cpm(dgList)
        countCheck <- cpm > 2
        keep <- which(rowSums(countCheck) >= 5)
        London_raw_mat <- London_raw_mat[keep,]
        se_raw <- se_raw[keep, ]
        
        # 3. Run gene-wise differential analysis using dear_seq()
        se_subset <- se_raw
        
        res_dearseq <- dearseq::dear_seq(object = se_subset,
                                         variables2test = "Condition",
                                         which_test='permutation',
                                         preprocessed=FALSE, 
                                         parallel_comp = interactive())
        
        # 4. Summarize and plot results using summary() and plot()
        # Save summary text output
        sink("dearseq_summary.txt")
        summary(res_dearseq)
        sink()
        
        # Save diagnostic plots to PDF
        pdf("dearseq_plots.pdf")
        plot(res_dearseq)
        dev.off()
        
        # Save results to CSV and RDS files
        write.csv(as.data.frame(res_dearseq\$pvals), "dearseq_results.csv", row.names = TRUE)
        saveRDS(res_dearseq, "dearseq_results.rds")

    writeLines(c(
        '"BIOC_DEARSEQ_GENE_WISE_ANALYSIS":',
        paste0('    dearseq: ', as.character(packageVersion('dearseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_wise_analysis.csv versions.yml
    """
}

workflow BIOC_DEARSEQ_GENE_WISE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.xlsx, metadata.csv ] ]

    main:
    BIOC_DEARSEQ_GENE_WISE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.tables
    plots    = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.plots
    objects  = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.objects
    versions = BIOC_DEARSEQ_GENE_WISE_ANALYSIS.out.versions
}
