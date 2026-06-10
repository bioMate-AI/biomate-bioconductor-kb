#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: process — individual_spectrum_alignment
// Process individual mass spectrometry files, normalize them, detect peaks, assess quality, and align peaks across spectra to identify proto-biomarkers.
// Input: testdir
// Container: quay.io/biocontainers/bioconductor-process:1.86.0--r45hdfd78af_0
// R packages: PROcess
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-process:1.86.0--r45hdfd78af_0"

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
    .bm_deps <- c("PROcess")
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
    
    # Load the required Bioconductor package
    library(PROcess)
    
    # Define the input directory containing raw mass spectrometry CSV files
    testdir <- "testdir"
    
    # Robustness check: Ensure the input directory exists and contains files
    if (!dir.exists(testdir)) {
      stop(paste("Error: Input directory '", testdir, "' does not exist in the working directory.", sep = ""))
    }
    
    csv_files <- list.files(testdir, pattern = "\\\\.csv\$", full.names = TRUE)
    if (length(csv_files) == 0) {
      stop(paste("Error: No CSV files found in '", testdir, "'.", sep = ""))
    }
    
    # 1. Baseline subtraction of raw spectra using rmBaseline
    message("Performing baseline subtraction...")
    testM <- rmBaseline(testdir)
    
    # 2. Renormalization of spectra using renorm
    message("Renormalizing spectra...")
    rtM <- renorm(testM, cutoff = 1500)
    
    # Define output file paths
    peakfile <- "testpeakinfo.csv"
    bmkfile <- "testbiomarker.csv"
    quality_file <- "quality_assessment.csv"
    plot_file <- "proto_biomarkers_plot.pdf"
    normalized_spectra_file <- "normalized_spectra.rds"
    biomarkers_rds_file <- "proto_biomarkers.rds"
    
    # 3. Peak identification in individual spectra using getPeaks
    message("Identifying peaks...")
    getPeaks(rtM, peakfile)
    
    # 4. Quality assessment of spectra using quality
    message("Assessing quality...")
    qualRes <- quality(testM, peakfile, cutoff = 1500)
    print(qualRes)
    
    # Save quality assessment results
    write.csv(qualRes, file = quality_file, row.names = TRUE)
    
    # 5. Peak alignment and proto-biomarker identification using pk2bmkr
    message("Aligning peaks and identifying proto-biomarkers...")
    testBio <- pk2bmkr(peakfile, rtM, bmkfile)
    
    # Save processed objects
    saveRDS(rtM, file = normalized_spectra_file)
    saveRDS(testBio, file = biomarkers_rds_file)
    
    # Extract m/z values of the proto-biomarkers
    bks <- getMzs(testBio)
    message("Identified proto-biomarkers (rounded m/z):")
    print(round(bks))
    
    # Save the list of biomarker m/z values
    writeLines(as.character(round(bks)), "biomarker_mzs.txt")
    
    # Generate and save the visualization plot
    message("Generating plot...")
    pdf(plot_file, width = 10, height = 7)
    mzs <- as.numeric(rownames(rtM))
    matplot(mzs, rtM, type = "l", xlim = c(1000, 10000),
            ylab = "intensities", main = "proto-biomarkers")
    abline(v = bks, col = "green")
    dev.off()
    
    message("Pipeline completed successfully. Outputs generated:")
    message("- ", peakfile)
    message("- ", bmkfile)
    message("- ", quality_file)
    message("- ", plot_file)
    message("- ", normalized_spectra_file)
    message("- ", biomarkers_rds_file)
    message("- biomarker_mzs.txt")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT":
        process: \$(Rscript -e 'cat(as.character(packageVersion("process")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_individual_spectrum_alignment.csv versions.yml
    """
}

workflow BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testdir ] ]

    main:
    BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT.out.tables
    plots    = BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT.out.plots
    objects  = BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT.out.objects
    versions = BIOC_PROCESS_INDIVIDUAL_SPECTRUM_ALIGNMENT.out.versions
}
