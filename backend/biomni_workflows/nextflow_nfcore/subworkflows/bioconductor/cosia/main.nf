#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CoSIA
// Cross-Species Investigation and Analysis (CoSIA) is a package that provides researchers with an alte
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CoSIA/inst/doc/CoSIA_Intro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CoSIA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COSIA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cosia"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cosia:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cosia:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cosia_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cosia_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cosia_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CoSIAn)
    library(jsonlite)

    # --- getTissues 1 [] ---
    # Key functions: getTissues
    CoSIA::getTissues("d_rerio")
    # --- getTissues 2 [] ---
    # Key functions: getTissues
    CoSIA::getTissues(c("m_musculus", "r_norvegicus"))
    # --- Co S I An [] ---
    # Key functions: CoSIAn

    # --- get Conversion [] ---
    # Key functions: getConversion
    CoSIAn_Obj_convert <- CoSIA::getConversion(CoSIAn_Obj)
    head(CoSIA::viewCoSIAn(CoSIAn_Obj_convert, "converted_id"))
    # --- use2 1 [] ---
    # Key functions: getGEx
    CoSIAn_Obj_gex <- CoSIA::getGEx(CoSIAn_Obj_convert)
    head(CoSIA::viewCoSIAn(CoSIAn_Obj_gex, "gex"), 5)
    # --- plot Species G Ex [] ---
    # Key functions: plotSpeciesGEx
    CoSIAn_Obj_gexplot <- CoSIA::plotSpeciesGEx(CoSIAn_Obj_gex, "adult mammalian kidney", "ENSG00000136463")
    # --- get G Ex Metrics [] ---
    # Key functions: getGExMetrics, plotCVGEx
    CoSIAn_Obj_CV <- CoSIA::getGExMetrics(CoSIAn_Obj_convert)
    CoSIAn_Obj_CVplot <- CoSIA::plotCVGEx(CoSIAn_Obj_CV)
    # --- Co S I An [] ---
    # Key functions: CoSIAn, getConversion, getGExMetrics, plotDSGEx


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cosia_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cosia_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cosia_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COSIA:", paste0("    cosia: ", packageVersion("CoSIA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosia_results.csv
    touch ${prefix}_cosia_output.rds
    echo "BIOC_COSIA:" > versions.yml
    echo "    cosia: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COSIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COSIA(ch_input)

    emit:
    results  = BIOC_COSIA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COSIA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COSIA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COSIA.out.versions  // channel: path(versions.yml)
}
