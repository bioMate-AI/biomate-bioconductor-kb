#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BiocSklearn — incremental_pca
// Perform memory-bounded incremental principal component analysis on large datasets.
// Input: irismat
// Container: quay.io/biocontainers/bioconductor-biocsklearn:1.32.0--py314r45hdfd78af_0
// R packages: BiocSklearn, BiocStyle
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCSKLEARN_INCREMENTAL_PCA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-biocsklearn:1.32.0--py314r45hdfd78af_0"

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
    .bm_deps <- c("BiocSklearn", "BiocStyle")
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
    
    library(BiocSklearn)
    
    # Import numpy with convert=FALSE as specified in the package guidelines
    np <- reticulate::import("numpy", convert=FALSE, delay_load=TRUE)
    
    # Read the user input file 'irismat' from the working directory
    irismat <- tryCatch({
      np\$genfromtxt("irismat", delimiter=",")
    }, error = function(e) {
      np\$load("irismat")
    })
    
    # Convert the numpy array to an R matrix to compute the standard PCA (fullpc)
    r_mat <- reticulate::py_to_r(irismat)
    fullpc <- prcomp(r_mat)\$x
    
    # === DOCUMENTED CODE ===
    ippcab = skIncrPCA (irismat, batch_size= 25L)
    round ( cor ( getTransformed (ippcab), fullpc), 3 )
    # === END DOCUMENTED CODE ===
    
    # Extract transformed coordinates
    transformed_coords <- getTransformed(ippcab)
    
    # Save the meaningful results to output files
    write.csv(as.matrix(transformed_coords), "transformed_coords.csv", row.names = FALSE)
    
    correlation_matrix <- round(cor(transformed_coords, fullpc), 3)
    write.csv(as.data.frame(correlation_matrix), "correlation_matrix.csv")

    writeLines(c(
        '"BIOC_BIOCSKLEARN_INCREMENTAL_PCA":',
        paste0('        BiocSklearn: ', as.character(packageVersion("BiocSklearn")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_incremental_pca.csv versions.yml
    """
}

workflow BIOC_BIOCSKLEARN_INCREMENTAL_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ irismat ] ]

    main:
    BIOC_BIOCSKLEARN_INCREMENTAL_PCA(ch_input)

    emit:
    tables   = BIOC_BIOCSKLEARN_INCREMENTAL_PCA.out.tables
    plots    = BIOC_BIOCSKLEARN_INCREMENTAL_PCA.out.plots
    objects  = BIOC_BIOCSKLEARN_INCREMENTAL_PCA.out.objects
    versions = BIOC_BIOCSKLEARN_INCREMENTAL_PCA.out.versions
}
