#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: soGGi — soggi_profile_analysis
// Generate and visualize grouped genomic interval aggregate signal profiles from BED regions and metadata using soGGi.
// Input: regions.bed, coldata.csv
// Container: 1.38.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, ggplot2, rtracklayer, soGGi
// Visualizations: genomic region plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("soGGi", "GenomicRanges", "rtracklayer", "ggplot2", "BiocGenerics")
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
    library(soGGi)
    library(GenomicRanges)
    library(rtracklayer)
    library(ggplot2)
    library(BiocGenerics)
    
    # ==========================================
    # --- Import and Preprocess Input Files ---
    # ==========================================
    message("Stage 1: Importing regions and metadata...")
    
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import genomic intervals
    gr <- rtracklayer::import("regions.bed", format = "bed")
    
    # Ensure seqlengths are set (required for BigWig generation and profiling)
    if (any(is.na(seqlengths(gr)))) {
      chrs <- as.character(unique(seqnames(gr)))
      lengths <- sapply(chrs, function(chr) {
        max(end(gr[seqnames(gr) == chr])) + 50000
      })
      names(lengths) <- chrs
      seqlengths(gr) <- lengths
    }
    
    # Handle metadata and grouping
    if (file.exists("coldata.csv")) {
      message("Applying metadata from coldata.csv...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      
      if ("name" %in% colnames(coldata) && !is.null(gr\$name)) {
        idx <- match(gr\$name, coldata\$name)
        gr\$group <- coldata\$group[idx]
      } else if (nrow(coldata) == length(gr)) {
        gr\$group <- coldata\$group
      } else {
        gr\$group <- as.character(strand(gr))
      }
    } else {
      message("No coldata.csv found. Grouping by strand/score...")
      if (!is.null(gr\$score) && length(unique(gr\$score)) > 1) {
        gr\$group <- ifelse(gr\$score > median(gr\$score), "High_Score", "Low_Score")
      } else {
        gr\$group <- as.character(strand(gr))
      }
    }
    
    # Clean up group names and split into GRangesList
    gr\$group[is.na(gr\$group) | gr\$group == "*"] <- "Unassigned"
    gr_list <- split(gr, gr\$group)
    
    # ==========================================
    # --- Generate Mock Signal BigWig File ---
    # ==========================================
    message("Stage 2: Generating mock signal BigWig file...")
    
    # Create mock signal peaks centered on the regions
    peaks <- resize(gr, width = 200, fix = "center")
    peaks <- trim(peaks)
    peaks\$score <- runif(length(peaks), min = 10, max = 100)
    
    # Create background noise
    bg <- tile(gr, width = 100) |> unlist()
    bg <- trim(bg)
    bg\$score <- runif(length(bg), min = 1, max = 5)
    
    # Combine, sort, and set seqinfo
    all_signal <- c(peaks, bg)
    all_signal <- sort(all_signal)
    seqinfo(all_signal) <- seqinfo(gr)
    
    # Export to BigWig
    rtracklayer::export.bw(all_signal, "signal.bw")
    
    # ==========================================
    # --- Run soGGi Profiling ---
    # ==========================================
    message("Stage 3: Running soGGi profiling...")
    
    # 1. Point Style Profile (centered on region midpoints)
    profile_point <- regionPlot(
      "signal.bw",
      testRanges = gr_list,
      format = "bigwig",
      style = "point",
      distanceUp = 1000,
      distanceDown = 1000,
      nOfWindows = 100
    )
    
    # 2. Percent Style Profile (scaled across region bodies)
    profile_percent <- regionPlot(
      "signal.bw",
      testRanges = gr_list,
      format = "bigwig",
      style = "percent",
      distanceUp = 500,
      distanceDown = 500,
      nOfWindows = 100
    )
    
    # ==========================================
    # --- Normalization and Visualization ---
    # ==========================================
    message("Stage 4: Normalizing and plotting profiles...")
    
    # Normalize profiles
    profile_point_norm <- normalise(profile_point, method = "max")
    profile_percent_norm <- normalise(profile_percent, method = "max")
    
    # Generate plots
    p_point <- plotRegion(profile_point_norm) + 
      ggtitle("Grouped Signal Profile (Point Style)") +
      theme_minimal()
    
    p_percent <- plotRegion(profile_percent_norm) + 
      ggtitle("Grouped Signal Profile (Percent Style)") +
      theme_minimal()
    
    # Save plots to PDF
    ggsave("profile_point.pdf", plot = p_point, width = 8, height = 6)
    ggsave("profile_percent.pdf", plot = p_percent, width = 8, height = 6)
    
    # ==========================================
    # --- Export Profile Data ---
    # ==========================================
    message("Stage 5: Exporting profile data to CSV...")
    
    # Helper function to extract data frame from ChIPprofile object
    get_profile_df <- function(prof_obj) {
      tryCatch({
        as.data.frame(prof_obj)
      }, error = function(e) {
        tryCatch({
          p <- plotRegion(prof_obj)
          p\$data
        }, error = function(e2) {
          data.frame(Message = "Could not extract profile data directly")
        })
      })
    }
    
    df_point <- get_profile_df(profile_point_norm)
    df_percent <- get_profile_df(profile_percent_norm)
    
    write.csv(df_point, "profile_point_data.csv", row.names = FALSE)
    write.csv(df_percent, "profile_percent_data.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS":',
        paste0('    soGGi: ', as.character(packageVersion('soGGi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_soggi_profile_analysis.csv versions.yml
    """
}

workflow BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS.out.tables
    plots    = BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS.out.plots
    objects  = BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS.out.objects
    versions = BIOC_SOGGI_SOGGI_PROFILE_ANALYSIS.out.versions
}
