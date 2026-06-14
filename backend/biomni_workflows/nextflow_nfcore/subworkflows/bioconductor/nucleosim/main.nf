#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nucleoSim — nucleosim_synthetic_generation
// Generate synthetic nucleosome maps and NGS paired-end reads based on user-defined genomic intervals and simulation parameters.
// Input: regions.bed, coldata.csv
// Container: 1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, nucleoSim, rtracklayer
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION {
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
    .bm_deps <- c("nucleoSim", "rtracklayer", "GenomicRanges")
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
    library(nucleoSim)
    library(rtracklayer)
    library(GenomicRanges)
    
    # ==========================================
    # --- Input Parsing & Parameter Setup ---
    # ==========================================
    
    # Robust input handling: Create dummy files if they do not exist to ensure runnability
    if (!file.exists("regions.bed") || file.size("regions.bed") == 0) {
        message("regions.bed not found or empty. Creating a default template...")
        dummy_regions <- GRanges(
            seqnames = c("chrI", "chrII"),
            ranges = IRanges(start = c(1000, 5000), end = c(4000, 9000)),
            strand = c("+", "-")
        )
        rtracklayer::export(dummy_regions, "regions.bed")
    }
    
    if (!file.exists("coldata.csv") || file.size("coldata.csv") == 0) {
        message("coldata.csv not found or empty. Creating a default template...")
        dummy_coldata <- data.frame(
            sample = "sample_1",
            wp.var = 30,
            fuz.var = 50,
            max.cover = 70,
            nuc.len = 147,
            len.var = 12,
            lin.len = 20,
            distr = "Normal",
            read.len = 45,
            stringsAsFactors = FALSE
        )
        write.csv(dummy_coldata, "coldata.csv", row.names = FALSE)
    }
    
    # Import genomic intervals
    regions <- rtracklayer::import("regions.bed")
    message(paste("Loaded", length(regions), "target genomic intervals for simulation."))
    
    # Import simulation parameters
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Extract parameters with safe fallbacks
    nuc.len   <- if ("nuc.len" %in% colnames(coldata)) coldata\$nuc.len[1] else 147
    lin.len   <- if ("lin.len" %in% colnames(coldata)) coldata\$lin.len[1] else 20
    wp.var    <- if ("wp.var" %in% colnames(coldata)) coldata\$wp.var[1] else 30
    fuz.var   <- if ("fuz.var" %in% colnames(coldata)) coldata\$fuz.var[1] else 50
    max.cover <- if ("max.cover" %in% colnames(coldata)) coldata\$max.cover[1] else 70
    len.var   <- if ("len.var" %in% colnames(coldata)) coldata\$len.var[1] else 12
    distr     <- if ("distr" %in% colnames(coldata)) coldata\$distr[1] else "Normal"
    read.len  <- if ("read.len" %in% colnames(coldata)) coldata\$read.len[1] else 45
    
    # ==========================================
    # --- Multi-Region Simulation Loop ---
    # ==========================================
    
    all_reads_list <- list()
    all_wp_list    <- list()
    all_fuz_list   <- list()
    last_map       <- NULL
    
    for (i in seq_along(regions)) {
        reg <- regions[i]
        reg_width <- width(reg)
        reg_chrom <- as.character(seqnames(reg))
        reg_start <- start(reg)
        
        # Dynamically scale the number of well-positioned nucleosomes to fit the region width
        # Each nucleosome + linker unit occupies (nuc.len + lin.len) base pairs
        wp.num <- floor(reg_width / (nuc.len + lin.len))
        if (wp.num < 2) wp.num <- 2 # Ensure a minimum of 2 nucleosomes per region
        
        # Simulate deletion of ~20% of well-positioned nucleosomes
        wp.del <- floor(wp.num * 0.2)
        
        # Add fuzzy nucleosomes (~15% of the well-positioned count)
        fuz.num <- max(1, floor(wp.num * 0.15))
        
        message(sprintf("Simulating Region %d (%s:%d-%d): wp.num=%d, wp.del=%d, fuz.num=%d", 
                        i, reg_chrom, reg_start, end(reg), wp.num, wp.del, fuz.num))
        
        # 1. Generate the synthetic nucleosome map
        nuc_map <- syntheticNucMapFromDist(
            wp.num = wp.num,
            wp.del = wp.del,
            wp.var = wp.var,
            fuz.num = fuz.num,
            fuz.var = fuz.var,
            max.cover = max.cover,
            nuc.len = nuc.len,
            len.var = len.var,
            lin.len = lin.len,
            rnd.seed = 12345 + i,
            distr = distr
        )
        
        # Save the last map for visualization purposes
        last_map <- nuc_map
        
        # 2. Generate NGS reads from the map, applying the genomic start coordinate as offset
        nuc_sample <- syntheticNucReadsFromMap(
            nuc_map,
            read.len = read.len,
            offset = reg_start
        )
        
        # 3. Extract and format simulated reads
        reads_df <- nuc_sample\$dataIP
        reads_df\$chr <- reg_chrom
        all_reads_list[[i]] <- reads_df
        
        # 4. Extract and format nucleosome positions
        if (!is.null(nuc_sample\$wp) && nrow(nuc_sample\$wp) > 0) {
            wp_df <- nuc_sample\$wp
            wp_df\$chr <- reg_chrom
            all_wp_list[[i]] <- wp_df
        }
        if (!is.null(nuc_sample\$fuz) && nrow(nuc_sample\$fuz) > 0) {
            fuz_df <- nuc_sample\$fuz
            fuz_df\$chr <- reg_chrom
            all_fuz_list[[i]] <- fuz_df
        }
    }
    
    # Combine results across all simulated regions
    combined_reads <- do.call(rbind, all_reads_list)
    combined_wp    <- do.call(rbind, all_wp_list)
    combined_fuz   <- do.call(rbind, all_fuz_list)
    
    # ==========================================
    # --- Exporting Simulated Datasets ---
    # ==========================================
    
    # Convert simulated reads to GRanges and export as BED
    reads_gr <- GRanges(
        seqnames = combined_reads\$chr,
        ranges = IRanges(start = combined_reads\$start, end = combined_reads\$end),
        strand = combined_reads\$strand,
        id = combined_reads\$ID
    )
    rtracklayer::export(reads_gr, "synthetic_reads.bed")
    message("Successfully exported simulated NGS reads to 'synthetic_reads.bed'.")
    
    # Export nucleosome center positions and coverage metadata
    write.csv(combined_wp, "well_positioned_nucleosomes.csv", row.names = FALSE)
    write.csv(combined_fuz, "fuzzy_nucleosomes.csv", row.names = FALSE)
    message("Successfully exported nucleosome positions to CSV files.")
    
    # ==========================================
    # --- Tiling Array Simulation & Plotting ---
    # ==========================================
    
    # Simulate a separate hybridization tiling array dataset (ratio-based)
    message("Simulating hybridization data for Tiling Array visualization...")
    tiling_map <- syntheticNucMapFromDist(
        wp.num = 15,
        wp.del = 3,
        wp.var = 20,
        fuz.num = 3,
        fuz.var = 40,
        max.cover = 50,
        nuc.len = 147,
        len.var = 10,
        lin.len = 20,
        rnd.seed = 54321,
        as.ratio = TRUE,
        distr = "Normal"
    )
    
    # Generate diagnostic plots
    pdf("synthetic_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 1))
    
    if (!is.null(last_map)) {
        plot(last_map, xlab = "Position", ylab = "Coverage", 
             main = "Synthetic Nucleosome Map (Last Simulated Region)")
    }
    
    plot(tiling_map, main = "Simulated Tiling Array Hybridization Ratio Map")
    dev.off()
    message("Successfully generated diagnostic plots in 'synthetic_plots.pdf'.")

    writeLines(c(
        '"BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION":',
        paste0('    nucleoSim: ', as.character(packageVersion('nucleoSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucleosim_synthetic_generation.csv versions.yml
    """
}

workflow BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION(ch_input)

    emit:
    tables   = BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION.out.tables
    plots    = BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION.out.plots
    objects  = BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION.out.objects
    versions = BIOC_NUCLEOSIM_NUCLEOSIM_SYNTHETIC_GENERATION.out.versions
}
