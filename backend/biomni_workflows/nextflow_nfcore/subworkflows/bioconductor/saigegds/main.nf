#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SAIGEgds
// Scalable implementation of generalized mixed models with highly optimized C++ implementation and int
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SAIGEgds/inst/doc/SAIGEgds.R
// Upstream  : SNPRelate, SeqArray, ggmanh
// Downstream: none
//
// Install: BiocManager::install("SAIGEgds")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SAIGEGDS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-saigegds"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-saigegds:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-saigegds:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_saigegds_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_saigegds_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_saigegds_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SAIGEgds)
    library(jsonlite)

    # --- Package [] ---
    # Key functions: package, seqOpen
    ---------------------------------------------------------------------------------------------------
    # open a SeqArray file in the package (1000 Genomes Phase1, chromosome 22)
    gds <- seqOpen(geno_fn)
    # --- Seqsetfilter [] ---
    # Key functions: seqSetFilter, seqExport
    ---------------------------------------------------------------------------------------------------
    grm_fn <- "grm_geno.gds"
    seqSetFilter(gds, variant.id=snpset.id)
    # export to a GDS genotype file without annotation data
    seqExport(gds, grm_fn, info.var=character(), fmt.var=character(), samp.var=character())
    # --- Seqclose [] ---
    # Key functions: seqClose
    ---------------------------------------------------------------------------------------------------
    # close the file
    seqClose(gds)
    # --- Seqassocglmm Spa [] ---
    # Key functions: seqAssocGLMM_SPA
    ---------------------------------------------------------------------------------------------------
    # genetic variants stored in the file geno_fn
    geno_fn
    # calculate, using 2 processes
    assoc <- seqAssocGLMM_SPA(geno_fn, glmm, mac=10, parallel=2)
    # --- Seqsaige Loadpval [] ---
    # Key functions: seqSAIGE_LoadPval
    ---------------------------------------------------------------------------------------------------
    res <- seqSAIGE_LoadPval("assoc.gds")
    head(res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_saigegds_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_saigegds_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_saigegds_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SAIGEGDS:", paste0("    saigegds: ", packageVersion("SAIGEgds"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_saigegds_results.csv
    touch ${prefix}_saigegds_output.rds
    echo "BIOC_SAIGEGDS:" > versions.yml
    echo "    saigegds: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SAIGEGDS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SAIGEGDS(ch_input)

    emit:
    results  = BIOC_SAIGEGDS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SAIGEGDS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SAIGEGDS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SAIGEGDS.out.versions  // channel: path(versions.yml)
}
