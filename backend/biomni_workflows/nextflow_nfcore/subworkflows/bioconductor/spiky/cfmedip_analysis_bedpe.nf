#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spiky — cfmedip_analysis_bedpe
// Perform absolute quantification and bias adjustment of cfMeDIP-seq data using BEDPE input files.
// Input: genomic_bedpe_path, spike_bedpe_path
// Container: quay.io/biocontainers/bioconductor-spiky:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, spiky
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, spiky
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load spike-in database
//  * 2. [Core Analysis] Scan genomic BEDPE coverage using scan_genomic_bedpe
//  * 3. [Core Analysis] Scan spike-in BEDPE coverage using scan_spike_bedpe
//  * 4. [Core Analysis] Calculate methylation specificity using methylation_specificity
//  * 5. [Core Analysis] Fit a Gaussian GLM using model_glm_pmol
//  * 6. [Core Analysis] Predict molar concentration using predict_pmol
//  * 7. [Core Analysis] Bin predicted concentrations into genomic windows using bin_pmol

nextflow.enable.dsl = 2

process BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "spiky")
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
    library(spiky)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Define user input file paths in the working directory
    genomic_bedpe_path <- "genomic_bedpe.bed.gz"
    spike_bedpe_path <- "spike_bedpe.bed.gz"
    
    # Verify input files exist
    if (!file.exists(genomic_bedpe_path)) {
      stop(paste("Required genomic BEDPE file missing:", genomic_bedpe_path))
    }
    if (!file.exists(spike_bedpe_path)) {
      stop(paste("Required spike-in BEDPE file missing:", spike_bedpe_path))
    }
    
    # 1. Load spike-in database
    spike <- spiky::spike
    
    # 2. Scan genomic BEDPE coverage
    genomic_coverage <- scan_genomic_bedpe(genomic_bedpe_path, genome="hg38")
    
    # 3. Scan spike-in BEDPE coverage
    spikes_coverage <- scan_spike_bedpe(spike_bedpe_path, spike=spike)
    
    # 4. Calculate methylation specificity
    methyl_spec <- methylation_specificity(spikes_coverage, spike=spike)
    print(methyl_spec)
    
    # 5. Fit a Gaussian GLM
    gaussian_glm <- model_glm_pmol(spikes_coverage, spike=spike)
    summary(gaussian_glm)
    
    # 6. Predict molar concentration
    sample_data_pmol <- predict_pmol(gaussian_glm, genomic_coverage, bsgenome="BSgenome.Hsapiens.UCSC.hg38", ret="df")
    head(sample_data_pmol, n=1)
    
    # 7. Bin predicted concentrations into genomic windows
    sample_binned_data <- bin_pmol(sample_data_pmol)
    head(sample_binned_data, n=1)
    
    # Write outputs to the working directory
    saveRDS(methyl_spec, "methylation_specificity.rds")
    writeLines(
      c(
        paste("Mean Methylation Specificity:", methyl_spec\$mean),
        paste("Median Methylation Specificity:", methyl_spec\$median)
      ),
      con = "methylation_specificity.txt"
    )
    
    saveRDS(gaussian_glm, "gaussian_glm.rds")
    sink("gaussian_glm_summary.txt")
    print(summary(gaussian_glm))
    sink()
    
    write.csv(sample_data_pmol, "sample_data_pmol.csv", row.names = TRUE)
    write.csv(sample_binned_data, "sample_binned_data.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE":',
        paste0('    spiky: ', as.character(packageVersion('spiky')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfmedip_analysis_bedpe.csv versions.yml
    """
}

workflow BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_bedpe_path, spike_bedpe_path ] ]

    main:
    BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE(ch_input)

    emit:
    tables   = BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE.out.tables
    plots    = BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE.out.plots
    objects  = BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE.out.objects
    versions = BIOC_SPIKY_CFMEDIP_ANALYSIS_BEDPE.out.versions
}
