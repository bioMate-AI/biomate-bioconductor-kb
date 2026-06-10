#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vegamc — chromosomal_imbalance_analysis
// Identify driver chromosomal imbalances (deletions, amplifications, LOH) from sorted or unsorted aCGH/SNP array data.
// Input: breast_Affy500K.txt, gist.txt
// Container: quay.io/biocontainers/bioconductor-vegamc:3.48.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-vegamc:3.48.0--r45h01b2380_0"

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
    .bm_deps <- c("vegamc")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(VegaMC)
    
    # Define input file paths (assumed to be in the working directory as per user input specification)
    breast_input <- "breast_Affy500K.txt"
    gist_input <- "gist.txt"
    
    # Verify input files exist before proceeding
    if (!file.exists(breast_input)) {
      stop(paste("Required input file missing:", breast_input))
    }
    if (!file.exists(gist_input)) {
      stop(paste("Required input file missing:", gist_input))
    }
    
    # 1. Run the joint segmentation, classification, and significance testing on the breast dataset
    results <- vegaMC(
      breast_input,
      output_file_name = "breast.analysis",
      beta = 1,
      min_region_bp_size = 2000,
      bs = 5000,
      html = FALSE,
      getGenes = FALSE
    )
    
    # Retrieve the results matrix and view the column names
    cat("Column names of breast analysis results:\n")
    print(colnames(results))
    
    # Save breast results to output files
    write.csv(results, "breast_analysis_results.csv", row.names = FALSE)
    saveRDS(results, "breast_analysis_results.rds")
    
    # 2. Sort the unsorted GIST dataset by genomic position using sortData
    gist_sorted <- "gist.sorted.txt"
    sortData(gist_input, gist_sorted)
    
    # 3. Run the joint segmentation, classification, and significance testing on the sorted GIST dataset
    gist.results <- vegaMC(
      gist_sorted,
      output_file_name = "gist.analysis.default",
      min_region_bp_size = 1000
    )
    
    # Retrieve the GIST results matrix and view the column names
    cat("Column names of GIST analysis results:\n")
    print(colnames(gist.results))
    
    # Save GIST results to output files
    write.csv(gist.results, "gist_analysis_results.csv", row.names = FALSE)
    saveRDS(gist.results, "gist_analysis_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS":
        vegamc: \$(Rscript -e 'cat(as.character(packageVersion("vegamc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromosomal_imbalance_analysis.csv versions.yml
    """
}

workflow BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ breast_Affy500K.txt, gist.txt ] ]

    main:
    BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS.out.tables
    plots    = BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS.out.plots
    objects  = BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS.out.objects
    versions = BIOC_VEGAMC_CHROMOSOMAL_IMBALANCE_ANALYSIS.out.versions
}
