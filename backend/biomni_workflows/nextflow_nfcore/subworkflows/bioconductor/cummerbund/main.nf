#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cummeRbund
// Allows for persistent storage, access, exploration, and manipulation of Cufflinks high-throughput se
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cummeRbund/inst/doc/cummeRbund-example-workflow.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cummeRbund")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CUMMERBUND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cummerbund"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cummerbund:2.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cummerbund:2.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cummerbund_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cummerbund_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cummerbund_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cummeRbund)
    library(jsonlite)

    # --- Model Fit 1 [] ---
    # Key functions: dispersionPlot, genes
    d<-dispersionPlot(genes(cuff))
    d
    # --- Model Fit 1 Plot [] ---
    # Key functions: dispersionPlot, genes
    d<-dispersionPlot(genes(cuff))
    d
    print(d)
    # --- Rep Boxplot 1 [] ---
    # Key functions: csBoxplot, genes
    pBoxRep<-csBoxplot(genes(cuff),replicates=T)
    pBoxRep
    # --- Rep Dendro 1 [] ---
    # Key functions: csDendro, genes
    pDendro<-csDendro(genes(cuff),replicates=T)
    pDendro
    # --- Rep Boxplot 1 Plot [] ---
    # Key functions: csBoxplot, genes
    pBoxRep<-csBoxplot(genes(cuff),replicates=T)
    pBoxRep
    print(pBoxRep)
    # --- Rep Dendro 1 Plot [] ---
    # Key functions: csDendro, genes
    pDendro<-csDendro(genes(cuff),replicates=T)
    pDendro
    print(pDendro)
    # --- Boxplot 1 [] ---
    # Key functions: csBoxplot, genes
    pBox<-csBoxplot(genes(cuff))
    pBox
    # --- Boxplot 1 Plot [] ---
    # Key functions: csBoxplot, genes
    pBox<-csBoxplot(genes(cuff))
    pBox
    print(pBox)
    # --- Diff Exp Genes 1 [] ---
    # Key functions: getSig
    sigGeneIds<-getSig(cuff,alpha=0.05,level="genes")
    head(sigGeneIds)
    length(sigGeneIds)
    # --- Diff Exp Genes 2 [] ---
    # Key functions: getSig
    hESCvsFibroblast.sigGeneIds<-getSig(cuff,"hESC","Fibroblasts",alpha=0.05,level="genes")
    head(hESCvsFibroblast.sigGeneIds)
    length(hESCvsFibroblast.sigGeneIds)
    # --- Diff Exp Genes 3 [] ---
    # Key functions: getGenes
    sigGenes<-getGenes(cuff,sigGeneIds)
    sigGenes
    # --- Diff Exp Feat 1 [] ---
    # Key functions: getSig
    sigGeneIds<-getSig(cuff,alpha=0.05,level="isoforms")
    head(sigGeneIds)
    length(sigGeneIds)
    # --- Ind Gene 1 [] ---
    # Key functions: getGene
    Pink1<-getGene(cuff,'PINK1')
    Pink1

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cummerbund_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cummerbund_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cummerbund_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CUMMERBUND:", paste0("    cummerbund: ", packageVersion("cummeRbund"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cummerbund_results.csv
    touch ${prefix}_cummerbund_output.rds
    echo "BIOC_CUMMERBUND:" > versions.yml
    echo "    cummerbund: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CUMMERBUND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CUMMERBUND(ch_input)

    emit:
    results  = BIOC_CUMMERBUND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CUMMERBUND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CUMMERBUND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CUMMERBUND.out.versions  // channel: path(versions.yml)
}
