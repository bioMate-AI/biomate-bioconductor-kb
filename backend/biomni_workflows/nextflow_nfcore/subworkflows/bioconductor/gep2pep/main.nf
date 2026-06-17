#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gep2pep — gep_to_pep_conversion
// Create a local pathway repository and convert ranked gene expression profiles (GEPs) into Pathway Expression Profiles (PEPs).
// Input: msigdb_v6.1.xml, geps_matrix
// Container: quay.io/biocontainers/bioconductor-gep2pep:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, gep2pep
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import MSigDB XML database and convert to CategorizedCollection
//  * 2. [Input & Preparation] Create a local repository using createRepository
//  * 3. [Input & Preparation] Load ranked GEP matrix
//  * 4. [Core Analysis] Convert GEPs to PEPs using buildPEPs
//  * 5. [Input & Preparation] Load ES and PV matrices using loadESmatrix and loadPVmatrix

nextflow.enable.dsl = 2

process BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("gep2pep", "GSEABase")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(gep2pep)
    suppressMessages(library(GSEABase))
    
    # 1. Import MSigDB XML database and convert to CategorizedCollection
    db <- importMSigDB.xml("msigdb_v6.1.xml")
    db <- as.CategorizedCollection(db)
    
    # 2. Create a local repository using createRepository
    colltypes <- sapply(db, collectionType)
    cats <- sapply(colltypes, attr, "category")
    subcats <- sapply(colltypes, attr, "subCategory")
    makeCollectionIDs(db)
    repoRoot <- file.path(tempdir(), "gep2pep_data")
    rp <- createRepository(repoRoot, db)
    
    # 3. Load ranked GEP matrix
    geps <- tryCatch({
      readRDS("geps_matrix")
    }, error = function(e) {
      as.matrix(read.table("geps_matrix", header=TRUE, row.names=1, check.names=FALSE))
    })
    
    # 4. Convert GEPs to PEPs using buildPEPs
    buildPEPs(rp, geps)
    
    # 5. Load ES and PV matrices using loadESmatrix and loadPVmatrix
    # Wrapped in tryCatch to prevent failure if "c3_TFT" is not present in the user's custom XML
    tryCatch({
      loadESmatrix(rp, "c3_TFT")[1:3, 1:3]
    }, error = function(e) {
      message("Note: c3_TFT ES matrix subset could not be displayed (likely not in input XML).")
    })
    
    tryCatch({
      loadPVmatrix(rp, "c3_TFT")[1:3, 1:3]
    }, error = function(e) {
      message("Note: c3_TFT PV matrix subset could not be displayed (likely not in input XML).")
    })
    
    # Export all generated ES and PV matrices to the working directory
    collections <- unique(makeCollectionIDs(db))
    for (coll in collections) {
      tryCatch({
        es_mat <- loadESmatrix(rp, coll)
        pv_mat <- loadPVmatrix(rp, coll)
        
        write.csv(es_mat, file = paste0("ES_matrix_", coll, ".csv"))
        write.csv(pv_mat, file = paste0("PV_matrix_", coll, ".csv"))
        saveRDS(es_mat, file = paste0("ES_matrix_", coll, ".rds"))
        saveRDS(pv_mat, file = paste0("PV_matrix_", coll, ".rds"))
      }, error = function(e) {
        message("Could not export matrices for collection: ", coll)
      })
    }
    
    # Copy the created repository to the working directory for persistence
    tryCatch({
      file.copy(repoRoot, ".", recursive = TRUE)
    }, error = function(e) {
      message("Could not copy repository to working directory.")
    })

    writeLines(c(
        '"BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION":',
        paste0('    gep2pep: ', as.character(packageVersion('gep2pep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gep_to_pep_conversion.csv versions.yml
    """
}

workflow BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ msigdb_v6.1.xml, geps_matrix ] ]

    main:
    BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION(ch_input)

    emit:
    tables   = BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION.out.tables
    plots    = BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION.out.plots
    objects  = BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION.out.objects
    versions = BIOC_GEP2PEP_GEP_TO_PEP_CONVERSION.out.versions
}
