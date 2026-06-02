#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GOstats
// A set of tools for interacting with GO and microarray data. A variety of basic manipulation tools fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GOstats/inst/doc/GOstatsForUnsupportedOrganisms.R
// Upstream  : AnnotationForge, GSEABase, RBGL, Rgraphviz, geneplotter
// Downstream: MineICA
//
// Install: BiocManager::install("GOstats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gostats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gostats:2.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gostats:2.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gostats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gostats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gostats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSEAGOHyperGParams)
    library(GSEAKEGGHyperGParams)
    library(GeneSetCollection)
    library(jsonlite)

    # --- Make GSC [] ---
    # Key functions: GeneSetCollection
    library("GSEABase")
    gsc <- GeneSetCollection(goAllFrame, setType = GOCollection())
    # --- make parameter [] ---
    # Key functions: GSEAGOHyperGParams
    library("GOstats")
    universe = Lkeys(org.Hs.egGO)
    params <- GSEAGOHyperGParams(name="My Custom GSEA based annot Params",
    # --- call HyperGTest [] ---
    # Key functions: hyperGTest
    Over <- hyperGTest(params)
    head(summary(Over))
    # --- KEGG Parameters [] ---
    # Key functions: GeneSetCollection, GSEAKEGGHyperGParams, hyperGTest
    gsc <- GeneSetCollection(keggFrame, setType = KEGGCollection())
    universe = Lkeys(org.Hs.egGO)
    kparams <- GSEAKEGGHyperGParams(name="My Custom GSEA based annot Params",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gostats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gostats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gostats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOSTATS:", paste0("    gostats: ", packageVersion("GOstats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gostats_results.csv
    touch ${prefix}_gostats_output.rds
    echo "BIOC_GOSTATS:" > versions.yml
    echo "    gostats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOSTATS(ch_input)

    emit:
    results  = BIOC_GOSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOSTATS.out.versions  // channel: path(versions.yml)
}
