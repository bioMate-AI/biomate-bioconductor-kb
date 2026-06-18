#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genarise — functional_enrichment_genmerge
// Perform functional genomic annotation and statistical over-representation analysis of differentially expressed genes.
// Input: association.txt, description.txt, population.genes, study.genes
// Container: quay.io/biocontainers/bioconductor-genarise:1.86.0--r45hdfd78af_0
// R packages: genArise
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genarise:1.86.0--r45hdfd78af_0"

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
    .bm_deps <- c("genArise")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(genArise)
    
    # ---------------------------------------------------------
    # --- Read User Input Files ---
    # ---------------------------------------------------------
    # Read the population genes provided by the user
    pop_data <- read.table("population.genes", header = FALSE, stringsAsFactors = FALSE, sep = "\t")
    pop_ids <- as.character(pop_data[[1]])
    
    # Read the study genes provided by the user
    study_data <- read.table("study.genes", header = FALSE, stringsAsFactors = FALSE, sep = "\t")
    study_ids <- as.character(study_data[[1]])
    
    # Define file paths for genMerge
    gene.association <- "association.txt"
    description <- "description.txt"
    population.genes <- "population.genes"
    study.genes <- "study.genes"
    
    # ---------------------------------------------------------
    # --- Construct o.spot and s.spot Objects from Input Data ---
    # ---------------------------------------------------------
    # o.spot needs to contain the population IDs in attr(o.spot, "spotData")\$Ids
    o.spot <- list()
    attr(o.spot, "spotData") <- list(Ids = pop_ids)
    
    # s.spot needs to contain Id.up and Id.down
    s.spot <- list(
      Id.up = study_ids,
      Id.down = character(0)
    )
    
    # ---------------------------------------------------------
    # --- Execute Documented Workflow Steps Exactly ---
    # ---------------------------------------------------------
    ids <- attr(o.spot, "spotData")\$Ids
    ids <- unique(ids)
    write.table(ids, "population.genes")
    
    study.ids <- c(s.spot\$Id.up, s.spot\$Id.down)
    study.ids <- unique(study.ids)
    write.table(study.ids, "study.genes")
    
    study.ids <- s.spot\$Id.up
    study.ids <- unique(study.ids)
    write.table(study.ids, "study.genes")
    
    # Run over-representation analysis using genMerge
    results <- genMerge(gene.association, description, population.genes, study.genes, output.file = "GeneMerge.txt")
    
    # ---------------------------------------------------------
    # --- Save Outputs ---
    # ---------------------------------------------------------
    # Save the returned object (if any) as an RDS file
    saveRDS(results, "genmerge_results.rds")
    
    # If the output file was successfully created, attempt to export a CSV version for convenience
    if (file.exists("GeneMerge.txt")) {
      tryCatch({
        gm_data <- read.delim("GeneMerge.txt", header = TRUE, sep = "\t")
        write.csv(gm_data, "GeneMerge_results.csv", row.names = FALSE)
      }, error = function(e) {
        message("Note: GeneMerge.txt was created but could not be parsed into a standard CSV: ", e\$message)
      })
    }

    writeLines(c(
        '"BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE":',
        paste0('        genarise: ', as.character(packageVersion("genarise")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_functional_enrichment_genmerge.csv versions.yml
    """
}

workflow BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ association.txt, description.txt, population.genes, study.genes ] ]

    main:
    BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE(ch_input)

    emit:
    tables   = BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE.out.tables
    plots    = BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE.out.plots
    objects  = BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE.out.objects
    versions = BIOC_GENARISE_FUNCTIONAL_ENRICHMENT_GENMERGE.out.versions
}
