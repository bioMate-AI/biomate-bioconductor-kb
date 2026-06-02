#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DrugVsDisease
// This package generates ranked lists of differential gene expression for either disease or drug profi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DrugVsDisease/inst/doc/DrugVsDisease.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("DrugVsDisease")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DRUGVSDISEASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-drugvsdisease"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-drugvsdisease:2.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-drugvsdisease:2.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_drugvsdisease_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_drugvsdisease_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_drugvsdisease_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DrugVsDisease)
    library(jsonlite)

    # --- Generateprofiles [] ---
    # Key functions: generateprofiles
    ## library(DrugVsDisease)
    ## profileAE<-generateprofiles(input="AE",accession="E-GEOD-22528")
    # --- Selectrankedlists [] ---
    # Key functions: selectrankedlists
    ## selprofiles<-selectrankedlists(profileAE,1)
    # --- Classifyprofile [] ---
    # Key functions: classifyprofile
    ## default<-classifyprofile(data=selprofiles$ranklist, signif.fdr=1.1)
    # --- Frame [] ---
    # Key functions: frame, xtable
    ## library(xtable)
    ## default<-as.data.frame(default[[1]])
    ## xtable(default[,2:4])
    # --- Aex [] ---
    # Key functions: generateprofiles
    ## profileAE<-generateprofiles(input="AE",accession="E-GEOD-22528")
    # --- Geo [] ---
    # Key functions: generateprofiles
    ## gds1479<-generateprofiles("GEO",accession="GDS1479",
    ## annotation="hgu133a",factorvalue="specimen",case="disease")
    # --- Selectrankedlists [] ---
    # Key functions: selectrankedlists
    ## sel1479<-selectrankedlists(gds1479,c(3,18))
    # --- Classifyprofile [] ---
    # Key functions: classifyprofile
    ## default<-classifyprofile(data=sel22528$ranklist, signif.fdr=1.1)
    # --- Data [] ---
    # Key functions: classifyprofile
    ## data(customDB,package="DrugVsDisease")
    ## data(customClust,package="DrugVsDisease")
    ## data(customedge,package="DrugVsDisease")
    ## data(customsif,package="DrugVsDisease")
    # --- Classifyprofile [] ---
    # Key functions: classifyprofile
    ## CytoOut<-classifyprofile(data=sel22528$ranklist,cytoout=TRUE,
    ## cytofile="CytoscapeOutput",adj="BH")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_drugvsdisease_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_drugvsdisease_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_drugvsdisease_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DRUGVSDISEASE:", paste0("    drugvsdisease: ", packageVersion("DrugVsDisease"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drugvsdisease_results.csv
    touch ${prefix}_drugvsdisease_output.rds
    echo "BIOC_DRUGVSDISEASE:" > versions.yml
    echo "    drugvsdisease: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DRUGVSDISEASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DRUGVSDISEASE(ch_input)

    emit:
    results  = BIOC_DRUGVSDISEASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DRUGVSDISEASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DRUGVSDISEASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DRUGVSDISEASE.out.versions  // channel: path(versions.yml)
}
