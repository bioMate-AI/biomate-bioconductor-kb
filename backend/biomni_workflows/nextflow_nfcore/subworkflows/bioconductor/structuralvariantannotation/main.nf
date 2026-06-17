#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: StructuralVariantAnnotation — sv_overlap_and_caller_comparison
// Load SV calls from multiple callers and compare them to a truth set to calculate precision and recall.
// Input: na12878_chr22_Sudmunt2015.vcf, na12878_chr22_crest.vcf, na12878_chr22_hydra.vcf
// Container: quay.io/biocontainers/bioconductor-structuralvariantannotation:1.26.0--r45hdfd78af_0
// R packages: VariantAnnotation, dplyr, ggbio, ggplot2, rtracklayer, StructuralVariantAnnotation
// Bioconductor: 3.20 | R: 4.4
// Requires: StructuralVariantAnnotation, VariantAnnotation, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load VCF files using VariantAnnotation::readVcf
//  * 2. [Core Analysis] Convert VCFs to breakend-centric GRanges using breakpointRanges
//  * 3. [Core Analysis] Combine caller GRanges and calculate overlaps with the truth set using countBreakpointOverlaps with custom matching margins
//  * 4. [Core Analysis] Calculate precision and recall metrics

nextflow.enable.dsl = 2

process BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("VariantAnnotation", "dplyr", "ggbio", "ggplot2", "rtracklayer", "StructuralVariantAnnotation")
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
    suppressPackageStartupMessages({
      library(StructuralVariantAnnotation)
      library(VariantAnnotation)
      library(dplyr)
      library(ggplot2)
    })
    
    # Define input file paths (expected in the working directory)
    truth_vcf_path <- "na12878_chr22_Sudmunt2015.vcf"
    crest_vcf_path <- "na12878_chr22_crest.vcf"
    hydra_vcf_path <- "na12878_chr22_hydra.vcf"
    
    # Check if input files exist
    for (f in c(truth_vcf_path, crest_vcf_path, hydra_vcf_path)) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing:", f))
      }
    }
    
    # 1. Load VCF files using VariantAnnotation::readVcf
    message("Loading VCF files...")
    truth_vcf <- readVcf(truth_vcf_path)
    crest_vcf <- readVcf(crest_vcf_path)
    hydra_vcf <- readVcf(hydra_vcf_path)
    
    # 2. Convert VCFs to breakend-centric GRanges using breakpointRanges
    message("Converting VCFs to GRanges...")
    truth_svgr <- breakpointRanges(truth_vcf)
    truth_svgr <- truth_svgr[seqnames(truth_svgr) == "chr22"]
    
    # Some SV callers don't report QUAL so we need to use a proxy
    VariantAnnotation::fixed(crest_vcf)\$QUAL <- info(crest_vcf)\$left_softclipped_read_count + info(crest_vcf)\$left_softclipped_read_count
    crest_svgr <- breakpointRanges(crest_vcf)
    crest_svgr\$caller <- "crest"
    
    hydra_svgr <- breakpointRanges(hydra_vcf)
    hydra_svgr\$caller <- "hydra"
    
    # 3. Combine caller GRanges and calculate overlaps with the truth set
    message("Combining caller GRanges and calculating overlaps...")
    svgr <- c(crest_svgr, hydra_svgr)
    
    svgr\$truth_matches <- countBreakpointOverlaps(svgr, truth_svgr,
      maxgap=100,
      sizemargin=0.25,
      restrictMarginToSizeMultiple=0.5,
      countOnlyBest=TRUE)
    
    # Save the combined GRanges object with overlap annotations
    saveRDS(svgr, "svgr_overlaps.rds")
    
    # 4. Calculate precision and recall metrics
    message("Calculating precision and recall metrics...")
    metrics <- as.data.frame(svgr) %>%
      dplyr::select(QUAL, caller, truth_matches) %>%
      dplyr::group_by(caller, QUAL) %>%
      dplyr::summarise(
        calls = dplyr::n(),
        tp = sum(truth_matches > 0),
        .groups = "drop"
      ) %>%
      dplyr::group_by(caller) %>%
      dplyr::arrange(dplyr::desc(QUAL)) %>%
      dplyr::mutate(
        cum_tp = cumsum(tp),
        cum_n = cumsum(calls),
        cum_fp = cum_n - cum_tp,
        Precision = cum_tp / cum_n,
        Recall = cum_tp / length(truth_svgr)
      ) %>%
      dplyr::ungroup()
    
    # Write metrics table to CSV
    write.csv(metrics, "caller_comparison_metrics.csv", row.names = FALSE)
    
    # Generate and save Precision-Recall plot
    message("Generating Precision-Recall plot...")
    p <- ggplot(metrics) +
      aes(x = Recall, y = Precision, colour = caller) +
      geom_point() +
      geom_line() +
      labs(
        title = "NA12878 chr22 CREST and HYDRA\nSudmunt 2015 truth set",
        x = "Recall",
        y = "Precision"
      ) +
      theme_minimal()
    
    ggsave("precision_recall_plot.pdf", plot = p, width = 7, height = 6)
    
    message("Pipeline completed successfully. Outputs written to 'svgr_overlaps.rds', 'caller_comparison_metrics.csv', and 'precision_recall_plot.pdf'.")

    writeLines(c(
        '"BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON":',
        paste0('    StructuralVariantAnnotation: ', as.character(packageVersion('StructuralVariantAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sv_overlap_and_caller_comparison.csv versions.yml
    """
}

workflow BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ na12878_chr22_Sudmunt2015.vcf, na12878_chr22_crest.vcf, na12878_chr22_hydra.vcf ] ]

    main:
    BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON(ch_input)

    emit:
    tables   = BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON.out.tables
    plots    = BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON.out.plots
    objects  = BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON.out.objects
    versions = BIOC_STRUCTURALVARIANTANNOTATION_SV_OVERLAP_AND_CALLER_COMPARISON.out.versions
}
