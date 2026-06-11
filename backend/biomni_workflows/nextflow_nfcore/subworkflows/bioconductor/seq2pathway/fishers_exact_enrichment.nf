#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seq2pathway — fishers_exact_enrichment
// Discover enriched GO terms or MSigDB gene-sets using Fisher's exact test with a corrected common background.
// Input: dat_chip, MsigDB_C5
// Container: quay.io/biocontainers/bioconductor-seq2pathway:1.34.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: seq2pathway
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run Fisher's exact test against MSigDB defined gene-sets using FisherTest_MsigDB. 2. Run Fisher's exact test against GO defined ge

nextflow.enable.dsl = 2

process BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(seq2pathway)
    library(GSA)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files from Working Directory
    # -----------------------------------------------------------------------------
    
    # Read dat_chip (gene-level measurements to extract gene symbols)
    if (file.exists("dat_chip.rds")) {
      dat_chip <- readRDS("dat_chip.rds")
    } else if (file.exists("dat_chip.csv")) {
      dat_chip <- read.csv("dat_chip.csv", row.names = 1, check.names = FALSE)
    } else {
      stop("Required input file 'dat_chip.rds' or 'dat_chip.csv' not found in the working directory.")
    }
    
    # Read MsigDB_C5 (GSA.genesets object)
    if (file.exists("MsigDB_C5.rds")) {
      MsigDB_C5 <- readRDS("MsigDB_C5.rds")
    } else {
      stop("Required input file 'MsigDB_C5.rds' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Run Fisher's Exact Test against MSigDB defined gene-sets
    # -----------------------------------------------------------------------------
    message("Running Fisher's exact test against MSigDB gene-sets...")
    
    FS_test<-FisherTest_MsigDB(gsmap=MsigDB_C5, gs=as.vector(rownames(dat_chip)))
    
    # Save MSigDB Fisher's exact test results
    write.csv(FS_test, file = "FisherTest_MsigDB_results.csv", row.names = FALSE)
    saveRDS(FS_test, file = "FisherTest_MsigDB_results.rds")
    
    # -----------------------------------------------------------------------------
    # 3. Run Fisher's Exact Test against GO defined gene-sets (BP)
    # -----------------------------------------------------------------------------
    message("Running Fisher's exact test against GO BP gene-sets...")
    
    FS_test<- FisherTest_GO_BP_MF_CC(gs=as.vector(rownames(dat_chip)),Ontology="BP")
    
    # Save GO Fisher's exact test results
    saveRDS(FS_test, file = "FisherTest_GO_BP_results.rds")
    
    # If the output contains the GO_BP data frame, write it to CSV as well
    if (is.list(FS_test) && "GO_BP" %in% names(FS_test)) {
      write.csv(FS_test\$GO_BP, file = "FisherTest_GO_BP_table.csv", row.names = FALSE)
    } else if (is.data.frame(FS_test)) {
      write.csv(FS_test, file = "FisherTest_GO_BP_table.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT":',
        paste0('    seq2pathway: ', as.character(packageVersion('seq2pathway')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fishers_exact_enrichment.csv versions.yml
    """
}

workflow BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat_chip, MsigDB_C5 ] ]

    main:
    BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT.out.tables
    plots    = BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT.out.plots
    objects  = BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT.out.objects
    versions = BIOC_SEQ2PATHWAY_FISHERS_EXACT_ENRICHMENT.out.versions
}
