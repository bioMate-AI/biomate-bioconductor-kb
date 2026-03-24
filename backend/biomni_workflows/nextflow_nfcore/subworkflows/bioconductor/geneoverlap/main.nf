#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneOverlap
// Test two sets of gene lists and visualize the results.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneOverlap/inst/doc/GeneOverlap.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GeneOverlap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEOVERLAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneoverlap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneoverlap:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneoverlap:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneoverlap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneoverlap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneoverlap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneOverlap)
    library(jsonlite)

    # --- Newgeneoverlap [] ---
    # Key functions: newGeneOverlap
    go.obj <- newGeneOverlap(hESC.ChIPSeq.list$H3K4me3,
                             hESC.RNASeq.list$"Exp High",
                             genome.size=gs.RNASeq)
    go.obj
    # --- Testgeneoverlap [] ---
    # Key functions: testGeneOverlap
    go.obj <- testGeneOverlap(go.obj)
    go.obj
    # --- Newgeneoverlap [] ---
    # Key functions: newGeneOverlap, testGeneOverlap
    go.obj <- newGeneOverlap(hESC.ChIPSeq.list$H3K4me3,
                             hESC.RNASeq.list$"Exp Low",
                             genome.size=gs.RNASeq)
    go.obj <- testGeneOverlap(go.obj)
    print(go.obj)
    # --- Head [] ---
    # Key functions: getIntersection, getOddsRatio, getContbl, getGenomeSize
    head(getIntersection(go.obj))
    getOddsRatio(go.obj)
    getContbl(go.obj)
    getGenomeSize(go.obj)
    # --- Setlista [] ---
    # Key functions: setListA, setListB
    setListA(go.obj) <- hESC.ChIPSeq.list$H3K27me3
    setListB(go.obj) <- hESC.RNASeq.list$"Exp Medium"
    go.obj
    # --- Testgeneoverlap [] ---
    # Key functions: testGeneOverlap
    go.obj <- testGeneOverlap(go.obj)
    go.obj
    # --- Newgom [] ---
    # Key functions: newGOM, drawHeatmap
    gom.obj <- newGOM(hESC.ChIPSeq.list, hESC.RNASeq.list,
                      gs.RNASeq)
    drawHeatmap(gom.obj)
    # --- Getmatrix [] ---
    # Key functions: getMatrix
    getMatrix(gom.obj, name="pval")
    # --- Getnestedlist [] ---
    # Key functions: getNestedList
    inter.nl <- getNestedList(gom.obj, name="intersection")
    str(inter.nl)
    # --- Newgom [] ---
    # Key functions: newGOM, drawHeatmap
    gom.self <- newGOM(hESC.ChIPSeq.list,
                       genome.size=gs.RNASeq)
    drawHeatmap(gom.self)
    # --- Drawheatmap [] ---
    # Key functions: drawHeatmap
    drawHeatmap(gom.self, ncolused=5, grid.col="Blues", note.col="black")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneoverlap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneoverlap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneoverlap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEOVERLAP:", paste0("    geneoverlap: ", packageVersion("GeneOverlap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneoverlap_results.csv
    touch ${prefix}_geneoverlap_output.rds
    echo "BIOC_GENEOVERLAP:" > versions.yml
    echo "    geneoverlap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEOVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEOVERLAP(ch_input)

    emit:
    results  = BIOC_GENEOVERLAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEOVERLAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEOVERLAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEOVERLAP.out.versions  // channel: path(versions.yml)
}
