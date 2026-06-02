#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSReg
// A package for gene set analysis based on the variability of expressions as well as a method to detec
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSReg/inst/doc/GSReg.R
// Upstream  : GSBenchMark, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("GSReg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSREG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsreg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsreg:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsreg:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsreg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsreg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsreg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DIRAC)
    library(EVA)
    library(SEVA)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, class
    library(GSBenchMark)
    data(diracpathways)
    class(diracpathways)
    names(diracpathways)[1:5]
    class(diracpathways[[1]])
    # --- Data [] ---
    # Key functions: data
    data(GSBenchMarkDatasets)
    print(GSBenchMark.Dataset.names)
    # --- Time [] ---
    # Key functions: time, DIRAC
    Nperm = 10
    system.time({DIRACperm =GSReg.GeneSets.DIRAC(exprsdata,diracpathways,phenotypes,Nperm=Nperm)})
    system.time({DIRACAn =GSReg.GeneSets.DIRAC(exprsdata,diracpathways,phenotypes)})
    # --- Plot [] ---
    # Key functions: pnorm
    plot(x=abs(DIRACAn$zscores),y=DIRACperm$pvalues,xlab="|Z-score|",
         ylab="p-value",col="red1",main="DIRAC p-value comparisons")
    zscorelin <- seq(min(abs(DIRACAn$zscores)),max(abs(DIRACAn$zscores)),by = 0.1)
    pvaltheoretic = (1-pnorm(zscorelin))*2
    lines(x=zscorelin,y=pvaltheoretic,type="l",pch=50,lty=5,col="darkblue")
    # --- Time [] ---
    # Key functions: time, EVA, factor
    #Calculating the variance for the pathways
    #Calculate how much it takes to calculate the statistics and their p-value for all pathways
    system.time({VarAnKendallV = GSReg.GeneSets.EVA(geneexpres=exprsdata,
      pathways=diracpathways, phenotypes=as.factor(phenotypes)) })
    names(VarAnKendallV)[[1]]
    # --- Vector [] ---
    # Key functions: EVA, sample
    Nperm = 10;
    VarAnPerm = vector(mode="list",length=Nperm)
    for( i in seq_len(Nperm))
    # --- Plot [] ---
    # Key functions: pnorm
    plot(x=abs(zscore),y=pvaluesperm,xlab="|Z-score|",
      ylab="p-value",col="red1",main="p-value comparisons")
     zscorelin = seq(0,6,0.1);
     pvaltheoretic = (1-pnorm(zscorelin))*2
     lines(x=zscorelin,y=pvaltheoretic,type="l",pch=50,lty=5,col="darkblue")
    # --- Plot [] ---
    # Key functions: lm, test
    plot(x=DIRACAn$pvalues,y=pvalustat,xlab ="DIRAC",
            ylab="EVA",main=sprintf("P-value Comparison corr=%2.2g",cor(x=DIRACAn$pvalues,y=pvalustat)))
    lmfit = lm(pvalustat~DIRACAn$pvalues-1)
    abline(lmfit)
    cor.test(x=DIRACAn$pvalues,y=pvalustat)
    # --- Plot [] ---
    # Key functions: lm
    plot(x=DIRACAn$pvalues,y=pvalustat,xlab ="DIRAC",
            ylab="EVA",main=sprintf("P-value Comparison corr=%2.2g",cor(x=DIRACAn$pvalues,y=pvalustat)))
      lmfit = lm(pvalustat~DIRACAn$pvalues-1)
    abline(lmfit)
    # --- Dirac [] ---
    # Key functions: DIRAC
    ## DIRACAn =GSReg.GeneSets.DIRAC(exprsdata,diracpathways,phenotypes,Nperm=1000)
    # --- Data [] ---
    # Key functions: overlapJunction
    require('Homo.sapiens')
    require('org.Hs.eg.db')
    require('GenomicRanges')
    data(juncExprsSimulated)
    # --- Data [] ---
    # Key functions: SEVA
    data(juncExprsSimulated)
    SEVAjunc <- GSReg.SEVA(juncExprs = junc.RPM.Simulated,
                           phenoVect = phenotypes,
                           geneexpr = geneExrsGSReg)
    print(sapply(SEVAjunc,function(x) x$pvalue))
    # --- Sessioinfo [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsreg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsreg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsreg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSREG:", paste0("    gsreg: ", packageVersion("GSReg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsreg_results.csv
    touch ${prefix}_gsreg_output.rds
    echo "BIOC_GSREG:" > versions.yml
    echo "    gsreg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSREG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSREG(ch_input)

    emit:
    results  = BIOC_GSREG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSREG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSREG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSREG.out.versions  // channel: path(versions.yml)
}
