#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NanoStringNCTools
// Tools for NanoString Technologies nCounter Technology. Provides support for reading RCC files into a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NanoStringNCTools/inst/doc/Introduction.R
// Upstream  : ggiraph, ggthemes, pheatmap
// Downstream: GeomxTools, GeoMxWorkflows
//
// Install: BiocManager::install("NanoStringNCTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NANOSTRINGNCTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nanostringnctools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nanostringnctools:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nanostringnctools:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nanostringnctools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nanostringnctools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nanostringnctools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NanoStringNCTools)
    library(jsonlite)

    # --- Design [] ---
    # Key functions: design, dimLabels, protocolData, sampleNames
    ---------------------------------------------------------------------
    # assign design information
    design(demoData) <- ~ `Treatment`
    design(demoData)
    # check the column names to use as labels for the features and samples respectively
    # --- Head [] ---
    # Key functions: sData
    ---------------------------------------------------------------------
    # summarize log2 counts for each feature
    head(summary(demoData, MARGIN = 1), 2)
    # summarize log2 counts for each sample
    head(summary(demoData, MARGIN = 2), 2)
    # --- Negativecontrolsubset [] ---
    # Key functions: negativeControlSubset
    ---------------------------------------------------------------------
    neg_set <- negativeControlSubset(demoData)
    class(neg_set)
    # --- Assaydataelement [] ---
    # Key functions: assayDataElement, assayDataApply, esBy
    ---------------------------------------------------------------------
    # calculate the log counts of gene expressions for each sample
    assayDataElement(demoData, "demoElem") <-
      assayDataApply(demoData, MARGIN=2, FUN=log, base=10, elt="exprs")
    assayDataElement(demoData, "demoElem")[1:3, 1:2]
    # --- Girafe [] ---
    # Key functions: girafe, autoplot, featureNames
    ---------------------------------------------------------------------
    girafe( ggobj = autoplot( demoData , "boxplot-feature" , index = featureNames(demoData)[3] , elt = "exprs" ) )
    autoplot( demoData , "heatmap-genes" , elt = "exprs_norm" )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nanostringnctools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nanostringnctools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nanostringnctools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NANOSTRINGNCTOOLS:", paste0("    nanostringnctools: ", packageVersion("NanoStringNCTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nanostringnctools_results.csv
    touch ${prefix}_nanostringnctools_output.rds
    echo "BIOC_NANOSTRINGNCTOOLS:" > versions.yml
    echo "    nanostringnctools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NANOSTRINGNCTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NANOSTRINGNCTOOLS(ch_input)

    emit:
    results  = BIOC_NANOSTRINGNCTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NANOSTRINGNCTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NANOSTRINGNCTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NANOSTRINGNCTOOLS.out.versions  // channel: path(versions.yml)
}
