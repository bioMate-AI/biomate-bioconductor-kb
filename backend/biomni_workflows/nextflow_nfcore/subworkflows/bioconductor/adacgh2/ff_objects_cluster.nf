#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adacgh2 — ff_objects_cluster
// Analyze large aCGH datasets or run parallelized analysis on Windows using disk-backed ff objects and socket clusters.
// Input: inputEx.RData
// Container: quay.io/biocontainers/bioconductor-adacgh2:2.50.0--r45h01b2380_1
// R packages: ADaCGH2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADACGH2_FF_OBJECTS_CLUSTER {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-adacgh2:2.50.0--r45h01b2380_1"

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
    .bm_deps <- c("ADaCGH2")
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
    
    library(ADaCGH2)
    
    # 1. Convert input data to disk-backed ff objects
    fnameRdata <- file.path(getwd(), "inputEx.RData")
    
    inputToADaCGH(ff.or.RAM = "ff",
                  RDatafilename = fnameRdata)
    
    # 2. Initialize socket cluster
    number.of.nodes <- 2
    cl2 <- parallel::makeCluster(number.of.nodes, "PSOCK")
    parallel::clusterSetRNGStream(cl2)
    parallel::setDefaultCluster(cl2)
    parallel::clusterEvalQ(NULL, library("ADaCGH2"))
    wdir <- getwd()
    parallel::clusterExport(NULL, "wdir")
    parallel::clusterEvalQ(NULL, setwd(wdir))
    
    # 3. Run parallelized segmentation using cluster
    haar.ff.cluster <- pSegmentHaarSeg("cghData.RData",
                                   "chromData.RData",
                                   merging = "MAD",
                                   typeParall = "cluster")
    
    # 4. Save and plot results
    save(haar.ff.cluster, file = "hs_mad.out.RData", compress = FALSE)
    
    pChromPlot(outRDataName = "hs_mad.out.RData",
               cghRDataName = "cghData.RData",
               chromRDataName = "chromData.RData",
               posRDataName = "posData.RData",
               probenamesRDataName = "probeNames.RData",
               imgheight = 350,
               typeParall = "cluster")
    
    # 5. Stop cluster
    parallel::stopCluster(cl2)
    
    # 6. Export meaningful results to CSV
    lapply(haar.ff.cluster, open)
    smoothed_df <- as.data.frame(haar.ff.cluster\$outSmoothed[,])
    state_df <- as.data.frame(haar.ff.cluster\$outState[,])
    
    write.csv(smoothed_df, "smoothed_values.csv", row.names = FALSE)
    write.csv(state_df, "state_calls.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ADACGH2_FF_OBJECTS_CLUSTER":
        adacgh2: \$(Rscript -e 'cat(as.character(packageVersion("adacgh2")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ff_objects_cluster.csv versions.yml
    """
}

workflow BIOC_ADACGH2_FF_OBJECTS_CLUSTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputEx.RData ] ]

    main:
    BIOC_ADACGH2_FF_OBJECTS_CLUSTER(ch_input)

    emit:
    tables   = BIOC_ADACGH2_FF_OBJECTS_CLUSTER.out.tables
    plots    = BIOC_ADACGH2_FF_OBJECTS_CLUSTER.out.plots
    objects  = BIOC_ADACGH2_FF_OBJECTS_CLUSTER.out.objects
    versions = BIOC_ADACGH2_FF_OBJECTS_CLUSTER.out.versions
}
