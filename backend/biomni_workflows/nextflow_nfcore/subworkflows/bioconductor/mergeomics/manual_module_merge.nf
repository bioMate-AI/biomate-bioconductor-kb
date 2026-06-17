#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mergeomics — manual_module_merge
// Manually merge and trim overlapping pathways/modules before running KDA.
// Input: Significant_pathways.txt, Significant_pathways.info.txt, symbols.txt
// Container: quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0
// R packages: Mergeomics
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MERGEOMICS_MANUAL_MODULE_MERGE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Mergeomics")
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
    
    # Load the required library
    library(Mergeomics)
    
    # Define job folder
    job <- list()
    job\$folder <- c("module_merge")
    
    # Read pathway and symbol data using tool.read
    # Replacing system.file calls with direct file paths in the working directory
    moddata <- tool.read("Significant_pathways.txt", c("MODULE", "GENE"))
    modinfo <- tool.read("Significant_pathways.info.txt", c("MODULE", "SOURCE", "DESCR"))
    
    syms <- tool.read("symbols.txt")
    syms <- syms[, c("HUMAN", "MOUSE")]
    names(syms) <- c("FROM", "TO")
    
    # Translate gene symbols using tool.translate
    moddata\$GENE <- tool.translate(words = moddata\$GENE, from = syms\$FROM, to = syms\$TO)
    
    # Merge and trim overlapping modules
    rmax <- 0.2
    moddata\$OVERLAP <- moddata\$MODULE
    moddata <- tool.coalesce(items = moddata\$GENE, groups = moddata\$MODULE, rcutoff = rmax)
    moddata\$MODULE <- moddata\$CLUSTER
    moddata\$GENE <- moddata\$ITEM
    moddata\$OVERLAP <- moddata\$GROUPS
    moddata <- moddata[, c("MODULE", "GENE", "OVERLAP")]
    moddata <- unique(moddata)
    modinfo <- modinfo[which(!is.na(match(modinfo[, 1], moddata[, 1]))), ]
    
    # Mark modules with overlaps
    for (i in which(moddata\$MODULE != moddata\$OVERLAP)) {
      modinfo[which(modinfo[, "MODULE"] == moddata[i, "MODULE"]), "MODULE"] <- paste(moddata[i, "MODULE"], "..", sep = ",")
      moddata[i, "MODULE"] <- paste(moddata[i, "MODULE"], "..", sep = ",")
    }
    
    # Save merged module data and info for KDA
    modfile <- "mergedModules.txt"
    modinfofile <- "mergedModules.info.txt"
    moddata\$NODE <- moddata\$GENE
    
    # Ensure output directory exists
    if (!dir.exists(job\$folder)) {
      dir.create(job\$folder, recursive = TRUE)
    }
    
    tool.save(frame = unique(moddata[, c("MODULE", "GENE", "OVERLAP", "NODE")]),
              file = modfile, directory = job\$folder)
    tool.save(frame = unique(modinfo[, c("MODULE", "SOURCE", "DESCR")]),
              file = modinfofile, directory = job\$folder)

    writeLines(c(
        '"BIOC_MERGEOMICS_MANUAL_MODULE_MERGE":',
        paste0('        mergeomics: ', as.character(packageVersion("mergeomics")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_module_merge.csv versions.yml
    """
}

workflow BIOC_MERGEOMICS_MANUAL_MODULE_MERGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Significant_pathways.txt, Significant_pathways.info.txt, symbols.txt ] ]

    main:
    BIOC_MERGEOMICS_MANUAL_MODULE_MERGE(ch_input)

    emit:
    tables   = BIOC_MERGEOMICS_MANUAL_MODULE_MERGE.out.tables
    plots    = BIOC_MERGEOMICS_MANUAL_MODULE_MERGE.out.plots
    objects  = BIOC_MERGEOMICS_MANUAL_MODULE_MERGE.out.objects
    versions = BIOC_MERGEOMICS_MANUAL_MODULE_MERGE.out.versions
}
