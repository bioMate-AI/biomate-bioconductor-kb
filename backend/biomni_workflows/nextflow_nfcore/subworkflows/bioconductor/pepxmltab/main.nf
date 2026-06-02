#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pepXMLTab
// Parsing pepXML files based one XML package. The package tries to handle pepXML files generated from 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pepXMLTab/inst/doc/pepXMLTab.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pepXMLTab")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEPXMLTAB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pepxmltab"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pepxmltab:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pepxmltab:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_pepxmltab_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pepxmltab_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pepxmltab_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PSMfilter)
    library(jsonlite)

    # --- Peptab [] ---
    # Key functions: pepXML2tab
    #MyriMatch example
    pepxml <- system.file("extdata/pepxml", "Myrimatch.pepXML",
        package="pepXMLTab")
    tttt <- pepXML2tab(pepxml)
    tttt[1:2,]
    # --- Filter [] ---
    # Key functions: pepXML2tab, PSMfilter
    ## MyriMatch example
    pepxml <- system.file("extdata/pepxml", "Myrimatch.pepXML",
            package="pepXMLTab")
    tttt <- pepXML2tab(pepxml)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pepxmltab_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pepxmltab_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pepxmltab_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEPXMLTAB:", paste0("    pepxmltab: ", packageVersion("pepXMLTab"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pepxmltab_results.csv
    touch ${prefix}_pepxmltab_output.rds
    echo "BIOC_PEPXMLTAB:" > versions.yml
    echo "    pepxmltab: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEPXMLTAB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_PEPXMLTAB(ch_input)

    emit:
    results  = BIOC_PEPXMLTAB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEPXMLTAB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEPXMLTAB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEPXMLTAB.out.versions  // channel: path(versions.yml)
}
