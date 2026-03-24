#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gatom
// This package implements a metabolic network analysis pipeline to identify an active metabolic module
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gatom/inst/doc/gatom-tutorial.R
// Upstream  : igraph, mwcsr
// Downstream: none
//
// Install: BiocManager::install("gatom")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GATOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gatom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gatom:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gatom:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gatom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gatom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gatom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(E)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("networkEx")
    data("met.kegg.dbEx")
    data("org.Mm.eg.gatom.annoEx")
    # --- Makemetabolicgraph [] ---
    # Key functions: makeMetabolicGraph
    ---------------------------------------------------------------------
    g <- makeMetabolicGraph(network=networkEx,
                            topology="atoms",
                            org.gatom.anno=org.Mm.eg.gatom.annoEx,
                            gene.de=gene.de.rawEx,
    # --- Rnc Solver [] ---
    # Key functions: rnc_solver
    ---------------------------------------------------------------------
    solver <- rnc_solver()
    # --- Createshinycyjswidget [] ---
    # Key functions: createShinyCyJSWidget
    ---------------------------------------------------------------------
    createShinyCyJSWidget(m)
    # --- Write Graph [] ---
    # Key functions: write_graph, path, tempdir
    ---------------------------------------------------------------------
    write_graph(m, file = file.path(tempdir(), "M0.vs.M1.graphml"), format = "graphml")
    # --- Savemoduletodot [] ---
    # Key functions: saveModuleToDot, path, tempdir
    ---------------------------------------------------------------------
    saveModuleToDot(m, file = file.path(tempdir(), "M0.vs.M1.dot"), name = "M0.vs.M1")
    # --- Readrds [] ---
    # Key functions: url
    ---------------------------------------------------------------------
    network.combined <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.combined.rds"))
    met.combined.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.combined.db.rds"))
    org.Mm.eg.gatom.anno <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/org.Mm.eg.gatom.anno.rds"))
    # --- Fread [] ---
    # Key functions: fread
    ---------------------------------------------------------------------
    gene2reaction.extra <- fread("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/gene2reaction.combined.mmu.eg.tsv", colClasses="character")
    # --- Makemetabolicgraph [] ---
    # Key functions: makeMetabolicGraph, scoreGraph, rnc_solver, solve_mwcsp
    ---------------------------------------------------------------------
    cg <- makeMetabolicGraph(network=network.combined,
                             topology="atoms",
                             org.gatom.anno=org.Mm.eg.gatom.anno,
                             gene.de=gene.de.raw,
    # --- Readrds [] ---
    # Key functions: url
    ---------------------------------------------------------------------
    network <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.kegg.rds"))
    met.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.kegg.db.rds"))
    # --- Makemetabolicgraph [] ---
    # Key functions: makeMetabolicGraph, scoreGraph, rnc_solver, solve_mwcsp
    ---------------------------------------------------------------------
    kg <- makeMetabolicGraph(network=network,
                            topology="atoms",
                            org.gatom.anno=org.Mm.eg.gatom.anno,
                            gene.de=gene.de.raw,
    # --- Readrds [] ---
    # Key functions: url
    ---------------------------------------------------------------------
    network.rhea <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.rhea.rds"))
    met.rhea.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.rhea.db.rds"))
    # --- Fread [] ---
    # Key functions: fread
    ---------------------------------------------------------------------
    gene2reaction.extra <- fread("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/gene2reaction.rhea.mmu.eg.tsv", colClasses="character")
    # --- Makemetabolicgraph [] ---
    # Key functions: makeMetabolicGraph, scoreGraph, rnc_solver, solve_mwcsp
    ---------------------------------------------------------------------
    rg <- makeMetabolicGraph(network=network.rhea,
                             topology="atoms",
                             org.gatom.anno=org.Mm.eg.gatom.anno,
                             gene.de=gene.de.raw,
    # --- Readrds [] ---
    # Key functions: url
    ---------------------------------------------------------------------
    network.lipids <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.rhea.lipids.rds"))
    met.lipids.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.lipids.db.rds"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gatom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gatom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gatom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GATOM:", paste0("    gatom: ", packageVersion("gatom"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gatom_results.csv
    touch ${prefix}_gatom_output.rds
    echo "BIOC_GATOM:" > versions.yml
    echo "    gatom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GATOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GATOM(ch_input)

    emit:
    results  = BIOC_GATOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GATOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GATOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GATOM.out.versions  // channel: path(versions.yml)
}
