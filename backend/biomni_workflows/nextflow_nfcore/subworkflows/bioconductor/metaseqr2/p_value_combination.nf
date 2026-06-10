#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaseqr2 — p_value_combination
// Combine externally calculated p-values from multiple differential expression algorithms using Simes, Harmonic Mean, or PANDORA weighting methods.
// Input: hg19pvalues
// Container: quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METASEQR2_P_VALUE_COMBINATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0"

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
    .bm_deps <- c("metaseqR2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(metaseqR2)
    
    # 1. Load external p-value data
    # The pipeline reads EXACTLY the 'hg19pvalues' file from the working directory.
    if (file.exists("hg19pvalues")) {
        hg19pvalues <- tryCatch({
            read.table("hg19pvalues", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }, error = function(e) {
            read.csv("hg19pvalues", row.names = 1, check.names = FALSE)
        })
    } else if (file.exists("hg19pvalues.csv")) {
        hg19pvalues <- read.csv("hg19pvalues.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("hg19pvalues.tsv")) {
        hg19pvalues <- read.table("hg19pvalues.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    } else {
        stop("Required input file 'hg19pvalues' (or hg19pvalues.csv/tsv) not found in the working directory.")
    }
    
    # Ensure the data is in matrix format for apply operations
    hg19pvalues <- as.matrix(hg19pvalues)
    
    # 2. Combine p-values using Simes method with combineSimes
    pSimes <- apply(hg19pvalues, 1, combineSimes)
    
    # 3. Retrieve PANDORA weights using getWeights
    w <- getWeights("human")
    
    # 4. Combine p-values using Harmonic Mean method with combineHarmonic
    pHarm <- apply(hg19pvalues, 1, combineHarmonic, w)
    
    # 5. Combine p-values using PANDORA weighted method with combineWeight
    pPandora <- apply(hg19pvalues, 1, combineWeight, w)
    
    # Construct a combined data frame of results
    results <- data.frame(
        hg19pvalues,
        p_Simes = pSimes,
        p_Harmonic = pHarm,
        p_Pandora = pPandora,
        check.names = FALSE
    )
    
    # Write named output files for the meaningful results
    write.csv(results, "combined_pvalues.csv", row.names = TRUE)
    saveRDS(results, "combined_pvalues.rds")
    
    # Generate a PDF plot of the combined p-value distributions
    pdf("combined_pvalues_distribution.pdf", width = 10, height = 4)
    par(mfrow = c(1, 3))
    hist(pSimes, main = "Simes p-values", xlab = "p-value", col = "skyblue", breaks = 20)
    hist(pHarm, main = "Harmonic Mean p-values", xlab = "p-value", col = "lightgreen", breaks = 20)
    hist(pPandora, main = "PANDORA p-values", xlab = "p-value", col = "salmon", breaks = 20)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_METASEQR2_P_VALUE_COMBINATION":
        metaseqr2: \$(Rscript -e 'cat(as.character(packageVersion("metaseqr2")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_p_value_combination.csv versions.yml
    """
}

workflow BIOC_METASEQR2_P_VALUE_COMBINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg19pvalues ] ]

    main:
    BIOC_METASEQR2_P_VALUE_COMBINATION(ch_input)

    emit:
    tables   = BIOC_METASEQR2_P_VALUE_COMBINATION.out.tables
    plots    = BIOC_METASEQR2_P_VALUE_COMBINATION.out.plots
    objects  = BIOC_METASEQR2_P_VALUE_COMBINATION.out.objects
    versions = BIOC_METASEQR2_P_VALUE_COMBINATION.out.versions
}
