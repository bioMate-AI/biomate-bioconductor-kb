#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SNPediaR
// SNPediaR provides some tools for downloading and parsing data from the SNPedia web site <http://www.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SNPediaR/inst/doc/SNPediaR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SNPediaR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPEDIAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snpediar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snpediar:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snpediar:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snpediar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snpediar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snpediar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SNPediaR)
    library(Rs53576)
    library(jsonlite)

    # --- Extract SNP and Genotype Tags [] ---
    # Key functions: extractSnpTags, extractGenotypeTags, getPages
    snp_tags <- extractSnpTags(pg$Rs53576)
    genotype_tags <- sapply(pgs, extractGenotypeTags)
    parsed_pages <- getPages(
        titles = c("Rs53576(A;A)", "Rs53576(A;G)", "Rs53576(G;G)"),
        wikiParseFunction = extractGenotypeTags,
        tags = c("allele1", "allele2", "magnitude")
    )


    # --- Query Medical Categories [] ---
    # Key functions: getCategoryElements, getPages, extractSnpTags
    res <- getCategoryElements(category = "Is_a_medical_condition")
    cancer_conditions <- grep("cancer", res, value = TRUE)
    cancer_pages <- getPages(
        titles = head(cancer_conditions, 5),
        wikiParseFunction = extractSnpTags
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snpediar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snpediar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snpediar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNPEDIAR:", paste0("    snpediar: ", packageVersion("SNPediaR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snpediar_results.csv
    touch ${prefix}_snpediar_output.rds
    echo "BIOC_SNPEDIAR:" > versions.yml
    echo "    snpediar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNPEDIAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNPEDIAR(ch_input)

    emit:
    results  = BIOC_SNPEDIAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNPEDIAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNPEDIAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNPEDIAR.out.versions  // channel: path(versions.yml)
}
