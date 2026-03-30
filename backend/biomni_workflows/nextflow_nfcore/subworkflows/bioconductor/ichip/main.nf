#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iChip
// Hidden Ising models are implemented to identify enriched genomic regions in ChIP-chip data.  They ca
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iChip/inst/doc/iChip.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iChip")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICHIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ichip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ichip:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ichip:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ichip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ichip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ichip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iChip)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(iChip)
    data(oct4)
    head(oct4,n=3L)
    # --- Lmtstat [] ---
    # Key functions: lmtstat
    oct4lmt = lmtstat(oct4[,5:6],oct4[,3:4])
    # --- Enrichreg [] ---
    # Key functions: enrichreg
    reg1 = enrichreg(pos=oct4[,1:2],enrich=oct4lmt,pp=oct4res2$pp,
      cutoff=0.9,method="ppcut",maxgap=500)
    print(reg1)
    # --- Frame [] ---
    # Key functions: frame
    bed1 = data.frame(chr=paste("chr",reg2[,1],sep=""),reg2[,2:3])
    print(bed1[1:2,])
    # --- Ichip1 [] ---
    # Key functions: iChip1
    oct4res1 =iChip1(enrich=oct4lmt,burnin=2000,sampling=10000,sdcut=2,beta0=3,
      minbeta=0,maxbeta=10,normsd=0.1,verbose=FALSE)
    # --- Enrichreg [] ---
    # Key functions: enrichreg
    enrichreg(pos=oct4[,1:2],enrich=oct4lmt,pp=oct4res1$pp,cutoff=0.9,
              method="ppcut",maxgap=500)
    enrichreg(pos=oct4[,1:2],enrich=oct4lmt,pp=oct4res1$pp,cutoff=0.01,
              method="fdrcut",maxgap=500)
    # --- Data [] ---
    # Key functions: lmtstat
    data(p53)
    head(p53,n=3L)
    # sort the p53 data by chromosome and genomic position
    p53 = p53[order(p53[,1],p53[,2]),]
    p53lmt = lmtstat(p53[,9:14],p53[,3:8])
    # --- Ichip2 [] ---
    # Key functions: iChip2
    p53res2 = iChip2(Y=p53Y,burnin=2000,sampling=10000,winsize=2,sdcut=2,beta=2.5)
    # --- Enrichreg [] ---
    # Key functions: enrichreg
    enrichreg(pos=p53[,1:2],enrich=p53lmt,pp=p53res2$pp,cutoff=0.9,
              method="ppcut",maxgap=500)
    enrichreg(pos=p53[,1:2],enrich=p53lmt,pp=p53res2$pp,cutoff=0.01,
              method="fdrcut",maxgap=500)
    # --- Ichip1 [] ---
    # Key functions: iChip1
    p53res1 =iChip1(enrich=p53lmt,burnin=2000,sampling=10000,sdcut=2,beta0=3,
      minbeta=0,maxbeta=10,normsd=0.1,verbose=FALSE)
    # --- Enrichreg [] ---
    # Key functions: enrichreg
    enrichreg(pos=p53[,1:2],enrich=p53lmt,pp=p53res1$pp,cutoff=0.9,
              method="ppcut",maxgap=500)
    enrichreg(pos=p53[,1:2],enrich=p53lmt,pp=p53res1$pp,cutoff=0.01,
              method="fdrcut",maxgap=500)
    # --- Ichip1 [] ---
    # Key functions: iChip1
    randomres1 =iChip1(enrich=randomY[,2],burnin=1000,sampling=5000,sdcut=2,
      beta0=3,minbeta=0,maxbeta=10,normsd=0.1,verbose=FALSE)
    table(randomres1$pp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ichip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ichip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ichip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICHIP:", paste0("    ichip: ", packageVersion("iChip"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ichip_results.csv
    touch ${prefix}_ichip_output.rds
    echo "BIOC_ICHIP:" > versions.yml
    echo "    ichip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICHIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICHIP(ch_input)

    emit:
    results  = BIOC_ICHIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICHIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICHIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICHIP.out.versions  // channel: path(versions.yml)
}
