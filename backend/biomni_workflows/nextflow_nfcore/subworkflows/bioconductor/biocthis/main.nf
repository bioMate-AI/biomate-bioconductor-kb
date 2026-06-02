#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biocthis
// This package expands the usethis package with the goal of helping automate the process of creating R
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biocthis/inst/doc/biocthis.R
// Upstream  : RefManageR, usethis, styler, rmarkdown, knitr
// Downstream: none
//
// Install: BiocManager::install("biocthis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCTHIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocthis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocthis:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocthis:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocthis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocthis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocthis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(jsonlite)

    # --- "install" [] ---
    # Key functions: valid
    if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
    BiocManager::install("biocthis")
    # --- 'create example pkg' [] ---
    # Key functions: biocthis_example_pkg
    pkgdir <- biocthis_example_pkg("biocthispkg", use_git = TRUE)
    # --- 'create dev' [] ---
    # Key functions: use_bioc_pkg_templates
    biocthis::use_bioc_pkg_templates()
    # --- 'bioc badges' [] ---
    # Key functions: use_bioc_badges
    biocthis::use_bioc_badges()
    # --- 'style code' [] ---
    # Key functions: style_pkg
    styler::style_pkg(pkgdir, transformers = biocthis::bioc_style())
    # --- 'bioc citation' [] ---
    # Key functions: use_bioc_citation
    biocthis::use_bioc_citation()
    # --- 'bioc description' [] ---
    # Key functions: use_bioc_description
    biocthis::use_bioc_description()
    # --- 'bioc github action' [] ---
    # Key functions: use_bioc_github_action
    biocthis::use_bioc_github_action()
    # --- 'bioc issue template' [] ---
    # Key functions: use_bioc_issue_template
    biocthis::use_bioc_issue_template()
    # --- 'bioc news' [] ---
    # Key functions: use_bioc_news_md
    biocthis::use_bioc_news_md()
    # --- "bioc pkgdown css" [] ---
    # Key functions: use_bioc_pkgdown_css
    biocthis::use_bioc_pkgdown_css()
    # --- 'bioc readme rmd' [] ---
    # Key functions: use_bioc_readme_rmd
    biocthis::use_bioc_readme_rmd()
    # --- 'bioc support' [] ---
    # Key functions: use_bioc_support
    biocthis::use_bioc_support()
    # --- 'bioc vignette' [] ---
    # Key functions: use_bioc_vignette
    biocthis::use_bioc_vignette("biocthispkg", "Introduction to biocthispkg")
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("biocthis.Rmd", "BiocStyle::html_document"))
    library("knitr")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocthis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocthis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocthis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCTHIS:", paste0("    biocthis: ", packageVersion("biocthis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocthis_results.csv
    touch ${prefix}_biocthis_output.rds
    echo "BIOC_BIOCTHIS:" > versions.yml
    echo "    biocthis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCTHIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCTHIS(ch_input)

    emit:
    results  = BIOC_BIOCTHIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCTHIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCTHIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCTHIS.out.versions  // channel: path(versions.yml)
}
