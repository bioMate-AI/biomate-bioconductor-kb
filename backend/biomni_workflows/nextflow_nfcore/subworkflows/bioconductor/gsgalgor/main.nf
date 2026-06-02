#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSgalgoR
// A multi-objective optimization algorithm for disease sub-type discovery based on a non-dominated sor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSgalgoR/inst/doc/GSgalgoR.R
// Upstream  : Biobase, breastCancerTRANSBIG, breastCancerUPP, genefu, ggplot2
// Downstream: none
//
// Install: BiocManager::install("GSgalgoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSGALGOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsgalgor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsgalgor:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsgalgor:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_gsgalgor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsgalgor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsgalgor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSgalgoR)
    library(jsonlite)


    # --- Libraries [] ---
    # Key functions: exprs, fData, pData, genes, function, for, which.max, featureNames
    library(GSgalgoR)
    library(Biobase)
    library(genefu)
    library(survival)
    library(survminer)
    library(ggplot2)
    data(pam50)
    data(upp)
    Train<- upp
    rm(upp)

    data(transbig)
    Test<- transbig
    rm(transbig)

    #To access gene expression data
    train_expr<- exprs(Train)
    #Custom function to drop duplicated genes (keep genes with highest variance)

    # --- Adapted Expression [] ---
    # Key functions: DropDuplicates, expandProbesets, Surv, pData, probes, identical, featureNames, sample
    Train=DropDuplicates(Train)
    Train=expandProbesets(Train)
    #Drop NAs in survival
    Train <- Train[,!is.na(
        survival::Surv(time=pData(Train)$t.rfs,event=pData(Train)$e.rfs))] 

    Test=DropDuplicates(Test)
    Test=expandProbesets(Test)
    #Drop NAs in survival
    Test <- 
    #First we will get PAM50 centroids from genefu package

    PAM50Centroids <- pam50$centroids
    PAM50Genes <- pam50$centroids.map$probe
    PAM50Genes<- featureNames(Train)[ featureNames(Train) %in% PAM50Genes]

    #Now we sample 200 random genes from expression matrix

    Non_PAM50Genes<- featureNames(Train)[ !featureNames(Train) %in% PAM50Genes]
    Non_PAM50Genes <- sample(Non_PAM50Genes,200, replace=FALSE)

    # --- Parameters [] ---
    # Key functions: pearson, galgo, class, to_list
    # For testing reasons it is set to a low number but ideally should be above 100
    population <- 30 
    # For testing reasons it is set to a low number but ideally should be above 150
    generations <-15
    nCV <- 5                      
    distancetype <- "pearson"     
    TournamentSize <- 2
    period <- 3650
    set.seed(264)
    output <- GSgalgoR::galgo(generations = generations, 
                            population = population, 
                            prob_matrix = train_expr, 
                            OS = train_surv,
                            nCV = nCV, 
                            distancetype = distancetype,
                            TournamentSize = TournamentSize, 
                            period = period)

    outputList <- to_list(output)
    head(names(outputList))

    # --- To Dataframe [] ---
    # Key functions: to_dataframe, plot_pareto, exprs, pData, fData, Surv, Reduce, cluster_classify
    outputDF <- to_dataframe(output)
    head(outputDF)
    plot_pareto(output)
    #The reduced UPP dataset will be used as training set 
    train_expression <- exprs(Train) 
    train_clinic<- pData(Train)
    train_features<- fData(Train)
    train_surv<- survival::Surv(time=train_clinic$t.rfs,event=train_clinic$e.rfs)

    #The reduced TRANSBIG dataset will be used as test set 

    test_expression <- exprs(Test) 
    test_clinic<- pData(Test)
    surv_formula <- 
        as.formula("Surv(train_clinic$t.rfs,train_clinic$e.rfs)~ PAM50_train")
    tumortotal1 <- surv_fit(surv_formula,data=train_clinic)
    tumortotal1diff <- survdiff(surv_formula)
    tumortotal1pval<- pchisq(tumortotal1diff$chisq, length(tumortotal1diff$n) - 1,
                             lower.tail = FALSE) 


    # --- Pam50 Surv Transbig [] ---
    # Key functions: as.formula, Surv, surv_fit, survdiff, pchisq, ggsurvplot, time, survival
    surv_formula <- 
        as.formula("Surv(test_clinic$t.rfs,test_clinic$e.rfs)~ PAM50_test")
    tumortotal2 <- surv_fit(surv_formula,data=test_clinic)
    tumortotal2diff <- survdiff(surv_formula)
    tumortotal2pval<- pchisq(tumortotal2diff$chisq, length(tumortotal2diff$n) - 1,
                            lower.tail = FALSE) 

    # --- Summary Results [] ---
    # Key functions: to_dataframe, unlist, non_dominated_summary, for, which.max, solution, create_centroids, classify_multiple
    output_df<- to_dataframe(output)
    NonDom_solutions<- output_df[output_df$Rank==1,]

    # N of non-dominated solutions 
    nrow(NonDom_solutions)

    # N of partitions found
    table(NonDom_solutions$k)

    #Average N of genes per signature
    RESULT<- non_dominated_summary(output=output,
                                OS=train_surv, 
                                prob_matrix= train_expression,
                                distancetype =distancetype 
                                )

    best_sol=NULL

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsgalgor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsgalgor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsgalgor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSGALGOR:", paste0("    gsgalgor: ", packageVersion("GSgalgoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsgalgor_results.csv
    touch ${prefix}_gsgalgor_output.rds
    echo "BIOC_GSGALGOR:" > versions.yml
    echo "    gsgalgor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSGALGOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_GSGALGOR(ch_input)

    emit:
    results  = BIOC_GSGALGOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSGALGOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSGALGOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSGALGOR.out.versions  // channel: path(versions.yml)
}
