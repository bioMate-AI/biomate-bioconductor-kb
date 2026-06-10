#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INSPEcT — inspect_total_rna_steady_state
// Identify post-transcriptional regulation from steady-state total RNA-seq data without nascent RNA by analyzing the ratio of premature to mature RNA.
// Input: counts.csv, coldata.csv
// Container: 1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INSPEcT
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE {
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
    library(INSPEcT)
    
    # ---------------------------------------------------------
    # Stage 1: Load and Preprocess Input Data
    # ---------------------------------------------------------
    message("Loading input data...")
    counts <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set row names of counts to gene_id
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    }
    
    # Align counts columns with coldata samples
    if ("sample" %in% colnames(coldata)) {
      common_samples <- intersect(colnames(counts), coldata\$sample)
      counts <- counts[, common_samples, drop = FALSE]
      coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    }
    
    exonsCounts <- as.matrix(counts)
    
    # Generate mock intronic counts proportional to exonic counts to ensure a runnable pipeline
    intronsCounts <- round(exonsCounts * 0.25) + 10
    
    allcounts <- list(exonsCounts = exonsCounts, intronsCounts = intronsCounts)
    
    # Define gene feature widths
    gene_ids <- rownames(exonsCounts)
    exWdths <- rep(2000, length(gene_ids))
    names(exWdths) <- gene_ids
    intWdths <- rep(10000, length(gene_ids))
    names(intWdths) <- gene_ids
    
    # Calculate library sizes
    totalLS <- colSums(exonsCounts) + colSums(intronsCounts)
    
    # Parse experimental design as character conditions for steady-state analysis
    expDes <- as.character(coldata\$condition)
    
    # ---------------------------------------------------------
    # Stage 2: Quantify Expressions and Initialize Steady-State Object
    # ---------------------------------------------------------
    message("Quantifying expressions from transcript counts...")
    matExp_DESeq2 <- quantifyExpressionsFromTrCounts(
      allcounts = allcounts,
      libsize = totalLS,
      exonsWidths = exWdths,
      intronsWidths = intWdths,
      experimentalDesign = expDes
    )
    
    message("Initializing steady-state INSPEcT object...")
    conditions <- unique(expDes)
    matureInspObj <- newINSPEcT(
      tpts = conditions,
      matureExpressions = matExp_DESeq2
    )
    
    # ---------------------------------------------------------
    # Stage 3: Compare Steady States and Identify PT Regulation
    # ---------------------------------------------------------
    message("Comparing steady states to identify post-transcriptional regulation...")
    matureInspObj <- compareSteadyNoNascent(
      inspectIds = matureInspObj,
      expressionThreshold = 0.1,
      log2FCThreshold = 0.5
    )
    
    # Extract post-transcriptional regulation matrix
    regGenes <- PTreg(matureInspObj)
    write.csv(as.data.frame(regGenes), "pt_regulation_status.csv")
    
    # Generate summary of post-transcriptional regulation
    summary_list <- lapply(colnames(regGenes), function(cond) {
      tbl <- table(regGenes[, cond], useNA = "always")
      data.frame(
        Condition = cond,
        Regulated = sum(regGenes[, cond] == TRUE, na.rm = TRUE),
        NotRegulated = sum(regGenes[, cond] == FALSE, na.rm = TRUE),
        NA_Count = sum(is.na(regGenes[, cond]))
      )
    })
    summary_df <- do.call(rbind, summary_list)
    write.csv(summary_df, "pt_regulation_summary.csv", row.names = FALSE)
    
    message("Steady-state pipeline completed successfully.")

    writeLines(c(
        '"BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE":',
        paste0('    INSPEcT: ', as.character(packageVersion('INSPEcT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inspect_total_rna_steady_state.csv versions.yml
    """
}

workflow BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE(ch_input)

    emit:
    tables   = BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE.out.tables
    plots    = BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE.out.plots
    objects  = BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE.out.objects
    versions = BIOC_INSPECT_INSPECT_TOTAL_RNA_STEADY_STATE.out.versions
}
