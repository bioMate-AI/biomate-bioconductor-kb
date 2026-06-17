#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DiffBind — occupancy_and_consensus
// Analyze peak overlaps across replicates and conditions to derive consensus peaksets.
// Input: tamoxifen.csv, BED/Peak files
// Container: quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0
// R packages: DiffBind
// Bioconductor: 3.20 | R: 4.4
// Requires: DiffBind
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load peaksets using dba
//  * 2. [Core Analysis] Calculate overlap rates using dba.overlap
//  * 3. [Core Analysis] Derive consensus peaksets based on metadata factors using dba.peakset
//  * 4. [Visualization & Output] Plot overlaps using dba.plotVenn

nextflow.enable.dsl = 2

process BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("DiffBind")
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
    
    # Load the required library
    library(DiffBind)
    
    # 1. Load peaksets using dba from the user-provided sample sheet
    tamoxifen <- dba(sampleSheet="tamoxifen.csv")
    
    # 2. Calculate overlap rates using dba.overlap
    olap.rate <- dba.overlap(tamoxifen, mode=DBA_OLAP_RATE)
    
    # 3. Derive consensus peaksets based on metadata factors using dba.peakset
    tamoxifen_consensus <- dba.peakset(tamoxifen, consensus=c(DBA_TISSUE, DBA_CONDITION), minOverlap=0.66)
    tamoxifen_consensus <- dba(tamoxifen_consensus, mask=tamoxifen_consensus\$masks\$Consensus, minOverlap=1)
    consensus_peaks <- dba.peakset(tamoxifen_consensus, bRetrieve=TRUE)
    
    # 4. Plot overlaps using dba.plotVenn and save plots to PDF
    pdf("occupancy_and_consensus_plots.pdf", width=8, height=8)
    
    # Plot overlap rate
    tryCatch({
      plot(olap.rate, type='b', ylab='# peaks', xlab='Overlap at least this many peaksets')
    }, error = function(e) {
      warning("Could not plot overlap rate: ", e\$message)
    })
    
    # Plot Venn diagram of the consensus peaksets
    tryCatch({
      dba.plotVenn(tamoxifen_consensus, tamoxifen_consensus\$masks\$Consensus)
    }, error = function(e) {
      warning("Could not plot Venn diagram for consensus: ", e\$message)
    })
    
    dev.off()
    
    # Write named output files for the meaningful results
    saveRDS(olap.rate, "overlap_rate.rds")
    saveRDS(tamoxifen_consensus, "tamoxifen_consensus.rds")
    saveRDS(consensus_peaks, "consensus_peaks.rds")
    
    # Export consensus peaks as a CSV table
    if (inherits(consensus_peaks, "GRanges")) {
      write.csv(as.data.frame(consensus_peaks), "consensus_peaks.csv", row.names=FALSE)
    } else {
      write.csv(consensus_peaks, "consensus_peaks.csv", row.names=FALSE)
    }

    writeLines(c(
        '"BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS":',
        paste0('    DiffBind: ', as.character(packageVersion('DiffBind')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_occupancy_and_consensus.csv versions.yml
    """
}

workflow BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifen.csv, BED/Peak files ] ]

    main:
    BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS(ch_input)

    emit:
    tables   = BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS.out.tables
    plots    = BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS.out.plots
    objects  = BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS.out.objects
    versions = BIOC_DIFFBIND_OCCUPANCY_AND_CONSENSUS.out.versions
}
