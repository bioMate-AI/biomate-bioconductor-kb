#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: semdist — calculate_information_accretion
// Calculate information accretion values for a custom ontology and annotation set.
// Input: mfo_ontology.txt, MFO_LABELS_TEST.txt
// Container: quay.io/biocontainers/bioconductor-semdist:1.44.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-semdist:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("semdist")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(SemDist)
    
    # 1. Define paths to the custom ontology and annotation files
    ontfile <- "mfo_ontology.txt"
    annotations <- "MFO_LABELS_TEST.txt"
    
    # Verify input files exist
    if (!file.exists(ontfile)) {
      stop(paste("Required ontology file not found in working directory:", ontfile))
    }
    if (!file.exists(annotations)) {
      stop(paste("Required annotations file not found in working directory:", annotations))
    }
    
    # 2. Compute information accretion values using computeIA with custom specifications
    message("Computing information accretion values...")
    IAccr <- computeIA("my", "values", specify.ont=TRUE, 
                    myont=ontfile, specify.annotations=TRUE, 
                    annotfile=annotations)
    
    # 3. Save the meaningful results to output files
    message("Saving results...")
    
    # Save the raw numeric vector as an RDS object
    saveRDS(IAccr, file = "information_accretion.rds")
    
    # Convert to a data frame and save as a CSV table
    ia_df <- data.frame(
      Term = names(IAccr),
      InformationAccretion = as.numeric(IAccr),
      stringsAsFactors = FALSE
    )
    write.csv(ia_df, file = "information_accretion.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to 'information_accretion.rds' and 'information_accretion.csv'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION":
        semdist: \$(Rscript -e 'cat(as.character(packageVersion("semdist")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_calculate_information_accretion.csv versions.yml
    """
}

workflow BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mfo_ontology.txt, MFO_LABELS_TEST.txt ] ]

    main:
    BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION(ch_input)

    emit:
    tables   = BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION.out.tables
    plots    = BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION.out.plots
    objects  = BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION.out.objects
    versions = BIOC_SEMDIST_CALCULATE_INFORMATION_ACCRETION.out.versions
}
