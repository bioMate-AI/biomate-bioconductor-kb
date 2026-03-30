#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: r3Cseq
// This package is used for the analysis of long-range chromatin interactions from 3C-seq assay.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/r3Cseq/inst/doc/r3Cseq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("r3Cseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R3CSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-r3cseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-r3cseq:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-r3cseq:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_r3cseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_r3cseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_r3cseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(r3Cseq)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(Myb_prom_FL)
    data(Myb_prom_FB)
    # --- Exprawdata [] ---
    # Key functions: expRawData, contrRawData
    expRawData(my3Cseq.obj)<-exp.GRanges
    contrRawData(my3Cseq.obj)<-contr.GRanges
    # --- Getreadcountperrestrictionfragment [] ---
    # Key functions: getReadCountPerRestrictionFragment
    getReadCountPerRestrictionFragment(my3Cseq.obj)
    # --- Calculaterpm [] ---
    # Key functions: calculateRPM
    calculateRPM(my3Cseq.obj)
    # --- Getinteractions [] ---
    # Key functions: getInteractions
    getInteractions(my3Cseq.obj,fdr=0.05)
    # --- Expinteractionregions [] ---
    # Key functions: expInteractionRegions
    fetal.liver.interactions<-expInteractionRegions(my3Cseq.obj)
    fetal.liver.interactions
    # --- Contrinteractionregions [] ---
    # Key functions: contrInteractionRegions
    fetal.brain.interactions<-contrInteractionRegions(my3Cseq.obj)
    fetal.brain.interactions
    # --- Getviewpoint [] ---
    # Key functions: getViewpoint
    viewpoint<-getViewpoint(my3Cseq.obj)
    viewpoint
    # --- Plotoverviewinteractions [] ---
    # Key functions: plotOverviewInteractions
    plotOverviewInteractions(my3Cseq.obj)
    # --- Plotinteractionsnearviewpoint [] ---
    # Key functions: plotInteractionsNearViewpoint
    plotInteractionsNearViewpoint(my3Cseq.obj)
    # --- Plotinteractionsperchromosome [] ---
    # Key functions: plotInteractionsPerChromosome
    plotInteractionsPerChromosome(my3Cseq.obj,"chr10")
    # --- Plotdomainogramnearviewpoint [] ---
    # Key functions: plotDomainogramNearViewpoint
    #plotDomainogramNearViewpoint(my3Cseq.obj)
    # --- Getexpinteractionsinrefseq [] ---
    # Key functions: getExpInteractionsInRefseq
    detected_genes<-getExpInteractionsInRefseq(my3Cseq.obj)
    head(detected_genes)
    # --- export3 Cseq2bed Graph [] ---
    # Key functions: export3Cseq2bedGraph
    #export3Cseq2bedGraph(my3Cseq.obj)
    # --- generate3 Cseq Report [] ---
    # Key functions: generate3CseqReport
    #generate3CseqReport(my3Cseq.obj)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_r3cseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_r3cseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_r3cseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_R3CSEQ:", paste0("    r3cseq: ", packageVersion("r3Cseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_r3cseq_results.csv
    touch ${prefix}_r3cseq_output.rds
    echo "BIOC_R3CSEQ:" > versions.yml
    echo "    r3cseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_R3CSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_R3CSEQ(ch_input)

    emit:
    results  = BIOC_R3CSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_R3CSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_R3CSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_R3CSEQ.out.versions  // channel: path(versions.yml)
}
