#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OSAT — standard_sample_assignment
// Optimize sample-to-batch assignment across multiple plates using the default shuffle algorithm to minimize batch effects for all variables.
// Input: samples.txt
// Container: quay.io/biocontainers/bioconductor-osat:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OSAT
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load sample metadata
//  * 2. [Input & Preparation] Define sample setup with variables to optimize
//  * 3. [Input & Preparation] Define container setup (plates and batch level)
//  * 4. [Input & Preparation] Create optimized setup using the default shuffle algorithm
//  * 5. [Visualization & Output] Export the optimized assignment to a CSV file
//  * 6. [Visualization & Output] Map the design to a robotic loader layout and export
//  * 7. [Visualization & Output] Perform quality control visualization and statistical testing

nextflow.enable.dsl = 2

process BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("OSAT")
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
    
    # Load required library
    library(OSAT)
    
    # 1. Load sample metadata from the working directory
    if (!file.exists("samples.txt")) {
      stop("Error: 'samples.txt' not found in the working directory.")
    }
    
    pheno <- read.table("samples.txt", 
                        header=TRUE, sep="\t", colClasses="factor")
    
    # 2. Define sample setup with variables to optimize
    optimal_vars <- setdiff(colnames(pheno), "ID")
    if (length(optimal_vars) == ncol(pheno)) {
      optimal_vars <- colnames(pheno)[-1]
    }
    gs <- setup.sample(pheno, optimal=optimal_vars)
    
    # 3. Define container setup (plates and batch level)
    num_plates <- ceiling(nrow(pheno) / 96)
    gc <- setup.container(IlluminaBeadChip96Plate, num_plates, batch='plates')
    
    # 4. Create optimized setup using the default shuffle algorithm
    set.seed(123)
    gSetup <- create.optimized.setup(sample=gs, container=gc, nSim=1000)
    
    # 5. Export the optimized assignment to a CSV file and RDS object
    write.csv(get.experiment.setup(gSetup), 
              file="gSetup.csv", row.names=FALSE)
    saveRDS(gSetup, file="gSetup.rds")
    
    # 6. Map the design to a robotic loader layout and export
    out <- map.to.MSA(gSetup, MSA4.plate)
    write.csv(out, "MSAsetup.csv", row.names = FALSE)
    
    # 7. Perform quality control visualization and statistical testing
    pdf("QC_report.pdf", width=11, height=8.5)
    QC(gSetup)
    invisible(dev.off())

    writeLines(c(
        '"BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT":',
        paste0('    OSAT: ', as.character(packageVersion('OSAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_sample_assignment.csv versions.yml
    """
}

workflow BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples.txt ] ]

    main:
    BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT(ch_input)

    emit:
    tables   = BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT.out.tables
    plots    = BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT.out.plots
    objects  = BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT.out.objects
    versions = BIOC_OSAT_STANDARD_SAMPLE_ASSIGNMENT.out.versions
}
