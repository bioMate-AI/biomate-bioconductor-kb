#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: aseb — site_specific_prediction
// Predict which specific lysine sites can be acetylated by a specific KAT-family and visualize the running-sum enrichment score curves.
// Input: background_sites.fa, predefined_sites.fa, sites_to_test.fa
// Container: quay.io/biocontainers/bioconductor-aseb:1.54.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASEB_SITE_SPECIFIC_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-aseb:1.54.0--r45ha27e39d_0"

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
    .bm_deps <- c("aseb")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(ASEB)
    
    # Define input file paths as specified by the user
    background_file <- "background_sites.fa"
    predefined_file <- "predefined_sites.fa"
    test_file       <- "sites_to_test.fa"
    
    # Verify that the required input files exist
    for (f in c(background_file, predefined_file, test_file)) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing:", f))
      }
    }
    
    # 1. Load sequences using readSequence
    message("Loading sequences...")
    backgroundSites <- readSequence(background_file)
    prodefinedSites <- readSequence(predefined_file)
    testSites       <- readSequence(test_file)
    
    # 2. Run site-specific prediction using asebSites
    message("Running site-specific prediction (asebSites)...")
    resultList <- asebSites(backgroundSites, prodefinedSites, testSites, permutationTimes=100)
    
    # Save the prediction results table to a CSV file
    message("Saving prediction results...")
    write.csv(resultList\$results, file = "aseb_prediction_results.csv", row.names = FALSE)
    
    # Save the complete result list object as an RDS file for downstream analysis
    saveRDS(resultList, file = "aseb_results.rds")
    
    # 3. Draw enrichment score curves using drawEScurve and save to a PDF file
    message("Generating enrichment score curve plots...")
    pdf("enrichment_score_curves.pdf", width = 8, height = 6)
    tryCatch({
      drawEScurve(resultList\$curveInfo, max_p_value=0.1, min_es=0.1)
    }, error = function(e) {
      warning("Could not draw ES curves. This can happen if no sites meet the max_p_value or min_es thresholds.")
      print(e)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs generated: 'aseb_prediction_results.csv', 'aseb_results.rds', and 'enrichment_score_curves.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ASEB_SITE_SPECIFIC_PREDICTION":
        aseb: \$(Rscript -e 'cat(as.character(packageVersion("aseb")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_site_specific_prediction.csv versions.yml
    """
}

workflow BIOC_ASEB_SITE_SPECIFIC_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ background_sites.fa, predefined_sites.fa, sites_to_test.fa ] ]

    main:
    BIOC_ASEB_SITE_SPECIFIC_PREDICTION(ch_input)

    emit:
    tables   = BIOC_ASEB_SITE_SPECIFIC_PREDICTION.out.tables
    plots    = BIOC_ASEB_SITE_SPECIFIC_PREDICTION.out.plots
    objects  = BIOC_ASEB_SITE_SPECIFIC_PREDICTION.out.objects
    versions = BIOC_ASEB_SITE_SPECIFIC_PREDICTION.out.versions
}
