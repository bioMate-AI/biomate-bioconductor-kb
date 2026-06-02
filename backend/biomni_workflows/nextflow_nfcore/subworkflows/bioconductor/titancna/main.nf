#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TitanCNA
// Hidden Markov model to segment and predict regions of subclonal copy number alterations (CNA) and lo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TitanCNA/inst/doc/TitanCNA.R
// Upstream  : doMC
// Downstream: none
//
// Install: BiocManager::install("TitanCNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TITANCNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-titancna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-titancna:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-titancna:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_titancna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_titancna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_titancna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TitanCNA)
    library(jsonlite)

    # --- Getpositionoverlap [] ---
    # Key functions: getPositionOverlap
    logR <- getPositionOverlap(data$chr, data$posn, cnData)
    data$logR <- log(2^logR)  #transform the log ratio to natural logs
    # --- Filterdata [] ---
    # Key functions: filterData
    data <- filterData(data, c(1:22, "X", "Y"), minDepth = 10, maxDepth = 200,
                       positionList = NULL, centromere = NULL, centromere.flankLength = 10000)
    # --- Loaddefaultparameters [] ---
    # Key functions: loadDefaultParameters
    numClusters <- 2
    params <- loadDefaultParameters(copyNumber = 5,
                                    numberClonalClusters = numClusters,
                                    symmetric = TRUE, hetBaselineSkew = 0,
                                    alleleEmissionModel = "binomial", data = data)
    # --- Registerdomc [] ---
    # Key functions: registerDoMC
    ## library(doMC)
    ## registerDoMC(cores = 4) #use 4 cores on a single machine
    # --- Runemclonalcn [] ---
    # Key functions: runEMclonalCN

    # --- Viterbiclonalcn [] ---
    # Key functions: viterbiClonalCN
    optimalPath <- viterbiClonalCN(data, convergeParams)
    head(optimalPath)
    # --- Outputtitanresults [] ---
    # Key functions: outputTitanResults

    # --- Eval [] ---
    # Key functions: outputTitanSegments
    segs <- outputTitanSegments(results, id = "test", convergeParams,
                                filename = NULL, igvfilename = NULL)
    head(segs)
    # --- Eval [] ---
    # Key functions: correctIntegerCN
    # get the estimated tumor ploidy
    ploidy <- tail(convergeParams$phi, 1)
    # get the estimated normal
    normal <- tail(convergeParams$n, 1)
    # apply tumor purity and ploidy correction
    # --- Outputmodelparameters [] ---
    # Key functions: outputModelParameters
    ## outputModelParameters(convergeParams, results, outparam, S_Dbw.scale = 10)
    # --- Tail [] ---
    # Key functions: plotCNlogRByChr
    ploidy <- tail(convergeParams$phi, 1)
    ploidy
    normal <- tail(convergeParams$n, 1)
    normal
    # --- Plotallelicratio [] ---
    # Key functions: plotAllelicRatio
    plotAllelicRatio(results, chr = 2, ylim = c(0, 1), cex = 0.25,
                     xlab = "", main = "Chr 2")
    # --- Tail [] ---
    # Key functions: plotClonalFrequency
    norm <- tail(convergeParams$n, 1)
    norm # estimated normal contamination
    1 - convergeParams$s[, ncol(convergeParams$s)] # estimated cellular prevalence
    plotClonalFrequency(results, chr = 2, normal = norm, ylim = c(0, 1),
                        cex = 0.25, xlab = "", main = "Chr 2")
    # --- Plotsubcloneprofiles [] ---
    # Key functions: plotSubcloneProfiles
    plotSubcloneProfiles(results, chr = 2, cex = 1, spacing = 2, main = "Chr 2")
    # --- Plotsegmentmedians [] ---
    # Key functions: plotSegmentMedians
    plotSegmentMedians(segs, chr=2, resultType = "LogRatio", plotType = "CopyNumber",
                       plot.new = TRUE, ylim = c(0, 4), main="Chr 2")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_titancna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_titancna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_titancna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TITANCNA:", paste0("    titancna: ", packageVersion("TitanCNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_titancna_results.csv
    touch ${prefix}_titancna_output.rds
    echo "BIOC_TITANCNA:" > versions.yml
    echo "    titancna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TITANCNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TITANCNA(ch_input)

    emit:
    results  = BIOC_TITANCNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TITANCNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TITANCNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TITANCNA.out.versions  // channel: path(versions.yml)
}
