#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellNOptR
// This package does optimisation of boolean logic networks of signalling pathways based on a previous 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellNOptR/inst/doc/CellNOptR-vignette.R
// Upstream  : doParallel, stringr
// Downstream: CNORdt, CNORfeeder, CNORfuzzy, CNORode
//
// Install: BiocManager::install("CellNOptR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLNOPTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellnoptr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellnoptr:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellnoptr:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellnoptr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellnoptr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellnoptr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CellNOptR)
    library(jsonlite)


    # --- Directory [] ---
    # Key functions: dir, file.copy, getwd, readMIDAS, makeCNOlist, CNOlist
    cpfile <- dir(system.file("ToyModel", package="CellNOptR"), full=TRUE)
    file.copy(from=cpfile, to=getwd(), overwrite=TRUE)
    dataToy <- readMIDAS("ToyDataMMB.csv", verbose=FALSE)
    CNOlistToy <- makeCNOlist(dataToy, subfield=FALSE, verbose=FALSE)
    data(CNOlistToy,package="CellNOptR", verbose=FALSE)
    CNOlistToy = CNOlist("ToyDataMMB.csv")
    CNOlistToy

    # --- Plot Cno [] ---
    # Key functions: readSIF, checkSignals, plotModel
    plot(CNOlistToy)
    pknmodel<-readSIF("ToyPKNMMB.sif")
    data(ToyModel,package="CellNOptR")
    checkSignals(CNOlistToy,pknmodel)
    plotModel(pknmodel, CNOlistToy)

    # --- Nonc [] ---
    # Key functions: indexFinder, findNONC, cutNONC, compressModel, expandGates, preprocessing, residualError
    indicesToy<-indexFinder(CNOlistToy,pknmodel,verbose=TRUE)
    ToyNCNOindices<-findNONC(pknmodel,indicesToy,verbose=TRUE)
    ToyNCNOcut<-cutNONC(pknmodel,ToyNCNOindices)
    indicesToyNCNOcut<-indexFinder(CNOlistToy,ToyNCNOcut)
    ToyNCNOcutComp<-compressModel(ToyNCNOcut,indicesToyNCNOcut)
    indicesToyNCNOcutComp<-indexFinder(CNOlistToy,ToyNCNOcutComp)
    model <- expandGates(ToyNCNOcutComp, maxInputsPerGate=3)
    model <- preprocessing(CNOlistToy, pknmodel, expansion=TRUE,
        compression=TRUE, cutNONC=TRUE, verbose=FALSE)
    resECNOlistToy <- residualError(CNOlistToy)

    # --- Initbs [] ---
    # Key functions: rep, gaBinaryT1, cutAndPlot, plotFit, plotModel
    initBstring <- rep(1,length(model$reacID))
    ToyT1opt <- gaBinaryT1(CNOlist=CNOlistToy, model=model,
        initBstring=initBstring, verbose=FALSE)
    cutAndPlot(model=model, bStrings=list(ToyT1opt$bString),
        CNOlist=CNOlistToy,plotPDF=TRUE)
    plotFit(optRes=ToyT1opt)
    plotModel(model, CNOlistToy, bString=ToyT1opt$bString)

    # --- Plot Model Toy2 [] ---
    # Key functions: mapBack, plotModel, unlink, testToy, readMIDAS, makeCNOlist, readSIF
    bs = mapBack(model, pknmodel, ToyT1opt$bString)
    plotModel(pknmodel, CNOlistToy, bs, compressed=model$speciesCompressed)
    unlink("testToy",recursive=TRUE)
    dataToy <- readMIDAS("ToyDataMMB.csv")
    CNOlistToy <- makeCNOlist(dataToy,subfield=FALSE)
    pknmodel <- readSIF("ToyPKNMMB.sif")
    unlink("Toy",recursive=TRUE)
    unlink("ToyDataMMB.csv")
    unlink("ToyPKNMMB.sif")
    unlink("Toy1Step",recursive=TRUE)
    unlink("ToyModelMMB2.sif")

    # --- Get Dream [] ---
    # Key functions: files, dir, file.copy, getwd, CNOlist, preprocessing, gaBinaryT1, cutAndPlot
    #Option 1: copy the SIF and MIDAS files (followed by readMIDAS, makeCNOlist and readSIF)
    cpfile<-dir(system.file("DREAMModel",package="CellNOptR"),full=TRUE)
    file.copy(from=cpfile,to=getwd(),overwrite=TRUE)
    #Option 2: load the CNOlist and model objects
    data(CNOlistDREAM,package="CellNOptR")
    data(DreamModel,package="CellNOptR")
    data(CNOlistToy2,package="CellNOptR")
    data(ToyModel2,package="CellNOptR")
    pknmodel = ToyModel2
    cnolist = CNOlist(CNOlistToy2)
    plot(cnolist)
    model = preprocessing(cnolist, pknmodel, verbose=FALSE)
    T1opt <- gaBinaryT1(cnolist, model, stallGenMax=10, maxTime=60, verbose=FALSE)
    sim <- cutAndPlot(model=model, bStrings=list(T1opt$bString),
        CNOlist=cnolist, plotPDF=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellnoptr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellnoptr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellnoptr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLNOPTR:", paste0("    cellnoptr: ", packageVersion("CellNOptR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellnoptr_results.csv
    touch ${prefix}_cellnoptr_output.rds
    echo "BIOC_CELLNOPTR:" > versions.yml
    echo "    cellnoptr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLNOPTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLNOPTR(ch_input)

    emit:
    results  = BIOC_CELLNOPTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLNOPTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLNOPTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLNOPTR.out.versions  // channel: path(versions.yml)
}
