#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FELLA
// Enrichment of metabolomics data using KEGG entries. Given a set of affected compounds, FELLA suggest
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FELLA/inst/doc/FELLA.R
// Upstream  : KEGGREST, igraph, magrittr
// Downstream: none
//
// Install: BiocManager::install("FELLA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FELLA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fella"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fella:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fella:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fella_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fella_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fella_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FELLA)
    library(jsonlite)

    # --- 01 Graph [] ---
    # Key functions: buildGraphFromKEGGREST
    library(FELLA)
    set.seed(1)
    # Filter overview pathways
    graph <- buildGraphFromKEGGREST(
        organism = "hsa",
    # --- 01 Database [] ---
    # Key functions: tempdir, unlink, buildDataFromGraph
    tmpdir <- paste0(tempdir(), "/my_database")
    # Mke sure the database does not exist from a former vignette build
    # Otherwise the vignette will rise an error
    # because FELLA will not overwrite an existing database
    unlink(tmpdir, recursive = TRUE)
    # --- 01 Loadkegg [] ---
    # Key functions: loadKEGGdata
    fella.data <- loadKEGGdata(
        databaseDir = tmpdir,
        internalDir = FALSE,
        loadMatrix = "diffusion"
    )
    # --- 01 Info [] ---
    # Key functions: getInfo
    cat(getInfo(fella.data))
    # --- 02 Mapcompounds [] ---
    # Key functions: defineCompounds
    analysis.epithelial <- defineCompounds(
        compounds = compounds.epithelial,
        data = fella.data)
    # --- 02 Mapped [] ---
    # Key functions: getInput, getExcluded
    getInput(analysis.epithelial)
    getExcluded(analysis.epithelial)
    # --- 03 Enrich [] ---
    # Key functions: runDiffusion
    analysis.epithelial <- runDiffusion(
        object = analysis.epithelial,
        data = fella.data,
        approx = "normality")
    # --- 04 Graph [] ---
    # Key functions: generateResultsGraph
    g <- generateResultsGraph(
        object = analysis.epithelial,
        method = "diffusion",
        nlimit = nlimit,
        data = fella.data)
    # --- 04 Go [] ---
    # Key functions: addGOToGraph
    # GO:0005739 is the term for mitochondrion
    g.go <- addGOToGraph(
        graph = g,
        GOterm = "GO:0005739",
        godata.options = list(
    # --- 04 Plot Go [] ---
    # Key functions: plotGraph
    plotGraph(
        g.go,
        vertex.label.cex = vertex.label.cex)
    # --- 04 Table [] ---
    # Key functions: generateResultsTable
    tab.all <- generateResultsTable(
        method = "diffusion",
        nlimit = 100,
        object = analysis.epithelial,
        data = fella.data)
    # --- 04 Enzyme [] ---
    # Key functions: generateEnzymesTable
    tab.enzyme <- generateEnzymesTable(
        method = "diffusion",
        nlimit = 100,
        object = analysis.epithelial,
        data = fella.data)
    # --- 04 File [] ---
    # Key functions: tempfile, exportResults
    tmpfile <- tempfile()
    exportResults(
        format = "csv",
        file = tmpfile,
        method = "diffusion",
    # --- 04 Pajek [] ---
    # Key functions: tempfile, exportResults
    tmpfile <- tempfile()
    exportResults(
        format = "pajek",
        file = tmpfile,
        method = "diffusion",
    # --- 05 [] ---
    # Key functions: enrich
    compounds.ovarian <- c(
        "C00275", "C00158", "C00042",
        "C00346", "C00122", "C06468")
    analysis.ovarian <- enrich(
        compounds = compounds.ovarian,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fella_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fella_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fella_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FELLA:", paste0("    fella: ", packageVersion("FELLA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fella_results.csv
    touch ${prefix}_fella_output.rds
    echo "BIOC_FELLA:" > versions.yml
    echo "    fella: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FELLA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FELLA(ch_input)

    emit:
    results  = BIOC_FELLA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FELLA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FELLA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FELLA.out.versions  // channel: path(versions.yml)
}
