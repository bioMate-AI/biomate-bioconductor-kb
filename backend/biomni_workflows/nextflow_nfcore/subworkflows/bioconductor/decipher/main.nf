#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decipher — taxonomic_classification
// Train a taxonomic classifier on reference sequences and classify query sequences (DNA or Amino Acids).
// Input: seqs_path, rank_path, fas
// Container: quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0
// R packages: DECIPHER
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION {
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
    .bm_deps <- c("DECIPHER")
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
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Define input file paths from command line arguments or default working directory files
    args <- commandArgs(trailingOnly = TRUE)
    seqs_path <- if (length(args) >= 1) args[1] else "training_seqs.fasta"
    rank_path <- if (length(args) >= 2) args[2] else "taxid.txt"
    fas       <- if (length(args) >= 3) args[3] else "query_seqs.fasta"
    
    # Validate mandatory inputs
    if (!file.exists(seqs_path)) {
      stop(paste("Error: Training sequences file not found at:", seqs_path))
    }
    if (!file.exists(fas)) {
      stop(paste("Error: Query sequences file not found at:", fas))
    }
    
    # ==========================================
    # Stage 1: Read training sequences and optional taxid file
    # ==========================================
    cat("Reading training sequences...\n")
    seqs <- readDNAStringSet(seqs_path)
    
    # Read optional taxid file if it exists
    if (file.exists(rank_path) && rank_path != "") {
      cat("Reading taxonomic rank file...\n")
      taxid <- read.table(rank_path,
                          header=FALSE,
                          col.names=c('Index', 'Name', 'Parent', 'Level', 'Rank'),
                          sep="*", # asterisks delimited
                          quote="", # preserve quotes
                          stringsAsFactors=FALSE)
    } else {
      cat("No taxonomic rank file provided or found. Proceeding with taxid = NULL.\n")
      taxid <- NULL
    }
    
    # ==========================================
    # Stage 2: Remove gaps and orient nucleotides
    # ==========================================
    cat("Cleaning and orienting training sequences...\n")
    seqs <- RemoveGaps(seqs)
    seqs <- OrientNucleotides(seqs)
    
    # ==========================================
    # Stage 3: Extract taxonomic group labels and subsample
    # ==========================================
    cat("Extracting taxonomic group labels...\n")
    groups <- names(seqs) # sequence names
    # Assume the taxonomy begins with 'Root;'
    groups <- gsub("(.*)(Root;)", "\\2", groups) # extract the group label
    groupCounts <- table(groups)
    u_groups <- names(groupCounts) # unique groups
    
    # Subsample groups to prevent bias (max 10 sequences per label)
    maxGroupSize <- 10 # max sequences per label (>= 1)
    remove <- logical(length(seqs))
    for (i in which(groupCounts > maxGroupSize)) {
      index <- which(groups==u_groups[i])
      keep <- sample(length(index), maxGroupSize)
      remove[index[-keep]] <- TRUE
    }
    cat("Eliminated", sum(remove), "sequences during initial group size normalization.\n")
    
    # ==========================================
    # Stage 4: Iteratively train the classifier and remove problem sequences
    # ==========================================
    maxIterations <- 3 # must be >= 1
    allowGroupRemoval <- FALSE
    
    probSeqsPrev <- integer() # suspected problem sequences from prior iteration
    for (i in seq_len(maxIterations)) {
      cat("Training iteration: ", i, "\n", sep="")
      
      # Train the classifier
      trainingSet <- LearnTaxa(seqs[!remove],
                               names(seqs)[!remove],
                               taxid)
      
      # Look for problem sequences
      probSeqs <- trainingSet\$problemSequences\$Index
      if (length(probSeqs)==0) {
        cat("No problem sequences remaining.\n")
        break
      } else if (length(probSeqs)==length(probSeqsPrev) && all(probSeqsPrev==probSeqs)) {
        cat("Iterations converged.\n")
        break
      }
      if (i==maxIterations) {
        break
      }
      probSeqsPrev <- probSeqs
      
      # Remove any problem sequences
      index <- which(!remove)[probSeqs]
      remove[index] <- TRUE # remove all problem sequences
      if (!allowGroupRemoval) {
        # Replace any removed groups
        missing <- !(u_groups %in% groups[!remove])
        missing <- u_groups[missing]
        if (length(missing) > 0) {
          index <- index[groups[index] %in% missing]
          remove[index] <- FALSE # don't remove
        }
      }
    }
    
    cat("Total sequences eliminated during training:", sum(remove), "\n")
    cat("Number of remaining problem sequences:", length(probSeqs), "\n")
    
    # Save the trained classifier object
    saveRDS(trainingSet, file="trained_classifier.rds")
    cat("Trained classifier saved to 'trained_classifier.rds'.\n")
    
    # ==========================================
    # Stage 5: Read and clean query sequences
    # ==========================================
    cat("Reading and cleaning query sequences...\n")
    test <- readDNAStringSet(fas)
    test <- RemoveGaps(test)
    
    # ==========================================
    # Stage 6: Classify query sequences using IdTaxa
    # ==========================================
    cat("Classifying query sequences...\n")
    ids <- IdTaxa(test,
                  trainingSet,
                  type="extended",
                  strand="top",
                  threshold=60,
                  processors=1)
    
    # Save raw classification results
    saveRDS(ids, file="classification_results.rds")
    cat("Raw classification results saved to 'classification_results.rds'.\n")
    
    # ==========================================
    # Stage 7: Plot and analyze taxonomic assignments
    # ==========================================
    cat("Generating taxonomic assignment plots and reports...\n")
    
    # Save plot to PDF
    pdf("taxonomic_classification_plots.pdf", width=10, height=8)
    plot(ids, trainingSet)
    dev.off()
    cat("Taxonomic classification plot saved to 'taxonomic_classification_plots.pdf'.\n")
    
    # Format and write output text file
    output <- sapply(ids, function (id) {
      paste(id\$taxon,
            " (",
            round(id\$confidence, digits=1),
            "%)",
            sep="",
            collapse="; ")
    })
    writeLines(output, "classification_assignments.txt")
    cat("Formatted assignments saved to 'classification_assignments.txt'.\n")
    
    # Create a structured CSV summary
    assignment <- sapply(ids, function(x) paste(x\$taxon, collapse=";"))
    results_df <- data.frame(
      Sequence_ID = names(test),
      Assignment = assignment,
      Detailed_Assignment = output,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "classification_results.csv", row.names=FALSE)
    cat("Structured classification table saved to 'classification_results.csv'.\n")
    
    cat("Pipeline completed successfully.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION":
        decipher: \$(Rscript -e 'cat(as.character(packageVersion("decipher")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomic_classification.csv versions.yml
    """
}

workflow BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seqs_path, rank_path, fas ] ]

    main:
    BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION.out.tables
    plots    = BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION.out.plots
    objects  = BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION.out.objects
    versions = BIOC_DECIPHER_TAXONOMIC_CLASSIFICATION.out.versions
}
