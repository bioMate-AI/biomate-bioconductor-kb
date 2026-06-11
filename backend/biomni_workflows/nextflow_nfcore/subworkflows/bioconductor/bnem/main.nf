#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bnem — pathway_logic_inference
// Infer Boolean logic gates of a signaling pathway from fold-change data and a prior knowledge network.
// Input: sifMatrix, fc
// Container: quay.io/biocontainers/bioconductor-bnem:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CellNOptR, bnem, mnem
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create and read the Prior Knowledge Network (PKN) from a
//  * 2. [Visualization & Output] Define the experimental design using dummyCNOlist
//  * 3. [Visualization & Output] Preprocess the PKN and CNOlist to build the Boolean
//  * 4. [Visualization & Output] Initialize the network state (binary string)
//  * 5. [Visualization & Output] Run the B-NEM optimization using greedy, genetic, or
//  * 6. [Visualization & Output] Visualize the optimized network and save to PDF

nextflow.enable.dsl = 2

process BIOC_BNEM_PATHWAY_LOGIC_INFERENCE {
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
    .bm_deps <- c("bnem", "CellNOptR", "mnem")
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
        library(bnem)
        library(CellNOptR)
        library(mnem)
        
        # Helper function to find and read sifMatrix from the working directory
        find_and_read_sif <- function() {
          candidates <- c("sifMatrix", "sifMatrix.tsv", "sifMatrix.csv", "sifMatrix.txt", "sifMatrix.sif")
          for (f in candidates) {
            if (file.exists(f)) {
              try({
                df <- read.table(f, header = FALSE, sep = "\t", stringsAsFactors = FALSE)
                if (ncol(df) >= 3) return(df)
              }, silent = TRUE)
              try({
                df <- read.csv(f, header = FALSE, stringsAsFactors = FALSE)
                if (ncol(df) >= 3) return(df)
              }, silent = TRUE)
            }
          }
          stop("Could not find or read 'sifMatrix' in the working directory.")
        }
        
        # Helper function to find and read fc from the working directory
        find_and_read_fc <- function() {
          candidates <- c("fc", "fc.tsv", "fc.csv", "fc.txt")
          for (f in candidates) {
            if (file.exists(f)) {
              try({
                mat <- as.matrix(read.table(f, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
                return(mat)
              }, silent = TRUE)
              try({
                mat <- as.matrix(read.csv(f, header = TRUE, row.names = 1, check.names = FALSE))
                return(mat)
              }, silent = TRUE)
            }
          }
          stop("Could not find or read 'fc' in the working directory.")
        }
        
        # Read user inputs
        sifMatrix <- find_and_read_sif()
        fc <- find_and_read_fc()
        
        # Define parallel and expression variables
        parallel <- NULL
        expression <- NULL
        
        # --- Create and read the Prior Knowledge Network (PKN) from a ---
        file <- tempfile(pattern="interaction",fileext=".sif")
        write.table(sifMatrix, file = file, sep = "\t",
                    row.names = FALSE, col.names = FALSE, quote = FALSE)
        PKN <- readSIF(file)
        
        # Dynamically determine stimuli and inhibitors from the PKN
        children <- unique(gsub(".*=|!", "", PKN\$reacID))
        stimuli <- unique(gsub("=.*|!", "", PKN\$reacID))
        stimuli <- stimuli[which(!(stimuli %in% children))]
        inhibitors <- PKN\$namesSpecies[!(PKN\$namesSpecies %in% stimuli)]
        
        # --- Define the experimental design using dummyCNOlist ---
        CNOlist <- dummyCNOlist(stimuli = stimuli,
                                inhibitors = inhibitors,
                                maxStim = 1, maxInhibit = 3)
        
        # --- Preprocess the PKN and CNOlist to build the Boolean ---
        model <- preprocessing(CNOlist, PKN)
        
        # --- Initialize the network state (binary string) ---
        initBstring <- rep(0, length(model\$reacID))
        
        # --- Run the B-NEM optimization using greedy, genetic, or ---
        bcrRes <- bnem(search = "greedy",
                           fc=fc,
                           CNOlist=CNOlist,
                           model=model,
                           parallel=parallel,
                           initBstring=initBstring,
                           draw = FALSE,
                           verbose = FALSE,
                           method = "cosine"
                           )
        
        # Save greedy results
        saveRDS(bcrRes, "bcrRes_greedy.rds")
        
        # Run genetic search
        genetic <- bnem(search = "genetic",
                   fc=fc,
                   expression=expression,
                   parallel = parallel,
                   CNOlist=CNOlist,
                   model=model,
                   initBstring=initBstring,
                   popSize = 10,
                   stallGenMax = 10,
                   draw = FALSE,
                   verbose = FALSE
                   )
        
        # Save genetic results
        saveRDS(genetic, "bcrRes_genetic.rds")
        
        # Run exhaustive search conditionally (only if search space <= 20 hyper-edges)
        if (length(model\$reacID) <= 20) {
          exhaustive <- bnem(search = "exhaustive",
                             parallel = parallel,
                             CNOlist=CNOlist,
                             fc=fc,
                             expression=expression,
                             model=model
                             )
          
          # Save exhaustive results
          saveRDS(exhaustive, "bcrRes_exhaustive.rds")
        } else {
          message("Skipping exhaustive search because the network has more than 20 hyper-edges.")
        }
        
        # --- Visualize the optimized network and save to PDF ---
        pdf("network_plots.pdf", width = 12, height = 6)
        par(mfrow=c(1,3))
        plotDnf(PKN\$reacID, main = "PKN", stimuli = stimuli)
        plotDnf(bcrRes\$graph, main = "greedy optimum (empty start)",
                stimuli = stimuli)
        dev.off()
        
        # Write out greedy optimum graph edges to a text file
        if (!is.null(bcrRes\$graph)) {
          writeLines(bcrRes\$graph, "greedy_optimum_edges.txt")
        }

    writeLines(c(
        '"BIOC_BNEM_PATHWAY_LOGIC_INFERENCE":',
        paste0('    bnem: ', as.character(packageVersion('bnem')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_logic_inference.csv versions.yml
    """
}

workflow BIOC_BNEM_PATHWAY_LOGIC_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sifMatrix, fc ] ]

    main:
    BIOC_BNEM_PATHWAY_LOGIC_INFERENCE(ch_input)

    emit:
    tables   = BIOC_BNEM_PATHWAY_LOGIC_INFERENCE.out.tables
    plots    = BIOC_BNEM_PATHWAY_LOGIC_INFERENCE.out.plots
    objects  = BIOC_BNEM_PATHWAY_LOGIC_INFERENCE.out.objects
    versions = BIOC_BNEM_PATHWAY_LOGIC_INFERENCE.out.versions
}
