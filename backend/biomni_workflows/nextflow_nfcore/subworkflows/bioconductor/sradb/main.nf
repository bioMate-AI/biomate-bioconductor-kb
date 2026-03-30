#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SRAdb
// The Sequence Read Archive (SRA) is the largest public repository of sequencing data from the next ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SRAdb/inst/doc/SRAdb.R
// Upstream  : Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("SRAdb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SRADB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sradb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sradb:1.68.1--r44_0' :
        'quay.io/biocontainers/bioconductor-sradb:1.68.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sradb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sradb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sradb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SQLite)
    library(TABLE_INFO)
    library(jsonlite)

    # --- Time [] ---
    # Key functions: time, getSRAdbFile
    ##
    ##
    ## timeStart <- proc.time()
    ## sqlfile <- getSRAdbFile()
    ## proc.time() - timeStart
    # --- Dbconnect [] ---
    # Key functions: dbConnect, SQLite
    sra_con <- dbConnect(SQLite(),sqlfile)
    # --- Dblisttables [] ---
    # Key functions: dbListTables
    sra_tables <- dbListTables(sra_con)
    sra_tables
    # --- Dblistfields [] ---
    # Key functions: dbListFields
    dbListFields(sra_con,"study")
    # --- Dbgetquery [] ---
    # Key functions: dbGetQuery, TABLE_INFO
    dbGetQuery(sra_con,'PRAGMA TABLE_INFO(study)')
    # --- Coldescriptions [] ---
    # Key functions: colDescriptions
    colDesc <- colDescriptions(sra_con=sra_con)[1:5,]
    colDesc[, 1:4]
    # --- db Get Query [] ---
    # Key functions: dbGetQuery
    rs <- dbGetQuery(sra_con,"select * from study limit 3")
    rs[, 1:3]
    # --- Function [] ---
    # Key functions: count, dbGetQuery, call
    getTableCounts <- function(tableName,conn) {
      sql <- sprintf("select count(*) from %s",tableName)
      return(dbGetQuery(conn,sql)[1,1])
    }
    do.call(rbind,sapply(sra_tables[c(2,4,5,11,12)],
    # --- Dbgetquery [] ---
    # Key functions: dbGetQuery, count
    rs <- dbGetQuery(sra_con, paste( "SELECT study_type AS StudyType,
    	count( * ) AS Number FROM `study` GROUP BY study_type order
    	by Number DESC ", sep=""))
    rs
    # --- Sraconvert [] ---
    # Key functions: sraConvert
    conversion <- sraConvert( c('SRP001007','SRP000931'), sra_con = sra_con )
    conversion[1:3,]
    # --- Getsra [] ---
    # Key functions: getSRA
    rs <- getSRA( search_terms = "breast cancer",
    	out_types = c('run','study'), sra_con )
    dim(rs)
    rs <- getSRA( search_terms = "breast cancer",
    	out_types = c("submission", "study", "sample",
    # --- Listsrafile [] ---
    # Key functions: listSRAfile
    rs = listSRAfile( c("SRX000122"), sra_con, fileType = 'sra' )
    # --- Getsrainfo [] ---
    # Key functions: getSRAinfo
    # rs = getSRAinfo ( c("SRX000122"), sra_con, sraType = "sra" )
    # rs[1:3,]
    # --- Getsrafile [] ---
    # Key functions: getSRAfile
    ## getSRAfile( c("SRR000648","SRR000657"), sra_con, fileType = 'sra' )
    # --- Getfastqinfo [] ---
    # Key functions: getFASTQinfo, getSRAfile
    ## getFASTQinfo( c("SRR000648","SRR000657"), sra_con, srcType = 'ftp' )
    ##
    ## getSRAfile( c("SRR000648","SRR000657"), sra_con, fileType = 'fastq' )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sradb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sradb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sradb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SRADB:", paste0("    sradb: ", packageVersion("SRAdb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sradb_results.csv
    touch ${prefix}_sradb_output.rds
    echo "BIOC_SRADB:" > versions.yml
    echo "    sradb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SRADB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SRADB(ch_input)

    emit:
    results  = BIOC_SRADB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SRADB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SRADB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SRADB.out.versions  // channel: path(versions.yml)
}
