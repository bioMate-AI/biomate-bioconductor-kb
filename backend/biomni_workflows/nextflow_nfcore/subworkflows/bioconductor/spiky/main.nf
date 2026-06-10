#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spiky — cfmedip_quant_bedpe
// Perform absolute quantification and bias adjustment of cfMeDIP-seq data using BEDPE input files.
// Input: genomic_bedpe.bed.gz, genomic_bedpe.bed.gz.tbi, spike_bedpe.bed.gz, spike_bedpe.bed.gz.tbi
// Container: quay.io/biocontainers/bioconductor-spiky:1.16.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPIKY_CFMEDIP_QUANT_BEDPE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spiky:1.16.0--r45hdfd78af_0"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(spiky)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Define input file paths from the working directory
    genomic_bedpe_path <- "genomic_bedpe.bed.gz"
    spike_bedpe_path <- "spike_bedpe.bed.gz"
    
    # Verify input files exist
    if (!file.exists(genomic_bedpe_path)) {
      stop(paste("Required genomic BEDPE file missing:", genomic_bedpe_path))
    }
    if (!file.exists(spike_bedpe_path)) {
      stop(paste("Required spike BEDPE file missing:", spike_bedpe_path))
    }
    
    # Load the reference spike-in database from the package namespace
    spike <- spiky::spike
    
    # 1. Scan genomic BEDPE to get genomic coverage
    message("Scanning genomic BEDPE...")
    genomic_coverage <- scan_genomic_bedpe(genomic_bedpe_path, genome="hg38")
    
    # 2. Scan spike-in BEDPE to get spike coverage
    message("Scanning spike BEDPE...")
    spikes_coverage <- scan_spike_bedpe(spike_bedpe_path, spike=spike)
    
    # 3. Calculate methylation specificity
    message("Calculating methylation specificity...")
    methyl_spec <- methylation_specificity(spikes_coverage, spike=spike)
    print(methyl_spec)
    
    # 4. Fit Gaussian GLM on spike-in data
    message("Fitting Gaussian GLM...")
    gaussian_glm <- model_glm_pmol(spikes_coverage, spike=spike)
    print(summary(gaussian_glm))
    
    # 5. Predict molar concentration (pmol) for genomic regions
    message("Predicting pmol concentration...")
    sample_data_pmol <- predict_pmol(gaussian_glm, genomic_coverage, bsgenome="BSgenome.Hsapiens.UCSC.hg38", ret="df")
    print(head(sample_data_pmol, n=1))
    
    # 6. Bin and adjust molar concentration into genomic windows
    message("Binning pmol concentration...")
    sample_binned_data <- bin_pmol(sample_data_pmol)
    print(head(sample_binned_data, n=1))
    
    # Save results to output files
    message("Saving outputs...")
    saveRDS(methyl_spec, "methylation_specificity.rds")
    write.table(as.data.frame(methyl_spec), "methylation_specificity.txt", sep="\t", quote=FALSE, row.names=TRUE)
    
    saveRDS(gaussian_glm, "gaussian_glm.rds")
    sink("glm_summary.txt")
    print(summary(gaussian_glm))
    sink()
    
    write.csv(sample_data_pmol, "sample_data_pmol.csv", row.names=TRUE)
    saveRDS(sample_data_pmol, "sample_data_pmol.rds")
    
    write.csv(sample_binned_data, "sample_binned_data.csv", row.names=TRUE)
    saveRDS(sample_binned_data, "sample_binned_data.rds")
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SPIKY_CFMEDIP_QUANT_BEDPE":
        spiky: \$(Rscript -e 'cat(as.character(packageVersion("spiky")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfmedip_quant_bedpe.csv versions.yml
    """
}

workflow BIOC_SPIKY_CFMEDIP_QUANT_BEDPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_bedpe.bed.gz, genomic_bedpe.bed.gz.tbi, spike_bedpe.bed.gz, spike_bedpe.bed.gz.tbi ] ]

    main:
    BIOC_SPIKY_CFMEDIP_QUANT_BEDPE(ch_input)

    emit:
    tables   = BIOC_SPIKY_CFMEDIP_QUANT_BEDPE.out.tables
    plots    = BIOC_SPIKY_CFMEDIP_QUANT_BEDPE.out.plots
    objects  = BIOC_SPIKY_CFMEDIP_QUANT_BEDPE.out.objects
    versions = BIOC_SPIKY_CFMEDIP_QUANT_BEDPE.out.versions
}
