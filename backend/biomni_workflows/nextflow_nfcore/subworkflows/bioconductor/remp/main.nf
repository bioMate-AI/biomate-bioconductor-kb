#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: REMP — repetitive_element_methylation_prediction
// Predict DNA methylation of locus-specific repetitive elements (RE) from user-provided DNA methylation data.
// Input: user_methylation_data.RData, user_seq_gr.RData
// Container: quay.io/biocontainers/bioconductor-remp:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, REMP, minfi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Groom and preprocess the methylation data using grooMethy
//  * 2. [Input & Preparation] Prepare and initialize the annotation data parcel using initREMP
//  * 3. [Visualization & Output] Save the generated annotation parcel to the working directory using saveParcel
//  * 4. [Core Analysis] Run the machine learning-based prediction using remp
//  * 5. [Core Analysis] Trim off less reliable predicted results using rempTrim
//  * 6. [Core Analysis] Aggregate predicted CpG methylation to RE-specific levels using rempAggregate
//  * 7. [Core Analysis] Add genomic region annotations to the predicted REs using decodeAnnot
//  * 8. [Visualization & Output] Plot the density of the predicted methylation values using remplot

nextflow.enable.dsl = 2

process BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("REMP", "GenomicRanges", "SummarizedExperiment")
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
        library(REMP)
        library(SummarizedExperiment)
        library(GenomicRanges)
        
        # Helper function to safely load RData files
        load_rdata <- function(file_path) {
          if (!file.exists(file_path)) {
            stop(paste("Required input file missing:", file_path))
          }
          env <- new.env()
          load(file_path, envir = env)
          vars <- ls(env)
          if (length(vars) == 0) {
            stop(paste("No objects found in", file_path))
          }
          # Return the first object loaded
          return(get(vars[1], envir = env))
        }
        
        # 1. Read User Input Files
        message("Loading user methylation data...")
        methy_data <- load_rdata("user_methylation_data.RData")
        
        seq_gr <- NULL
        if (file.exists("user_seq_gr.RData")) {
          message("Loading optional user sequence GRanges data...")
          seq_gr <- load_rdata("user_seq_gr.RData")
        }
        
        # Determine arrayType dynamically
        arrayType <- "450k"
        if (!is.null(seq_gr)) {
          arrayType <- "Sequencing"
        } else if (inherits(methy_data, "RatioSet") || inherits(methy_data, "GenomicRatioSet")) {
          # Attempt to extract platform from minfi object annotation
          ann <- minfi::annotation(methy_data)
          if (any(grepl("epic", ann, ignore.case = TRUE))) {
            arrayType <- "EPIC"
          } else if (any(grepl("450k", ann, ignore.case = TRUE))) {
            arrayType <- "450k"
          }
        } else {
          # Fallback heuristic for matrix/DataFrame based on row count
          rnames <- rownames(methy_data)
          if (!is.null(rnames)) {
            if (any(grepl("^cg", rnames))) {
              if (nrow(methy_data) > 500000) {
                arrayType <- "EPIC"
              } else {
                arrayType <- "450k"
              }
            }
          }
        }
        message(paste("Inferred arrayType:", arrayType))
        
        # 2. Groom and preprocess the methylation data
        message("Grooming methylation data...")
        if (!is.null(seq_gr)) {
          methy_data <- grooMethy(methy_data, Seq.GR = seq_gr)
        } else {
          methy_data <- grooMethy(methy_data)
        }
        print(methy_data)
        
        # 3. Prepare and initialize the annotation data parcel
        message("Initializing REMP parcel...")
        # We omit the 'RE' argument to let initREMP fetch the complete RE sequence dataset
        # from AnnotationHub (AH) automatically, as recommended for real user workflows.
        if (arrayType == "Sequencing") {
          remparcel <- initREMP(arrayType = arrayType,
                               REtype = "Alu",
                               annotation.source = "AH",
                               genome = "hg19",
                               Seq.GR = seq_gr,
                               ncore = 1,
                               work.dir = ".")
        } else {
          remparcel <- initREMP(arrayType = arrayType,
                               REtype = "Alu",
                               annotation.source = "AH",
                               genome = "hg19",
                               ncore = 1,
                               work.dir = ".")
        }
        print(remparcel)
        
        # 4. Save the generated annotation parcel to the working directory
        message("Saving REMP parcel...")
        saveParcel(remparcel)
        
        # 5. Run the machine learning-based prediction
        message("Running REMP prediction...")
        remp.res <- remp(methy_data, 
                         REtype = 'Alu', 
                         parcel = remparcel, 
                         ncore = 1, 
                         seed = 777)
        
        # Display details and accessors
        print(remp.res)
        details(remp.res)
        head(rempB(remp.res))
        head(rempM(remp.res))
        head(rowRanges(remp.res))
        head(rempImp(remp.res))
        message(paste("Seed used:", metadata(remp.res)\$Seed))
        
        # 6. Trim off less reliable predicted results
        message("Trimming predictions...")
        remp.res <- rempTrim(remp.res, threshold = 1.7, missingRate = 0.2)
        details(remp.res)
        
        # 7. Aggregate predicted CpG methylation to RE-specific levels
        message("Aggregating predictions...")
        remp.res <- rempAggregate(remp.res, NCpG = 2)
        details(remp.res)
        
        # 8. Add genomic region annotations to the predicted REs
        message("Decoding annotations...")
        remp.res <- decodeAnnot(remp.res)
        head(rempAnnot(remp.res))
        
        # 9. Plot the density of the predicted methylation values
        message("Generating plot...")
        pdf("remplot.pdf", width = 7, height = 7)
        remplot(remp.res, main = "Alu methylation", col = "blue")
        dev.off()
        
        # 10. Save meaningful outputs to the working directory
        message("Saving output files...")
        saveRDS(remp.res, file = "remp_results.rds")
        
        # Export predicted Beta and M values
        write.csv(as.data.frame(rempB(remp.res)), "predicted_beta.csv", row.names = TRUE)
        write.csv(as.data.frame(rempM(remp.res)), "predicted_m.csv", row.names = TRUE)
        
        # Export genomic annotations
        write.csv(as.data.frame(rempAnnot(remp.res)), "predicted_annotations.csv", row.names = TRUE)
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION":',
        paste0('    REMP: ', as.character(packageVersion('REMP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_repetitive_element_methylation_prediction.csv versions.yml
    """
}

workflow BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_methylation_data.RData, user_seq_gr.RData ] ]

    main:
    BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION.out.tables
    plots    = BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION.out.plots
    objects  = BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION.out.objects
    versions = BIOC_REMP_REPETITIVE_ELEMENT_METHYLATION_PREDICTION.out.versions
}
