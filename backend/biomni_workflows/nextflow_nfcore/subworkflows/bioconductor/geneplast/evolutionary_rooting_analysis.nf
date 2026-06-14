#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneplast — evolutionary_rooting_analysis
// Determine the evolutionary root of genes in a given species tree using the Bridge algorithm.
// Input: cogdata, phyloTree, spid
// Container: quay.io/biocontainers/bioconductor-geneplast:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ape, geneplast
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess rooting data using groot.preprocess
//  * 2. [Core Analysis] Run rooting analysis using groot
//  * 3. [Core Analysis] Retrieve results using groot.get
//  * 4. [Visualization & Output] Plot rooting results using groot.plot

nextflow.enable.dsl = 2

process BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("geneplast", "ape")
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
    
    # Load required libraries
    library(geneplast)
    library(ape)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read cogdata (data frame mapping genes to orthologous groups and species)
    cogdata_files <- c("cogdata.rds", "cogdata.csv", "cogdata.tsv", "cogdata.txt", "cogdata")
    cogdata <- NULL
    for (f in cogdata_files) {
      if (file.exists(f)) {
        if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
          cogdata <- readRDS(f)
        } else if (grepl("\\\\.csv\$", f, ignore.case = TRUE)) {
          cogdata <- read.csv(f, stringsAsFactors = FALSE)
        } else {
          cogdata <- read.delim(f, stringsAsFactors = FALSE)
        }
        break
      }
    }
    if (is.null(cogdata)) {
      stop("Error: cogdata file not found in the working directory.")
    }
    
    # Read phyloTree (phylogenetic tree object of class 'phylo')
    phyloTree_files <- c("phyloTree.rds", "phyloTree.nwk", "phyloTree.tre", "phyloTree.txt", "phyloTree")
    phyloTree <- NULL
    for (f in phyloTree_files) {
      if (file.exists(f)) {
        if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
          phyloTree <- readRDS(f)
        } else {
          phyloTree <- read.tree(f)
        }
        break
      }
    }
    if (is.null(phyloTree)) {
      stop("Error: phyloTree file not found in the working directory.")
    }
    
    # Read spid (NCBI taxonomy ID of the reference species)
    spid_files <- c("spid.rds", "spid.txt", "spid")
    spid <- NULL
    for (f in spid_files) {
      if (file.exists(f)) {
        if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
          spid <- readRDS(f)
        } else {
          spid <- trimws(readLines(f, n = 1, warn = FALSE))
        }
        break
      }
    }
    if (is.null(spid)) {
      stop("Error: spid file not found in the working directory.")
    }
    spid <- as.character(spid)
    
    # ==========================================
    # 2. ADAPTED WORKFLOW
    # ==========================================
    
    # Stage 1: Preprocess rooting data using groot.preprocess
    ogr <- groot.preprocess(cogdata=cogdata, phyloTree=phyloTree, spid=spid, verbose=FALSE)
    
    # Stage 2: Run rooting analysis using groot
    set.seed(1)
    ogr <- groot(ogr, nPermutations=100, verbose=FALSE)
    
    # Stage 3: Retrieve results using groot.get
    res <- groot.get(ogr, what="results")
    head(res)
    
    # Write meaningful results to output files
    write.csv(res, "rooting_results.csv", row.names = TRUE)
    saveRDS(res, "rooting_results.rds")
    saveRDS(ogr, "ogr_output.rds")
    
    # Stage 4: Plot rooting results using groot.plot
    # Wrap in tryCatch to handle cases where the specific demo OG "NOG40170" is absent in user data
    tryCatch({
      groot.plot(ogr, whichOG="NOG40170")
    }, error = function(e) {
      message("groot.plot for NOG40170 failed (likely because NOG40170 is not in the input data): ", e\$message)
      # Fallback to first available OG to demonstrate plotting
      if (nrow(res) > 0) {
        first_og <- rownames(res)[1]
        message("Attempting to plot available OG: ", first_og)
        try(groot.plot(ogr, whichOG=first_og))
      }
    })
    
    tryCatch({
      groot.plot(ogr, plot.lcas = TRUE)
    }, error = function(e) {
      message("groot.plot with plot.lcas=TRUE failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS":',
        paste0('    geneplast: ', as.character(packageVersion('geneplast')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_evolutionary_rooting_analysis.csv versions.yml
    """
}

workflow BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cogdata, phyloTree, spid ] ]

    main:
    BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS.out.tables
    plots    = BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS.out.plots
    objects  = BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS.out.objects
    versions = BIOC_GENEPLAST_EVOLUTIONARY_ROOTING_ANALYSIS.out.versions
}
