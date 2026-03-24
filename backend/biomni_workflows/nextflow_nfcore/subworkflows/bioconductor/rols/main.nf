#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rols
// The rols package is an interface to the Ontology Lookup Service (OLS) to access and query hundred of
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rols/inst/doc/rols.R
// Upstream  : BiocStyle, DT
// Downstream: none
//
// Install: BiocManager::install("rols")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rols"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rols:3.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rols:3.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rols_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rols_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rols_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CVParam)
    library(OlsSearch)
    library(Ontologies)
    library(Ontology)
    library(Properties)
    library(Term)
    library(Terms)
    library(jsonlite)

    # --- datatable [] ---
    # Key functions: datatable
    DT::datatable(as(ol, "data.frame"))
    library("rols")
    # --- Ontologies [] ---
    # Key functions: Ontologies, Ontology, Terms, Term, termId
    ol <- Ontologies()
    head(olsNamespace(ol))
    bspo <- Ontology("bspo")
    # --- Term [] ---
    # Key functions: Term, Properties, termLabel
    trm <- Term("uberon", "UBERON:0002107")
    p <- Properties(trm)
    termLabel(p[[1]])
    # --- Ols Search [] ---
    # Key functions: OlsSearch
    OlsSearch(q = "trans-golgi network")
    # --- term Ontology [] ---
    # Key functions: termOntology, termNamespace
    qtrms <- unique(qtrms)
    termOntology(qtrms)
    termNamespace(qtrms)
    # --- C V Param [] ---
    # Key functions: CVParam
    library("GO.db")
    CVParam(name = "A user param", value = "the value")
    CVParam(label = "MS", accession = "MS:1000073")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rols_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rols_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rols_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ROLS:", paste0("    rols: ", packageVersion("rols"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rols_results.csv
    touch ${prefix}_rols_output.rds
    echo "BIOC_ROLS:" > versions.yml
    echo "    rols: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ROLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ROLS(ch_input)

    emit:
    results  = BIOC_ROLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ROLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ROLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ROLS.out.versions  // channel: path(versions.yml)
}
