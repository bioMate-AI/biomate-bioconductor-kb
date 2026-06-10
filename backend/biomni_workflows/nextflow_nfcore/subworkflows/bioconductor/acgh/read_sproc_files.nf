#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: acgh — read_sproc_files
// Read and combine multiple Sproc files along with a clone mapping file into an aCGH object.
// Input: sprocCR40.txt, sprocCR43.txt, human.clones.info.Jul03.txt
// Container: quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0
// R packages: aCGH
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ACGH_READ_SPROC_FILES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0"

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
    .bm_deps <- c("aCGH")
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
    library(aCGH)
    
    # Define the directory containing the user input files (current working directory)
    datadir <- "."
    
    # Define the path to the clone mapping file
    latest.mapping.file <- file.path(datadir, "human.clones.info.Jul03.txt")
    
    # Read and combine the Sproc files and mapping file into an aCGH object
    # Keeping the exact function call and argument names as documented
    ex.acgh <-
    	aCGH.read.Sprocs(dir(path = datadir,pattern = "sproc",
    			full.names = TRUE), latest.mapping.file,
    			chrom.remove.threshold = 23)
    
    # Plot the imported batch and save to a PDF file
    pdf("sproc_batch_plot.pdf", width = 10, height = 8)
    plot(ex.acgh)
    dev.off()
    
    # Save the meaningful results
    # 1. Save the complete aCGH object as an RDS file
    saveRDS(ex.acgh, file = "ex_acgh.rds")
    
    # 2. Extract and save log2 ratios to a CSV file
    write.csv(log2.ratios(ex.acgh), file = "log2_ratios.csv", row.names = TRUE)
    
    # 3. Extract and save clone mapping information to a CSV file
    write.csv(clones.info(ex.acgh), file = "clones_info.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ACGH_READ_SPROC_FILES":
        acgh: \$(Rscript -e 'cat(as.character(packageVersion("acgh")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_sproc_files.csv versions.yml
    """
}

workflow BIOC_ACGH_READ_SPROC_FILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sprocCR40.txt, sprocCR43.txt, human.clones.info.Jul03.txt ] ]

    main:
    BIOC_ACGH_READ_SPROC_FILES(ch_input)

    emit:
    tables   = BIOC_ACGH_READ_SPROC_FILES.out.tables
    plots    = BIOC_ACGH_READ_SPROC_FILES.out.plots
    objects  = BIOC_ACGH_READ_SPROC_FILES.out.objects
    versions = BIOC_ACGH_READ_SPROC_FILES.out.versions
}
