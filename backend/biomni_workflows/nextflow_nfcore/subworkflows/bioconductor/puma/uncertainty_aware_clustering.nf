#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — uncertainty_aware_clustering
// Cluster probe-sets taking into account expression-level uncertainties and replicate information.
// Input: eset_estrogen_mmgmos, Clustii.exampleE, Clustii.exampleStd
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// R packages: puma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0"

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
    .bm_deps <- c("puma")
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
    library(puma)
    
    # Helper function to robustly read user input files
    read_input <- function(filename) {
      if (file.exists(filename)) {
        # Try reading as RDS first
        tryCatch({
          return(readRDS(filename))
        }, error = function(e) {
          # If RDS fails, try loading as RData
          tryCatch({
            env <- new.env()
            load(filename, envir = env)
            return(get(ls(env)[1], envir = env))
          }, error = function(e2) {
            # If RData fails, try reading as CSV
            return(as.matrix(read.csv(filename, row.names = 1)))
          })
        })
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else if (file.exists(paste0(filename, ".RData"))) {
        env <- new.env()
        load(paste0(filename, ".RData"), envir = env)
        return(get(ls(env)[1], envir = env))
      } else if (file.exists(paste0(filename, ".csv"))) {
        return(as.matrix(read.csv(paste0(filename, ".csv"), row.names = 1)))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # 1. Load the declared user input files
    message("Loading input files...")
    eset_estrogen_mmgmos <- read_input("eset_estrogen_mmgmos")
    Clustii.exampleE     <- read_input("Clustii.exampleE")
    Clustii.exampleStd   <- read_input("Clustii.exampleStd")
    
    # 2. Run pumaClust for standard clustering incorporating uncertainty
    message("Running pumaClust...")
    pumaClust_estrogen <- pumaClust(eset_estrogen_mmgmos, clusters=7)
    
    # Summarize cluster assignments and centers
    message("Summarizing pumaClust results...")
    clust_summary <- summary(as.factor(pumaClust_estrogen\$cluster))
    print(clust_summary)
    print(pumaClust_estrogen\$centers)
    
    # Write pumaClust results
    write.csv(pumaClust_estrogen\$cluster, file="pumaClust_clusters.csv")
    saveRDS(pumaClust_estrogen, file="pumaClust_results.rds")
    
    # 3. Run pumaClustii for robust Student's t mixture model clustering with replicates
    message("Running pumaClustii...")
    r <- vector(mode="integer", 0)
    for (i in c(1:20)) {
      for (j in c(1:4)) {
        r <- c(r, i)
      }
    }
    
    cl <- pumaClustii(Clustii.exampleE, Clustii.exampleStd,
                      mincls=6, maxcls=6, conds=20, reps=r, eps=1e-3)
    
    # Summarize and write pumaClustii results
    message("Summarizing pumaClustii results...")
    cl_summary <- summary(as.factor(cl\$cluster))
    print(cl_summary)
    
    write.csv(cl\$cluster, file="pumaClustii_clusters.csv")
    saveRDS(cl, file="pumaClustii_results.rds")
    
    message("Workflow completed successfully. Outputs written to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING":
        puma: \$(Rscript -e 'cat(as.character(packageVersion("puma")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_uncertainty_aware_clustering.csv versions.yml
    """
}

workflow BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eset_estrogen_mmgmos, Clustii.exampleE, Clustii.exampleStd ] ]

    main:
    BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING.out.tables
    plots    = BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING.out.plots
    objects  = BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING.out.objects
    versions = BIOC_PUMA_UNCERTAINTY_AWARE_CLUSTERING.out.versions
}
