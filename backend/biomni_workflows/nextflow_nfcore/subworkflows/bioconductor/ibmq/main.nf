#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iBMQ
// integrated Bayesian Modeling of eQTL data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iBMQ/inst/doc/iBMQ.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("iBMQ")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IBMQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ibmq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ibmq:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ibmq:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ibmq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ibmq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ibmq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iBMQ)
    library(jsonlite)

    # --- Calculate Ppa [] ---
    # Key functions: eqtlMcmc
    ## #  PPA <-  eqtlMcmc(snp, gene, n.iter=100,burn.in=100,n.sweep=20,mc.cores=6, RIS=TRUE)
    # --- Calculatethreshold [] ---
    # Key functions: calculateThreshold
    ## cutoff <- calculateThreshold(PPA, 0.1)
    # --- Count Eqtl [] ---
    # Key functions: eqtlFinder
    ## eqtl <- eqtlFinder(PPA, cutoff)
    # --- Class Snp Data [] ---
    # Key functions: eqtlClassifier
    ## eqtltype <- eqtlClassifier(eqtl, snppos, genepos,1000000)
    # --- Ploteqtls [] ---
    # Key functions: ggplot, aes, geom_point, facet_grid, theme_bw, theme, element_blank
    ## library(ggplot2)
    ## ggplot(eqtltype, aes(y=GeneStart, x=MarkerPosition)) +
    ## geom_point(aes(y=GeneStart, x=MarkerPosition,color = PPA), size = 1.5)+
    ## facet_grid(GeneChrm~MarkerChrm)+theme_bw(base_size = 12, base_family = "")+
    ## theme(axis.ticks = element_blank(), axis.text.x = element_blank(), axis.text.y = element_blank())+scale_x_reverse()
    # --- Hotpot [] ---
    # Key functions: hotspotFinder
    ## hotspot <- hotspotFinder(eqtltype, 10)
    # --- Hotpot [] ---
    # Key functions: data
    ## data(genotype.liver)
    # --- Hotpot [] ---
    # Key functions: eqtlMcmc
    ## #PPA.liver <-  eqtlMcmc(genotype.liver, phenotype.liver, n.iter=100,burn.in=100,n.sweep=20,mc.cores=6, RIS=FALSE)
    # --- Hotpot [] ---
    # Key functions: calculateThreshold
    cutoff.liver <- calculateThreshold(PPA.liver, 0.2)
    # --- Hotpot [] ---
    # Key functions: eqtlFinder
    eqtl.liver <- eqtlFinder(PPA.liver, cutoff.liver)
    # --- Hotpot [] ---
    # Key functions: eqtlClassifier
    eqtl.type.liver <- eqtlClassifier(eqtl.liver, map.liver, probe.liver,5000000)
    # --- Ploteqtls [] ---
    # Key functions: ggplot, aes, geom_point, facet_grid, theme_bw, theme, element_blank
    library(ggplot2)
    ggplot(eqtl.type.liver, aes(y=GeneStart, x=MarkerPosition)) +
    geom_point(aes(y=GeneStart, x=MarkerPosition,color = PPA), size = 1.5)+
    facet_grid(GeneChrm~MarkerChrm)+theme_bw(base_size = 12, base_family = "")+
    theme(axis.ticks = element_blank(), axis.text.x = element_blank(), axis.text.y = element_blank())+scale_x_reverse()
    # --- Hotpot [] ---
    # Key functions: hotspotFinder
    ## hotspot.liver <- hotspotFinder(eqtl.type.liver,20)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ibmq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ibmq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ibmq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IBMQ:", paste0("    ibmq: ", packageVersion("iBMQ"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ibmq_results.csv
    touch ${prefix}_ibmq_output.rds
    echo "BIOC_IBMQ:" > versions.yml
    echo "    ibmq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IBMQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IBMQ(ch_input)

    emit:
    results  = BIOC_IBMQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IBMQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IBMQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IBMQ.out.versions  // channel: path(versions.yml)
}
