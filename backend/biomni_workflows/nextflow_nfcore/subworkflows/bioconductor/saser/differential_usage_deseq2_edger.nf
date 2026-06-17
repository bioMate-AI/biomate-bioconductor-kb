#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: saseR — differential_usage_deseq2_edger
// Perform differential bin usage/splicing analysis using adapted offsets in DESeq2 and edgeR.
// Input: genes.mini.gtf, A_C_0.bam, A_C_1.bam, A_C_2.bam, A_D_0.bam, A_D_1.bam, A_D_2.bam
// Container: quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0
// R packages: DESeq2, GenomicAlignments, GenomicFeatures, dplyr, edgeR, saseR, txdbmaker
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, GenomicAlignments, GenomicFeatures, dplyr, edgeR, saseR, txdbmaker
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation, alignment/mapping QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Build TxDb and extract exonic parts
//  * 2. [Visualization & Output] Summarize overlaps to get bin counts
//  * 3. [Visualization & Output] Define experimental conditions in colData (adapted to 6
//  * 4. [Visualization & Output] Aggregate bin counts per gene to calculate gene-level
//  * 5. [Visualization & Output] Replace zero offsets and counts with 1 to avoid errors in
//  * 6. [Visualization & Output] Run DESeq2 analysis with custom normalization factors
//  * 7. [Visualization & Output] Run edgeR analysis with custom log-offsets

nextflow.enable.dsl = 2

process BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DESeq2", "GenomicAlignments", "GenomicFeatures", "dplyr", "edgeR", "saseR", "txdbmaker", "SummarizedExperiment")
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
    library(saseR)
    library(SummarizedExperiment)
    library(edgeR)
    library(DESeq2)
    library(dplyr)
    library(GenomicAlignments)
    library(GenomicFeatures)
    library(txdbmaker)
    
    # Define input files from the working directory
    gtfFileName <- "genes.mini.gtf"
    BAMFiles <- c("A_C_0.bam", "A_C_1.bam", "A_C_2.bam", "A_D_0.bam", "A_D_1.bam", "A_D_2.bam")
    
    # --- Build TxDb and extract exonic parts ---
    genomeTxDb <- txdbmaker::makeTxDbFromGFF(gtfFileName)
    flattenedAnnotation = GenomicFeatures::exonicParts(genomeTxDb, 
                                      linked.to.single.gene.only=TRUE )
    
    # --- Summarize overlaps to get bin counts ---
    se = GenomicAlignments::summarizeOverlaps(
        flattenedAnnotation,
        BAMFiles, 
        singleEnd=TRUE, 
        ignore.strand=TRUE )
    
    # Preprocess gene_id to ensure it is a standard character vector (resolving CharacterList S4 class issues)
    rowData(se)\$gene_id <- as.character(rowData(se)\$gene_id)
    
    # --- Define experimental conditions in colData (adapted to 6 ---
    colData(se)\$condition <- factor(c(rep(c("control", "case"), each = 3)))
    
    # --- Aggregate bin counts per gene to calculate gene-level ---
    counts <- assays(se)\$counts
    offsetsGene <- aggregate(counts,
                         by = list("gene" = rowData(se)\$gene_id), FUN = sum) 
    offsets <- offsetsGene[match(rowData(se)\$gene_id, offsetsGene\$gene), ] %>% 
                         mutate("gene" = NULL) %>% 
                         as.matrix() 
    
    # --- Replace zero offsets and counts with 1 to avoid errors in ---
    index <- offsets == 0
    counts[index] <- 1
    offsets[index] <- 1
    
    # --- Run DESeq2 analysis with custom normalization factors ---
    dds <- DESeqDataSetFromMatrix(countData = counts,
                                  colData = colData(se),
                                  rowData = rowData(se),
                                  design= ~ condition)
    normalizationFactors(dds) <- offsets
    dds <- DESeq2::estimateDispersionsGeneEst(dds)
    dispersions(dds) <- mcols(dds)\$dispGeneEst
    dds <- DESeq2::nbinomWaldTest(dds)
    results_dds <- DESeq2::results(dds)
    
    # --- Run edgeR analysis with custom log-offsets ---
    DGE <- DGEList(counts = counts)
    DGE\$offset <- log(offsets)
    design <- model.matrix(~condition, data = colData(se))
    DGE <- edgeR::estimateDisp(DGE, design = design)
    fitDGE <- edgeR::glmFit(DGE, design= design)
    results_DGE <- edgeR::glmLRT(fitDGE, coef = 2)
    
    # Save meaningful results to output files
    write.csv(as.data.frame(results_dds), file = "deseq2_results.csv", row.names = TRUE)
    saveRDS(results_dds, file = "deseq2_results.rds")
    
    write.csv(as.data.frame(topTags(results_DGE, n = Inf)), file = "edger_results.csv", row.names = TRUE)
    saveRDS(results_DGE, file = "edger_results.rds")
    
    # Generate diagnostic plots
    pdf("diagnostic_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    hist(results_dds\$pvalue, main = "DESeq2 p-values", xlab = "p-value", col = "skyblue", breaks = 20)
    hist(results_DGE\$table\$PValue, main = "edgeR p-values", xlab = "p-value", col = "salmon", breaks = 20)
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "alignment/mapping QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER":',
        paste0('    saseR: ', as.character(packageVersion('saseR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_usage_deseq2_edger.csv versions.yml
    """
}

workflow BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes.mini.gtf, A_C_0.bam, A_C_1.bam, A_C_2.bam, A_D_0.bam, A_D_1.bam, A_D_2.bam ] ]

    main:
    BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER(ch_input)

    emit:
    tables   = BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER.out.tables
    plots    = BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER.out.plots
    objects  = BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER.out.objects
    versions = BIOC_SASER_DIFFERENTIAL_USAGE_DESEQ2_EDGER.out.versions
}
