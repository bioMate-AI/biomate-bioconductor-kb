#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: maskBAD
// Package includes functions to analyze and mask microarray expression data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/maskBAD/inst/doc/maskBAD.R
// Upstream  : gcrma, hgu95av2probe
// Downstream: none
//
// Install: BiocManager::install("maskBAD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MASKBAD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-maskbad"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-maskbad:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-maskbad:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_maskbad_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_maskbad_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_maskbad_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(maskBAD)
    library(jsonlite)

    # --- Affybatch [] ---
    # Key functions: mask
    ## data available by loading data(AffyBatch)
    newAffyBatch
    exmask <- mask(newAffyBatch,ind=rep(1:2,each=10),verbose=FALSE,useExpr=F)
    # --- Quantile [] ---
    # Key functions: plotProbe
    ## add rownames containing x and y coordinates of each probe
    rownames(exmask[[1]]) <-apply(exmask[[1]][,c("x","y")],1,
                                  function(x)paste(x[1],x[2],sep="."))
    ## filtering for probes around the choosen cutoff
    probesToSee = rownames(exmask[[1]][exmask[[1]]$quality.score<0.03
    # --- Err [] ---
    # Key functions: overlapExprExtMasks
    overlapExSeq <- overlapExprExtMasks(exmask$probes[,1:3],
                                        sequenceMask[,c(1,2,4)],verbose=FALSE,
                                        cutoffs=quantile(exmask$probes[,3],seq(0,1,0.05)))
    # --- Figerr [] ---
    # Key functions: overlapExprExtMasks
    overlapExSeq <- overlapExprExtMasks(exmask$probes[,1:3],
                                        sequenceMask[,c(1,2,4)],verbose=FALSE,
                                        cutoffs=quantile(exmask$probes[,3],seq(0,1,0.05)))
    # --- Err [] ---
    # Key functions: overlapExprExtMasks
    overlapTests <- overlapExprExtMasks(exmask$probes[,1:3],verbose=FALSE,
                                        sequenceMask[,c(1,2,4)],
                                        wilcox.ks=T,sample=100)
    # --- Figwil1 [] ---
    # Key functions: value, signif
    plot(overlapTests$testCutoff[[1]],overlapTests$ksBoot,col="lightgrey",
         main="Kolmogorov-Smirnov Test",xlab="Quality score cutoff",
         ylab="p value (Kolmogorov-Smirnov Test)",ylim=c(0,1),pch=16,xaxt="n",cex=1.5)
    axis(1,at=seq(1,length(unique(overlapTests$testCutoff[[2]])),2),
         labels=signif(unique(overlapTests$testCutoff[[2]]),2)[seq(1,length(unique(overlapTests$testCutoff[[2]])),2)],
    # --- Figwil2 [] ---
    # Key functions: value, signif
    plot(overlapTests$testCutoff[[1]],overlapTests$wilcoxonBoot,col="lightgrey",
         main="Wilcoxon Rank Sum Test",xlab="Quality score cutoff",
         ylab="p value (Wilcoxon Rank Sum Test)",ylim=c(0,1),pch=16,xaxt="n",cex=1.5)
    axis(1,at=seq(1,length(unique(overlapTests$testCutoff[[2]])),2),
         labels=signif(unique(overlapTests$testCutoff[[2]]),2)[seq(1,length(unique(overlapTests$testCutoff[[2]])),2)],
    # --- Affbs [] ---
    # Key functions: prepareMaskedAffybatch
    affyBatchAfterMasking <-
      prepareMaskedAffybatch(affy=newAffyBatch,exmask=exmask$probes,
                             cutoff=quantile(exmask[[1]]$quality.score,0.22))
    newAffyBatch
    affyBatchAfterMasking
    # --- Cdf [] ---
    # Key functions: cdfName
    cdfName(affyBatchAfterMasking[[1]])
    # --- Rmaex [] ---
    # Key functions: exprs, rma
    new_cdf=affyBatchAfterMasking[[2]]
    head(exprs(rma(affyBatchAfterMasking[[1]])))
    # --- Grmaex1 [] ---
    # Key functions: affinities
    library(gcrma)
    library(hgu95av2probe)
    affy.affinities=compute.affinities("hgu95av2",verbose=FALSE)
    # --- Grmaex2 [] ---
    # Key functions: prepareMaskedAffybatch
    affy.affinities.m=prepareMaskedAffybatch(affy=affy.affinities,
      exmask=exmask$probes,cdfName="MaskedAffinitesCdf")
    # --- Grmaex2 [] ---
    # Key functions: exprs, gcrma
    head(exprs(gcrma(affyBatchAfterMasking[[1]],affy.affinities.m)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_maskbad_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_maskbad_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_maskbad_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MASKBAD:", paste0("    maskbad: ", packageVersion("maskBAD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_maskbad_results.csv
    touch ${prefix}_maskbad_output.rds
    echo "BIOC_MASKBAD:" > versions.yml
    echo "    maskbad: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MASKBAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MASKBAD(ch_input)

    emit:
    results  = BIOC_MASKBAD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MASKBAD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MASKBAD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MASKBAD.out.versions  // channel: path(versions.yml)
}
