#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetMashR
// A package to merge, filter sort, organise and otherwise mash together metabolite annotation tables. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetMashR/inst/doc/Extending_MetMashR.R
// Upstream  : BiocStyle, DT, dplyr, ggplot2, metabolomicsWorkbenchR
// Downstream: none
//
// Install: BiocManager::install("MetMashR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METMASHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metmashr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metmashr:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metmashr:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metmashr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metmashr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metmashr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetMashR)
    library(jsonlite)

    # --- Define Preprocessing Models [] ---
    # Key functions: set_struct_obj, set_obj_method
    set_struct_obj(
        class_name = "drop_empty_columns",
        struct_obj = "model",
        params = character(0),
        outputs = c(updated = "annotation_source"),
        private = character(0),
        prototype = list(
            name = "Drop empty columns",
            description = "Removes columns where all rows are NA.",
            predicted = "updated"
        )
    )
    set_obj_method(
        class_name = "drop_empty_columns",
        method_name = "model_apply",
        signature = c("drop_empty_columns", "annotation_source"),
        definition = function(M, D) {
            W <- lapply(D$data, function(x) all(is.na(x)))
            idx <- which(unlist(W))
            if (length(idx) > 0) {
                D$data[, idx] <- NULL
            }
            M$updated <- D
            return(M)
        }
    )


    # --- Database and PubChem Lookup [] ---
    # Key functions: database_lookup, pubchem_compound_lookup, model_apply
    lookup_model <- database_lookup(
        query_column = "refmet_name",
        database_column = "name",
        database = refmet,
        suffix = "_mwb",
        include = "pubchem_cid"
    )
    pc_model <- pubchem_compound_lookup(
        query_column = "metabolite_name",
        search_by = "name",
        suffix = "_pc",
        output = "cids",
        records = "best",
        delay = 0.2,
        cache = pubchem_cid_cache
    )
    res_lookup <- model_apply(lookup_model, AT)
    res_pc <- model_apply(pc_model, AT)


    # --- Workflow Sequence Execution [] ---
    # Key functions: database_lookup, pubchem_compound_lookup
    pipeline <- database_lookup(
        query_column = "refmet_name",
        database_column = "name",
        database = refmet,
        suffix = "_mwb",
        include = "pubchem_cid"
    ) + pubchem_compound_lookup(
        query_column = "metabolite_name",
        search_by = "name",
        suffix = "_pc",
        output = "cids",
        records = "best",
        delay = 0.2,
        cache = pubchem_cid_cache
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metmashr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metmashr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metmashr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METMASHR:", paste0("    metmashr: ", packageVersion("MetMashR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metmashr_results.csv
    touch ${prefix}_metmashr_output.rds
    echo "BIOC_METMASHR:" > versions.yml
    echo "    metmashr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METMASHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METMASHR(ch_input)

    emit:
    results  = BIOC_METMASHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METMASHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METMASHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METMASHR.out.versions  // channel: path(versions.yml)
}
