#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiDataSet
// Implementation of the BRGE's (Bioinformatic Research Group in Epidemiology from Center for Research 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiDataSet/inst/doc/MultiDataSet.R
// Upstream  : Biobase, GenomicRanges, brgedata
// Downstream: MEAL
//
// Install: BiocManager::install("MultiDataSet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIDATASET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multidataset"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multidataset:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multidataset:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multidataset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multidataset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multidataset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- New Multi [] ---
    # Key functions: createMultiDataSet
    multi <- createMultiDataSet()
    # --- add eset 10 [] ---
    # Key functions: add_eset
    data("brge_gexp")
    multi2 <- add_eset(multi, brge_gexp, dataset.type = "expression")
    # --- add eset 2 [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi2, brge_gexp, dataset.type = "expression", dataset.name = "new")
    # --- add eset add id to eset [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp2, dataset.type = "expression")
    # --- add eset overwrite [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp, dataset.type = "expression", warnings = FALSE)
    multi2 <- add_eset(multi2, brge_gexp2, dataset.type = "expression", warnings = FALSE, overwrite = FALSE)
    multi2 <- add_eset(multi2, brge_gexp2, dataset.type = "expression", warnings = FALSE, overwrite = TRUE)
    # --- add eset GRanges [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp, dataset.type = "expression", warnings = FALSE, GRanges = NA)
    # --- add rse overwrite [] ---
    # Key functions: createMultiDataSet, add_rse
    data("brge_methy")
    multi <- createMultiDataSet()
    multi2 <- add_rse(multi, brge_methy, dataset.type = "methylation", warnings = FALSE)
    # --- create Multi Data Set [] ---
    # Key functions: createMultiDataSet, add_genexp
    multi <- createMultiDataSet()
    multi2 <- add_genexp(multi, brge_gexp)
    # --- add_genexp [] ---
    # Key functions: add_genexp
    multi2 <- add_genexp(multi2, brge_gexp, dataset.name = "2")
    # --- Subsetting intro [] ---
    # Key functions: createMultiDataSet, add_methy, add_genexp, add_eset
    multi <- createMultiDataSet()
    multi <- add_methy(multi, brge_methy)
    multi <- add_genexp(multi, brge_gexp)
    # --- sample Names [] ---
    # Key functions: sampleNames
    samples <- sampleNames(brge_gexp)[76:100]
    # --- subset common samples [] ---
    # Key functions: commonSamples
    commonSamples(multi)
    length(intersect(sampleNames(brge_gexp), sampleNames(brge_methy)))
    # --- Genomic Ranges [] ---
    # Key functions: GRanges
    range <- GRanges("chr17:1-100000")
    # --- Genomic Ranges 2 [] ---
    # Key functions: GRanges
    range2 <- GRanges(c("chr17:1-100000", "chr17:1000000-2000000"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multidataset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multidataset_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multidataset_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIDATASET:", paste0("    multidataset: ", packageVersion("MultiDataSet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multidataset_results.csv
    touch ${prefix}_multidataset_output.rds
    echo "BIOC_MULTIDATASET:" > versions.yml
    echo "    multidataset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIDATASET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIDATASET(ch_input)

    emit:
    results  = BIOC_MULTIDATASET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIDATASET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIDATASET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIDATASET.out.versions  // channel: path(versions.yml)
}
