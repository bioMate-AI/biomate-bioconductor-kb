#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromdraw — bed_file_karyotype
// Visualize karyotypes from a BED format file.
// Input: bed_file.bed
// Container: quay.io/biocontainers/bioconductor-chromdraw:2.40.0--r45ha27e39d_0
// R packages: chromDraw
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMDRAW_BED_FILE_KARYOTYPE {
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
    .bm_deps <- c("chromDraw")
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
    
    # Load the required library
    library(chromDraw)
    
    # Define the input path pointing to the user-provided BED file in the working directory
    INPUTPATH <- file.path(getwd(), "bed_file.bed")
    
    # Define the output path as the current working directory
    OUTPUTPATH <- file.path(getwd())
    
    # Ensure the input file exists before running
    if (!file.exists(INPUTPATH)) {
      stop(paste("Required input file 'bed_file.bed' not found in the working directory:", getwd()))
    }
    
    # Run the visualization using chromDraw specifying the BED format
    # This call is preserved exactly as documented
    chromDraw(argc=7,  
              argv=c("chromDraw", "-f", "bed", "-d", INPUTPATH, "-o", OUTPUTPATH))

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHROMDRAW_BED_FILE_KARYOTYPE":
        chromdraw: \$(Rscript -e 'cat(as.character(packageVersion("chromdraw")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bed_file_karyotype.csv versions.yml
    """
}

workflow BIOC_CHROMDRAW_BED_FILE_KARYOTYPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bed_file.bed ] ]

    main:
    BIOC_CHROMDRAW_BED_FILE_KARYOTYPE(ch_input)

    emit:
    tables   = BIOC_CHROMDRAW_BED_FILE_KARYOTYPE.out.tables
    plots    = BIOC_CHROMDRAW_BED_FILE_KARYOTYPE.out.plots
    objects  = BIOC_CHROMDRAW_BED_FILE_KARYOTYPE.out.objects
    versions = BIOC_CHROMDRAW_BED_FILE_KARYOTYPE.out.versions
}
