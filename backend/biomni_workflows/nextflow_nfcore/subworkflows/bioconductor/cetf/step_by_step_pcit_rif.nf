#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CeTF — step_by_step_pcit_rif
// Manually perform differential expression, normalization, PCIT network construction, and RIF analysis step-by-step for custom control over each stage.
// Input: counts_matrix.tsv, sample_metadata.csv, tf_list.txt
// Container: quay.io/biocontainers/bioconductor-cetf:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CeTF
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Filter and identify differentially expressed genes using expDiff. 2. Normalize expression data using normExp. 3. Split normalized 

nextflow.enable.dsl = 2

process BIOC_CETF_STEP_BY_STEP_PCIT_RIF {
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
    library(CeTF)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    if (!file.exists("counts_matrix.tsv")) {
        stop("Required input file 'counts_matrix.tsv' not found.")
    }
    if (!file.exists("sample_metadata.csv")) {
        stop("Required input file 'sample_metadata.csv' not found.")
    }
    if (!file.exists("tf_list.txt")) {
        stop("Required input file 'tf_list.txt' not found.")
    }
    
    # Read raw counts matrix
    counts <- read.delim("counts_matrix.tsv", row.names = 1, check.names = FALSE)
    counts <- as.matrix(counts)
    
    # Read sample metadata
    metadata <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
    
    # Identify sample and condition columns
    sample_col <- NULL
    if ("sample" %in% colnames(metadata)) {
        sample_col <- "sample"
    } else {
        sample_col <- colnames(metadata)[1]
    }
    
    cond_col <- NULL
    if ("condition" %in% colnames(metadata)) {
        cond_col <- "condition"
    } else if ("cond" %in% colnames(metadata)) {
        cond_col <- "cond"
    } else {
        cond_col <- colnames(metadata)[2]
    }
    
    # Align samples between counts and metadata
    samples <- as.character(metadata[[sample_col]])
    common_samples <- intersect(samples, colnames(counts))
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts_matrix.tsv and sample_metadata.csv.")
    }
    
    metadata <- metadata[metadata[[sample_col]] %in% common_samples, ]
    counts <- counts[, metadata[[sample_col]], drop = FALSE]
    
    # Map user conditions to 'untrt' and 'trt' to ensure compatibility with downstream hardcoded steps
    user_conds <- unique(metadata[[cond_col]])
    if (length(user_conds) < 2) {
        stop("Metadata must contain at least two distinct conditions.")
    }
    
    # Map first condition to 'untrt' and second to 'trt'
    mapped_conds <- ifelse(metadata[[cond_col]] == user_conds[1], "untrt", "trt")
    
    # Create annotation data frame and sort to group conditions
    anno <- data.frame(cond = mapped_conds, row.names = metadata[[sample_col]])
    anno <- anno[order(anno\$cond, decreasing = TRUE), , drop = FALSE]
    
    # Sort count data samples by conditions
    counts <- counts[, rownames(anno), drop = FALSE]
    
    # Append condition suffixes to column names
    n_untrt <- sum(anno\$cond == "untrt")
    n_trt <- sum(anno\$cond == "trt")
    colnames(counts) <- paste0(colnames(counts), c(rep("_untrt", n_untrt), rep("_trt", n_trt)))
    
    # Read transcription factors list
    TFs_input <- readLines("tf_list.txt")
    TFs_input <- trimws(TFs_input)
    TFs_input <- TFs_input[TFs_input != ""]
    
    # ==========================================
    # 2. Step-by-Step PCIT and RIF Workflow
    # ==========================================
    
    # Stage 1: Filter and identify differentially expressed genes using expDiff
    # Using a standard lfc threshold of 1.0 to ensure sufficient DE genes are selected
    DEGenes <- expDiff(exp = counts,
                       anno = anno,
                       conditions = c('untrt', 'trt'),
                       lfc = 1.0,
                       padj = 0.05, 
                       diffMethod = "Reverter")
    
    if (nrow(DEGenes\$DE_unique) == 0) {
        stop("No differentially expressed genes found. Try lowering the lfc or padj thresholds.")
    }
    
    # Selecting only DE genes from counts data
    counts_de <- counts[rownames(DEGenes\$DE_unique), , drop = FALSE]
    
    # Converting count data to TPM
    tpm <- apply(counts_de, 2, function(x) {
                (1e+06 * x)/sum(x)
            })
    
    # Stage 2: Normalize expression data using normExp
    PCIT_input <- normExp(tpm)
    
    # Stage 3: Split normalized data by condition
    PCIT_input_untrt <- PCIT_input[, grep("_untrt", colnames(PCIT_input)), drop = FALSE]
    PCIT_input_trt <- PCIT_input[, grep("_trt", colnames(PCIT_input)), drop = FALSE]
    
    # Stage 4: Run PCIT analysis on each condition using PCIT
    PCIT_out_untrt <- PCIT(PCIT_input_untrt, tolType = "mean")
    PCIT_out_trt <- PCIT(PCIT_input_trt, tolType = "mean")
    
    # Stage 5: Visualize PCIT network properties using histPlot and densityPlot
    pdf("pcit_plots.pdf", width = 12, height = 6)
    p1 <- histPlot(PCIT_out_trt\$adj_sig)
    p2 <- densityPlot(mat1 = PCIT_out_trt\$adj_raw, 
                      mat2 = PCIT_out_trt\$adj_sig, 
                      threshold = 0.5)
    print(p1)
    print(p2)
    dev.off()
    
    # Stage 6: Run RIF analysis to identify key regulators using RIF
    Clean_Dat <- normExp(tpm)
    
    # Verifying which TFs are in the subsetted normalized data
    TFs_present <- rownames(Clean_Dat)[rownames(Clean_Dat) %in% TFs_input]
    
    if (length(TFs_present) == 0) {
        stop("None of the transcription factors in tf_list.txt were found in the differentially expressed genes.")
    }
    
    # Selecting the Target genes
    Target <- setdiff(rownames(Clean_Dat), TFs_present)
    
    # Ordering rows of normalized count data
    RIF_input <- Clean_Dat[c(Target, TFs_present), ]
    
    # Performing RIF analysis
    RIF_out <- RIF(input = RIF_input,
                   nta = length(Target),
                   ntf = length(TFs_present),
                   nSamples1 = n_untrt,
                   nSamples2 = n_trt)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save PCIT results
    write.csv(PCIT_out_untrt\$tab, "pcit_out_untrt.csv", row.names = FALSE)
    write.csv(PCIT_out_trt\$tab, "pcit_out_trt.csv", row.names = FALSE)
    saveRDS(PCIT_out_untrt, "pcit_out_untrt.rds")
    saveRDS(PCIT_out_trt, "pcit_out_trt.rds")
    
    # Save RIF results
    write.csv(RIF_out, "rif_out.csv", row.names = TRUE)
    saveRDS(RIF_out, "rif_out.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CETF_STEP_BY_STEP_PCIT_RIF":',
        paste0('    CeTF: ', as.character(packageVersion('CeTF')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_pcit_rif.csv versions.yml
    """
}

workflow BIOC_CETF_STEP_BY_STEP_PCIT_RIF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.tsv, sample_metadata.csv, tf_list.txt ] ]

    main:
    BIOC_CETF_STEP_BY_STEP_PCIT_RIF(ch_input)

    emit:
    tables   = BIOC_CETF_STEP_BY_STEP_PCIT_RIF.out.tables
    plots    = BIOC_CETF_STEP_BY_STEP_PCIT_RIF.out.plots
    objects  = BIOC_CETF_STEP_BY_STEP_PCIT_RIF.out.objects
    versions = BIOC_CETF_STEP_BY_STEP_PCIT_RIF.out.versions
}
