#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fccac — fccac_covariance_analysis
// Evaluate covariance and reproducibility across multiple NGS datasets using functional canonical correlation analysis and visualize the results as a heatmap.
// Input: peakFile.bed, bigwig1.bw, bigwig2.bw, bigwig3.bw
// Container: quay.io/biocontainers/bioconductor-fccac:1.36.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-fccac:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("fccac")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # 1. Load the fCCAC package and define paths to the bigWig and peak files
    library(fCCAC)
    
    # Define input files from the working directory as specified by the user
    peakFile <- "peakFile.bed"
    bigwig1  <- "bigwig1.bw"
    bigwig2  <- "bigwig2.bw"
    bigwig3  <- "bigwig3.bw"
    
    # Verify that the required input files exist before proceeding
    inputs <- c(peakFile, bigwig1, bigwig2, bigwig3)
    missing_files <- inputs[!file.exists(inputs)]
    if (length(missing_files) > 0) {
      stop(paste("Required input file(s) missing in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # Windows OS restriction check (rtracklayer bigWig reading limitation)
    if (.Platform\$OS.type == "windows") {
      stop("fCCAC relies on rtracklayer's bigWig import, which is not supported on Windows.")
    }
    
    # Define labels and title for the analysis
    labels <- c("Dataset1", "Dataset2", "Dataset3")
    ti <- "fCCAC Covariance Analysis"
    
    # 2. Run the functional canonical correlation analysis using fccac()
    # Keeping all documented argument names exactly as specified
    fc <- fccac(
      bar = NULL, 
      main = ti, 
      peaks = peakFile, 
      bigwigs = c(bigwig1, bigwig2, bigwig3), 
      labels = labels, 
      splines = 15, 
      nbins = 100, 
      ncan = 15
    )
    
    # 3. Inspect the resulting correlation and F-value data frame
    print("Head of fCCAC results:")
    print(head(fc))
    
    # Save the resulting data frame to a CSV file
    write.csv(fc, file = "fccac_covariance_results.csv", row.names = FALSE)
    
    # Save the fCCAC object as an RDS file for downstream analysis
    saveRDS(fc, file = "fccac_results.rds")
    
    # 4. Plot a heatmap of the F-values using heatmapfCCAC() and save as PDF
    pdf("fccac_heatmap.pdf", width = 7, height = 7)
    heatmapfCCAC(fc)
    dev.off()
    
    print("Analysis complete. Results saved to 'fccac_covariance_results.csv', 'fccac_results.rds', and 'fccac_heatmap.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS":
        fccac: \$(Rscript -e 'cat(as.character(packageVersion("fccac")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fccac_covariance_analysis.csv versions.yml
    """
}

workflow BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peakFile.bed, bigwig1.bw, bigwig2.bw, bigwig3.bw ] ]

    main:
    BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS.out.tables
    plots    = BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS.out.plots
    objects  = BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS.out.objects
    versions = BIOC_FCCAC_FCCAC_COVARIANCE_ANALYSIS.out.versions
}
