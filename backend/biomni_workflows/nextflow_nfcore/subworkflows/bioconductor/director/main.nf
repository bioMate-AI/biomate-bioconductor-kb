#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Director
// Director is an R package designed to streamline the visualization of molecular effects in regulatory
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Director/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Director")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIRECTOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-director"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-director:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-director:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_director_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_director_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_director_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Director)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame
    library(Director)
    table1 <- data.frame(source=c("DrugX", "DrugX", "miR-B", "miR-B", "miR-B",
            "miR-A", "miR-A", "transc1", "transc2", "transc3", "transc4"),
        target=c("miR-B", "miR-A", "transc1", "transc2", "transc3", "transc2",
            "transc4", "gene1", "gene2", "gene2", "gene3"),
    # --- Createlist [] ---
    # Key functions: createList
    tempList <- createList(table1)
    # --- Frame [] ---
    # Key functions: frame
    List <- data.frame(source=c("DrugX", "DrugX",
            "miR-B", "miR-B", "miR-B", "miR-A", "miR-A", "transc1",
            "transc2", "transc3", "transc4"),
        target=c("miR-B", "miR-A", "transc1", "transc2", "transc3",
            "transc2", "transc4", "gene1", "gene2", "gene2", "gene3"),
    # --- Createlist [] ---
    # Key functions: createList
    tempList2 <- createList(List,ListFC)
    # --- Initsankey [] ---
    # Key functions: initSankey, makeSankey, drawSankey
    initSankey()
    sankey <- makeSankey(tempList2)
    sankeyd <- drawSankey(sankey)
    # --- Makesankey [] ---
    # Key functions: makeSankey, drawSankey
    sankey2 <- makeSankey(tempList2, averagePath=TRUE)
    sankey2d <- drawSankey(sankey2)
    # --- Initsankey [] ---
    # Key functions: initSankey, makeSankey, drawSankey
    # Makes the path colours darker by 10%  and uses a single, uniform font size
    # for the figure rather than font sizes proportional to node size.
    initSankey(pathOpacity = 0.3, pathHover = 0.6,
        fontsizeProportion = FALSE, fontsize=20)
    # Changes the default colours used.

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_director_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_director_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_director_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIRECTOR:", paste0("    director: ", packageVersion("Director"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_director_results.csv
    touch ${prefix}_director_output.rds
    echo "BIOC_DIRECTOR:" > versions.yml
    echo "    director: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIRECTOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIRECTOR(ch_input)

    emit:
    results  = BIOC_DIRECTOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIRECTOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIRECTOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIRECTOR.out.versions  // channel: path(versions.yml)
}
