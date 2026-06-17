#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HTSFilter — edger_pipeline
// Filter edgeR differential expression results (DGEExact or DGELRT objects) using HTSFilter.
// Input: counts_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-htsfilter:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HTSFilter, edgeR
// Visualizations: plot (ggplot/base)
// QC: TMM normalization, dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a DGEList and calculate normalization factors
//  * 2. [Core Analysis] Estimate dispersions and perform exact test (for DGEExact) or fit a GLM and perform a likelihood ratio test (for DGELRT)
//  * 3. [Core Analysis] Apply HTSFilter to the exact test or LRT results
//  * 4. [Core Analysis] Extract top tags from the filtered object

nextflow.enable.dsl = 2

process BIOC_HTSFILTER_EDGER_PIPELINE {
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
    .bm_deps <- c("HTSFilter", "edgeR")
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
    library(HTSFilter)
    library(edgeR)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read raw count matrix
    counts_data <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    counts_matrix <- as.matrix(counts_data)
    
    # Read sample metadata
    metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align columns of counts with rows of metadata
    common_samples <- intersect(colnames(counts_matrix), rownames(metadata))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample IDs found between counts_matrix.csv and sample_metadata.csv")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # Identify condition column from metadata
    col_idx <- grep("condition|group|cell.line|treatment|class", colnames(metadata), ignore.case = TRUE)
    if (length(col_idx) > 0) {
      conds <- as.character(metadata[[col_idx[1]]])
    } else {
      conds <- as.character(metadata[[1]])
    }
    
    # ==========================================
    # Optional: Generate Jaccard Index Plot
    # ==========================================
    pdf("htsfilter_jaccard_plot.pdf")
    filter_plot <- HTSFilter(counts_matrix, conds, s.len=25, plot=TRUE)
    dev.off()
    
    # ==========================================
    # 2. S3 Class DGEExact Pipeline
    # ==========================================
    
    dge <- DGEList(counts=counts_matrix, group=conds)
    dge <- calcNormFactors(dge)
    dge <- estimateDisp(dge)
    et <- exactTest(dge)
    et <- HTSFilter(et, DGEList=dge, s.len=25, plot=FALSE)\$filteredData
    
    # Display and save DGEExact results
    dim(et)
    class(et)
    top_et <- topTags(et, n = Inf)
    print(head(top_et))
    
    # Save outputs
    saveRDS(et, "edgeR_exactTest_filtered_object.rds")
    write.csv(as.data.frame(top_et), "edgeR_exactTest_filtered_topTags.csv")
    
    # ==========================================
    # 3. S3 Class DGELRT Pipeline
    # ==========================================
    
    design <- model.matrix(~conds)
    dge <- DGEList(counts=counts_matrix, group=conds)
    dge <- calcNormFactors(dge)
    dge <- estimateDisp(dge, design)
    fit <- glmFit(dge,design)
    lrt <- glmLRT(fit,coef=2)
    lrt <- HTSFilter(lrt, DGEGLM=fit, s.len=25, plot=FALSE)\$filteredData
    
    # Display and save DGELRT results
    dim(lrt)
    class(lrt)
    top_lrt <- topTags(lrt, n = Inf)
    print(head(top_lrt))
    
    # Save outputs
    saveRDS(lrt, "edgeR_lrt_filtered_object.rds")
    write.csv(as.data.frame(top_lrt), "edgeR_lrt_filtered_topTags.csv")

    writeLines(c(
        '"BIOC_HTSFILTER_EDGER_PIPELINE":',
        paste0('    HTSFilter: ', as.character(packageVersion('HTSFilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edger_pipeline.csv versions.yml
    """
}

workflow BIOC_HTSFILTER_EDGER_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HTSFILTER_EDGER_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HTSFILTER_EDGER_PIPELINE.out.tables
    plots    = BIOC_HTSFILTER_EDGER_PIPELINE.out.plots
    objects  = BIOC_HTSFILTER_EDGER_PIPELINE.out.objects
    versions = BIOC_HTSFILTER_EDGER_PIPELINE.out.versions
}
