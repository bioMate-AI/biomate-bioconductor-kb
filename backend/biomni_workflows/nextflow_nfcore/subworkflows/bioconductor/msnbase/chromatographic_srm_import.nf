#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msnbase — chromatographic_srm_import
// Import and extract chromatographic data from SRM/MRM experiments.
// Input: MRM_file.mzML
// Container: quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0"

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
    .bm_deps <- c("MSnbase")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(MSnbase)
    
    # Define the input file as specified by the user
    fl <- "MRM_file.mzML"
    
    # 1. Import SRM data
    srm <- readSRMData(fl)
    
    # 2. Extract precursor and product m/z values
    prec_mz <- precursorMz(srm)
    prod_mz <- productMz(srm)
    
    # 3. Save meaningful results to output files
    # Save the imported SRM object as an RDS file
    saveRDS(srm, file = "srm_object.rds")
    
    # Save the extracted m/z values to a CSV file
    mz_data <- data.frame(
      Precursor_m_z = prec_mz,
      Product_m_z = prod_mz,
      stringsAsFactors = FALSE
    )
    write.csv(mz_data, file = "srm_mz_values.csv", row.names = FALSE)
    
    # Generate a PDF plot of the chromatograms
    tryCatch({
      pdf("srm_chromatograms.pdf", width = 10, height = 8)
      plot(srm)
      dev.off()
    }, error = function(e) {
      warning("Could not generate chromatogram plot: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT":
        msnbase: \$(Rscript -e 'cat(as.character(packageVersion("msnbase")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatographic_srm_import.csv versions.yml
    """
}

workflow BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MRM_file.mzML ] ]

    main:
    BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT(ch_input)

    emit:
    tables   = BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT.out.tables
    plots    = BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT.out.plots
    objects  = BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT.out.objects
    versions = BIOC_MSNBASE_CHROMATOGRAPHIC_SRM_IMPORT.out.versions
}
