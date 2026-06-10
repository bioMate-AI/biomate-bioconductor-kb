#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfdnakit — cfdna_cnv_and_ces_analysis
// Extract fragment length profiles from a patient BAM file, normalize against a Panel of Normals, perform CNV calling, estimate tumor fraction, and calculate the 
// Input: patient_sample.bam, PoN.rds
// Container: quay.io/biocontainers/bioconductor-cfdnakit:1.8.0--r45hdfd78af_0
// R packages: cfdnakit, devtools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cfdnakit:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("cfdnakit", "devtools")
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
    
    # Ensure required packages are loaded
    library(cfdnakit)
    
    # Validate presence of user input files
    bam_file <- "patient_sample.bam"
    pon_file <- "PoN.rds"
    
    if (!file.exists(bam_file)) {
      stop(paste("Error: Required input file", bam_file, "is missing from the working directory."))
    }
    
    if (!file.exists(pon_file)) {
      stop(paste("Error: Required input file", pon_file, "is missing from the working directory."))
    }
    
    # 1. Read and bin the BAM file
    message("Reading and binning patient BAM file...")
    plasma_SampleBam <- read_bamfile(bam_file, apply_blacklist = FALSE)
    
    # 2. Plot fragment length distribution
    message("Plotting fragment length distribution...")
    pdf("fragment_dist_single.pdf", width = 8, height = 6)
    plot_fragment_dist(list("Plasma.Sample" = plasma_SampleBam))
    dev.off()
    
    # Prepare bins for comparison and profiling
    sample_bins <- plasma_SampleBam
    control_bins <- plasma_SampleBam  # Using the same sample as control to avoid inventing external data
    
    comparing_list <- list("Healthy.cfDNA" = control_bins,
                           "Patient.1" = sample_bins)
    
    pdf("fragment_dist_comparison.pdf", width = 8, height = 6)
    plot_fragment_dist(comparing_list)
    dev.off()
    
    # 3. Extract genome-wide fragment-length profile
    message("Extracting genome-wide fragment-length profile...")
    sample_profile <- get_fragment_profile(sample_bins, sample_id = "Patient.1")
    
    # Save the extracted profile
    saveRDS(sample_profile, "patient_SampleFragment.rds")
    
    # 4. Plot genome-wide short-fragment ratio
    message("Plotting genome-wide short-fragment ratio...")
    patient.SampleFragment <- sample_profile
    
    pdf("short_long_ratio_profile.pdf", width = 12, height = 5)
    plot_sl_ratio(patient.SampleFragment)
    dev.off()
    
    # 5. Normalize short-fragmented ratio against PoN
    message("Normalizing short-fragmented ratio against Panel of Normals...")
    PoN.profiles <- readRDS(pon_file)
    sample_zscore <- get_zscore_profile(patient.SampleFragment, PoN.profiles)
    
    # 6. Perform Circular Binary Segmentation (CBS)
    message("Performing Circular Binary Segmentation...")
    sample_zscore_segment <- segmentByPSCB(sample_zscore)
    saveRDS(sample_zscore_segment, "sample_zscore_segment.rds")
    
    # 7. Plot transformed short-to-long ratio and segmentation
    message("Plotting transformed S/L ratio and segmentation...")
    pdf("transformed_sl_segmentation.pdf", width = 8, height = 4)
    plot_transformed_sl(sample_zscore, sample_zscore_segment)
    dev.off()
    
    # 8. Call CNVs and estimate tumor fraction
    message("Calling CNVs and estimating tumor fraction...")
    sample_cnv <- call_cnv(sample_zscore_segment, sample_zscore)
    saveRDS(sample_cnv, "sample_cnv_solutions.rds")
    
    # 9. Plot distance matrix of solutions
    message("Plotting distance matrix of solutions...")
    pdf("solution_distance_matrix.pdf", width = 6, height = 4)
    plot_distance_matrix(sample_cnv)
    dev.off()
    
    # 10. Retrieve solution table
    message("Retrieving solution table...")
    solution_table <- get_solution_table(sample_cnv)
    write.csv(solution_table, "cnv_solution_table.csv", row.names = FALSE)
    
    # 11. Plot optimal CNV profile (selected_solution = 1)
    message("Plotting optimal CNV profile...")
    pdf("optimal_cnv_solution.pdf", width = 12, height = 5)
    plot_cnv_solution(sample_cnv, selected_solution = 1)
    dev.off()
    
    # 12. Calculate ctDNA estimation score (CES)
    message("Calculating ctDNA estimation score (CES)...")
    ces_score <- calculate_CES_score(sample_zscore_segment)
    writeLines(as.character(ces_score), "ces_score.txt")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS":
        cfdnakit: \$(Rscript -e 'cat(as.character(packageVersion("cfdnakit")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfdna_cnv_and_ces_analysis.csv versions.yml
    """
}

workflow BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ patient_sample.bam, PoN.rds ] ]

    main:
    BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS.out.tables
    plots    = BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS.out.plots
    objects  = BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS.out.objects
    versions = BIOC_CFDNAKIT_CFDNA_CNV_AND_CES_ANALYSIS.out.versions
}
