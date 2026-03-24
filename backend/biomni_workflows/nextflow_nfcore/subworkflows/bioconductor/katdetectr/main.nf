#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: katdetectr
// Kataegis refers to the occurrence of regional hypermutation and is a phenomenon observed in a wide r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/katdetectr/inst/doc/General_overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("katdetectr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KATDETECTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-katdetectr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-katdetectr:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-katdetectr:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_katdetectr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_katdetectr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_katdetectr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(katdetectr)
    library(jsonlite)

    # --- label = "Importing genomic variants" [] ---
    # Key functions: generateSyntheticData
    pathToVCF <- system.file(package = "katdetectr", "extdata/CPTAC_Breast.vcf")
    pathToMAF <- system.file(package = "katdetectr", "extdata/APL_primary.maf")
    In addition, we can generate synthetic genomic variants including kataegis foci using generateSyntheticData().
    # --- label = "Detection of kataegis foci" [] ---
    # Key functions: detectKataegis
    kdVCF <- detectKataegis(genomicVariants = pathToVCF)
    kdMAF <- detectKataegis(genomicVariants = pathToMAF, aggregateRecords = TRUE)
    kdSynthetic <- detectKataegis(genomicVariants = syntheticData)
    # --- label = "Overview of KatDetect objects" [] ---
    # Key functions: show
    summary(kdVCF)
    print(kdVCF)
    show(kdVCF)
    # --- label = "Retrieving information from KatDetect objects" [] ---
    # Key functions: getGenomicVariants, getSegments, getKataegisFoci, getInfo
    getGenomicVariants(kdVCF)
    getSegments(kdVCF)
    getKataegisFoci(kdVCF)
    # --- label = "Visualisation of KatDetect objects" [] ---
    # Key functions: rainfallPlot, as_tibble
    rainfallPlot(kdVCF)
    With showSegmentation, the detected segments (changepoints) as visualized with their mean IMD.
    rainfallPlot(kdMAF, showSegmentation = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_katdetectr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_katdetectr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_katdetectr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KATDETECTR:", paste0("    katdetectr: ", packageVersion("katdetectr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_katdetectr_results.csv
    touch ${prefix}_katdetectr_output.rds
    echo "BIOC_KATDETECTR:" > versions.yml
    echo "    katdetectr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KATDETECTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KATDETECTR(ch_input)

    emit:
    results  = BIOC_KATDETECTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KATDETECTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KATDETECTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KATDETECTR.out.versions  // channel: path(versions.yml)
}
