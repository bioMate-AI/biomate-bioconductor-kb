#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ccfindr — maximum_likelihood_nmf
// Perform unsupervised clustering of single-cell RNA-seq data using Maximum Likelihood NMF and evaluate factorization quality across multiple ranks.
// Input: matrix.mtx, genes.tsv, barcodes.tsv
// Container: quay.io/biocontainers/bioconductor-ccfindr:1.30.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ccfindr:1.30.0--r45ha27e39d_0"

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
    .bm_deps <- c("ccfindr", "s4vectors")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required package
    library(ccfindR)
    
    # Define the input directory as the current working directory
    dir <- "."
    
    # 1. Read 10x Genomics data to create an scNMFSet object
    sc <- read_10x(dir = dir, count = 'matrix.mtx', genes = 'genes.tsv', barcodes = 'barcodes.tsv')
    
    # 2. Filter cells based on UMI count thresholds
    sc <- filter_cells(sc, umi.min = 10^2.6, umi.max = 10^3.4)
    
    # 3. Filter genes based on variance-to-mean ratio (VMR) and minimum cell expression
    markers <- c('CD4','CD8A','CD8B','CD19','CD3G','CD3D',
                 'CD3Z','CD14')
    sc0 <- filter_genes(sc, markers = markers, vmr.min = 1.5, 
                min.cells.expressed = 50, rescue.genes = FALSE)
    
    # Assign the gene-filtered object to sc to proceed with factorization on the filtered dataset
    sc <- sc0
    
    # 4. Perform Maximum Likelihood NMF factorization across a range of ranks
    sc <- factorize(sc, ranks = seq(3,7), nrun = 5, verbose = 1, progress.bar = FALSE)
    
    # 5. Evaluate factorization quality measures (dispersion, cophenetic correlation)
    measures_df <- measure(sc)
    
    # Write outputs to the working directory
    write.csv(measures_df, "factorization_measures.csv", row.names = FALSE)
    
    pdf("factorization_plots.pdf")
    plot(sc)
    dev.off()
    
    saveRDS(sc, "sc_factorized.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF":
        ccfindr: \$(Rscript -e 'cat(as.character(packageVersion("ccfindr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_maximum_likelihood_nmf.csv versions.yml
    """
}

workflow BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix.mtx, genes.tsv, barcodes.tsv ] ]

    main:
    BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF(ch_input)

    emit:
    tables   = BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF.out.tables
    plots    = BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF.out.plots
    objects  = BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF.out.objects
    versions = BIOC_CCFINDR_MAXIMUM_LIKELIHOOD_NMF.out.versions
}
