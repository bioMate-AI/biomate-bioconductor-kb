#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsutils — strand_haplotype_intersection
// Filter and intersect haplotypes from forward and reverse sequencing strands to reduce sequencing errors.
// Input: ToyData_FWReads.fna, ToyData_RVReads.fna
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("QSutils")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(QSutils)
    
    # Define input file paths in the working directory
    file_fw <- "ToyData_FWReads.fna"
    file_rv <- "ToyData_RVReads.fna"
    
    # Verify input files exist
    if (!file.exists(file_fw)) {
      stop(paste("Required input file missing:", file_fw))
    }
    if (!file.exists(file_rv)) {
      stop(paste("Required input file missing:", file_rv))
    }
    
    # 1. Load forward and reverse amplicon sequences using ReadAmplSeqs
    filepath <- file_fw
    lstFW <- ReadAmplSeqs(filepath, type="DNA")
    
    filepath <- file_rv
    lstRV <- ReadAmplSeqs(filepath, type="DNA")
    
    # 2. Intersect and filter strand haplotypes using IntersectStrandHpls
    lstI <- IntersectStrandHpls(lstFW\$nr, lstFW\$hseqs, lstRV\$nr, lstRV\$hseqs)
    
    # Save the complete intersection results list as an RDS object
    saveRDS(lstI, file = "intersected_haplotypes.rds")
    
    # Create and write a summary table of the intersection process
    summary_df <- data.frame(
      Metric = c(
        "FW_Total_Reads", 
        "RV_Total_Reads", 
        "FW_Reads_Above_Threshold", 
        "RV_Reads_Above_Threshold", 
        "Common_Reads", 
        "Common_Haplotypes"
      ),
      Value = c(
        sum(lstFW\$nr),
        sum(lstRV\$nr),
        sum(lstI\$pFW),
        sum(lstI\$pRV),
        sum(lstI\$nr),
        length(lstI\$nr)
      )
    )
    
    write.csv(summary_df, file = "intersection_summary.csv", row.names = FALSE)
    
    # Print summary to console
    cat("Workflow completed successfully.\n")
    cat("Outputs saved:\n")
    cat(" - intersected_haplotypes.rds (Full intersection list object)\n")
    cat(" - intersection_summary.csv (Summary statistics table)\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION":
        qsutils: \$(Rscript -e 'cat(as.character(packageVersion("qsutils")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_strand_haplotype_intersection.csv versions.yml
    """
}

workflow BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyData_FWReads.fna, ToyData_RVReads.fna ] ]

    main:
    BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION(ch_input)

    emit:
    tables   = BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION.out.tables
    plots    = BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION.out.plots
    objects  = BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION.out.objects
    versions = BIOC_QSUTILS_STRAND_HAPLOTYPE_INTERSECTION.out.versions
}
