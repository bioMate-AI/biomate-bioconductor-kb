#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wiggleplotr — read_coverage_plotting
// Plot sequencing read coverage from BigWig or Parquet files across transcript structures.
// Input: bigwig_files, sample_metadata, exons_list
// Container: quay.io/biocontainers/bioconductor-wiggleplotr:1.34.0--r45hdfd78af_0
// R packages: GenomicFeatures, GenomicRanges, arrow, cowplot, dplyr, readr, wiggleplotr
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, GenomicRanges, arrow, cowplot, dplyr, readr, wiggleplotr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a sample metadata data frame containing sample IDs, conditions, scaling factors, and paths to BigWig files
//  * 2. [Visualization & Output] Add track_id and colour_group columns to define plotting tracks and colors
//  * 3. [Visualization & Output] Plot read coverage alongside transcript annotations using plotCoverage, optionally specifying Parquet input, overlaying individual

nextflow.enable.dsl = 2

process BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GenomicFeatures", "GenomicRanges", "arrow", "cowplot", "dplyr", "readr", "wiggleplotr")
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
        library("wiggleplotr")
        library("dplyr")
        library("GenomicRanges")
        library("GenomicFeatures")
        library("arrow")
        library("readr")
        library("cowplot")
        
        # Define input file paths in the working directory
        sample_metadata_path = "sample_metadata.csv"
        exons_list_path = "exons_list.rds"
        cdss_list_path = "cdss_list.rds"
        transcript_metadata_path = "transcript_metadata.csv"
        parquet_path = "coverage.parquet"
        
        # Verify that required input files exist
        if (!file.exists(sample_metadata_path)) {
          stop(paste("Required input file missing:", sample_metadata_path))
        }
        if (!file.exists(exons_list_path)) {
          stop(paste("Required input file missing:", exons_list_path))
        }
        
        # Load user inputs
        sample_data = readr::read_csv(sample_metadata_path)
        ncoa7_exons = readRDS(exons_list_path)
        
        ncoa7_cdss = NULL
        if (file.exists(cdss_list_path)) {
          ncoa7_cdss = readRDS(cdss_list_path)
        }
        
        ncoa7_metadata = NULL
        if (file.exists(transcript_metadata_path)) {
          ncoa7_metadata = readr::read_csv(transcript_metadata_path)
        }
        
        # Ensure condition is a factor
        if ("condition" %in% colnames(sample_data)) {
          sample_data\$condition = factor(sample_data\$condition)
        }
        
        # Ensure scaling_factor exists
        if (!"scaling_factor" %in% colnames(sample_data)) {
          sample_data\$scaling_factor = 1
        }
        
        # Ensure bigWig paths are correctly set to local files if not already specified
        if (!"bigWig" %in% colnames(sample_data)) {
          sample_data = sample_data %>%
            dplyr::mutate(bigWig = file.path(getwd(), paste0(sample_id, ".bw")))
        }
        
        # Dynamically select transcripts to plot (fallback to first two if defaults are missing)
        available_transcripts = names(ncoa7_exons)
        selected_transcripts = c("ENST00000438495", "ENST00000392477")
        if (!all(selected_transcripts %in% available_transcripts)) {
          selected_transcripts = available_transcripts[1:min(2, length(available_transcripts))]
        }
        
        cdss_subset = if (!is.null(ncoa7_cdss)) ncoa7_cdss[selected_transcripts] else NULL
        
        # 1. Create track data with condition-based tracks and colors
        track_data = dplyr::mutate(sample_data, track_id = condition, colour_group = condition)
        
        pq_file = if (file.exists(parquet_path)) parquet_path else NULL
        
        # 2. Plot mean read coverage across groups
        p1 = plotCoverage(ncoa7_exons[selected_transcripts], cdss_subset, 
                     ncoa7_metadata, track_data,
                     heights = c(2,1), fill_palette = getGenotypePalette(),
                     coverage_ranges_pq = pq_file)
        
        cowplot::save_plot("coverage_plot_mean.pdf", p1, base_height = 8, base_width = 10)
        
        # 3. Plot individual samples overlaid (mean_only = FALSE)
        p2 = plotCoverage(ncoa7_exons[selected_transcripts], cdss_subset, 
                     ncoa7_metadata, track_data,
                     heights = c(2,1), fill_palette = getGenotypePalette(), mean_only = FALSE, alpha = 0.5,
                     coverage_ranges_pq = pq_file)
        
        cowplot::save_plot("coverage_plot_individual.pdf", p2, base_height = 8, base_width = 10)
        
        # 4. Plot using Parquet coverage data if available
        if (file.exists(parquet_path)) {
          p3 = plotCoverage(ncoa7_exons[selected_transcripts], cdss_subset, 
                       ncoa7_metadata, track_data,
                       heights = c(2,1), fill_palette = getGenotypePalette(), 
                       coverage_ranges_pq = parquet_path, rescale_introns = T)
          
          cowplot::save_plot("coverage_plot_parquet.pdf", p3, base_height = 8, base_width = 10)
        }
        
        # 5. Overlay multiple conditions on a single track using line plots
        track_data = dplyr::mutate(sample_data, track_id = "RNA-seq", colour_group = condition)
        p4 = plotCoverage(ncoa7_exons[selected_transcripts], cdss_subset, 
                    ncoa7_metadata, track_data,
                     heights = c(2,1), fill_palette = getGenotypePalette(), coverage_type = "line",
                     coverage_ranges_pq = pq_file)
        
        cowplot::save_plot("coverage_plot_line.pdf", p4, base_height = 8, base_width = 10)
        
        # Save final track metadata configuration
        readr::write_csv(track_data, "track_data_output.csv")

    writeLines(c(
        '"BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING":',
        paste0('    wiggleplotr: ', as.character(packageVersion('wiggleplotr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_coverage_plotting.csv versions.yml
    """
}

workflow BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bigwig_files, sample_metadata, exons_list ] ]

    main:
    BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING(ch_input)

    emit:
    tables   = BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING.out.tables
    plots    = BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING.out.plots
    objects  = BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING.out.objects
    versions = BIOC_WIGGLEPLOTR_READ_COVERAGE_PLOTTING.out.versions
}
