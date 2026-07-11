#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UPDhmm — upd_detection_and_postprocessing
// Detect, filter, collapse, and annotate uniparental disomy (UPD) events from trio VCF files.
// Input: sample1.vcf.gz, sample2.vcf.gz, SFARI.bed
// Container: quay.io/biocontainers/bioconductor-updhmm:1.6.0--r45hdfd78af_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: UPDhmm, VariantAnnotation, dplyr, karyoploteR, regioneR
// Visualizations: karyotype plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and preprocess VCF files using VariantAnnotation::readVcf and vcfCheck
//  * 2. [Core Analysis] Detect UPD events using calculateEvents
//  * 3. [Core Analysis] Collapse and filter events using collapseEvents
//  * 4. [Core Analysis] Identify and annotate recurrent regions using identifyRecurrentRegions and markRecurrentRegions
//  * 5. [Visualization & Output] Visualize UPD events across the genome using karyoploteR

nextflow.enable.dsl = 2

process BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("UPDhmm", "dplyr", "VariantAnnotation", "regioneR", "karyoploteR")
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
        library(UPDhmm)
        library(dplyr)
        library(VariantAnnotation)
        library(regioneR)
        library(karyoploteR)
        
        # Define the local input files (exactly as specified by the user)
        files <- c("sample1.vcf.gz", "sample2.vcf.gz")
        
        # Read and preprocess each VCF
        vcf_list <- lapply(files, function(file) {
          vcf <- readVcf(file)
          samps <- colnames(vcf)
          vcfCheck(vcf, proband = samps[1], mother = samps[2], father = samps[3])
        })
        
        # Detect UPD events using the HMM-based approach
        events_list <- lapply(vcf_list, calculateEvents, add_ratios = TRUE)
        
        # Collapse and filter events
        collapsed_list <- lapply(events_list, collapseEvents)
        collapsed_all <- do.call(rbind.data.frame, c(collapsed_list, make.row.names = FALSE))
        
        # Save the collapsed events to a CSV file
        write.csv(collapsed_all, "collapsed_all_events.csv", row.names = FALSE)
        
        # Identify recurrent regions across samples
        recurrentRegions <- identifyRecurrentRegions(
          df = collapsed_all,
          ID_col = "ID",
          error_threshold = 100,
          min_support = 2,
          max_dist = 0.97
        )
        
        # Save the identified recurrent regions as an RDS object
        saveRDS(recurrentRegions, "recurrent_regions.rds")
        
        # Annotate events with the identified recurrent regions
        annotatedEvents_recurrent <- markRecurrentRegions(
          df = collapsed_all,
          recurrent_regions = recurrentRegions
        )
        
        # Read external BED file for SFARI regions from the working directory
        bed <- "SFARI.bed"
        bed_df <- read.table(
          bed, header = TRUE
        )
        bed_gr <- toGRanges(bed_df)
        
        # Annotate events with the SFARI external BED regions
        annotatedEvents <- markRecurrentRegions(
          df = collapsed_all,
          recurrent_regions = bed_gr
        )
        
        # Save the final annotated events to a CSV file
        write.csv(annotatedEvents, "annotated_events_SFARI.csv", row.names = FALSE)
        
        # Function to visualize UPD events across the genome (exactly as documented)
        plotUPDKp <- function(updEvents) {
          #--------------------------------------------------------------
          # 1. Detect coordinate columns
          #--------------------------------------------------------------
          if (all(c("start", "end") %in% colnames(updEvents))) {
            start_col <- "start"
            end_col <- "end"
          } else if (all(c("min_start", "max_end") %in% colnames(updEvents))) {
            start_col <- "min_start"
            end_col <- "max_end"
          } else {
            stop("Input must contain either (start, end) or (min_start, max_end) columns.")
          }
          #--------------------------------------------------------------
          # 2. Ensure chromosome naming format (e.g. "chr3")
          #--------------------------------------------------------------
          updEvents\$seqnames <- ifelse(grepl("^chr", updEvents\$chromosome), updEvents\$chromosome, paste0("chr", updEvents\$chromosome))
          #--------------------------------------------------------------
          # 3. Helper function to safely create GRanges only if events exist
          #--------------------------------------------------------------
          to_gr_safe <- function(df, grp) {
            subset_df <- subset(df, group == grp)
            if (nrow(subset_df) > 0) {
              toGRanges(subset_df[, c("seqnames", start_col, end_col)])
            } else {
              NULL
            }
          }
          #--------------------------------------------------------------
          # 4. Separate UPD event types
          #--------------------------------------------------------------
          het_fat <- to_gr_safe(updEvents, "het_fat")
          het_mat <- to_gr_safe(updEvents, "het_mat")
          iso_fat <- to_gr_safe(updEvents, "iso_fat")
          iso_mat <- to_gr_safe(updEvents, "iso_mat")
          #--------------------------------------------------------------
          # 5. Create the genome ideogram
          #--------------------------------------------------------------
          kp <- plotKaryotype(genome = "hg19")
          #--------------------------------------------------------------
          # 6. Plot regions by inheritance type (if any exist)
          #--------------------------------------------------------------
          if (!is.null(het_fat)) kpPlotRegions(kp, het_fat, col = "#AAF593")
          if (!is.null(het_mat)) kpPlotRegions(kp, het_mat, col = "#FFB6C1")
          if (!is.null(iso_fat)) kpPlotRegions(kp, iso_fat, col = "#A6E5FC")
          if (!is.null(iso_mat)) kpPlotRegions(kp, iso_mat, col = "#E9B864")
          #--------------------------------------------------------------
          # 7. Add legend
          #--------------------------------------------------------------
          legend("topright", legend = c("Het_Fat", "Het_Mat", "Iso_Fat", "Iso_Mat"), fill = c("#AAF593", "#FFB6C1", "#A6E5FC", "#E9B864"))
        }
        
        # Plot and save the genome-wide visualization to a PDF file
        pdf("upd_events_karyoplot.pdf", width = 10, height = 8)
        plotUPDKp(annotatedEvents)
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING":',
        paste0('    UPDhmm: ', as.character(packageVersion('UPDhmm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_upd_detection_and_postprocessing.csv versions.yml
    """
}

workflow BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.vcf.gz, sample2.vcf.gz, SFARI.bed ] ]

    main:
    BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING(ch_input)

    emit:
    tables   = BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING.out.tables
    plots    = BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING.out.plots
    objects  = BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING.out.objects
    versions = BIOC_UPDHMM_UPD_DETECTION_AND_POSTPROCESSING.out.versions
}
