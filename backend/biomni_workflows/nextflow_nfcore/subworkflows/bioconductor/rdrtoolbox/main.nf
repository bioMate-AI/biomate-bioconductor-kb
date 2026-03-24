#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RDRToolbox
// A package for nonlinear dimension reduction using the Isomap and LLE algorithm. It also includes a r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RDRToolbox/inst/doc/vignette.R
// Upstream  : golubEsets
// Downstream: none
//
// Install: BiocManager::install("RDRToolbox")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RDRTOOLBOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rdrtoolbox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rdrtoolbox:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rdrtoolbox:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rdrtoolbox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rdrtoolbox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rdrtoolbox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DBIndex)
    library(Isomap)
    library(LLE)
    library(SwissRoll)
    library(jsonlite)

    # --- Swissroll [] ---
    # Key functions: SwissRoll
    ## swissData=SwissRoll(N = 1000, Plot=TRUE)
    # --- Generatedata [] ---
    # Key functions: generateData
    sim = generateData(samples=20, genes=1000, diffgenes=100, diffsamples=10)
    simData = sim[[1]]
    simLabels = sim[[2]]
    # --- Lle [] ---
    # Key functions: LLE
    simData_dim3_lle = LLE(data=simData, dim=3, k=10)
    head(simData_dim3_lle)
    simData_dim2_lle = LLE(data=simData, dim=2, k=5)
    head(simData_dim2_lle)
    # --- Isomap [] ---
    # Key functions: Isomap
    simData_dim2_IM = Isomap(data=simData, dims=2, k=10)
    head(simData_dim2_IM$dim2)
    # --- Plotdr [] ---
    # Key functions: plotDR
    plotDR(data=simData_dim2_lle, labels=simLabels)
    # --- Generatedata [] ---
    # Key functions: generateData, DBIndex
    d = generateData(samples=20, genes=50, diffgenes=10, blocksize=5)
    DBIndex(data=d[[1]], labels=d[[2]])
    # --- Dbindex [] ---
    # Key functions: DBIndex
    DBIndex(data=simData_dim2_lle, labels=simLabels)
    # --- Data [] ---
    # Key functions: data
    library(golubEsets)
    data(Golub_Merge)
    # --- Isomap [] ---
    # Key functions: Isomap
    Isomap(data=golubExprs, dims=1:10, plotResiduals=TRUE, k=5)
    # --- Isomap [] ---
    # Key functions: Isomap, LLE
    golubIsomap = Isomap(data=golubExprs, dims=2, k=5)
    golubLLE = LLE(data=golubExprs, dim=2, k=5)
    # --- Dbindex [] ---
    # Key functions: DBIndex
    DBIndex(data=golubIsomap$dim2, labels=labels)
    DBIndex(data=golubLLE, labels=labels)
    # --- Plotgolubisomap [] ---
    # Key functions: plotDR
    plotDR(data=golubIsomap$dim2, labels=labels, axesLabels=c("", ""), legend=TRUE)
    title(main="Isomap")
    # --- Plotgolublle [] ---
    # Key functions: plotDR
    plotDR(data=golubLLE, labels=labels, axesLabels=c("", ""), legend=TRUE)
    title(main="LLE")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rdrtoolbox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rdrtoolbox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rdrtoolbox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RDRTOOLBOX:", paste0("    rdrtoolbox: ", packageVersion("RDRToolbox"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rdrtoolbox_results.csv
    touch ${prefix}_rdrtoolbox_output.rds
    echo "BIOC_RDRTOOLBOX:" > versions.yml
    echo "    rdrtoolbox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RDRTOOLBOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RDRTOOLBOX(ch_input)

    emit:
    results  = BIOC_RDRTOOLBOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RDRTOOLBOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RDRTOOLBOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RDRTOOLBOX.out.versions  // channel: path(versions.yml)
}
