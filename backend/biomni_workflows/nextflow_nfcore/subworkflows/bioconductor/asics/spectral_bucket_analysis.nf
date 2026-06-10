#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: asics — spectral_bucket_analysis
// Align and bin 1D 1H NMR spectra into buckets, and perform downstream statistical analysis directly on the bucketed intensities.
// Input: spectra_file.txt, design_file.txt
// Container: quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0
// R packages: ASICS
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("ASICS")
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
    library(ASICS)
    
    # Define input file paths
    spectra_file <- "spectra_file.txt"
    design_file <- "design_file.txt"
    
    # Check if input files exist
    if (!file.exists(spectra_file)) {
      stop(paste("Error: Input spectra file not found:", spectra_file))
    }
    if (!file.exists(design_file)) {
      stop(paste("Error: Input design file not found:", design_file))
    }
    
    # Read user input files
    # spectra_file.txt: spectra in columns, chemical shifts in rows (row names)
    spectra_data_txt <- read.table(spectra_file, header = TRUE, row.names = 1, check.names = FALSE)
    # design_file.txt: sample metadata with sample names in the first column
    design <- read.table(design_file, header = TRUE, check.names = FALSE)
    
    # 1. Align spectra using alignment
    message("Aligning spectra...")
    spectra_align <- alignment(spectra_data_txt)
    
    # 2. Bin spectra into buckets using binning
    message("Binning spectra...")
    spectra_bucket <- binning(spectra_align)
    
    # 3. Format bucketed data and merge with design metadata using formatForAnalysis
    message("Formatting data for analysis...")
    analysis_data_bucket <- formatForAnalysis(spectra_bucket, design = design, zero.threshold = 75)
    
    # 4. Perform OPLS-DA on buckets using oplsda with type.data = "buckets"
    message("Performing OPLS-DA on buckets...")
    resOPLSDA_buckets <- oplsda(analysis_data_bucket, condition = "condition", type.data = "buckets")
    
    # Save OPLS-DA text summary
    sink("oplsda_summary.txt")
    print(resOPLSDA_buckets)
    sink()
    
    # 5. Visualize bucket-level OPLS-DA results using plot with graph = "buckets"
    message("Generating OPLS-DA bucket plot...")
    pdf("oplsda_buckets_plot.pdf", width = 10, height = 7)
    plot(resOPLSDA_buckets, graph = "buckets")
    dev.off()
    
    # Save R objects for downstream use
    saveRDS(analysis_data_bucket, "analysis_data_bucket.rds")
    saveRDS(resOPLSDA_buckets, "resOPLSDA_buckets.rds")
    
    message("Pipeline completed successfully. Outputs saved: oplsda_summary.txt, oplsda_buckets_plot.pdf, analysis_data_bucket.rds, resOPLSDA_buckets.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS":
        asics: \$(Rscript -e 'cat(as.character(packageVersion("asics")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spectral_bucket_analysis.csv versions.yml
    """
}

workflow BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spectra_file.txt, design_file.txt ] ]

    main:
    BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS.out.tables
    plots    = BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS.out.plots
    objects  = BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS.out.objects
    versions = BIOC_ASICS_SPECTRAL_BUCKET_ANALYSIS.out.versions
}
