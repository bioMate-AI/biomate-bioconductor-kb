#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RJMCMCNucleosomes
// This package does nucleosome positioning using informative Multinomial-Dirichlet prior in a t-mixtur
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RJMCMCNucleosomes/inst/doc/RJMCMCNucleosomes.R
// Upstream  : GenomicRanges, nucleoSim
// Downstream: none
//
// Install: BiocManager::install("RJMCMCNucleosomes")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RJMCMCNUCLEOSOMES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rjmcmcnucleosomes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rjmcmcnucleosomes:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rjmcmcnucleosomes:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rjmcmcnucleosomes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rjmcmcnucleosomes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rjmcmcnucleosomes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GRangesList)
    library(jsonlite)

    # --- synthetic Nuc Reads From Dist [] ---
    # Key functions: syntheticNucReadsFromDist
    library(nucleoSim)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, segmentation
    library(GenomicRanges)
    # --- rjmcmc [] ---
    # Key functions: rjmcmc

    # --- merge All R D S Files From Directory [] ---
    # Key functions: mergeAllRDSFilesFromDirectory

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, postTreatment
    reads <- GRanges(sample$dataIP)
    resultsPostTreatment <- postTreatment(reads = reads,
    chrLength = max(start(reads), end(reads)) + 1000)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, GRangesList, plotNucleosomes
    reads <-GRanges(sample$dataIP)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, seqnames, rjmcmcCHR
    data(syntheticNucleosomeReads)
    nrow(syntheticNucleosomeReads$dataIP)
    sampleGRanges <- GRanges(syntheticNucleosomeReads$dataIP)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rjmcmcnucleosomes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rjmcmcnucleosomes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rjmcmcnucleosomes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RJMCMCNUCLEOSOMES:", paste0("    rjmcmcnucleosomes: ", packageVersion("RJMCMCNucleosomes"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rjmcmcnucleosomes_results.csv
    touch ${prefix}_rjmcmcnucleosomes_output.rds
    echo "BIOC_RJMCMCNUCLEOSOMES:" > versions.yml
    echo "    rjmcmcnucleosomes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RJMCMCNUCLEOSOMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RJMCMCNUCLEOSOMES(ch_input)

    emit:
    results  = BIOC_RJMCMCNUCLEOSOMES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RJMCMCNUCLEOSOMES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RJMCMCNUCLEOSOMES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RJMCMCNUCLEOSOMES.out.versions  // channel: path(versions.yml)
}
