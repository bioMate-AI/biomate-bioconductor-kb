#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UPDhmm — upd_detection_and_postprocessing
// Detect, filter, collapse, and annotate uniparental disomy (UPD) events from trio VCF files.
// Input: sample1.vcf.gz, sample2.vcf.gz, SFARI.bed
// Container: quay.io/biocontainers/bioconductor-updhmm:1.6.0--r45hdfd78af_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: UPDhmm, VariantAnnotation, dplyr, karyoploteR, regioneR
// Visualizations: plot (ggplot/base)
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
