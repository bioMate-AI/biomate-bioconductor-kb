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
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_rimmport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rimmport_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rimmport_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIMMPORT:", paste0("    rimmport: ", as.character(packageVersion("RImmPort")))),
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
