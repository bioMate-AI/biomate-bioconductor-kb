#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: apComplex
// Functions to estimate a bipartite graph of protein complex membership using AP-MS data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/apComplex/inst/doc/apComplex.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("apComplex")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APCOMPLEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-apcomplex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-apcomplex:2.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-apcomplex:2.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_apcomplex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_apcomplex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_apcomplex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(apComplex)
    library(jsonlite)

    # --- Truedata [] ---
    # Key functions: ftM2graphNEL, plotGraph
    FromT <- c(rep("P1",3),rep("P2",3),rep("P3",2))
    ToT <- c("P2","P4","P6","P1","P4","P6","P4","P5")
    LT <- cbind(FromT,ToT)
    apEXGT <- ftM2graphNEL(LT)
    fcT <- c(rep("yellow",3),rep("white",3))
    # --- Observeddata [] ---
    # Key functions: ftM2adjM, plotGraph
    From <- c(rep("P1",3),rep("P2",2),rep("P3",3),"P8")
    To <- c("P2","P4","P6","P1","P6","P4","P5","P7","P3")
    L <- cbind(From,To)
    M1 <- ftM2adjM(L)
    apEXG <- as(M1,"graphNEL")
    # --- Pcmg0 [] ---
    # Key functions: bhmaxSubgraph
    PCMG0 <- bhmaxSubgraph(apEX)
    PCMG0
    # --- sub Graph [] ---
    # Key functions: subGraph, edgemode, plotGraph
    par(mfrow=c(2,2))
    sn1 <- c("P3","P8")
    sg1 <- subGraph(sn1,apEXG)
    edgemode(sg1) <- "directed"
    fc1 <- fc[sn1]
    # --- Bp1 [] ---
    # Key functions: ftM2graphNEL, plotGraph
    FromBP1 <- c("P1","P1","P2","P3","P3","P4","P4","P5","P6","P6","P7","P8")
    ToBP1 <- paste("BHM",c(2,3,2,1,4,3,4,4,2,3,4,1),sep="")
    LBP1 <- cbind(FromBP1,ToBP1)
    gBP1 <- ftM2graphNEL(LBP1, edgemode="undirected")
    fc <- c(rep("yellow",4),rep("white",4),rep("salmon",4))
    # --- Mergecomplexes [] ---
    # Key functions: mergeComplexes
    PCMG1 <- mergeComplexes(PCMG0,apEX,sensitivity=.7,specificity=.75)
    PCMG1
    # --- Mergedcomplex [] ---
    # Key functions: plotGraph, subGraph, edgemode
    par(mfrow=c(1,3))
    plotGraph(sg1,nodeAttrs=nA1,edgeAttrs=eA1)
    title("Complex1")
    sn5 <- c("P1","P2","P4","P6")
    sg5 <- subGraph(sn5,apEXG)
    # --- Bp2 [] ---
    # Key functions: ftM2graphNEL, plotGraph
    FromBP2 <- paste("P",c(1,2,3,3,8,4,4,5,6,7),sep="")
    ToBP2 <- paste("C",c(2,2,1,3,1,2,3,3,2,3),sep="")
    LBP2 <- cbind(FromBP2,ToBP2)
    gBP2 <- ftM2graphNEL(LBP2, edgemode="undirected")
    fc <- c(rep("yellow",4),rep("white",4),rep("thistle",3))
    # --- Findcomplexes [] ---
    # Key functions: findComplexes
    PCMG2 <- findComplexes(apEX,sensitivity=.7,specificity=.75)
    PCMG2
    # --- Sortcomps [] ---
    # Key functions: sortComplexes
    sortComplexes(PCMG2,adjMat=apEX)
    # --- Publicdatatap [] ---
    # Key functions: adj
    data(TAP)
    dim(TAP)
    data(TAPgraph)
    which(TAP["Abd1",]==1)
    adj(TAPgraph,"Abd1")
    # --- Publicdatahmspci [] ---
    # Key functions: adj
    data(HMSPCI)
    dim(HMSPCI)
    data(HMSPCIgraph)
    which(HMSPCI["YAL015C",]==1)
    adj(HMSPCIgraph,"YAL015C")
    # --- data [] ---
    # Key functions: data
    data(MBMEcTAP)
    which(MBMEcTAP[,37]==1)
    which(MBMEcTAP[,38]==1)
    which(MBMEcTAP[,39]==1)
    which(MBMEcTAP[,195]==1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_apcomplex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_apcomplex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_apcomplex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_APCOMPLEX:", paste0("    apcomplex: ", packageVersion("apComplex"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_apcomplex_results.csv
    touch ${prefix}_apcomplex_output.rds
    echo "BIOC_APCOMPLEX:" > versions.yml
    echo "    apcomplex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_APCOMPLEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_APCOMPLEX(ch_input)

    emit:
    results  = BIOC_APCOMPLEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_APCOMPLEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_APCOMPLEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_APCOMPLEX.out.versions  // channel: path(versions.yml)
}
