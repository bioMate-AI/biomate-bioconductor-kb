#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ABSSeq — complex_design_analysis
// Perform differential expression analysis for complex experimental designs using linear models in combination with limma.
// Input: counts.tsv, design_metadata.csv
// Container: quay.io/biocontainers/bioconductor-absseq:1.64.0--r45hdfd78af_0
// R packages: ABSSeq, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: ABSSeq, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the ABSDataSet object with counts
//  * 2. [Input & Preparation] Create a design matrix using model.matrix
//  * 3. [Core Analysis] Run the linear model analysis using ABSSeqlm for pairwise comparisons or ANOVA

nextflow.enable.dsl = 2

process BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS {
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
    .bm_deps <- c("ABSSeq", "limma")
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
    library(ABSSeq)
    library(limma)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read raw integer counts matrix
    counts_data <- read.table("counts.tsv", header=TRUE, sep="\t", row.names=1, check.names=FALSE)
    counts_matrix <- as.matrix(counts_data)
    storage.mode(counts_matrix) <- "integer"
    
    # Read design metadata
    metadata <- read.csv("design_metadata.csv", header=TRUE, row.names=1, check.names=FALSE)
    
    # Align counts columns and metadata rows if necessary
    common_samples <- intersect(colnames(counts_matrix), rownames(metadata))
    if (length(common_samples) > 0) {
      counts_matrix <- counts_matrix[, common_samples, drop=FALSE]
      metadata <- metadata[common_samples, , drop=FALSE]
    }
    
    # Identify the experimental factor column
    group_col <- NULL
    possible_cols <- c("groups", "group", "condition", "treatment", "class")
    for (col in possible_cols) {
      if (col %in% colnames(metadata)) {
        group_col <- col
        break
      }
    }
    if (is.null(group_col)) {
      group_col <- colnames(metadata)[1]
    }
    
    # Map the user's group levels to "0", "1", etc.
    # This ensures that model.matrix(~0+groups) produces columns named "groups0", "groups1", etc.,
    # matching the exact condition names used in the documented vignette code.
    raw_groups <- as.factor(metadata[[group_col]])
    levels(raw_groups) <- as.character(seq_len(length(levels(raw_groups))) - 1)
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    # Define groups factor
    groups <- factor(raw_groups)
    
    # Construct the ABSDataSet object with counts
    obj <- ABSDataSet(counts=counts_matrix)
    
    # Create a design matrix using model.matrix
    design <- model.matrix(~0+groups)
    
    # Run the linear model analysis using ABSSeqlm for pairwise comparisons (with limma)
    res_pairwise <- ABSSeqlm(obj, design, condA=c("groups0"), condB=c("groups1"))
    head(res_pairwise)
    
    # Run the linear model analysis using ABSSeqlm for ANOVA-like comparison
    res_anova <- ABSSeqlm(obj, design, condA=c("groups0", "groups1"))
    head(res_anova)
    
    # Run the linear model analysis using ABSSeqlm for pairwise comparisons (without limma)
    res_pairwise_nolm <- ABSSeqlm(obj, design, condA=c("groups0"), condB=c("groups1"), lmodel=FALSE)
    head(res_pairwise_nolm)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save results tables
    write.csv(res_pairwise, "res_pairwise_limma.csv", row.names=TRUE)
    write.csv(res_anova, "res_anova_limma.csv", row.names=TRUE)
    write.csv(res_pairwise_nolm, "res_pairwise_no_limma.csv", row.names=TRUE)
    
    # Save R objects for downstream analysis
    saveRDS(obj, "ABSDataSet_object.rds")
    saveRDS(design, "design_matrix.rds")

    writeLines(c(
        '"BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS":',
        paste0('    ABSSeq: ', as.character(packageVersion('ABSSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_design_analysis.csv versions.yml
    """
}

workflow BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv, design_metadata.csv ] ]

    main:
    BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.tables
    plots    = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.plots
    objects  = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.objects
    versions = BIOC_ABSSEQ_COMPLEX_DESIGN_ANALYSIS.out.versions
}
