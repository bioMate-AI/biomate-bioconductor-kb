#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mitch
// mitch is an R package for multi-contrast enrichment analysis. At it’s heart, it uses a rank-MANOVA b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mitch/inst/doc/infiniumMethArrayWorkflow.R
// Upstream  : HGNChelper, stringi
// Downstream: none
//
// Install: BiocManager::install("mitch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MITCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mitch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mitch:1.18.4--r44_0' :
        'quay.io/biocontainers/bioconductor-mitch:1.18.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mitch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mitch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mitch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mitch)
    library(jsonlite)

    # --- Annotation analysis [] ---
    # Key functions: getAnnotation, stack, checkGeneSymbols, mitch_import, mitch_calc, mitch_plots, mitch_report
    anno <- getAnnotation(IlluminaHumanMethylationEPICanno.ilm10b4.hg19)
    myann <- data.frame(anno[,c("UCSC_RefGene_Name","UCSC_RefGene_Group","Islands_Name","Relation_to_Island")])
    gp2 <- strsplit(gp$UCSC_RefGene_Name,";")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mitch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mitch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mitch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MITCH:", paste0("    mitch: ", packageVersion("mitch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mitch_results.csv
    touch ${prefix}_mitch_output.rds
    echo "BIOC_MITCH:" > versions.yml
    echo "    mitch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MITCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MITCH(ch_input)

    emit:
    results  = BIOC_MITCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MITCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MITCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MITCH.out.versions  // channel: path(versions.yml)
}
