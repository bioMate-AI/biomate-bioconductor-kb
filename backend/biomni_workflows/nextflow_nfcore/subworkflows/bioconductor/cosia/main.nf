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
    library(CoSIA)
    library(CoSIAn)
    library(jsonlite)

    # --- Initialize Cross-Species Analysis [] ---
    # Key functions: CoSIAn
    cosian_obj <- CoSIA::CoSIAn(
        gene_set = c("PKD1", "PKD2", "UMOD", "HNF1B"),
        i_species = "h_sapiens",
        o_species = c("h_sapiens", "r_norvegicus"),
        input_id = "Symbol",
        output_ids = "Ensembl_id",
        map_species = c("h_sapiens", "r_norvegicus"),
        map_tissues = c("adult mammalian kidney", "heart"),
        mapping_tool = "annotationDBI",
        ortholog_database = "HomoloGene",
        metric_type = "CV_Species"
    )


    # --- Convert Identifiers and Map Orthologs [] ---
    # Key functions: getConversion, viewCoSIAn
    cosian_converted <- CoSIA::getConversion(
        CoSIAn_obj = cosian_obj
    )
    mapped_ids <- CoSIA::viewCoSIAn(
        CoSIAn_obj = cosian_converted,
        slot_name = "converted_id"
    )

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
