#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BiocSklearn — manual_incremental_pca
// Perform manual incremental PCA step-by-step on data chunks or streams.
// Input: irismat
// Container: quay.io/biocontainers/bioconductor-biocsklearn:1.32.0--py314r45hdfd78af_0
// R packages: BiocSklearn, reticulate
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA {
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
    .bm_deps <- c("BiocSklearn", "reticulate")
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
    library(BiocSklearn)
    library(reticulate)
    
    # Initialize numpy with convert=FALSE and delay_load=TRUE as recommended
    np <- reticulate::import("numpy", convert = FALSE, delay_load = TRUE)
    
    # Locate and read the user-provided input file 'irismat'
    if (file.exists("irismat")) {
      irismat_file <- "irismat"
    } else if (file.exists("irismat.csv")) {
      irismat_file <- "irismat.csv"
    } else {
      stop("Required input file 'irismat' or 'irismat.csv' not found in the working directory.")
    }
    
    # Load the dataset into a numpy array
    irismat <- tryCatch({
      np\$genfromtxt(irismat_file, delimiter = ",")
    }, error = function(e) {
      np\$genfromtxt(irismat_file)
    })
    
    # 1. Define slicer utility
    ta = np \$ take
    
    # 2. Initialize and update PCA state iteratively using skPartialPCA_step
    ipc = skPartialPCA_step ( ta (irismat, 0 : 49 ,0L))
    ipc = skPartialPCA_step ( ta (irismat, 50 : 99 ,0L), obj= ipc)
    ipc = skPartialPCA_step ( ta (irismat, 100 : 149 ,0L), obj= ipc)
    
    # 3. Transform a subset of data using the final PCA object
    transformed_py = ipc \$ transform ( ta (irismat, 0 : 5 ,0L))
    
    # Convert the transformed python object to an R matrix for output
    transformed_r <- reticulate::py_to_r(transformed_py)
    
    # Write the meaningful results to output files
    write.csv(transformed_r, "transformed_subset.csv", row.names = FALSE)
    
    # Generate a PDF plot of the transformed subset (first two principal components)
    pdf("pca_transformed_plot.pdf")
    plot(
      transformed_r[, 1], 
      transformed_r[, 2], 
      col = "blue", 
      pch = 19,
      xlab = "PC1", 
      ylab = "PC2", 
      main = "Manual Incremental PCA (Subset)"
    )
    dev.off()
    
    # Save the final PCA state/object attributes if possible, or save the R matrix as RDS
    saveRDS(transformed_r, "transformed_subset.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA":
        BiocSklearn: \$(Rscript -e 'cat(as.character(packageVersion("BiocSklearn")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_incremental_pca.csv versions.yml
    """
}

workflow BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ irismat ] ]

    main:
    BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA(ch_input)

    emit:
    tables   = BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA.out.tables
    plots    = BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA.out.plots
    objects  = BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA.out.objects
    versions = BIOC_BIOCSKLEARN_MANUAL_INCREMENTAL_PCA.out.versions
}
