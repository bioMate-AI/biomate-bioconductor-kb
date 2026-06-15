#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miRNAtap — mirna_target_enrichment
// Predict miRNA target genes using aggregated source predictions and perform Gene Ontology (GO) enrichment analysis using rank information.
// Input: mirna_name.txt
// Container: quay.io/biocontainers/bioconductor-mirnatap:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: miRNAtap, org.Hs.eg.db, topGO
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve aggregated miRNA target predictions using getPredictedTargets
//  * 2. [Core Analysis] Extract rank product information for downstream analysis
//  * 3. [Input & Preparation] Set up GO annotations and create a topGOdata object using the ranked genes
//  * 4. [Core Analysis] Run Kolmogorov-Smirnov (K-S) test for GO enrichment using runTest
//  * 5. [Core Analysis] Generate a table of top enriched GO terms using GenTable

nextflow.enable.dsl = 2

process BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT {
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
    .bm_deps <- c("miRNAtap", "topGO", "org.Hs.eg.db")
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
    library(miRNAtap)
    library(topGO)
    library(org.Hs.eg.db)
    
    # Read miRNA name from the user input file
    if (!file.exists("mirna_name.txt")) {
      stop("Error: 'mirna_name.txt' file not found in the working directory.")
    }
    
    mir_lines = readLines("mirna_name.txt", warn = FALSE)
    mir_lines = trimws(mir_lines)
    mir_lines = mir_lines[mir_lines != ""]
    
    if (length(mir_lines) == 0) {
      stop("Error: 'mirna_name.txt' is empty.")
    }
    
    mir = mir_lines[1]
    message(paste("Processing miRNA:", mir))
    
    # 1. Retrieve aggregated miRNA target predictions using getPredictedTargets
    message("Retrieving predicted targets using geometric mean aggregation...")
    predictions = getPredictedTargets(mir, species = 'hsa',
                                        method = 'geom', min_src = 2)
    print(head(predictions))
    
    message("Retrieving predicted targets using minimum rank aggregation...")
    predictions_min = getPredictedTargets(mir, species = 'hsa',
                                        method = 'min', min_src = 2)
    print(head(predictions_min))
    
    message("Retrieving predicted targets translated for Rattus norvegicus...")
    predictions_rat = getPredictedTargets(mir, species = 'rno',
                                        method = 'geom', min_src = 2)
    print(head(predictions_rat))
    
    # 2. Extract rank product information for downstream analysis
    rankedGenes = predictions[,'rank_product']
    
    # 3. Set up GO annotations and create a topGOdata object using the ranked genes
    selection = function(x) TRUE 
    # we do not want to impose a cut off, instead we are using rank information
    allGO2genes = annFUN.org(whichOnto='BP', feasibleGenes = NULL,
                    mapping="org.Hs.eg.db", ID = "entrez")
    
    GOdata =  new('topGOdata', ontology = 'BP', allGenes = rankedGenes, 
                annot = annFUN.GO2genes, GO2genes = allGO2genes, 
                geneSel = selection, nodeSize=10)
    
    # 4. Run Kolmogorov-Smirnov (K-S) test for GO enrichment using runTest
    results.ks = runTest(GOdata, algorithm = "classic", statistic = "ks")
    print(results.ks)
    
    # 5. Generate a table of top enriched GO terms using GenTable
    allRes = GenTable(GOdata, KS = results.ks, orderBy = "KS", topNodes = 20)
    print(allRes[,c('GO.ID','Term','KS')])
    
    # Save outputs to files
    write.csv(as.data.frame(predictions), "predictions_geom.csv", row.names = TRUE)
    write.csv(as.data.frame(predictions_min), "predictions_min.csv", row.names = TRUE)
    write.csv(as.data.frame(predictions_rat), "predictions_rat.csv", row.names = TRUE)
    write.csv(allRes, "go_enrichment_results.csv", row.names = FALSE)
    saveRDS(GOdata, "godata.rds")
    
    message("Workflow completed successfully. Outputs saved to predictions_geom.csv, predictions_min.csv, predictions_rat.csv, go_enrichment_results.csv, and godata.rds.")

    writeLines(c(
        '"BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT":',
        paste0('    miRNAtap: ', as.character(packageVersion('miRNAtap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_target_enrichment.csv versions.yml
    """
}

workflow BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mirna_name.txt ] ]

    main:
    BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT.out.tables
    plots    = BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT.out.plots
    objects  = BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT.out.objects
    versions = BIOC_MIRNATAP_MIRNA_TARGET_ENRICHMENT.out.versions
}
