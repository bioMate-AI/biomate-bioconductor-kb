#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: procoil — coiled_coil_prediction
// Predict the oligomerization state (dimer vs. trimer) of a single coiled coil sequence and visualize its residue-level contribution profile.
// Input: sequence.fasta, register.txt
// Container: quay.io/biocontainers/bioconductor-procoil:2.38.0--r45hdfd78af_0
// R packages: Biostrings, procoil
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, procoil
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run prediction using predict() with the default model, sequence, and register
//  * 2. [Core Analysis] Display the prediction score and classification
//  * 3. [Visualization & Output] Plot the contribution profile using plot()

nextflow.enable.dsl = 2

process BIOC_PROCOIL_COILED_COIL_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "procoil")
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
        
        # Load required libraries
        library(procoil)
        library(Biostrings)
        
        # 1. Read the user input files from the working directory
        if (!file.exists("sequence.fasta")) {
          stop("Error: 'sequence.fasta' not found in the working directory.")
        }
        if (!file.exists("register.txt")) {
          stop("Error: 'register.txt' not found in the working directory.")
        }
        
        # Read sequence
        seq_set <- readAAStringSet("sequence.fasta")
        seq_char <- as.character(seq_set[[1]])
        
        # Read register and clean any whitespace/newlines
        reg_lines <- readLines("register.txt", warn = FALSE)
        reg_char <- gsub("[[:space:]]", "", paste(reg_lines, collapse = ""))
        
        # Validate equal lengths
        if (nchar(seq_char) != nchar(reg_char)) {
          stop(sprintf("Sequence length (%d) and register length (%d) must be exactly equal.",
                       nchar(seq_char), nchar(reg_char)))
        }
        
        # 2. Run prediction using predict() with the default model, sequence, and register
        # (Adapting the documented call: GCN4wt <- predict(PrOCoilModel, "seq", "reg"))
        GCN4wt <- predict(PrOCoilModel,
                          seq_char,
                          reg_char)
        
        # 3. Display the prediction score and classification
        show(GCN4wt)
        
        # 4. Plot the contribution profile using plot() and save to PDF
        pdf_width <- max(nchar(seq_char)) * 6 / 24
        pdf_width <- max(pdf_width, 6) # Ensure a reasonable minimum width
        pdf(file = "profile_plot.pdf", height = 6, width = pdf_width)
        plot(GCN4wt)
        dev.off()
        
        # 5. Write named output files for the meaningful results
        # Save the complete S4 object
        saveRDS(GCN4wt, "prediction_object.rds")
        
        # Extract and save prediction results
        pred_df <- tryCatch({
          predictions(GCN4wt)
        }, error = function(e) {
          if (.hasSlot(GCN4wt, "predictions")) {
            GCN4wt@predictions
          } else {
            data.frame(Score = GCN4wt@predictions\$Score, Class = GCN4wt@predictions\$Class)
          }
        })
        write.csv(pred_df, "prediction_report.csv", row.names = FALSE)
        
        # Extract and save residue-level contribution profile
        prof_val <- tryCatch({
          profile(GCN4wt)
        }, error = function(e) {
          if (.hasSlot(GCN4wt, "profile")) {
            GCN4wt@profile
          } else {
            NULL
          }
        })
        
        if (!is.null(prof_val)) {
          if (is.matrix(prof_val)) {
            contributions <- as.vector(prof_val[1, ])
          } else {
            contributions <- as.vector(prof_val)
          }
          
          profile_df <- data.frame(
            Position = 1:length(contributions),
            Residue = strsplit(seq_char, "")[[1]],
            Register = strsplit(reg_char, "")[[1]],
            Contribution = contributions
          )
          write.csv(profile_df, "profile_data.csv", row.names = FALSE)
        }

    writeLines(c(
        '"BIOC_PROCOIL_COILED_COIL_PREDICTION":',
        paste0('    procoil: ', as.character(packageVersion('procoil')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coiled_coil_prediction.csv versions.yml
    """
}

workflow BIOC_PROCOIL_COILED_COIL_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.fasta, register.txt ] ]

    main:
    BIOC_PROCOIL_COILED_COIL_PREDICTION(ch_input)

    emit:
    tables   = BIOC_PROCOIL_COILED_COIL_PREDICTION.out.tables
    plots    = BIOC_PROCOIL_COILED_COIL_PREDICTION.out.plots
    objects  = BIOC_PROCOIL_COILED_COIL_PREDICTION.out.objects
    versions = BIOC_PROCOIL_COILED_COIL_PREDICTION.out.versions
}
