#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metagene2 — chipseq_metagene_analysis
// Perform a standard ChIP-seq metagene analysis using contiguous regions, an experimental design, and region metadata.
// Input: bam_files, regions
// Container: quay.io/biocontainers/bioconductor-metagene2:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, metagene2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Initialize metagene2 object
//  * 3. [Visualization & Output] Define experimental design dynamically based on available
//  * 4. [Visualization & Output] Define region metadata

nextflow.enable.dsl = 2

process BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("metagene2", "GenomicRanges")
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
    library(metagene2)
    library(GenomicRanges)
    
    # --- Read user input files from the working directory ---
    # Read BAM files
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(bam_files) == 0) {
      stop("No BAM files found in the working directory.")
    }
    # Name the BAM files for metagene2
    names(bam_files) <- gsub("\\\\.bam\$", "", basename(bam_files))
    
    # Read regions (BED files or RDS containing GRanges/GRangesList)
    if (file.exists("regions.rds")) {
      regions <- readRDS("regions.rds")
    } else {
      regions <- list.files(pattern = "\\\\.(bed|BED|narrowPeak|broadPeak|gtf)\$", full.names = TRUE)
      if (length(regions) == 0) {
        stop("No regions (BED/narrowPeak/broadPeak/gtf or regions.rds) found in the working directory.")
      }
    }
    
    # --- Initialize metagene2 object ---
    mg <- metagene2\$new(regions = regions, 
                       bam_files = bam_files, 
                       assay='chipseq')
    
    # Produce and save the first metagene plot
    pdf("metagene_plot_simple.pdf")
    print(mg\$produce_metagene(title = "Demo metagene plot"))
    dev.off()
    
    # --- Define experimental design dynamically based on available ---
    n_bams <- length(bam_files)
    if (n_bams >= 3) {
      align1_vals <- rep(0, n_bams)
      align2_vals <- rep(0, n_bams)
      half <- floor((n_bams - 1) / 2)
      align1_vals[1:half] <- 1
      align1_vals[n_bams] <- 2
      align2_vals[(half+1):(n_bams-1)] <- 1
      align2_vals[n_bams] <- 2
      
      example_design <- data.frame(Samples = bam_files,
                                   align1 = align1_vals,
                                   align2 = align2_vals)
    } else {
      align1_vals <- rep(1, n_bams)
      
      example_design <- data.frame(Samples = bam_files,
                                   align1 = align1_vals)
    }
    
    # Produce and save metagene plot with design
    pdf("metagene_plot_design.pdf")
    print(mg\$produce_metagene(design=example_design))
    dev.off()
    
    # --- Define region metadata ---
    # Extract post-processed GRanges to build metadata
    regions_gr <- mg\$get_regions()
    
    bed_names <- names(regions_gr)
    if (is.null(bed_names)) {
      if (!is.null(regions_gr\$region_name)) {
        bed_names <- regions_gr\$region_name
      } else {
        bed_names <- paste0("region_", seq_along(regions_gr))
      }
    }
    
    demo_metadata = data.frame(BedName=bed_names,
                               EvenStart=ifelse((start(regions_gr) %% 2) == 0, "Even", "Odd"),
                               Strand=strand(regions_gr))
    
    # Re-initialize metagene2 object with region metadata
    mg <- metagene2\$new(regions = regions,
                       region_metadata=demo_metadata,
                       bam_files = bam_files,
                       assay='chipseq')
    
    # Produce and save metagene plot split by metadata
    pdf("metagene_plot_metadata.pdf")
    print(mg\$produce_metagene(split_by=c("EvenStart", "Strand"), facet_by=EvenStart~Strand, group_by="design"))
    dev.off()
    
    # Save meaningful results
    # Save the final data frame of calculated coverages and confidence intervals
    df_results <- mg\$add_metadata()
    write.csv(df_results, "metagene_analysis_results.csv", row.names = FALSE)
    
    # Save the metagene2 object
    saveRDS(mg, "metagene_analysis_object.rds")

    writeLines(c(
        '"BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS":',
        paste0('    metagene2: ', as.character(packageVersion('metagene2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_metagene_analysis.csv versions.yml
    """
}

workflow BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files, regions ] ]

    main:
    BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS.out.tables
    plots    = BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS.out.plots
    objects  = BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS.out.objects
    versions = BIOC_METAGENE2_CHIPSEQ_METAGENE_ANALYSIS.out.versions
}
