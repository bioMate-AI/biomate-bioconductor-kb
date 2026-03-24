#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metabomxtr
// The functions in this package return optimized parameter estimates and log likelihoods for mixture m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metabomxtr/inst/doc/Metabomxtr_Vignette.R
// Upstream  : ggplot2, plyr, reshape2, xtable
// Downstream: none
//
// Install: BiocManager::install("metabomxtr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METABOMXTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metabomxtr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metabomxtr:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metabomxtr:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metabomxtr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metabomxtr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metabomxtr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metabomxtr)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(metabdata)
    dim(metabdata)
    # --- Colnames [] ---
    # Key functions: na
    yvars<-colnames(metabdata)[24:27]
    apply(metabdata[,yvars],2,function(x){sum(is.na(x))})
    # --- Levels [] ---
    # Key functions: levels, relevel
    levels(metabdata$PHENO)
    metabdata$PHENO<-relevel(metabdata$PHENO,ref="MomLowFPG")
    # --- Mxtrmod [] ---
    # Key functions: mxtrmod
    fullModelResults<-mxtrmod(ynames=yvars,mxtrModel=fullModel,data=metabdata)
    fullModelResults
    # --- Mxtrmodlrt [] ---
    # Key functions: mxtrmodLRT
    finalResult<-mxtrmodLRT(fullmod=fullModelResults,redmod=reducedModelResults,adj="BH")
    finalResult
    # --- Frame [] ---
    # Key functions: frame
    finalResultTable<-data.frame(Metabolite=fullModelResults$.id,HighFPG.Prop=HighFPG.Prop,
    LowFPG.Prop=LowFPG.Prop,HighFPG.Mean=HighFPG.Mean,
    LowFPG.Mean=LowFPG.Mean,Mean.Difference=FPG.MeanDiff,
    FDR.Adj.P=round(finalResult$adjP,digits=4))
    # --- Dtable [] ---
    # Key functions: xtable
    library(xtable)
    finalXTable<-xtable(finalResultTable,digits=c(0,2,2,2,2,2,2,4))
    print(finalXTable)
    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metabomxtr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metabomxtr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metabomxtr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METABOMXTR:", paste0("    metabomxtr: ", packageVersion("metabomxtr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabomxtr_results.csv
    touch ${prefix}_metabomxtr_output.rds
    echo "BIOC_METABOMXTR:" > versions.yml
    echo "    metabomxtr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METABOMXTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METABOMXTR(ch_input)

    emit:
    results  = BIOC_METABOMXTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METABOMXTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METABOMXTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METABOMXTR.out.versions  // channel: path(versions.yml)
}
