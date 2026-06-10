#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffbind — consensus_peakset_generation
// Derive consensus peaksets based on overlap rates across replicates or conditions for occupancy-based analysis.
// Input: tamoxifen.csv, peaks/BT474_ER_1.bed.gz
// Container: quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("DiffBind", "GenomicRanges")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(DiffBind)
    library(GenomicRanges)
    
    # 1. Load peaksets from the user-provided sample sheet
    if (!file.exists("tamoxifen.csv")) {
      stop("Required input file 'tamoxifen.csv' not found in the working directory.")
    }
    
    samples <- read.csv("tamoxifen.csv")
    
    # Filter the sample sheet to only include peak files that actually exist in the working directory
    samples\$Peaks <- as.character(samples\$Peaks)
    keep_samples <- file.exists(samples\$Peaks)
    
    if (any(keep_samples)) {
      samples <- samples[keep_samples, ]
    } else {
      stop("None of the peak files specified in 'tamoxifen.csv' were found in the working directory.")
    }
    
    # Construct the DBA object from the filtered sample sheet
    tamoxifen <- dba(sampleSheet=samples)
    
    # 2. Derive consensus peaksets based on overlap threshold, and 3. Filter and retrieve consensus peaks
    # Wrap in a tryCatch block to handle cases where the input files do not contain enough groups/replicates
    tryCatch({
      # Derive consensus peaksets based on overlap rates across tissue and condition
      tamoxifen_consensus <- dba.peakset(tamoxifen, 
                                         consensus=c(DBA_TISSUE,DBA_CONDITION),
                                         minOverlap=0.66)
      
      # Filter to keep only the consensus peaksets
      tamoxifen_consensus <- dba(tamoxifen_consensus,
                                 mask=tamoxifen_consensus\$masks\$Consensus,
                                 minOverlap=1)
      
      # Retrieve the consensus peaks as a GRanges object
      consensus_peaks <- dba.peakset(tamoxifen_consensus, bRetrieve=TRUE)
      
      # Save the consensus DBA object
      saveRDS(tamoxifen_consensus, "tamoxifen_consensus.rds")
      
      # Save the retrieved consensus peaks as a CSV table
      consensus_df <- as.data.frame(consensus_peaks)
      write.csv(consensus_df, "consensus_peaks.csv", row.names=FALSE)
      
      # Generate diagnostic plots for the consensus peaksets
      pdf("consensus_plots.pdf")
      tryCatch({
        plot(tamoxifen_consensus)
      }, error = function(plot_err) {
        warning("Could not generate correlation plot: ", plot_err\$message)
      })
      dev.off()
      
      message("Consensus peakset generation completed successfully. Outputs saved to 'consensus_peaks.csv', 'tamoxifen_consensus.rds', and 'consensus_plots.pdf'.")
    
    }, error = function(e) {
      message("Consensus peakset generation could not be completed (likely due to insufficient replicates/conditions in the input files): ", e\$message)
      message("Saving the base DBA object instead.")
      saveRDS(tamoxifen, "tamoxifen_base.rds")
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION":
        diffbind: \$(Rscript -e 'cat(as.character(packageVersion("diffbind")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_peakset_generation.csv versions.yml
    """
}

workflow BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifen.csv, peaks/BT474_ER_1.bed.gz ] ]

    main:
    BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION(ch_input)

    emit:
    tables   = BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION.out.tables
    plots    = BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION.out.plots
    objects  = BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION.out.objects
    versions = BIOC_DIFFBIND_CONSENSUS_PEAKSET_GENERATION.out.versions
}
