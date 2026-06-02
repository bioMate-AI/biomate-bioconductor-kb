#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNVPanelizer
// A method that allows for the use of a collection of non-matched normal tissue samples. Our approach 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNVPanelizer/inst/doc/CNVPanelizer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CNVPanelizer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNVPANELIZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnvpanelizer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnvpanelizer:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnvpanelizer:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnvpanelizer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnvpanelizer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnvpanelizer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNVPanelizer)
    library(jsonlite)


    # --- Loading Synthetic Data [] ---
    # Key functions: row.names
    data(sampleReadCounts)
    data(referenceReadCounts)

    # Gene names should be same size as row columns
    # For real data this is a vector of the genes associated
    # with each row/amplicon. For example Gene1, Gene1, Gene2, Gene2, Gene3, ...
    geneNames <- row.names(referenceReadCounts)

    # Not defined for synthetic data
    # For real data this gives a unique name to each amplicon.

    # --- Normalized Read Counts [] ---
    # Key functions: CombinedNormalizedCounts, samples, reference
    normalizedReadCounts <- CombinedNormalizedCounts(sampleReadCounts,
                                                     referenceReadCounts,
                                                     ampliconNames = ampliconNames)

    # After normalization data sets need to be splitted again to perform bootstrap
    samplesNormalizedReadCounts = normalizedReadCounts["samples"][[1]]
    referenceNormalizedReadCounts = normalizedReadCounts["reference"][[1]]

    # --- Number Of Replicates [] ---
    # Key functions: cnvpanelizer
    # Number of bootstrap replicates to be used
    replicates <- 10000

    # --- Boot List [] ---
    # Key functions: BootList
    # Perform the bootstrap based analysis
    bootList <- BootList(geneNames,
                         samplesNormalizedReadCounts,
                         referenceNormalizedReadCounts,
                         replicates = replicates)

    # --- Background Noise [] ---
    # Key functions: Background
    # Estimate the background noise left after normalization
    backgroundNoise <- Background(geneNames,
                                  samplesNormalizedReadCounts,
                                  referenceNormalizedReadCounts,
                                  bootList,
                                  replicates = replicates,
                                  significanceLevel = 0.1,
                                  robust = TRUE)

    # --- Report Tables [] ---
    # Key functions: ReportTables
    # Build report tables
    reportTables <- ReportTables(geneNames,
                                 samplesNormalizedReadCounts,
                                 referenceNormalizedReadCounts,
                                 bootList,
                                 backgroundNoise)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnvpanelizer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnvpanelizer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnvpanelizer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNVPANELIZER:", paste0("    cnvpanelizer: ", packageVersion("CNVPanelizer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnvpanelizer_results.csv
    touch ${prefix}_cnvpanelizer_output.rds
    echo "BIOC_CNVPANELIZER:" > versions.yml
    echo "    cnvpanelizer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNVPANELIZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNVPANELIZER(ch_input)

    emit:
    results  = BIOC_CNVPANELIZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNVPANELIZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNVPANELIZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNVPANELIZER.out.versions  // channel: path(versions.yml)
}
