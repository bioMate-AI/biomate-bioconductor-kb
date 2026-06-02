#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flagme
// Fragment-level analysis of gas chromatography-massspectrometry metabolomics data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flagme/inst/doc/flagme-knitr.R
// Upstream  : gcspikelite
// Downstream: none
//
// Install: BiocManager::install("flagme")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLAGME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flagme"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flagme:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flagme:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_flagme_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flagme_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flagme_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MatchedFilterParam)
    library(jsonlite)

    # --- Rawdata [] ---
    # Key functions: package, peaksDataset, addAMDISPeaks
    gcmsPath <- paste(find.package("gcspikelite"), "data", sep="/")
    data(targets)
    cdfFiles <- paste(gcmsPath, targets$FileName, sep="/")
    eluFiles <- gsub("CDF", "ELU", cdfFiles)
    pd <- peaksDataset(cdfFiles, mz=seq(50,550), rtrange=c(7.5,8.5))
    # --- Addxcms [] ---
    # Key functions: peaksDataset, MatchedFilterParam, addXCMSPeaks
    pd.2 <- peaksDataset(cdfFiles[1:3], mz = seq(50, 550), rtrange = c(7.5, 8.5))
    mfp <- xcms::MatchedFilterParam(fwhm = 10, snthresh = 5)
    pd.2 <- addXCMSPeaks(cdfFiles[1:3], pd.2, settings = mfp)
    pd.2
    # --- Plotexample1 [] ---
    # Key functions: plotChrom
    plotChrom(pd, rtrange=c(7.5,8.5), plotPeaks=TRUE, plotPeakLabels=TRUE,
         max.near=8, how.near=0.5, col=rep(c("blue","red","black"), each=3))
    # --- Plotexample2 [] ---
    # Key functions: plotImage
    r <- 1
    plotImage(pd, run=r, rtrange=c(7.5,8.5), main="")
    v <- which(pd@peaksdata[[r]] > 0, arr.ind=TRUE) # find detected peaks
    abline(v=pd@peaksrt[[r]])
    points(pd@peaksrt[[r]][v[,2]], pd@mz[v[,1]], pch=19, cex=.6, col="white")
    # --- Pairwisealignexample [] ---
    # Key functions: peaksAlignment, plotAlignment
    Ds <- c(0.1, 10, 0.1, 0.1)
    gaps <- c(0.5, 0.5, 0.1, 0.9)
    par(mfrow=c(2,2), mai=c(0.8466,0.4806,0.4806,0.1486))
    for(i in 1:4){
      pa <- peaksAlignment(pd@peaksdata[[1]], pd@peaksdata[[2]],
    # --- Multiplealignment [] ---
    # Key functions: multipleAlignment
    print(targets)
    ma <- multipleAlignment(pd, group=targets$Group, wn.gap=0.5, wn.D=.05,
                            bw.gap=.6, bw.D=0.05, usePeaks=TRUE, filterMin=1,
                            df=50, verbose=FALSE, metric = 1, type = 1) # bug
    ma
    # --- Multiplealignmentfig [] ---
    # Key functions: plotChrom
    plotChrom(pd, rtrange=c(7.5,8.5), runs=ma@betweenAlignment@runs,
         mind=ma@betweenAlignment@ind, plotPeaks=TRUE,
         plotPeakLabels=TRUE, max.near=8, how.near=.5,
         col=rep(c("blue","red","black"), each=3))
    # --- Correlationalignment [] ---
    # Key functions: correlationAlignment
    ## mp <- correlationAlignment(object=pd.2, thr=0.85, D=20, penality=0.2,
    ##                            normalize=TRUE, minFilter=1)
    ## mp
    # --- Alignmentres [] ---
    # Key functions: gatherInfo, unlist
    outList <- gatherInfo(pd,ma)
    outList[[8]]
    rtmat <- matrix(unlist(lapply(outList,.subset,"rt"), use.names=FALSE),
                    nr=length(outList), byrow=TRUE)
    colnames(rtmat) <- names(outList[[1]]$rt); rownames(rtmat) <- 1:nrow(rtmat)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flagme_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flagme_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flagme_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLAGME:", paste0("    flagme: ", packageVersion("flagme"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flagme_results.csv
    touch ${prefix}_flagme_output.rds
    echo "BIOC_FLAGME:" > versions.yml
    echo "    flagme: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLAGME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_FLAGME(ch_input)

    emit:
    results  = BIOC_FLAGME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLAGME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLAGME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLAGME.out.versions  // channel: path(versions.yml)
}
