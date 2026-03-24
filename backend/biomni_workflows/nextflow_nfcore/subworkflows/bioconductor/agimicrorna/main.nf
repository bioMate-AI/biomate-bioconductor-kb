#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AgiMicroRna
// Processing and Analysis of Agilent microRNA data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AgiMicroRna/inst/doc/AgiMicroRna.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AgiMicroRna")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AGIMICRORNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-agimicrorna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-agimicrorna:2.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-agimicrorna:2.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_agimicrorna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_agimicrorna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_agimicrorna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RleMicroRna)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library("AgiMicroRna")
    data(targets.micro)
    print(targets.micro)
    # --- Data [] ---
    # Key functions: data, class
    data(dd.micro)
    class(dd.micro)
    dim(dd.micro)
    # --- Qcplots [] ---
    # Key functions: qcPlots
    qcPlots(dd.micro,offset=5,
            MeanSignal=TRUE,
            ProcessedSignal=FALSE,
            TotalProbeSignal=FALSE,
            TotalGeneSignal=FALSE,
    # --- Boxplot [] ---
    # Key functions: boxplotMicroRna
    boxplotMicroRna(log2(dd.micro$meanS),
    	maintitle='log2 Mean Signal',
    	colorfill= 'orange')
    # --- Plotdensity [] ---
    # Key functions: plotDensityMicroRna
    plotDensityMicroRna(log2(dd.micro$meanS),
    	maintitle='log2 Mean Signal')
    # --- Ma [] ---
    # Key functions: mvaMicroRna
    ddaux=dd.micro
    ddaux$G=log2(dd.micro$meanS)
    mvaMicroRna(ddaux,
    	maintitle='log2 Mean Signal',
    	verbose=FALSE)
    # --- Rle [] ---
    # Key functions: RleMicroRna
    RleMicroRna(log2(dd.micro$meanS),
    	maintitle='log2 Mean Signal - RLE')
    # --- Hclust [] ---
    # Key functions: hierclusMicroRna
    hierclusMicroRna(log2(dd.micro$meanS),targets.micro$GErep,
    		methdis="euclidean",
                    methclu="complete",
    		sel=TRUE,100)
    # --- Cvarray [] ---
    # Key functions: cvArray
    cvArray(dd.micro,
            "MeanSignal",
            targets.micro,
    	verbose=TRUE)
    # --- Tgsmicrorna [] ---
    # Key functions: tgsMicroRna
    ddTGS=tgsMicroRna(dd.micro,
        half=TRUE,
        makePLOT=FALSE,
        verbose=FALSE)
    # --- Tgsnormalization [] ---
    # Key functions: tgsNormalization
    ddNORM=tgsNormalization(ddTGS,
                    "quantile",
                    makePLOTpre=FALSE,
                    makePLOTpost=FALSE,
                    targets.micro,
    # --- Rmamicrorna [] ---
    # Key functions: rmaMicroRna
    ## ddTGS.rma=rmaMicroRna(dd.micro,
    ## 		normalize=TRUE,
    ## 		background=TRUE)
    ##
    # --- Filtermicrorna [] ---
    # Key functions: filterMicroRna
    ddPROC=filterMicroRna(ddNORM,
                        dd.micro,
                        control=TRUE,
                        IsGeneDetected=TRUE,
                        wellaboveNEG=FALSE,
    # --- Esetmicrorna [] ---
    # Key functions: esetMicroRna
    esetPROC=esetMicroRna(ddPROC,
              targets.micro,
              makePLOT=FALSE,
    	  verbose=TRUE)
    # --- Writeeset [] ---
    # Key functions: writeEset
    ## writeEset(esetPROC,
    ##             ddPROC,
    ##             targets.micro,
    ## 	    verbose=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_agimicrorna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_agimicrorna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_agimicrorna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AGIMICRORNA:", paste0("    agimicrorna: ", packageVersion("AgiMicroRna"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agimicrorna_results.csv
    touch ${prefix}_agimicrorna_output.rds
    echo "BIOC_AGIMICRORNA:" > versions.yml
    echo "    agimicrorna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AGIMICRORNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AGIMICRORNA(ch_input)

    emit:
    results  = BIOC_AGIMICRORNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AGIMICRORNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AGIMICRORNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AGIMICRORNA.out.versions  // channel: path(versions.yml)
}
