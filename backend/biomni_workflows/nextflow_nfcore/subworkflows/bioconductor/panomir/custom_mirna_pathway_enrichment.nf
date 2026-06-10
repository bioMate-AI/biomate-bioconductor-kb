#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PanomiR — custom_mirna_pathway_enrichment
// Generate a customized miRNA-pathway enrichment reference table tailored to the specific genes and miRNAs expressed in your experiment.
// Input: mirna_targets.RData, pathway_sets.RData, expressed_genes.txt, expressed_mirnas.txt
// Container: quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0
// R packages: PanomiR
// Bioconductor: 3.20 | R: 4.4
// Requires: PanomiR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate custom miRNA-pathway enrichment using miRNAPathwayEnrichment
//  * 2. [Visualization & Output] Format and filter the enrichment results for reporting using reportEnrichment

nextflow.enable.dsl = 2

process BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("PanomiR")
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
    
    # Load required libraries
    library(PanomiR)
    
    # -----------------------------------------------------------------------------
    # 1. Load User Input Files
    # -----------------------------------------------------------------------------
    
    # Load miRNA target sets (e.g., TargetScan) from mirna_targets.RData
    mir_env <- new.env()
    load("mirna_targets.RData", envir = mir_env)
    mir_obj_names <- ls(mir_env)
    if (length(mir_obj_names) == 0) {
      stop("No objects found in mirna_targets.RData")
    }
    mirSets <- mir_env[[mir_obj_names[1]]]
    
    # Load pathway gene sets (e.g., MSigDB) from pathway_sets.RData
    path_env <- new.env()
    load("pathway_sets.RData", envir = path_env)
    path_obj_names <- ls(path_env)
    if (length(path_obj_names) == 0) {
      stop("No objects found in pathway_sets.RData")
    }
    pathwaySets <- path_env[[path_obj_names[1]]]
    
    # Read expressed genes and miRNAs
    yourGenes <- readLines("expressed_genes.txt")
    yourMicroRNAs <- readLines("expressed_mirnas.txt")
    
    # -----------------------------------------------------------------------------
    # 2. Calculate Custom miRNA-Pathway Enrichment
    # -----------------------------------------------------------------------------
    
    customeTableEnrich <- miRNAPathwayEnrichment(mirSets = mirSets,
                                                  pathwaySets = pathwaySets,
                                                  geneSelection = yourGenes,
                                                  mirSelection = yourMicroRNAs,
                                                  fromID = "ENSEMBL",
                                                  toID = "ENTREZID",
                                                  minPathSize = 9,
                                                  numCores = 1,
                                                  outDir = ".",
                                                  saveOutName = NULL)
    
    # -----------------------------------------------------------------------------
    # 3. Format and Filter Enrichment Results for Reporting
    # -----------------------------------------------------------------------------
    
    enrichmentReport <- reportEnrichment(customeTableEnrich)
    
    # Print the head of the report to console
    print(head(enrichmentReport))
    
    # -----------------------------------------------------------------------------
    # 4. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the raw enrichment results object
    saveRDS(customeTableEnrich, file = "custom_mirna_pathway_enrichment.rds")
    
    # Save the formatted enrichment report as a CSV
    write.csv(enrichmentReport, file = "custom_mirna_pathway_enrichment_report.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT":',
        paste0('    PanomiR: ', as.character(packageVersion('PanomiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_mirna_pathway_enrichment.csv versions.yml
    """
}

workflow BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mirna_targets.RData, pathway_sets.RData, expressed_genes.txt, expressed_mirnas.txt ] ]

    main:
    BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT.out.tables
    plots    = BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT.out.plots
    objects  = BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT.out.objects
    versions = BIOC_PANOMIR_CUSTOM_MIRNA_PATHWAY_ENRICHMENT.out.versions
}
