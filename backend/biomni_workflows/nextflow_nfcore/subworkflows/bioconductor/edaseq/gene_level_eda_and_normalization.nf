#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edaseq — gene_level_eda_and_normalization
// Diagnose gene-level biases (GC-content, length, over-dispersion) and perform within-lane and between-lane normalization on count data.
// Input: gene_counts.tsv, gene_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0
// R packages: DESeq2, EDASeq, edgeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("DESeq2", "EDASeq", "edgeR")
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
    library(EDASeq)
    library(edgeR)
    library(DESeq2)
    
    # -----------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------
    # Read gene counts matrix (genes as rows, samples as columns)
    geneLevelData <- read.delim("gene_counts.tsv", row.names = 1, check.names = FALSE)
    
    # Read gene metadata (must contain 'gc' and 'length' columns, genes as rows)
    gene_metadata <- read.delim("gene_metadata.tsv", row.names = 1, check.names = FALSE)
    
    # Extract GC-content and length vectors
    yeastGC <- gene_metadata\$gc
    names(yeastGC) <- rownames(gene_metadata)
    
    yeastLength <- gene_metadata\$length
    names(yeastLength) <- rownames(gene_metadata)
    
    # -----------------------------------------------------------------
    # 2. Filter and Construct SeqExpressionSet
    # -----------------------------------------------------------------
    # Filter out non-expressed or low-count genes (mean count > 10)
    filter <- apply(geneLevelData, 1, function(x) mean(x) > 10)
    common <- intersect(names(yeastGC), rownames(geneLevelData[filter, ]))
    
    # Construct feature data frame
    feature <- data.frame(gc = yeastGC, length = yeastLength)
    
    # Define experimental conditions (defaulting to alternating mut/wt based on sample size)
    n_samples <- ncol(geneLevelData)
    conditions_vector <- factor(rep(c("mut", "wt"), length.out = n_samples))
    
    # Create the SeqExpressionSet object
    data <- newSeqExpressionSet(counts = as.matrix(geneLevelData[common, ]),
                                featureData = feature[common, ],
                                phenoData = data.frame(
                                  conditions = conditions_vector,
                                  row.names = colnames(geneLevelData)))
    
    # Print basic structure info to stdout
    cat("--- SeqExpressionSet Object Summary ---\n")
    print(head(counts(data)))
    print(pData(data))
    print(head(fData(data)))
    print(head(offst(data)))
    
    # -----------------------------------------------------------------
    # 3. Visualizations (EDA)
    # -----------------------------------------------------------------
    pdf("eda_diagnostic_plots.pdf", width = 10, height = 8)
    
    # Define colors for plotting
    colors <- rep(c(rgb(1, 0, 0, alpha = 0.7), rgb(0, 0, 1, alpha = 0.7)), length.out = n_samples)
    
    # Boxplot of gene counts
    boxplot(data, col = colors)
    
    # Mean-Difference (MD) Plot (comparing sample 1 and sample 3, or last sample if < 3)
    lane_compare <- ifelse(ncol(data) >= 3, 3, ncol(data))
    MDPlot(data, c(1, lane_compare))
    
    # Over-dispersion diagnostics (Mean-Variance Plots)
    if (ncol(data) >= 2) {
      meanVarPlot(data[, 1:2], log = TRUE, ylim = c(0, 16))
    }
    meanVarPlot(data, log = TRUE, ylim = c(0, 16))
    
    # GC-content bias plot
    biasPlot(data, "gc", log = TRUE, ylim = c(1, 5))
    
    # Stratified boxplot of log-fold-change by GC-content
    lfc <- log(counts(data)[, lane_compare] + 0.1) - log(counts(data)[, 1] + 0.1)
    biasBoxplot(lfc, fData(data)\$gc)
    
    dev.off()
    
    # -----------------------------------------------------------------
    # 4. Normalization (Within-Lane and Between-Lane)
    # -----------------------------------------------------------------
    # Perform within-lane normalization (GC-content correction) followed by between-lane normalization
    dataWithin <- withinLaneNormalization(data, "gc", which = "full")
    dataNorm <- betweenLaneNormalization(dataWithin, which = "full")
    
    # Save normalized diagnostic plots
    pdf("normalized_diagnostic_plots.pdf", width = 10, height = 8)
    biasPlot(dataNorm, "gc", log = TRUE, ylim = c(1, 5))
    boxplot(dataNorm, col = colors)
    dev.off()
    
    # Save normalized counts object
    saveRDS(dataNorm, "dataNorm.rds")
    write.csv(counts(dataNorm), "normalized_counts.csv")
    
    # -----------------------------------------------------------------
    # 5. Calculate and Export Normalization Offsets
    # -----------------------------------------------------------------
    dataOffset <- withinLaneNormalization(data, "gc", which = "full", offset = TRUE)
    dataOffset <- betweenLaneNormalization(dataOffset, which = "full", offset = TRUE)
    
    # Save offset object
    saveRDS(dataOffset, "dataOffset.rds")
    
    # -----------------------------------------------------------------
    # 6. Downstream Differential Expression Analysis
    # -----------------------------------------------------------------
    
    # --- edgeR Workflow ---
    design <- model.matrix(~conditions, data = pData(dataOffset))
    y <- DGEList(counts = counts(dataOffset), group = pData(dataOffset)\$conditions)
    y\$offset <- -offst(dataOffset) # Note the negative sign convention for edgeR offsets
    y <- estimateDisp(y, design)
    fit <- glmFit(y, design)
    lrt <- glmLRT(fit, coef = 2)
    
    edgeR_results <- topTags(lrt, n = Inf)
    write.csv(as.data.frame(edgeR_results), "edgeR_differential_expression.csv")
    
    # --- DESeq2 Workflow ---
    dds <- DESeqDataSetFromMatrix(countData = counts(dataOffset), 
                                  colData = pData(dataOffset), 
                                  design = ~ conditions)
    normFactors <- exp(-1 * offst(dataOffset))
    normFactors <- normFactors / exp(rowMeans(log(normFactors)))
    normalizationFactors(dds) <- normFactors
    dds <- DESeq(dds)
    res <- results(dds)
    
    write.csv(as.data.frame(res), "deseq2_differential_expression.csv")
    
    # -----------------------------------------------------------------
    # 7. Unrounded Normalization and Offset Verification
    # -----------------------------------------------------------------
    dataNorm_unrounded <- betweenLaneNormalization(data, round = FALSE, offset = TRUE)
    norm1 <- normCounts(dataNorm_unrounded)
    norm2 <- exp(log(counts(dataNorm_unrounded) + 0.1) + offst(dataNorm_unrounded)) - 0.1
    
    write.csv(head(norm1 - norm2), "unrounded_offset_verification.csv")
    
    rounded_diff <- head(round(normCounts(dataNorm_unrounded)) - round(counts(dataNorm_unrounded) * exp(offst(dataNorm_unrounded))))
    write.csv(rounded_diff, "rounded_offset_verification.csv")
    
    # -----------------------------------------------------------------
    # 8. Optional: Retrieve Gene Length and GC-Content (Robust tryCatch)
    # -----------------------------------------------------------------
    tryCatch({
      cat("Attempting to retrieve gene metadata via getGeneLengthAndGCContent...\n")
      # Example call using human genes as documented
      getGeneLengthAndGCContent(id = c("ENSG00000012048", "ENSG00000139618"), org = "hsa")
    }, error = function(e) {
      message("getGeneLengthAndGCContent call skipped or failed (likely offline or missing DB): ", e\$message)
    })
    
    cat("Pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION":',
        paste0('        edaseq: ', as.character(packageVersion("edaseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_eda_and_normalization.csv versions.yml
    """
}

workflow BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts.tsv, gene_metadata.tsv ] ]

    main:
    BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.tables
    plots    = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.plots
    objects  = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.objects
    versions = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.versions
}
