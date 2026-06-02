#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: consensusSeekeR
// This package compares genomic positions and genomic ranges from multiple experiments to extract comm
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/consensusSeekeR/inst/doc/consensusSeekeR.R
// Upstream  : GenomeInfoDb, GenomicRanges, ggplot2, knitr, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("consensusSeekeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CONSENSUSSEEKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-consensusseeker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-consensusseeker:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-consensusseeker:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_consensusseeker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_consensusseeker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_consensusseeker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(consensusSeekeR)
    library(Seqinfo)
    library(jsonlite)

    # --- Data Loading and Formatting [] ---
    # Key functions: readNarrowPeakFile
    file_narrowPeak <- system.file("extdata",
        "A549_FOSL2_ENCSR000BQO_MZW_part_chr_1_and_12.narrowPeak",
        package = "consensusSeekeR")
    result <- readNarrowPeakFile(file_narrowPeak,
                                 extractRegions = TRUE,
                                 extractPeaks = TRUE)
    regions <- result$narrowPeak
    peaks <- result$peak

    # --- Genome Information Setup [] ---
    # Key functions: Seqinfo
    chrList <- GenomeInfoDb::Seqinfo(seqnames = "chr1",
                                     seqlengths = 135534747,
                                     isCircular = NA)

    # --- Consensus Peak Identification [] ---
    # Key functions: findConsensusPeakRegions
    data(NOrMAL_nucleosome_positions)
    data(NOrMAL_nucleosome_ranges)
    data(PING_nucleosome_positions)
    data(PING_nucleosome_ranges)
    names(NOrMAL_nucleosome_positions) <- rep("NOrMAL",
        length(NOrMAL_nucleosome_positions))
    names(NOrMAL_nucleosome_ranges) <- rep("NOrMAL",
        length(NOrMAL_nucleosome_ranges))
    names(PING_nucleosome_positions) <- rep("PING",
        length(PING_nucleosome_positions))
    names(PING_nucleosome_ranges) <- rep("PING",
        length(PING_nucleosome_ranges))
    chrList <- GenomeInfoDb::Seqinfo("chr1", 135534747, NA)
    results <- findConsensusPeakRegions(
        narrowPeaks = c(NOrMAL_nucleosome_ranges, PING_nucleosome_ranges),
        peaks = c(NOrMAL_nucleosome_positions, PING_nucleosome_positions),
        chrInfo = chrList,
        extendingSize = 25,
        expandToFitPeakRegion = TRUE,
        shrinkToFitPeakRegion = TRUE,
        minNbrExp = 2,
        nbrThreads = 1)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_consensusseeker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_consensusseeker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_consensusseeker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CONSENSUSSEEKER:", paste0("    consensusseeker: ", packageVersion("consensusSeekeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensusseeker_results.csv
    touch ${prefix}_consensusseeker_output.rds
    echo "BIOC_CONSENSUSSEEKER:" > versions.yml
    echo "    consensusseeker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CONSENSUSSEEKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CONSENSUSSEEKER(ch_input)

    emit:
    results  = BIOC_CONSENSUSSEEKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CONSENSUSSEEKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CONSENSUSSEEKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CONSENSUSSEEKER.out.versions  // channel: path(versions.yml)
}
