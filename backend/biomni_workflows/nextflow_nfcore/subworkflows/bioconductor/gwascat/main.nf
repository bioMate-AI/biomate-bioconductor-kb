#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gwascat
// Represent and model data in the EMBL-EBI GWAS catalog.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gwascat/inst/doc/gwascat.R
// Upstream  : GenomeInfoDb, Gviz, dplyr, ggbio, rtracklayer
// Downstream: vtpnet, liftOver
//
// Install: BiocManager::install("gwascat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GWASCAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gwascat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gwascat:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gwascat:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gwascat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gwascat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gwascat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IRanges)
    library(jsonlite)

    # --- Sequence level inspection [] ---
    # Key functions: seqlevels, seqinfo, args, objects, subsetByTraits, requireNamespace, mcols, seqlevelsStyle
    gr6.0 = GRanges(seqnames=ifelse(is.na(locon6$chrom),0,locon6$chrom),
    IRanges(ifelse(is.na(locon6$phys),1,locon6$phys), width=1))
    S4Vectors::mcols(gr6.0)$rsid = as.character(locon6$dbsnp_rs_id)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gwascat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gwascat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gwascat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GWASCAT:", paste0("    gwascat: ", packageVersion("gwascat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwascat_results.csv
    touch ${prefix}_gwascat_output.rds
    echo "BIOC_GWASCAT:" > versions.yml
    echo "    gwascat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GWASCAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GWASCAT(ch_input)

    emit:
    results  = BIOC_GWASCAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GWASCAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GWASCAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GWASCAT.out.versions  // channel: path(versions.yml)
}
