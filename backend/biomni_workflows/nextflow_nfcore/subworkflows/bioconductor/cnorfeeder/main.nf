#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNORfeeder
// This package integrates literature-constrained and data-driven methods to infer signalling networks 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNORfeeder/inst/doc/CNORfeeder-vignette.R
// Upstream  : CNORode, CellNOptR, MEIGOR, OmnipathR, doParallel
// Downstream: none
//
// Install: BiocManager::install("CNORfeeder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNORFEEDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnorfeeder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnorfeeder:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnorfeeder:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnorfeeder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnorfeeder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnorfeeder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNORfeeder)
    library(jsonlite)

    # --- Installpackage2 [] ---
    # Key functions: packages
    ## install.packages("path_to_CNORfeeder/CNORfeeder_1.0.0.tar.gz",
    ##     repos=NULL, type="source")
    # --- Getdata1 [] ---
    # Key functions: model
    ## # load the data already formatted as CNOlist
    ## data(CNOlistDREAM,package="CellNOptR")
    ## # load the model (PKN) already in the CNO format
    ## data(DreamModel,package="CellNOptR")
    # --- Getdata2 [] ---
    # Key functions: makeBTables
    ## BTable <- makeBTables(CNOlist=CNOlistDREAM, k=2, measErr=c(0.1, 0))
    # --- Linkrank [] ---
    # Key functions: linksRanking
    ## Lrank <- linksRanking(CNOlist=CNOlistDREAM, measErr=c(0.1, 0), savefile=FALSE)
    # --- Getdata3 [] ---
    # Key functions: preprocessing
    ## model<-preprocessing(data=CNOlistDREAM, model=DreamModel)
    # --- Integration [] ---
    # Key functions: mapBTables2model
    ## modelIntegr <- mapBTables2model(BTable=BTable,model=model,allInter=TRUE)
    # --- Plotdata [] ---
    # Key functions: plotModel
    ## plotModel(model=modelIntegr, CNOlist=CNOlistDREAM, indexIntegr=modelIntegr$indexIntegr)
    # --- Weight [] ---
    # Key functions: weighting
    ## modelIntegrWeight <- weighting(modelIntegr=modelIntegr, PKNmodel=DreamModel,
    ##                                CNOlist=CNOlistDREAM, integrFac=10)
    # --- Weightppi [] ---
    # Key functions: weighting
    ## data(PPINigraph,package="CNORfeeder")
    ## data(UniprotIDdream,package="CNORfeeder")
    ## modelIntegrWeight <- weighting(modelIntegr=modelIntegr, PKNmodel=DreamModel,
    ##                                CNOlist=CNOlistDREAM, integrFac=10,
    ##                                UniprotID=UniprotIDdream, PPI=PPINigraph)
    # --- Train [] ---
    # Key functions: algorithm, gaBinaryT1W
    ## # training to data using genetic algorithm (run longer to obtain better results)
    ## DreamT1opt<-gaBinaryT1W(CNOlist=CNOlistDREAM, model=modelIntegrWeight,
    ##                         maxGens=2, popSize=5, verbose=FALSE)
    # --- Results1 [] ---
    # Key functions: plotModel, cutAndPlotResultsT1
    ## # model
    ## plotModel(model=modelIntegrWeight, CNOlist=CNOlistDREAM, bString=DreamT1opt$bString)
    ## # data
    ## cutAndPlotResultsT1(model=modelIntegrWeight, CNOlist=CNOlistDREAM,
    ##                     bString=DreamT1opt$bString)
    # --- Results2 [] ---
    # Key functions: plotModel, plotCNOlist
    ## # loading the necessary packages
    ## library(CellNOptR)
    ## library(MEIGOR)
    ## library(CNORode)
    ## library(doParallel)
    # --- Results3 [] ---
    # Key functions: import_Omnipath_Interactions
    ## ## Loading database
    ## data(database, package="CNORfeeder")
    ## ## Alternatively, users can download the database from Omnipath and retain only
    ## ## activatory/inhibitory interactions as shown below.
    ## ## Please note that OmniPath is in continuous update and new links are
    # --- Results4 [] ---
    # Key functions: parameters, createLBodeContPars, defaultParametersSSm, parEstimationLBode, plotLBodeFitness
    ## # set initial parameters (here parameters k and tau are optimised and n fixed to 3)
    # --- Results5 [] ---
    # Key functions: fits, identifyMisfitIndices
    ## # Identifying the mis-fits (measurements with mse worse than 0.05)
    ## indices = identifyMisfitIndices(cnolist = cnolist, model = model,
    ##                                 simData = simData, mseThresh = 0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnorfeeder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnorfeeder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnorfeeder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNORFEEDER:", paste0("    cnorfeeder: ", packageVersion("CNORfeeder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnorfeeder_results.csv
    touch ${prefix}_cnorfeeder_output.rds
    echo "BIOC_CNORFEEDER:" > versions.yml
    echo "    cnorfeeder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNORFEEDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNORFEEDER(ch_input)

    emit:
    results  = BIOC_CNORFEEDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNORFEEDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNORFEEDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNORFEEDER.out.versions  // channel: path(versions.yml)
}
