#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: myvariant
// MyVariant.info is a comprehensive aggregation of variant annotation resources. myvariant is a wrappe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/myvariant/inst/doc/myvariant.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("myvariant")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MYVARIANT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-myvariant"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-myvariant:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-myvariant:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_myvariant_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_myvariant_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_myvariant_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(myvariant)
    library(jsonlite)

    # --- Formathgvs [] ---
    # Key functions: formatHgvs
    hgvs <- formatHgvs(vcf, variant_type="snp")
    head(hgvs)
    # --- Getvariant [] ---
    # Key functions: getVariant
    variant <- getVariant("chr1:g.35367G>A")
    variant[[1]]$dbnsfp$genename
    variant[[1]]$cadd$phred
    # --- Getvariants [] ---
    # Key functions: getVariants
    getVariants(c("chr1:g.35367G>A", "chr16:g.28883241A>G"),
                fields="cadd.consequence")
    # --- Queryvariant [] ---
    # Key functions: queryVariant
    queryVariant(q="dbnsfp.genename:MLL2", fields=c("cadd.phred", "cadd.consequence"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_myvariant_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_myvariant_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_myvariant_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MYVARIANT:", paste0("    myvariant: ", packageVersion("myvariant"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_myvariant_results.csv
    touch ${prefix}_myvariant_output.rds
    echo "BIOC_MYVARIANT:" > versions.yml
    echo "    myvariant: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MYVARIANT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MYVARIANT(ch_input)

    emit:
    results  = BIOC_MYVARIANT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MYVARIANT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MYVARIANT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MYVARIANT.out.versions  // channel: path(versions.yml)
}
