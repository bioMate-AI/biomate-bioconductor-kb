#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GRENITS — linear_network_inference
// Infer a gene regulatory network from time-series expression data using a linear interaction model and Gibbs Variable Selection.
// Input: expression_matrix.txt
// Container: quay.io/biocontainers/bioconductor-grenits:1.62.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GRENITS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the time-series expression data
//  * 2. [Visualization & Output] Run the MCMC simulation using LinearNet to generate raw chain outputs
//  * 3. [Visualization & Output] Analyze the raw MCMC output using analyse.output to generate convergence and analysis plots
//  * 4. [Input & Preparation] Read MCMC chains using read.chain to check convergence
//  * 5. [Input & Preparation] Load the network probability matrix and apply a threshold to predict network connections
//  * 6. [Input & Preparation] Load the network probability list to determine interaction strengths and signs

nextflow.enable.dsl = 2

process BIOC_GRENITS_LINEAR_NETWORK_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("GRENITS")
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
    
    # Load required library
    library(GRENITS)
    
    # 1. Load the time-series expression data
    # The user input file 'expression_matrix.txt' is expected to be a tab-separated file
    # with genes in rows and time points in columns.
    expression_data <- as.matrix(read.table("expression_matrix.txt", header = TRUE, row.names = 1, sep = "\t"))
    
    # 2. Run the MCMC simulation using LinearNet to generate raw chain outputs
    output.folder <- paste(tempdir(), "/Example_LinearNet", sep="")
    LinearNet(output.folder, expression_data)
    
    # 3. Analyze the raw MCMC output using analyse.output to generate convergence and analysis plots
    analyse.output(output.folder)
    
    # 4. Read MCMC chains using read.chain to check convergence
    chain1 <- read.chain(output.folder,1)
    chain2 <- read.chain(output.folder,2)
    gamma1 <- colMeans(chain1\$gamma)
    gamma2 <- colMeans(chain2\$gamma)
    
    # Save convergence plot to a PDF file
    pdf("convergence_plot.pdf", width = 6, height = 6)
    plot(x = gamma1, y = gamma2, xlab = "chain1", ylab = "chain2", main = "Convergence plot for link probabilities", xlim = c(0,1), ylim = c(0,1), cex = 1.5, cex.lab = 1.6, cex.main = 1.6)
    lines(c(0,1), c(0,1), col = "red")
    dev.off()
    
    # Save raw chains as RDS objects for downstream analysis
    saveRDS(chain1, "chain1.rds")
    saveRDS(chain2, "chain2.rds")
    
    # 5. Load the network probability matrix and apply a threshold to predict network connections
    prob.file <- paste(output.folder, "/NetworkProbability_Matrix.txt", sep = "")
    prob.mat  <- read.table(prob.file)
    print(prob.mat)
    
    inferred.net <- 1*(prob.mat > 0.8)
    print(inferred.net)
    
    # Save the probability matrix and inferred network matrix to CSV files
    write.csv(prob.mat, "network_probability_matrix.csv", row.names = TRUE)
    write.csv(inferred.net, "inferred_network_matrix.csv", row.names = TRUE)
    
    # 6. Load the network probability list to determine interaction strengths and signs
    prob.list.file <- paste(output.folder, "/NetworkProbability_List.txt", sep = "")
    prob.list      <- read.table(prob.list.file, header = T)
    above.08       <- (prob.list[,3] > 0.8)
    print(prob.list[above.08,])
    
    # Save the full and filtered interaction lists to CSV files
    write.csv(prob.list, "network_probability_list.csv", row.names = FALSE)
    write.csv(prob.list[above.08,], "significant_interactions_above_0.8.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GRENITS_LINEAR_NETWORK_INFERENCE":',
        paste0('    GRENITS: ', as.character(packageVersion('GRENITS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linear_network_inference.csv versions.yml
    """
}

workflow BIOC_GRENITS_LINEAR_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.txt ] ]

    main:
    BIOC_GRENITS_LINEAR_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_GRENITS_LINEAR_NETWORK_INFERENCE.out.tables
    plots    = BIOC_GRENITS_LINEAR_NETWORK_INFERENCE.out.plots
    objects  = BIOC_GRENITS_LINEAR_NETWORK_INFERENCE.out.objects
    versions = BIOC_GRENITS_LINEAR_NETWORK_INFERENCE.out.versions
}
