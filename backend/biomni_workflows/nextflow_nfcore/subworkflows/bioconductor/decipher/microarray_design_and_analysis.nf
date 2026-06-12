#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decipher — microarray_design_and_analysis
// Design microarray probes for OTUs and solve for OTU abundance using Non-Negative Least Squares (NNLS).
// Input: fas
// Container: quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0
// R packages: Biostrings, DECIPHER
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0"

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
    .bm_deps <- c("Biostrings", "DECIPHER")
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
    library(DECIPHER)
    library(Biostrings)
    
    # --- Read DNA sequences ---
    fas <- "fas"
    if (!file.exists(fas)) {
      stop("Required input file 'fas' not found in the working directory.")
    }
    dna <- readDNAStringSet(fas)
    
    # --- Calculate distance matrix using DistanceMatrix ---
    dMatrix <- DistanceMatrix(dna, verbose=FALSE)
    
    # --- Cluster sequences using Treeline ---
    clusters <- Treeline(myDistMatrix=dMatrix, type="clusters", cutoff=0.03, method="complete", verbose=FALSE)
    
    # --- Generate consensus sequences for clusters using ---
    conSeqs <- tapply(dna, clusters\$cluster, ConsensusSequence)
    conSeqs <- unlist(DNAStringSetList(conSeqs))
    
    # --- Design microarray probes using DesignArray ---
    probes <- DesignArray(conSeqs, maxPermutations=2, numProbes=20,
    	start=120, end=1450, verbose=FALSE)
    
    # --- Convert probes to a design matrix using Array2Matrix ---
    A <- Array2Matrix(probes, verbose=FALSE)
    
    # Simulate the microarray hybridization intensities (b) as documented in the vignette
    set.seed(123)
    present <- sample(length(conSeqs), max(1, floor(0.1 * length(conSeqs))))
    x <- numeric(length(conSeqs))
    x[present] <- abs(rnorm(length(present), sd=2))
    
    background <- 0.2
    b <- matrix(tapply(A\$x[A\$j]*x[A\$j], A\$i, sum), ncol=1) + background
    b <- b + rnorm(length(b), sd=0.2*b) # add 20% error
    b <- b - background # background subtracted brightnesses
    
    bad_hybs <- sample(length(b), max(1, floor(0.05*length(b))))
    b[bad_hybs] <- abs(rnorm(length(bad_hybs), sd=max(b)/3))
    
    # --- Solve for OTU abundance using NNLS ---
    x_out <- NNLS(A, b, verbose=FALSE)
    
    # Write meaningful output files
    write.csv(as.data.frame(probes), "designed_probes.csv", row.names=FALSE)
    
    results_df <- data.frame(
      OTU = names(conSeqs),
      Expected_Abundance = x,
      Predicted_Abundance = x_out\$x
    )
    write.csv(results_df, "otu_abundances.csv", row.names=FALSE)
    
    saveRDS(x_out, "nnls_results.rds")
    
    pdf("expected_vs_predicted_abundance.pdf")
    ranges <- range(c(x_out\$x, x))
    plot(x, x_out\$x,
         xlab="Expected Amount", ylab="Predicted Amount",
         xlim=ranges, ylim=ranges, pch=19, col="blue",
         main="Microarray NNLS Abundance Estimation")
    abline(a=0, b=1, col="red", lty=2)
    dev.off()

    writeLines(c(
        '"BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS":',
        paste0('        decipher: ', as.character(packageVersion("decipher")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_design_and_analysis.csv versions.yml
    """
}

workflow BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fas ] ]

    main:
    BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS.out.tables
    plots    = BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS.out.plots
    objects  = BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS.out.objects
    versions = BIOC_DECIPHER_MICROARRAY_DESIGN_AND_ANALYSIS.out.versions
}
