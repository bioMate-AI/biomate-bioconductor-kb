#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OSAT — prioritized_blocking_assignment
// Optimize sample-to-batch assignment prioritizing a primary biological variable (blocking) while optimizing other confounding variables.
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
//  * 2. [Input & Preparation] Define sample setup specifying the primary variable as strata and all variables as optimal
//  * 3. [Input & Preparation] Define container setup
//  * 4. [Input & Preparation] Create optimized setup using the "optimal.block" algorithm
//  * 5. [Visualization & Output] Perform quality control visualization and statistical testing

nextflow.enable.dsl = 2

process BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    
    # Identify variables to use (exclude columns where every value is unique, like sample IDs)
    is_unique <- sapply(pheno, function(x) length(unique(x)) == nrow(pheno))
    opt_vars <- colnames(pheno)[!is_unique]
    
    # Fallback in case all columns are unique
    if (length(opt_vars) == 0) {
      opt_vars <- colnames(pheno)
    }
    
    # 2. Define sample setup specifying the primary variable as strata and all variables as optimal
    gs2 <- setup.sample(pheno,  strata=opt_vars[1], 
              optimal=opt_vars )
    
    # 3. Define container setup
    # Calculate the required number of plates (96 wells per IlluminaBeadChip96Plate)
    num_plates <- ceiling(nrow(pheno) / 96)
    gc <- setup.container(IlluminaBeadChip96Plate, num_plates, batch='plates')
    
    # 4. Create optimized setup using the "optimal.block" algorithm
    set.seed(123)
    gSetup2 <- create.optimized.setup("optimal.block", 
              sample=gs2, container=gc, nSim=1000)
    
    # 5. Perform quality control visualization and statistical testing
    # Save the QC plot to a PDF file
    pdf("QC_plot.pdf", width=10, height=8)
    QC(gSetup2)
    dev.off()
    
    # 6. Write named output files for the meaningful results
    # Save the optimized experiment setup as a CSV file
    setup_df <- get.experiment.setup(gSetup2)
    write.csv(setup_df, file="optimized_setup.csv", row.names=FALSE)
    
    # Save the gSetup2 object as an RDS file
    saveRDS(gSetup2, file="gSetup2.rds")

    writeLines(c(
        '"BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT":',
        paste0('    OSAT: ', as.character(packageVersion('OSAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prioritized_blocking_assignment.csv versions.yml
    """
}

workflow BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples.txt ] ]

    main:
    BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT(ch_input)

    emit:
    tables   = BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT.out.tables
    plots    = BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT.out.plots
    objects  = BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT.out.objects
    versions = BIOC_OSAT_PRIORITIZED_BLOCKING_ASSIGNMENT.out.versions
}
