#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: preciseTAD — model_training_and_prediction
// Build a random forest model from ground-truth TAD boundaries and genomic annotations, and use it to predict base-level boundary regions and points.
// Input: arrowhead_gm12878_5kb, tfbsList
// Container: quay.io/biocontainers/bioconductor-precisetad:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, e1071, preciseTAD
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract unique boundaries using extractBoundaries()
//  * 2. [Core Analysis] Convert BED files to GRangesList using bedToGRangesList()
//  * 3. [Input & Preparation] Create training and testing data using createTADdata()
//  * 4. [Core Analysis] Perform recursive feature elimination using TADrfe()
//  * 5. [Core Analysis] Train a random forest model using TADrandomForest()
//  * 6. [Core Analysis] Predict precise boundaries at base-level resolution using preciseTAD()
//  * 7. [Core Analysis] Format predicted boundaries for Juicebox using juicer_func()

nextflow.enable.dsl = 2

process BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("preciseTAD", "e1071", "GenomicRanges")
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
        library(preciseTAD)
        library(e1071)
        library(GenomicRanges)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Load arrowhead_gm12878_5kb (BED-like data frame of TAD coordinates)
        if (file.exists("arrowhead_gm12878_5kb.rds")) {
          arrowhead_gm12878_5kb <- readRDS("arrowhead_gm12878_5kb.rds")
        } else if (file.exists("arrowhead_gm12878_5kb")) {
          arrowhead_gm12878_5kb <- read.table("arrowhead_gm12878_5kb", header = FALSE, stringsAsFactors = FALSE)
        } else if (file.exists("arrowhead_gm12878_5kb.txt")) {
          arrowhead_gm12878_5kb <- read.table("arrowhead_gm12878_5kb.txt", header = FALSE, stringsAsFactors = FALSE)
        } else if (file.exists("arrowhead_gm12878_5kb.csv")) {
          arrowhead_gm12878_5kb <- read.csv("arrowhead_gm12878_5kb.csv", header = FALSE, stringsAsFactors = FALSE)
        } else {
          stop("Required input file 'arrowhead_gm12878_5kb' not found in the working directory.")
        }
        
        arrowhead_gm12878_5kb <- as.data.frame(arrowhead_gm12878_5kb)
        
        # Load tfbsList (GRangesList of transcription factor binding sites or path to BED files)
        if (dir.exists("tfbsList")) {
          # Convert BED files to GRangesList using bedToGRangesList()
          tfbsList <- bedToGRangesList(filepath = "tfbsList", pattern = "*.bed", signal = 4)
        } else if (file.exists("tfbsList.rds")) {
          tfbsList <- readRDS("tfbsList.rds")
        } else if (file.exists("tfbsList")) {
          tfbsList <- readRDS("tfbsList")
        } else {
          stop("Required input 'tfbsList' (directory of BED files or RDS file) not found in the working directory.")
        }
        
        # ==========================================
        # 2. Extract Unique Boundaries
        # ==========================================
        # Dynamically determine chromosomes from the user data
        raw_chroms <- unique(arrowhead_gm12878_5kb[, 1])
        formatted_chroms <- paste0("CHR", toupper(sub("^chr", "", raw_chroms, ignore.case = TRUE)))
        
        train_chr <- formatted_chroms[1]
        predict_chr <- if (length(formatted_chroms) > 1) formatted_chroms[2] else formatted_chroms[1]
        
        bounds <- extractBoundaries(domains.mat = arrowhead_gm12878_5kb, filter = FALSE, CHR = unique(c(train_chr, predict_chr)), resolution = 5000)
        
        # Save extracted boundaries
        write.table(as.data.frame(bounds), "extracted_boundaries.txt", sep = "\t", quote = FALSE, row.names = FALSE)
        
        # ==========================================
        # 3. Create Training and Testing Data
        # ==========================================
        set.seed(123)
        tadData <- createTADdata(bounds.GR = bounds, resolution = 5000, genomicElements.GR = tfbsList, featureType = "distance", resampling = "rus", trainCHR = train_chr, predictCHR = predict_chr)
        
        # ==========================================
        # 4. Recursive Feature Elimination (RFE)
        # ==========================================
        set.seed(123)
        rfe_res <- TADrfe(trainData = tadData[[1]], tuneParams = list(ntree = 500, nodesize = 1), cvFolds = 5, cvMetric = "Accuracy", verbose = TRUE)
        
        # Save RFE results
        saveRDS(rfe_res, "rfe_results.rds")
        write.csv(rfe_res[[1]], "rfe_performances.csv", row.names = FALSE)
        
        # ==========================================
        # 5. Train Random Forest Model
        # ==========================================
        # Filter tfbsList to the top 4 transcription factors
        tfbsList_filt <- tfbsList[names(tfbsList) %in% c("Gm12878-Ctcf-Broad", "Gm12878-Rad21-Haib", "Gm12878-Smc3-Sydh", "Gm12878-Znf143-Sydh")]
        
        # Fallback to ensure tfbsList_filt is not empty if custom names are used
        if (length(tfbsList_filt) == 0) {
          matches <- grep("ctcf|rad21|smc3|znf143", names(tfbsList), ignore.case = TRUE, value = TRUE)
          if (length(matches) > 0) {
            tfbsList_filt <- tfbsList[matches]
          } else {
            tfbsList_filt <- tfbsList[seq_len(min(4, length(tfbsList)))]
          }
        }
        
        set.seed(123)
        tadData <- createTADdata(bounds.GR = bounds, resolution = 5000, genomicElements.GR = tfbsList_filt, featureType = "distance", resampling = "rus", trainCHR = train_chr, predictCHR = predict_chr)
        
        set.seed(123)
        tadModel <- TADrandomForest(trainData = tadData[[1]], testData = tadData[[2]], tuneParams = list(mtry = 2, ntree = 500, nodesize = 1), cvFolds = 3, cvMetric = "Accuracy", verbose = FALSE, model = TRUE, importances = TRUE, impMeasure = "MDA", performances = TRUE)
        
        # Save trained model and performances
        saveRDS(tadModel, "tad_model.rds")
        write.csv(tadModel[[2]], "variable_importances.csv", row.names = TRUE)
        write.csv(tadModel[[3]], "model_performances.csv", row.names = FALSE)
        
        # ==========================================
        # 6. Predict Precise Boundaries
        # ==========================================
        # Dynamically determine a valid coordinate range for the prediction chromosome
        predict_chr_raw <- raw_chroms[which(formatted_chroms == predict_chr)[1]]
        predict_data <- arrowhead_gm12878_5kb[arrowhead_gm12878_5kb[, 1] == predict_chr_raw, ]
        min_coord <- as.numeric(min(predict_data[, 2:3], na.rm = TRUE))
        max_coord <- as.numeric(max(predict_data[, 2:3], na.rm = TRUE))
        # Limit to a 2Mb region to avoid memory issues with BaseProbs = TRUE
        end_coord <- min(max_coord, min_coord + 2000000)
        
        set.seed(123)
        pt <- tryCatch({
          preciseTAD(genomicElements.GR = tfbsList_filt, featureType = "distance", CHR = predict_chr, chromCoords = list(min_coord, end_coord), tadModel = tadModel[[1]], threshold = 1, verbose = TRUE, parallel = NULL, DBSCAN_params = list(eps = c(30000), MinPts = c(100)), slope = 5000, genome = "hg19", BaseProbs = TRUE)
        }, error = function(e) {
          warning("preciseTAD prediction failed: ", e\$message)
          NULL
        })
        
        # Save preciseTAD predictions and plot base probabilities if successful
        if (!is.null(pt)) {
          saveRDS(pt, "preciseTAD_predictions.rds")
          
          # Plot base probabilities
          if (!is.null(pt\$Summaries\$BaseProbs)) {
            pdf("base_probabilities_plot.pdf")
            plot(pt\$Summaries\$BaseProbs[1:min(100000, length(pt\$Summaries\$BaseProbs))],
                 main = "Base-level Probabilities (First 100k bases)",
                 xlab = "Base Index", ylab = "Probability", col = "blue", type = "l")
            dev.off()
          }
          
          # ==========================================
          # 7. Format Predicted Boundaries for Juicebox
          # ==========================================
          if (!is.null(pt\$PTBP) && length(pt\$PTBP) > 0) {
            pt_juice <- juicer_func(pt\$PTBP)
            write.table(pt_juice, "pt_juice.bed", quote = FALSE, col.names = FALSE, row.names = FALSE, sep = "\t")
          } else {
            message("No preciseTAD boundary points (PTBP) predicted. Skipping juicer_func.")
          }
        } else {
          message("preciseTAD failed or returned NULL. Skipping downstream formatting.")
        }

    writeLines(c(
        '"BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION":',
        paste0('    preciseTAD: ', as.character(packageVersion('preciseTAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_model_training_and_prediction.csv versions.yml
    """
}

workflow BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arrowhead_gm12878_5kb, tfbsList ] ]

    main:
    BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION(ch_input)

    emit:
    tables   = BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION.out.tables
    plots    = BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION.out.plots
    objects  = BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION.out.objects
    versions = BIOC_PRECISETAD_MODEL_TRAINING_AND_PREDICTION.out.versions
}
