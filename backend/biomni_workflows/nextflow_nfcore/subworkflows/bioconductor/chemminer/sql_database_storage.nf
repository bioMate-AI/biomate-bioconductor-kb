#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChemmineR — sql_database_storage
// Store small molecules and their computed features in an SQLite database for fast indexing, querying, and retrieval.
// Input: sdfsample.sdf
// Container: quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0
// Requires: ChemmineR, RSQLite
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize a new SQLite database using initDb
//  * 2. [Input & Preparation] Load compounds and compute custom features using loadSdf
//  * 3. [Core Analysis] Query compounds based on feature criteria using findCompounds
//  * 4. [Core Analysis] Retrieve matching compounds as an SDFset using getCompounds

nextflow.enable.dsl = 2

process BIOC_CHEMMINER_SQL_DATABASE_STORAGE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(ChemmineR)
    library(RSQLite)
    
    # Clean up any pre-existing database file to ensure a clean run
    if (file.exists("test.db")) {
      file.remove("test.db")
    }
    
    # Read user input file
    sdfsample <- read.SDFset("sdfsample.sdf")
    
    # Initialize a new SQLite database
    conn <- initDb("test.db")
    
    # Load compounds and compute custom features
    ids<-loadSdf(conn,sdfsample, function(sdfset) 
    					 data.frame(rings(sdfset,type="count",upper=6, arom=TRUE)) )
    
    # Print and save features in the database
    features <- listFeatures(conn)
    print(features)
    writeLines(features, "database_features.txt")
    
    # Query compounds based on feature criteria
    results = findCompounds(conn,"rings",c("rings <= 1"))
    
    # Retrieve matching compounds as an SDFset
    compounds = getCompounds(conn,results)
    
    # Write outputs
    write.csv(data.frame(db_compound_id = results), "query_results.csv", row.names=FALSE)
    write.SDF(compounds, file="matching_compounds.sdf")
    saveRDS(compounds, "matching_compounds.rds")
    
    # Close database connection
    dbDisconnect(conn)

    writeLines(c(
        '"BIOC_CHEMMINER_SQL_DATABASE_STORAGE":',
        paste0('    ChemmineR: ', as.character(packageVersion('ChemmineR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sql_database_storage.csv versions.yml
    """
}

workflow BIOC_CHEMMINER_SQL_DATABASE_STORAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sdfsample.sdf ] ]

    main:
    BIOC_CHEMMINER_SQL_DATABASE_STORAGE(ch_input)

    emit:
    tables   = BIOC_CHEMMINER_SQL_DATABASE_STORAGE.out.tables
    plots    = BIOC_CHEMMINER_SQL_DATABASE_STORAGE.out.plots
    objects  = BIOC_CHEMMINER_SQL_DATABASE_STORAGE.out.objects
    versions = BIOC_CHEMMINER_SQL_DATABASE_STORAGE.out.versions
}
