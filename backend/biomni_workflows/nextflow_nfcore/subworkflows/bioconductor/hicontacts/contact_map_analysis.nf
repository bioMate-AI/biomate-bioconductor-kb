#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiContacts — contact_map_analysis
// Perform virtual 4C analysis, calculate cis-trans ratios, and compute/compare distance decay P(s) curves.
// Input: mcool_file.mcool, pairs.gz
// Container: quay.io/biocontainers/bioconductor-hicontacts:1.12.0--r45hdfd78af_0
// R packages: HiCExperiment, HiContacts, InteractionSet, dplyr, ggplot2, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: HiCExperiment, HiContacts, IRanges, InteractionSet, dplyr, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Cis-Trans Ratios
//  * 2. [Visualization & Output] Compare P(s) Curves Across Chromosomes

nextflow.enable.dsl = 2

process BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("HiCExperiment", "HiContacts", "InteractionSet", "dplyr", "ggplot2", "rtracklayer")
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
    library(dplyr)
    library(ggplot2)
    library(HiCExperiment)
    library(HiContacts)
    library(rtracklayer)
    library(InteractionSet)
    
    # Define input files from the working directory
    mcool_file <- "mcool_file.mcool"
    pairs_file <- "pairs.gz"
    
    # Verify input files exist
    if (!file.exists(mcool_file)) {
        stop(paste("Required input file missing:", mcool_file))
    }
    if (!file.exists(pairs_file)) {
        stop(paste("Required input file missing:", pairs_file))
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1 & 2: Import Hi-C matrix and Virtual 4C Analysis
    # -----------------------------------------------------------------------------
    message("Stage 1 & 2: Importing Hi-C matrix and performing Virtual 4C analysis...")
    tryCatch({
        # Import without hardcoded resolution to get available chromosomes
        hic_init <- import(mcool_file, format = 'mcool')
        target_chr <- seqlevels(hic_init)[1]
        
        # Focus on the first available chromosome dynamically
        hic <- import(mcool_file, format = 'mcool', focus = target_chr)
        vp <- GRanges(target_chr, IRanges::IRanges(1, 10000))
        
        v4C <- virtual4C(hic, viewpoint = vp)
        
        # Plot 4C
        p_4c <- plot4C(v4C, ggplot2::aes(x = center, y = score))
        ggsave("virtual4C_plot.pdf", plot = p_4c, width = 8, height = 6)
        
        # Save 4C data
        write.csv(as.data.frame(v4C), "virtual4C_data.csv", row.names = FALSE)
        message("Virtual 4C analysis completed successfully.")
    }, error = function(e) {
        warning("Virtual 4C analysis failed: ", e\$message)
    })
    
    # -----------------------------------------------------------------------------
    # --- Cis-Trans Ratios ---
    # -----------------------------------------------------------------------------
    message("Stage 3: Calculating cis-trans interaction ratios...")
    tryCatch({
        # Import without hardcoded resolution
        hic <- import(mcool_file, format = 'mcool')
        ct_ratio <- cisTransRatio(hic)
        write.csv(as.data.frame(ct_ratio), "cis_trans_ratio.csv", row.names = FALSE)
        print(ct_ratio)
        message("Cis-trans ratio calculation completed successfully.")
    }, error = function(e) {
        warning("Cis-trans ratio calculation failed: ", e\$message)
    })
    
    # -----------------------------------------------------------------------------
    # Stage 4 & 5: Distance Decay P(s) Curves (Without and With Pairs File)
    # -----------------------------------------------------------------------------
    message("Stage 4 & 5: Computing distance decay P(s) curves...")
    tryCatch({
        # Without a pairs file (import without hardcoded resolution)
        hic <- import(mcool_file, format = 'mcool')
        ps <- distanceLaw(hic)
        p_ps_approx <- plotPs(ps, ggplot2::aes(x = binned_distance, y = norm_p))
        ggsave("distance_decay_approx_plot.pdf", plot = p_ps_approx, width = 8, height = 6)
        
        # With a pairs file
        pairsFile(hic) <- pairs_file
        ps <- distanceLaw(hic)
        
        p_ps_exact <- plotPs(ps, ggplot2::aes(x = binned_distance, y = norm_p))
        ggsave("distance_decay_exact_plot.pdf", plot = p_ps_exact, width = 8, height = 6)
        
        p_ps_slope <- plotPsSlope(ps, ggplot2::aes(x = binned_distance, y = slope))
        ggsave("distance_decay_slope_plot.pdf", plot = p_ps_slope, width = 8, height = 6)
        
        write.csv(as.data.frame(ps), "distance_decay_data.csv", row.names = FALSE)
        message("Distance decay analysis completed successfully.")
    }, error = function(e) {
        warning("Distance decay analysis failed: ", e\$message)
    })
    
    # -----------------------------------------------------------------------------
    # --- Compare P(s) Curves Across Chromosomes ---
    # -----------------------------------------------------------------------------
    message("Stage 6: Comparing P(s) curves across chromosomes...")
    tryCatch({
        # Compare two different chromosomes from the same sample instead of mock samples
        hic_full <- import(mcool_file, format = 'mcool')
        chrs <- seqlevels(hic_full)
        chr1 <- chrs[1]
        chr2 <- if (length(chrs) > 1) chrs[2] else chrs[1]
        
        c1 <- import(
            mcool_file, 
            format = 'mcool',
            focus = chr1, 
            pairsFile = pairs_file
        )
        c2 <- import(
            mcool_file, 
            format = 'mcool',
            focus = chr2, 
            pairsFile = pairs_file
        )
        
        ps_1 <- distanceLaw(c1) |> mutate(sample = chr1)
        ps_2 <- distanceLaw(c2) |> mutate(sample = chr2)
        ps <- rbind(ps_1, ps_2)
        
        p_compare <- plotPs(ps, ggplot2::aes(x = binned_distance, y = norm_p, group = sample, color = sample))
        ggsave("distance_decay_comparison_plot.pdf", plot = p_compare, width = 8, height = 6)
        
        p_compare_slope <- plotPsSlope(ps, ggplot2::aes(x = binned_distance, y = slope, group = sample, color = sample))
        ggsave("distance_decay_comparison_slope_plot.pdf", plot = p_compare_slope, width = 8, height = 6)
        
        write.csv(as.data.frame(ps), "distance_decay_comparison_data.csv", row.names = FALSE)
        message("Comparison of P(s) curves completed successfully.")
    }, error = function(e) {
        warning("Comparison of P(s) curves failed: ", e\$message)
    })
    
    message("Pipeline execution finished.")

    writeLines(c(
        '"BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS":',
        paste0('    HiContacts: ', as.character(packageVersion('HiContacts')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_contact_map_analysis.csv versions.yml
    """
}

workflow BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mcool_file.mcool, pairs.gz ] ]

    main:
    BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS.out.tables
    plots    = BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS.out.plots
    objects  = BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS.out.objects
    versions = BIOC_HICONTACTS_CONTACT_MAP_ANALYSIS.out.versions
}
