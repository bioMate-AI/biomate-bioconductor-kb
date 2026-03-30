#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: casper
// Infer alternative splicing from paired-end RNA-seq data. The model is based on counting paths across
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/casper/inst/doc/casper.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("casper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CASPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-casper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-casper:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-casper:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_casper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_casper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_casper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(casper)
    library(jsonlite)

    # --- Process1 [] ---
    # Key functions: data
    library(casper)
    data(K562.r1l1)
    names(K562.r1l1)
    data(hg19DB)
    hg19DB
    # --- Process2 [] ---
    # Key functions: rmShortInserts, getDistrs
    bam0 <- rmShortInserts(K562.r1l1, isizeMin=100)
    distrs <- getDistrs(hg19DB,bam=bam0,readLength=75)
    # --- Procbam [] ---
    # Key functions: procBam, getReads
    pbam0 <- procBam(bam0)
    pbam0
    head(getReads(pbam0))
    # --- Pathcounts [] ---
    # Key functions: pathCounts
    pc <- pathCounts(pbam0, DB=hg19DB)
    pc
    head(pc@counts[[1]])
    # --- Calcexp [] ---
    # Key functions: calcExp, exprs, fData
    eset <- calcExp(distrs=distrs, genomeDB=hg19DB, pc=pc, readLength=75, rpkm=FALSE)
    eset
    head(exprs(eset))
    head(fData(eset))
    # --- Relisoformexpr [] ---
    # Key functions: calcExp, exprs
    eset <- calcExp(distrs=distrs, genomeDB=hg19DB, pc=pc, readLength=75, rpkm=TRUE)
    head(exprs(eset))
    # --- Plot1 [] ---
    # Key functions: transcripts, getChr, getIsland
    transcripts(hg19DB)
    tx <- transcripts(hg19DB, txid='NM_005158')
    tx
    getChr(txid='NM_005158',genomeDB=hg19DB)
    islandid <- getIsland(txid='NM_005158',genomeDB=hg19DB)
    # --- Plot2 [] ---
    # Key functions: genePlot
    genePlot(islandid=islandid,genomeDB=hg19DB)
    # --- Plot3 [] ---
    # Key functions: genePlot
    genePlot(islandid=islandid,genomeDB=hg19DB,reads=pbam0,exp=eset)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_casper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_casper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_casper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CASPER:", paste0("    casper: ", packageVersion("casper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_casper_results.csv
    touch ${prefix}_casper_output.rds
    echo "BIOC_CASPER:" > versions.yml
    echo "    casper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CASPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CASPER(ch_input)

    emit:
    results  = BIOC_CASPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CASPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CASPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CASPER.out.versions  // channel: path(versions.yml)
}
