#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNORfuzzy
// This package is an extension to CellNOptR.  It contains additional functionality needed to simulate 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNORfuzzy/inst/doc/CNORfuzzy-vignette.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("CNORfuzzy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNORFUZZY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnorfuzzy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnorfuzzy:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnorfuzzy:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnorfuzzy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnorfuzzy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnorfuzzy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNORwrapFuzzy)
    library(CNOlist)
    library(jsonlite)

    # --- Installcnorfuzzy [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("CNORfuzzy")
    # --- Quickstart [] ---
    # Key functions: data
    library(CNORfuzzy)
    data(CNOlistToy, package="CellNOptR")
    data(ToyModel, package="CellNOptR")
    # --- Cnorfuzzy Vignette.Rnw:153 157 [] ---
    # Key functions: data
    library(CNORfuzzy)
    library(xtable)
    data(CNOlistToy, package="CellNOptR")
    data(ToyModel, package="CellNOptR")
    # --- Reacidtab [] ---
    # Key functions: xtable
    xtable(matrix(ToyModel$reacID, ncol=4), caption="The ToyModel object contains a prior knowledge
    network with 16 reactions stored in the field \\emph{ToyModel\\$reacID}.
    There are other fields such as \\emph{namesSpecies} or \\emph{interMat} that are used during the
    analysis.", label="tab:reacID")
    # --- Quickstartplotmodel [] ---
    # Key functions: plotModel
    library(CNORfuzzy)
    data(CNOlistToy, package="CellNOptR")
    data(ToyModel, package="CellNOptR")
    plotModel(ToyModel, CNOlistToy, compressed=c("p38", "TRAF6", "Ras"))
    # --- Quickstartplotmodelcompressed [] ---
    # Key functions: plotModel, expandGates, compressModel, indexFinder
    library(CNORfuzzy)
    data(CNOlistToy, package="CellNOptR")
    data(ToyModel, package="CellNOptR")
    plotModel(expandGates(compressModel(ToyModel, indexFinder(CNOlistToy, ToyModel))), CNOlistToy)
    # --- Cnolist [] ---
    # Key functions: CNOlist
    data(CNOlistToy, package="CellNOptR")
    CNOlistToy = CNOlist(CNOlistToy)
    print(CNOlistToy)
    # --- Plotcnolist [] ---
    # Key functions: CNOlist, plotCNOlist
    # with the old CNOlist (output of makeCNOlist), type
    data(CNOlistToy, package="CellNOptR")
    plotCNOlist(CNOlistToy)
    # with the new version, just type:
    CNOlistToy = CNOlist(CNOlistToy)
    # --- Cnorfuzzy Vignette.Rnw:246 250 [] ---
    # Key functions: defaultParametersFuzzy
    paramsList = defaultParametersFuzzy(CNOlistToy, ToyModel)
    paramsList$popSize = 50
    paramsList$maxGens = 50
    paramsList$optimisation$maxtime = 30
    # --- Optimisation [] ---
    # Key functions: CNORwrapFuzzy
    N = 1
    allRes = list()
    paramsList$verbose=TRUE
    for (i in 1:N){
        Res = CNORwrapFuzzy(CNOlistToy, ToyModel, paramsList=paramsList)
    # --- Compilemultires [] ---
    # Key functions: compileMultiRes
    summary = compileMultiRes(allRes,show=FALSE)
    # --- Plotmeanfuzzyfit [] ---
    # Key functions: plotMeanFuzzyFit
    plotMeanFuzzyFit(0.1, summary$allFinalMSEs, allRes,
        plotParams=list(cmap_scale=0.5, cex=.9, margin=0.3))
    # --- Fullanalysis Start [] ---
    # Key functions: data
    library(CNORfuzzy)
    data(DreamModel, package="CellNOptR")
    data(CNOlistDREAM, package="CellNOptR")
    # --- Quickstartplotmodel2 [] ---
    # Key functions: compressModel, indexFinder, plotModel
    library(CNORfuzzy)
    data(CNOlistToy, package="CellNOptR")
    data(ToyModel, package="CellNOptR")
    compModel = compressModel(DreamModel,  indexFinder(CNOlistDREAM, DreamModel))
    compSpecies = compModel$speciesCompressed
    # --- Quickstartplotmodelcompressed2 [] ---
    # Key functions: compressModel, indexFinder, plotModel
    library(CNORfuzzy)
    data(CNOlistToy, package="CellNOptR")
    data(ToyModel, package="CellNOptR")
    compModel = compressModel(DreamModel,  indexFinder(CNOlistDREAM, DreamModel))
    plotModel(compModel, CNOlistDREAM, graphvizParams=list(fontsize=40))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnorfuzzy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnorfuzzy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnorfuzzy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNORFUZZY:", paste0("    cnorfuzzy: ", packageVersion("CNORfuzzy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnorfuzzy_results.csv
    touch ${prefix}_cnorfuzzy_output.rds
    echo "BIOC_CNORFUZZY:" > versions.yml
    echo "    cnorfuzzy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNORFUZZY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNORFUZZY(ch_input)

    emit:
    results  = BIOC_CNORFUZZY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNORFUZZY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNORFUZZY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNORFUZZY.out.versions  // channel: path(versions.yml)
}
