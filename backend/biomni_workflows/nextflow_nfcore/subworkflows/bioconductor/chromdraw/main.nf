#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromdraw — text_file_karyotype
// Visualize karyotypes and cytogenetic marks using custom text-based definition and color files.
// Input: karyotype_definition.txt, color_definitions.txt
// Container: quay.io/biocontainers/bioconductor-chromdraw:2.40.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chromdraw:2.40.0--r45ha27e39d_0"

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
    .bm_deps <- c("chromdraw", "genomicranges")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(chromDraw)
    
    # 1. Define output path and input file paths
    # The pipeline reads exactly these files from the working directory as specified
    INPUTPATH <- file.path(getwd(), "karyotype_definition.txt")
    COLORPATH <- file.path(getwd(), "color_definitions.txt")
    OUTPUTPATH <- file.path(getwd())
    
    # Verify that the required input files exist before running
    if (!file.exists(INPUTPATH)) {
      stop(paste("Required input file missing:", INPUTPATH))
    }
    if (!file.exists(COLORPATH)) {
      stop(paste("Required color file missing:", COLORPATH))
    }
    
    # 2. Run visualization using chromDraw with command-line style arguments
    # The first element of the argv vector must always be the package name "chromDraw"
    # argc is set to 7, representing the 7 elements in the argv vector
    status <- chromDraw(
      argc = 7,  
      argv = c(
        "chromDraw",
        "-c", COLORPATH,
        "-d", INPUTPATH,
        "-o", OUTPUTPATH
      )
    )
    
    # 3. Write named output files for the meaningful results
    # Save the execution status of the chromDraw run
    saveRDS(status, file = file.path(OUTPUTPATH, "chromDraw_status.rds"))
    
    # Print execution status
    cat("chromDraw execution completed with status code:", status, "\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE":
        chromdraw: \$(Rscript -e 'cat(as.character(packageVersion("chromdraw")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_text_file_karyotype.csv versions.yml
    """
}

workflow BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ karyotype_definition.txt, color_definitions.txt ] ]

    main:
    BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE(ch_input)

    emit:
    tables   = BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE.out.tables
    plots    = BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE.out.plots
    objects  = BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE.out.objects
    versions = BIOC_CHROMDRAW_TEXT_FILE_KARYOTYPE.out.versions
}
