#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ontoProc
// Support harvesting of diverse bioinformatic ontologies, making particular use of the ontologyIndex p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ontoProc/inst/doc/owlents.R
// Upstream  : none
// Downstream: SingleRBook
//
// Install: BiocManager::install("ontoProc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONTOPROC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ontoproc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ontoproc:2.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ontoproc:2.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ontoproc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ontoproc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ontoproc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ontoProc)
    library(jsonlite)

    # --- Cell Ontology Visualization [] ---
    # Key functions: onto_plot2
    sel <- c("CL_0000492", "CL_0001054", "CL_0000236", "CL_0000625")
    onto_plot2(cle, sel)


    # --- Human Phenotype Ontology Processing [] ---
    # Key functions: owl2cache, setup_entities2, onto_plot2
    hpont_path <- owl2cache(url = "http://purl.obolibrary.org/obo/hp.owl")
    hpents <- setup_entities2(hpont_path)
    kp <- grep("UBER", names(hpents$name), value = TRUE)[21:30]
    onto_plot2(hpents, kp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ontoproc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ontoproc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ontoproc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ONTOPROC:", paste0("    ontoproc: ", packageVersion("ontoProc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ontoproc_results.csv
    touch ${prefix}_ontoproc_output.rds
    echo "BIOC_ONTOPROC:" > versions.yml
    echo "    ontoproc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ONTOPROC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ONTOPROC(ch_input)

    emit:
    results  = BIOC_ONTOPROC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ONTOPROC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ONTOPROC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ONTOPROC.out.versions  // channel: path(versions.yml)
}
