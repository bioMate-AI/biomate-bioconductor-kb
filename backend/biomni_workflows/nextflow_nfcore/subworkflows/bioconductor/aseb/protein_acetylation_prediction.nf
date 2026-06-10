#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASEB — protein_acetylation_prediction
// Predict all lysine sites on specific query proteins that can be acetylated by a specific KAT-family and visualize the statistics along the proteins.
// Input: background_sites.fa, predefined_sites.fa, proteins_to_test.fa
// Container: quay.io/biocontainers/bioconductor-aseb:1.54.0--r45ha27e39d_0
// Requires: ASEB
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read sequences using readSequence
//  * 2. [Core Analysis] Predict acetylation sites on proteins using asebProteins
//  * 3. [Visualization & Output] Draw protein-wide statistics using drawStat

nextflow.enable.dsl = 2

process BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("ASEB")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the required Bioconductor package
    library(ASEB)
    
    # Define input file paths in the working directory
    bg_file <- "background_sites.fa"
    predefined_file <- "predefined_sites.fa"
    test_file <- "proteins_to_test.fa"
    
    # Verify that the required input files exist
    if (!file.exists(bg_file)) {
      stop(paste("Error: Required input file not found in working directory:", bg_file))
    }
    if (!file.exists(predefined_file)) {
      stop(paste("Error: Required input file not found in working directory:", predefined_file))
    }
    if (!file.exists(test_file)) {
      stop(paste("Error: Required input file not found in working directory:", test_file))
    }
    
    # 1. Read sequences using readSequence
    message("Reading input FASTA sequences...")
    backgroundSites <- readSequence(bg_file)
    prodefinedSites <- readSequence(predefined_file)
    testProteins <- readSequence(test_file)
    
    # 2. Predict acetylation sites on proteins using asebProteins
    message("Predicting lysine sites that can be acetylated...")
    resultList <- asebProteins(backgroundSites, prodefinedSites, testProteins, permutationTimes=100)
    
    # Display the first few results in the console
    message("Preview of prediction results:")
    print(head(resultList\$results))
    
    # Save the prediction results table and the full result list object
    write.csv(resultList\$results, file = "acetylation_predictions.csv", row.names = FALSE)
    saveRDS(resultList, file = "aseb_results.rds")
    message("Results successfully saved to 'acetylation_predictions.csv' and 'aseb_results.rds'.")
    
    # 3. Draw protein-wide statistics using drawStat and save to PDF
    message("Generating protein-wide statistics plot...")
    pdf("protein_statistics.pdf", width = 8, height = 6)
    drawStat(curveInfoDataFrame=resultList\$curveInfo)
    dev.off()
    message("Plot successfully saved to 'protein_statistics.pdf'.")

    writeLines(c(
        '"BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION":',
        paste0('    ASEB: ', as.character(packageVersion('ASEB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_acetylation_prediction.csv versions.yml
    """
}

workflow BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ background_sites.fa, predefined_sites.fa, proteins_to_test.fa ] ]

    main:
    BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION.out.tables
    plots    = BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION.out.plots
    objects  = BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION.out.objects
    versions = BIOC_ASEB_PROTEIN_ACETYLATION_PREDICTION.out.versions
}
