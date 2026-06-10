#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnbeads — bisulfite_sequencing_analysis
// Perform an automated end-to-end analysis of bisulfite sequencing data (WGBS or RRBS) starting from BED files.
// Input: bed, sample_annotation.csv
// Container: quay.io/biocontainers/bioconductor-rnbeads:2.28.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rnbeads:2.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("RnBeads")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(RnBeads)
    
    # Define the user input paths
    # The documented code uses 'idat.dir' and 'sample.annotation' to construct 'data.source'
    idat.dir <- "bed"
    sample.annotation <- "sample_annotation.csv"
    
    # Define the report directory (must not exist prior to running)
    report.dir <- "rnbeads_reports"
    if (dir.exists(report.dir)) {
      unlink(report.dir, recursive = TRUE)
    }
    
    # Read sample annotation to dynamically configure the identifier column
    annot_df <- read.csv(sample.annotation, stringsAsFactors = FALSE)
    id_col <- colnames(annot_df)[1]
    if ("Sample_ID" %in% colnames(annot_df)) {
      id_col <- "Sample_ID"
    } else if ("sampleID" %in% colnames(annot_df)) {
      id_col <- "sampleID"
    }
    
    # Set RnBeads options
    rnb.options(
      filtering.sex.chromosomes.removal = TRUE,
      identifiers.column = id_col,
      disk.dump.big.matrices = TRUE
    )
    
    # 1. Define the data source paths (EXACTLY as documented)
    data.source <- c(idat.dir, sample.annotation)
    
    # 2. Run the complete analysis pipeline specifying the sequencing data type (EXACTLY as documented)
    rnb.run.analysis(dir.reports=report.dir, data.source=data.source,
        data.type="bs.bed.dir")
    
    # Extract and write meaningful results to named output files
    tryCatch({
      # Import the dataset to perform explicit exports of RDS and CSV files
      rnb.set <- rnb.execute.import(data.source = data.source, data.type = "bs.bed.dir")
      
      # Save the RnBSet object as an RDS file
      saveRDS(rnb.set, file = "rnbeads_rnbset.rds")
      
      # Export the site-level methylation beta values
      meth_matrix <- meth(rnb.set, type = "sites")
      write.csv(meth_matrix, file = "methylation_beta_values.csv", row.names = TRUE)
      
      # Export phenotypic data
      pheno_data <- pheno(rnb.set)
      write.csv(pheno_data, file = "extracted_phenotypes.csv", row.names = TRUE)
      
    }, error = function(e) {
      cat("An error occurred during explicit data export: ", e\$message, "\n")
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS":
        rnbeads: \$(Rscript -e 'cat(as.character(packageVersion("rnbeads")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bisulfite_sequencing_analysis.csv versions.yml
    """
}

workflow BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bed, sample_annotation.csv ] ]

    main:
    BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS.out.tables
    plots    = BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS.out.plots
    objects  = BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS.out.objects
    versions = BIOC_RNBEADS_BISULFITE_SEQUENCING_ANALYSIS.out.versions
}
