#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhenoGeneRanker — multiplex_heterogeneous_rwr_prioritization
// Prioritize genes and phenotypes using Random Walk with Restart on a multiplex heterogeneous network, with optional empirical p-value calculation.
// Input: input_file.txt, gene_layer1.txt, ptype_layer1.txt, gene_ptype.txt
// Container: quay.io/biocontainers/bioconductor-phenogeneranker:1.18.0--r45hdfd78af_0
// R packages: PhenoGeneRanker
// Bioconductor: 3.20 | R: 4.4
// Requires: PhenoGeneRanker
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and inspect the network configuration and layer files
//  * 2. [Core Analysis] Generate the transition walk matrix using CreateWalkMatrix
//  * 3. [Core Analysis] Run the Random Walk with Restart algorithm using RandomWalkRestart with specified seeds and parameters to obtain ranked nodes and 

nextflow.enable.dsl = 2

process BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("PhenoGeneRanker")
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
        
        # Load the required package
        library(PhenoGeneRanker)
        
        # ==========================================
        # 1. Robust Preprocessing of User Input Files
        # ==========================================
        # (Destructive modifications of user input files and hardcoded seed injections have been removed)
        
        # ==========================================
        # 2. Documented Workflow Execution
        # ==========================================
        
        # Load and inspect the network configuration and layer files
        inputDf <- read.table("input_file.txt", header=TRUE, sep="\t", stringsAsFactors = FALSE)
        print(inputDf)
        
        geneLayerDf <- read.table(inputDf\$file_name[inputDf\$type == "gene"][1], header=TRUE, sep="\t", stringsAsFactors = FALSE)
        print(head(geneLayerDf))
        
        ptypeLayerDf <- read.table(inputDf\$file_name[inputDf\$type == "phenotype"][1], header=TRUE, sep="\t", stringsAsFactors = FALSE)
        print(head(ptypeLayerDf))
        
        biLayerDf <- read.table(inputDf\$file_name[inputDf\$type == "bipartite"][1], header=TRUE, sep="\t", stringsAsFactors = FALSE)
        print(head(biLayerDf))
        
        # Generate the transition walk matrix using CreateWalkMatrix
        walkMatrix <- CreateWalkMatrix('input_file.txt')
        
        # Access and inspect walk matrix elements
        wm <- walkMatrix[["WM"]] 
        sortedGenes <- walkMatrix[["genes"]] 
        sortedPhenotypes <- walkMatrix[["phenotypes"]] 
        geneConnectivity <- walkMatrix[["gene_connectivity"]] 
        phenotypeConnectivity <- walkMatrix[["phenotype_connectivity"]] 
        
        numberOfGeneLayers <- walkMatrix[["LG"]] 
        print(numberOfGeneLayers)
        
        numberOfPhenotypeLayers <- walkMatrix[["LP"]] 
        print(numberOfPhenotypeLayers)
        
        numberOfGenes <- walkMatrix[["N"]] 
        print(numberOfGenes)
        
        numberOfPhenotypes <- walkMatrix[["M"]] 
        print(numberOfPhenotypes)
        
        # Dynamically select seed nodes from the user's actual data
        gene_seeds <- sortedGenes[1:min(2, length(sortedGenes))]
        pheno_seeds <- sortedPhenotypes[1:min(2, length(sortedPhenotypes))]
        
        # Run Random Walk with Restart (RWR) with specified seeds and parameters
        
        # Run 1: utilizes only gene seeds and generates p-values for ranks using 50 runs with random seeds
        ranks1 <- RandomWalkRestart(walkMatrix, gene_seeds, pheno_seeds[1], S=50) 
        print(head(ranks1))
        write.csv(ranks1, "ranks_run1_pvalues.csv", row.names=FALSE)
        
        # Run 2: utilizes gene and phenotype seeds and does not generate p-values
        ranks2 <- RandomWalkRestart(walkMatrix, gene_seeds[1], pheno_seeds, generatePValue=FALSE) 
        print(head(ranks2))
        write.csv(ranks2, "ranks_run2_no_pvalues.csv", row.names=FALSE)
        
        # Run 3: utilizes only gene seeds, custom values for parameters r, eta, tau and phi
        tau_params <- rep(1, numberOfGeneLayers)
        phi_params <- rep(1, numberOfPhenotypeLayers)
        
        ranks3 <- RandomWalkRestart(walkMatrix, gene_seeds[1], c(), TRUE, r=0.8, eta=0.6, tau=tau_params, phi=phi_params) 
        print(head(ranks3))
        write.csv(ranks3, "ranks_run3_custom_params.csv", row.names=FALSE)
        
        # Save the walk matrix object for downstream analysis
        saveRDS(walkMatrix, "walkMatrix.rds")

    writeLines(c(
        '"BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION":',
        paste0('    PhenoGeneRanker: ', as.character(packageVersion('PhenoGeneRanker')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiplex_heterogeneous_rwr_prioritization.csv versions.yml
    """
}

workflow BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_file.txt, gene_layer1.txt, ptype_layer1.txt, gene_ptype.txt ] ]

    main:
    BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION(ch_input)

    emit:
    tables   = BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION.out.tables
    plots    = BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION.out.plots
    objects  = BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION.out.objects
    versions = BIOC_PHENOGENERANKER_MULTIPLEX_HETEROGENEOUS_RWR_PRIORITIZATION.out.versions
}
