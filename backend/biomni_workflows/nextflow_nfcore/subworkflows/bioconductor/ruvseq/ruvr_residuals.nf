#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVSeq — ruvr_residuals
// Estimate factors of unwanted variation using residuals from a first-pass GLM regression.
// Input: counts_matrix.csv, sample_groups.csv
// Container: quay.io/biocontainers/bioconductor-ruvseq:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EDASeq, RUVSeq, edgeR
// Visualizations: PCA plot
// QC: TMM normalization, diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform a first-pass GLM regression without RUV
//  * 2. [Core Analysis] Extract deviance residuals from the GLM fit
//  * 3. [Core Analysis] Estimate unwanted variation factors using RUVr with the residuals

nextflow.enable.dsl = 2

process BIOC_RUVSEQ_RUVR_RESIDUALS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(RUVSeq)
    library(EDASeq)
    library(edgeR)
    
    # ------------------------------------------------------------------------------
    # 1. Read User Input Files
    # ------------------------------------------------------------------------------
    # Read raw RNA-Seq read counts
    counts_data <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Read experimental design covariates
    sample_groups <- read.csv("sample_groups.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between counts and sample groups
    common_samples <- intersect(colnames(counts_data), rownames(sample_groups))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample names found between counts_matrix.csv and sample_groups.csv")
    }
    
    counts_data <- counts_data[, common_samples, drop = FALSE]
    sample_groups <- sample_groups[common_samples, , drop = FALSE]
    
    # Extract the covariate of interest 'x'
    if ("x" %in% colnames(sample_groups)) {
      x <- as.factor(sample_groups\$x)
    } else {
      # Fallback to the first column if 'x' is not explicitly named
      x <- as.factor(sample_groups[[1]])
    }
    
    # Construct the SeqExpressionSet object
    set <- newSeqExpressionSet(as.matrix(counts_data),
                               phenoData = data.frame(x, row.names = colnames(counts_data)))
    
    # Define genes to be used for estimating factors of unwanted variation (all genes)
    genes <- rownames(set)
    
    # ------------------------------------------------------------------------------
    # 2. Perform First-Pass GLM Regression & Extract Deviance Residuals
    # ------------------------------------------------------------------------------
    design <- model.matrix(~x, data=pData(set))
    y <- DGEList(counts=counts(set), group=x)
    y <- calcNormFactors(y, method="upperquartile")
    y <- estimateGLMCommonDisp(y, design)
    y <- estimateGLMTagwiseDisp(y, design)
    fit <- glmFit(y, design)
    res <- residuals(fit, type="deviance")
    
    # ------------------------------------------------------------------------------
    # 3. Estimate Unwanted Variation Factors using RUVr
    # ------------------------------------------------------------------------------
    set4 <- RUVr(set, genes, k=1, res)
    
    # ------------------------------------------------------------------------------
    # 4. Write Outputs
    # ------------------------------------------------------------------------------
    # Save the estimated factors of unwanted variation (W_1, etc.)
    write.csv(pData(set4), "unwanted_factors.csv", row.names = TRUE)
    
    # Save the normalized counts (for exploration/visualization purposes)
    write.csv(normCounts(set4), "normalized_counts.csv", row.names = TRUE)
    
    # Save the final SeqExpressionSet object as an RDS file
    saveRDS(set4, "ruvr_output.rds")
    
    # Generate diagnostic plots (RLE and PCA) before and after RUVr
    pdf("ruvr_diagnostics.pdf", width = 10, height = 10)
    par(mfrow = c(2, 2))
    
    # Before RUVr
    plotRLE(set, outline = FALSE, main = "RLE Before RUVr")
    plotPCA(set, main = "PCA Before RUVr")
    
    # After RUVr
    plotRLE(set4, outline = FALSE, main = "RLE After RUVr")
    plotPCA(set4, main = "PCA After RUVr")
    
    dev.off()

    writeLines(c(
        '"BIOC_RUVSEQ_RUVR_RESIDUALS":',
        paste0('    RUVSeq: ', as.character(packageVersion('RUVSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvr_residuals.csv versions.yml
    """
}

workflow BIOC_RUVSEQ_RUVR_RESIDUALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_groups.csv ] ]

    main:
    BIOC_RUVSEQ_RUVR_RESIDUALS(ch_input)

    emit:
    tables   = BIOC_RUVSEQ_RUVR_RESIDUALS.out.tables
    plots    = BIOC_RUVSEQ_RUVR_RESIDUALS.out.plots
    objects  = BIOC_RUVSEQ_RUVR_RESIDUALS.out.objects
    versions = BIOC_RUVSEQ_RUVR_RESIDUALS.out.versions
}
