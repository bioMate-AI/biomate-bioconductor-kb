#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSgalgoR — disease_subtype_discovery
// Identify Pareto-optimal gene signatures, generate prototypic centroids, and classify samples into disease subtypes.
// Input: expression_matrix.csv, survival_data.csv
// Container: quay.io/biocontainers/bioconductor-gsgalgor:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSgalgoR, genefu, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Scale the expression matrix using robust linear scaling. 2. Prepare the survival object using the survival package. 3. Run the Gal

nextflow.enable.dsl = 2

process BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GSgalgoR)
    library(Biobase)
    library(genefu)
    library(survival)
    
    # ==========================================
    # 1. Read User Input Files and Prepare Data
    # ==========================================
    
    # Read expression matrix (genes as rows, samples as columns)
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Read survival data
    surv_df <- read.csv("survival_data.csv", row.names = 1, check.names = FALSE)
    
    # Standardize survival column names to match documented code expectations (t.rfs and e.rfs)
    col_names <- colnames(surv_df)
    time_col <- grep("time|t.rfs|OS.time|survival", col_names, ignore.case = TRUE, value = TRUE)[1]
    event_col <- grep("event|e.rfs|OS|status", col_names, ignore.case = TRUE, value = TRUE)[1]
    
    if (!is.na(time_col)) {
      colnames(surv_df)[colnames(surv_df) == time_col] <- "t.rfs"
    } else {
      stop("Could not find survival time column in survival_data.csv")
    }
    
    if (!is.na(event_col)) {
      colnames(surv_df)[colnames(surv_df) == event_col] <- "e.rfs"
    } else {
      stop("Could not find survival event column in survival_data.csv")
    }
    
    # Align samples between expression matrix and survival data
    common_samples <- intersect(colnames(expr_df), rownames(surv_df))
    if (length(common_samples) == 0) {
      stop("No matching sample IDs found between expression_matrix.csv and survival_data.csv")
    }
    
    expr_df <- expr_df[, common_samples, drop = FALSE]
    surv_df <- surv_df[common_samples, , drop = FALSE]
    
    # Drop NAs in survival data
    valid_surv <- !is.na(surv_df\$t.rfs) & !is.na(surv_df\$e.rfs)
    expr_df <- expr_df[, valid_surv, drop = FALSE]
    surv_df <- surv_df[valid_surv, , drop = FALSE]
    
    # Split samples into Train and Test sets (60% Train, 40% Test)
    set.seed(123)
    n_samples <- ncol(expr_df)
    train_size <- ceiling(n_samples * 0.6)
    train_idx <- sample(seq_len(n_samples), size = train_size)
    test_idx <- setdiff(seq_len(n_samples), train_idx)
    
    train_expr_raw <- as.matrix(expr_df[, train_idx, drop = FALSE])
    test_expr_raw <- as.matrix(expr_df[, test_idx, drop = FALSE])
    
    train_clinic <- surv_df[train_idx, , drop = FALSE]
    test_clinic <- surv_df[test_idx, , drop = FALSE]
    
    # Construct ExpressionSet objects
    Train <- Biobase::ExpressionSet(assayData = train_expr_raw, phenoData = Biobase::AnnotatedDataFrame(train_clinic))
    Test <- Biobase::ExpressionSet(assayData = test_expr_raw, phenoData = Biobase::AnnotatedDataFrame(test_clinic))
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    # Robust linear scaling of expression matrix
    exprs(Train) <- t(apply(exprs(Train),1,genefu::rescale,na.rm=TRUE,q=0.05))
    exprs(Test) <- t(apply(exprs(Test),1,genefu::rescale,na.rm=TRUE,q=0.05))
    train_expr <- exprs(Train)
    test_expr <- exprs(Test)
    
    # Assign duplicate variables to match different naming conventions in documented code
    train_expression <- train_expr
    test_expression <- test_expr
    
    # Prepare survival object
    train_surv <- survival::Surv(time=train_clinic\$t.rfs,event=train_clinic\$e.rfs)
    
    # Define Galgo parameters
    generations <- 5
    population <- 15
    nCV <- 3
    distancetype <- "pearson"
    TournamentSize <- 2
    period <- min(3650, max(train_clinic\$t.rfs, na.rm = TRUE))
    
    # Run Galgo algorithm
    set.seed(264)
    output <- GSgalgoR::galgo(generations = generations, 
                            population = population, 
                            prob_matrix = train_expr, 
                            OS = train_surv,
                            nCV = nCV, 
                            distancetype = distancetype,
                            TournamentSize = TournamentSize, 
                            period = period)
    
    # Convert output to list or data frame
    outputList <- to_list(output)
    outputList[["Solution.1"]]
    outputDF <- to_dataframe(output)
    
    # Plot Pareto front
    pdf("pareto_front.pdf")
    plot_pareto(output)
    dev.off()
    
    # Summarize non-dominated solutions
    RESULT<- non_dominated_summary(output=output,
                                OS=train_surv, 
                                prob_matrix= train_expression,
                                distancetype =distancetype 
                                )
    
    # Select best performing solutions
    best_sol=NULL
    for(i in unique(RESULT\$k)){
        best_sol=c(
        best_sol,
        RESULT[RESULT\$k==i,"solution"][which.max(RESULT[RESULT\$k==i,"C.Index"])])
    }
    
    # Create prototypic centroids
    CentroidsList <- create_centroids(output, 
                                    solution_names = best_sol,
                                    trainset = train_expression)
    
    # Classify samples into subtypes
    train_classes<- classify_multiple(prob_matrix=train_expression,
                                    centroid_list= CentroidsList, 
                                    distancetype = distancetype)
    
    test_classes<- classify_multiple(prob_matrix=test_expression,
                                    centroid_list= CentroidsList, 
                                    distancetype = distancetype)
    
    # ==========================================
    # 3. Save Outputs to Working Directory
    # ==========================================
    
    write.csv(outputDF, "galgo_solutions.csv", row.names = TRUE)
    write.csv(RESULT, "non_dominated_summary.csv", row.names = FALSE)
    saveRDS(CentroidsList, "centroids.rds")
    write.csv(train_classes, "train_subtypes.csv", row.names = TRUE)
    write.csv(test_classes, "test_subtypes.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY":',
        paste0('    GSgalgoR: ', as.character(packageVersion('GSgalgoR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_disease_subtype_discovery.csv versions.yml
    """
}

workflow BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, survival_data.csv ] ]

    main:
    BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY.out.tables
    plots    = BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY.out.plots
    objects  = BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY.out.objects
    versions = BIOC_GSGALGOR_DISEASE_SUBTYPE_DISCOVERY.out.versions
}
