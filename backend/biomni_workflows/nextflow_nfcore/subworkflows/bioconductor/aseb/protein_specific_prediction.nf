#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: aseb — protein_specific_prediction
// Predict all lysine sites on specific proteins that can be acetylated by a specific KAT-family and visualize the P-values and enrichment scores.
// Input: background_sites.fa, predefined_sites.fa, proteins_to_test.fa
// Container: quay.io/biocontainers/bioconductor-aseb:1.54.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION {
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
    .bm_deps <- c("ASEB")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required Bioconductor package
    library(ASEB)
    
    # Define input file paths as specified by the user
    background_file <- "background_sites.fa"
    predefined_file <- "predefined_sites.fa"
    proteins_file   <- "proteins_to_test.fa"
    
    # Verify that the required input files exist before proceeding
    for (f in c(background_file, predefined_file, proteins_file)) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing:", f))
      }
    }
    
    # 1. Load sequences using readSequence
    message("Reading input FASTA sequences...")
    backgroundSites <- readSequence(background_file)
    prodefinedSites <- readSequence(predefined_file)
    testProteins    <- readSequence(proteins_file)
    
    # 2. Run protein-specific prediction using asebProteins
    message("Running protein-specific prediction (asebProteins)...")
    resultList <- asebProteins(backgroundSites, prodefinedSites, testProteins, permutationTimes=100)
    
    # Print the first few results to the console
    message("Prediction completed. First few results:")
    print(head(resultList\$results, n=10))
    
    # Save the prediction results table to a CSV file
    write.csv(resultList\$results, file="aseb_protein_results.csv", row.names=FALSE)
    
    # Save the complete result list object as an RDS file for downstream analysis
    saveRDS(resultList, file="aseb_protein_results.rds")
    
    # 3. Draw P-values and enrichment scores for all sites on the protein using drawStat
    message("Generating visualization plot...")
    pdf("aseb_stat_plot.pdf", width=8, height=6)
    drawStat(curveInfoDataFrame=resultList\$curveInfo)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'aseb_protein_results.csv', 'aseb_protein_results.rds', and 'aseb_stat_plot.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION":
        aseb: \$(Rscript -e 'cat(as.character(packageVersion("aseb")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_specific_prediction.csv versions.yml
    """
}

workflow BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ background_sites.fa, predefined_sites.fa, proteins_to_test.fa ] ]

    main:
    BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION(ch_input)

    emit:
    tables   = BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION.out.tables
    plots    = BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION.out.plots
    objects  = BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION.out.objects
    versions = BIOC_ASEB_PROTEIN_SPECIFIC_PREDICTION.out.versions
}
