#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RImmPort
// The RImmPort package simplifies access to ImmPort data for analysis in the R environment. It provide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RImmPort/inst/doc/RImmPort_Article.R
// Upstream  : DBI, plyr, sqldf
// Downstream: none
//
// Install: BiocManager::install("RImmPort")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIMMPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rimmport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rimmport:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rimmport:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rimmport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rimmport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rimmport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RImmPort)
    library(jsonlite)

    # --- Getlistofstudies [] ---
    # Key functions: getListOfStudies, getStudy
    ---------------------------------------------------------------------
    # view documentation on Study
    ?Study
    # get all study ids
    getListOfStudies()
    # --- Getlistofdomains [] ---
    # Key functions: getListOfDomains, getDomainCode, getDomainDataOfStudies
    ---------------------------------------------------------------------
    # get the list of names of all supported Domains
    getListOfDomains()
    ?"Demographics Domain"
    # get domain code of Demographics domain
    # --- Getstudieswithspecificdomaindata [] ---
    # Key functions: getStudiesWithSpecificDomainData
    ---------------------------------------------------------------------
    # get list of studies with Cellular Quantification data
    domain_name <- "Cellular Quantification"
    study_ids_l <- getStudiesWithSpecificDomainData(domain_name)
    study_ids_l
    # --- Getdomaincode [] ---
    # Key functions: getDomainCode, getDomainDataOfStudies
    ---------------------------------------------------------------------
    # get Cellular Quantification data of studies `SDY139` and `SDY208`
    # get domain code of Cellular Quantification domain
    domain_name <- "Cellular Quantification"
    getDomainCode(domain_name)
    # --- Getlistofassaytypes [] ---
    # Key functions: getListOfAssayTypes
    ---------------------------------------------------------------------
    getListOfAssayTypes()
    # --- Getassaydataofstudies [] ---
    # Key functions: getAssayDataOfStudies
    ---------------------------------------------------------------------
    # get 'ELISPOT' data of study `SDY139`
    assay_type <- "ELISPOT"
    study_id = "SDY139"
    elispot_l <- getAssayDataOfStudies(study_id, assay_type)
    # --- Files [] ---
    # Key functions: files
    ---------------------------------------------------------------------
    list.files(db_dir)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rimmport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rimmport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rimmport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIMMPORT:", paste0("    rimmport: ", packageVersion("RImmPort"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rimmport_results.csv
    touch ${prefix}_rimmport_output.rds
    echo "BIOC_RIMMPORT:" > versions.yml
    echo "    rimmport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIMMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIMMPORT(ch_input)

    emit:
    results  = BIOC_RIMMPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIMMPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIMMPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIMMPORT.out.versions  // channel: path(versions.yml)
}
