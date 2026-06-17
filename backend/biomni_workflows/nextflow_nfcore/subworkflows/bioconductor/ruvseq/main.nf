#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVSeq — ruvg_control_genes
// Estimate factors of unwanted variation using negative control genes (e.g., spike-ins or empirical controls) and perform differential expression.
// Input: counts_matrix.csv, control_genes.txt
// Container: quay.io/biocontainers/bioconductor-ruvseq:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, RColorBrewer, RUVSeq, edgeR
// Visualizations: PCA plot
// QC: TMM normalization, diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-expressed genes
//  * 2. [Input & Preparation] Create a SeqExpressionSet object
//  * 3. [Core Analysis] Perform optional upper-quartile normalization
//  * 4. [Core Analysis] Estimate unwanted variation factors using RUVg with control genes
//  * 5. [Input & Preparation] Build a design matrix including the estimated factors (W_1)
//  * 6. [Core Analysis] Perform differential expression analysis using edgeR or DESeq2

nextflow.enable.dsl = 2

process BIOC_RUVSEQ_RUVG_CONTROL_GENES {
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
    .bm_deps <- c("RUVSeq", "edgeR", "DESeq2", "RColorBrewer")
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
    library(RUVSeq)
    library(edgeR)
    library(DESeq2)
    library(RColorBrewer)
    
    # 1. Read User Inputs
    if (!file.exists("counts_matrix.csv")) {
      stop("Error: counts_matrix.csv not found in the working directory.")
    }
    if (!file.exists("control_genes.txt")) {
      stop("Error: control_genes.txt not found in the working directory.")
    }
    
    # Load raw RNA-Seq read counts
    zfGenes <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Load negative control gene identifiers
    control_input <- readLines("control_genes.txt")
    
    # 2. Filter low-expressed genes
    filter <- apply(zfGenes, 1, function(x) length(x[x>5])>=2)
    filtered <- zfGenes[filter,]
    
    # Define spikes (control genes) and other genes based on user input
    spikes <- intersect(rownames(filtered), control_input)
    if (length(spikes) == 0) {
      stop("Error: No control genes from control_genes.txt found in the filtered counts matrix.")
    }
    genes <- setdiff(rownames(filtered), spikes)
    
    # Infer group factor x (Ctl vs Trt) from column names or split into two groups
    col_names <- colnames(filtered)
    if (any(grepl("Trt|trt|Treat|treat", col_names)) && any(grepl("Ctl|ctl|Control|control", col_names))) {
      x_char <- rep("Ctl", length(col_names))
      x_char[grepl("Trt|trt|Treat|treat", col_names)] <- "Trt"
      x <- as.factor(x_char)
    } else {
      half <- ceiling(length(col_names) / 2)
      x <- as.factor(rep(c("Ctl", "Trt"), each = half)[1:length(col_names)])
    }
    
    # 3. Create SeqExpressionSet object
    set <- newSeqExpressionSet(as.matrix(filtered),
                               phenoData = data.frame(x, row.names=colnames(filtered)))
    
    # Setup PDF for diagnostic plots
    pdf("RUVSeq_diagnostic_plots.pdf", width = 10, height = 8)
    colors <- brewer.pal(3, "Set2")
    
    # Plot raw RLE and PCA
    plotRLE(set, outline=FALSE, ylim=c(-4, 4), col=colors[x], main="Raw RLE")
    plotPCA(set, col=colors[x], cex=1.2, main="Raw PCA")
    
    # 4. Perform upper-quartile normalization
    set <- betweenLaneNormalization(set, which="upper")
    
    # Plot after UQ normalization
    plotRLE(set, outline=FALSE, ylim=c(-4, 4), col=colors[x], main="UQ Normalized RLE")
    plotPCA(set, col=colors[x], cex=1.2, main="UQ Normalized PCA")
    
    # 5. Estimate unwanted variation factors using RUVg with control genes
    set1 <- RUVg(set, spikes, k=1)
    
    # Plot after RUVg normalization
    plotRLE(set1, outline=FALSE, ylim=c(-4, 4), col=colors[x], main="RUVg Normalized RLE")
    plotPCA(set1, col=colors[x], cex=1.2, main="RUVg Normalized PCA")
    dev.off()
    
    # 6. Build design matrix including estimated factors (W_1)
    design <- model.matrix(~x + W_1, data=pData(set1))
    
    # 7. Perform differential expression analysis using edgeR
    y <- DGEList(counts=counts(set1), group=x)
    y <- calcNormFactors(y, method="upperquartile")
    y <- estimateGLMCommonDisp(y, design)
    y <- estimateGLMTagwiseDisp(y, design)
    fit <- glmFit(y, design)
    lrt <- glmLRT(fit, coef=2)
    
    # Print top tags to console and save to CSV
    print(topTags(lrt))
    write.csv(as.data.frame(topTags(lrt, n = Inf)), "edgeR_RUVg_results.csv", row.names = TRUE)
    
    # 8. Perform differential expression analysis using DESeq2
    dds <- DESeqDataSetFromMatrix(countData = counts(set1),
                                  colData = pData(set1),
                                  design = ~ W_1 + x)
    dds <- DESeq(dds)
    res <- results(dds)
    
    # Print DESeq2 results to console and save to CSV
    print(res)
    write.csv(as.data.frame(res), "DESeq2_RUVg_results.csv", row.names = TRUE)
    
    # Save normalized counts and estimated factors
    write.csv(normCounts(set1), "RUVg_normalized_counts.csv", row.names = TRUE)
    write.csv(pData(set1), "RUVg_estimated_factors.csv", row.names = TRUE)
    
    # Save RDS objects for downstream analysis
    saveRDS(set1, "RUVSeq_set1.rds")
    saveRDS(lrt, "edgeR_lrt.rds")
    saveRDS(dds, "DESeq2_dds.rds")
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_RUVSEQ_RUVG_CONTROL_GENES":',
        paste0('    RUVSeq: ', as.character(packageVersion('RUVSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvg_control_genes.csv versions.yml
    """
}

workflow BIOC_RUVSEQ_RUVG_CONTROL_GENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, control_genes.txt ] ]

    main:
    BIOC_RUVSEQ_RUVG_CONTROL_GENES(ch_input)

    emit:
    tables   = BIOC_RUVSEQ_RUVG_CONTROL_GENES.out.tables
    plots    = BIOC_RUVSEQ_RUVG_CONTROL_GENES.out.plots
    objects  = BIOC_RUVSEQ_RUVG_CONTROL_GENES.out.objects
    versions = BIOC_RUVSEQ_RUVG_CONTROL_GENES.out.versions
}
