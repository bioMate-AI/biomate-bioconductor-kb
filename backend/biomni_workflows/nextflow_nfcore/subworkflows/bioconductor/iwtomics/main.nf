#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IWTomics
// Implementation of the Interval-Wise Testing (IWT) for omics data. This inferential procedure tests f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IWTomics/inst/doc/IWTomics.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IWTomics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IWTOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iwtomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iwtomics:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iwtomics:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iwtomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iwtomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iwtomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IWTomics)
    library(jsonlite)

    # --- Exploratory Visualization [] ---
    # Key functions: plot, lengthRegions
    plot(regionsFeatures, type='pairs')
    plot(regionsFeatures, type='pairsSmooth', col='violet')
    plot(
        regionsFeatures, type='curves',
        N_regions=lengthRegions(regionsFeatures),
        id_features_subset='ftr1'
    )


    # --- Interval-Wise Hypothesis Testing [] ---
    # Key functions: IWTomicsTest, adjusted_pval
    result1 <- IWTomicsTest(
        regionsFeatures, mu=c(0, 5),
        id_region1='control', id_region2='',
        id_features_subset=c('ftr1', 'ftr2')
    )
    result2_mean <- IWTomicsTest(
        regionsFeatures,
        id_region1=c('elem1', 'elem2', 'elem3'),
        id_region2=c('control', 'control', 'control')
    )
    pvals <- adjusted_pval(result2_mean)


    # --- Test Visualization and Summary [] ---
    # Key functions: plotTest, plotSummary
    plotTest(result2_mean, alpha=0.05, id_features_subset='ftr1')
    plotSummary(
        result2_mean, alpha=0.05,
        groupby='feature', align_lab='Center'
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iwtomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iwtomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iwtomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IWTOMICS:", paste0("    iwtomics: ", packageVersion("IWTomics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iwtomics_results.csv
    touch ${prefix}_iwtomics_output.rds
    echo "BIOC_IWTOMICS:" > versions.yml
    echo "    iwtomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IWTOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IWTOMICS(ch_input)

    emit:
    results  = BIOC_IWTOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IWTOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IWTOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IWTOMICS.out.versions  // channel: path(versions.yml)
}
