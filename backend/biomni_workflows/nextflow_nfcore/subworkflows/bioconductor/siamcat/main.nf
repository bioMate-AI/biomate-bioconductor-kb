#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SIAMCAT
// Pipeline for Statistical Inference of Associations between Microbial Communities And host phenoTypes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SIAMCAT/inst/doc/SIAMCAT_confounder.R
// Upstream  : curatedMetagenomicData
// Downstream: none
//
// Install: BiocManager::install("SIAMCAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIAMCAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-siamcat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-siamcat:2.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-siamcat:2.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_siamcat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_siamcat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_siamcat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SIAMCAT)
    library(jsonlite)

    # --- clean metadata 1 [] ---
    # Key functions: group_by, ungroup
    select(sampleID, subjectID, study_condition, disease_subtype,
    mutate(visit=str_extract(sampleID, '_[0-9]+$')) %>%
    mutate(visit=str_remove(visit, '_')) %>%
    # --- curated Metagenomic Data [] ---
    # Key functions: curatedMetagenomicData
    feat <- curatedMetagenomicData(x=x, dryrun=FALSE)
    # --- group_by [] ---
    # Key functions: group_by, ungroup
    meta.nielsen <- read_tsv(paste0(data.loc, 'meta_Nielsen.tsv'))
    filter(Group %in% c('CTR', 'UC')) %>%
    group_by(Individual_ID) %>%
    # --- conf assoc plot [] ---
    # Key functions: ggplot, geom_point, xlab, ylab, theme_classic
    assoc.sp <- associations(sc.obj)
    assoc.sp$species <- rownames(assoc.sp)
    assoc.sp_dnk <- associations(sc.obj.full)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: meta, str_detect, ggplot, geom_boxplot, geom_jitter
    feat.dnk <- get.filt_feat.matrix(sc.obj.full)
    label.dnk <- label(sc.obj.full)$label
    country <- meta(sc.obj.full)$Country

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_siamcat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_siamcat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_siamcat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIAMCAT:", paste0("    siamcat: ", packageVersion("SIAMCAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_siamcat_results.csv
    touch ${prefix}_siamcat_output.rds
    echo "BIOC_SIAMCAT:" > versions.yml
    echo "    siamcat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIAMCAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIAMCAT(ch_input)

    emit:
    results  = BIOC_SIAMCAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIAMCAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIAMCAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIAMCAT.out.versions  // channel: path(versions.yml)
}
