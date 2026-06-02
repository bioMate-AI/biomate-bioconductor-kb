#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: COSNet
// Package that implements the COSNet classification algorithm. The algorithm predicts node labels in p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/COSNet/inst/doc/COSNet_v.R
// Upstream  : PerfMeas, bionetdata
// Downstream: none
//
// Install: BiocManager::install("COSNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COSNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cosnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cosnet:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cosnet:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_cosnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cosnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cosnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(COSNet)
    library(jsonlite)


    # --- A1 [] ---
    # Key functions: cosnet
    library(COSNet);
    library(bionetdata)
    data(Yeast.STRING.data)
    dim(Yeast.STRING.data)
    rownames(Yeast.STRING.data)[1:10]
    data(Yeast.STRING.FunCat)
    dim(Yeast.STRING.FunCat)
    rownames(Yeast.STRING.FunCat)[1:10]
    colnames(Yeast.STRING.FunCat)[1:10]

    # --- A3 [] ---
    # Key functions: colSums, cosnet.cross.validation
    ## excluding the dummy "00" root
    to.be.excl <- which(colnames(Yeast.STRING.FunCat) == "00")
    Yeast.STRING.FunCat <- Yeast.STRING.FunCat[, -to.be.excl]
    ## choosing the first 35 classes
    labeling <- Yeast.STRING.FunCat[, 1:35] 
    ## number of positive labels
    colSums(labeling)       
    Yeast.STRING.FunCat[Yeast.STRING.FunCat == 0] <- -1
    out <- cosnet.cross.validation(labeling, Yeast.STRING.data, 5, cost=0)

    # --- A5 [] ---
    # Key functions: cosnet.cross.validation
    out.r <- cosnet.cross.validation(labeling, Yeast.STRING.data, 5, cost=0.0001)
    predictions <- out$predictions
    scores <- out$scores;
    labels <- out$labels;
    predictions.r <- out.r$predictions
    scores.r <- out.r$scores;
    labels.r <- out.r$labels;

    # --- A7 [] ---
    # Key functions: F.measure.single.over.classes, AUC.single.over.classes, precision.at.multiple.recall.level.over.classes, read.table, unlist, function, substr
    library(PerfMeas);
    ## computing F-score 
    Fs <- F.measure.single.over.classes(labels, predictions);
    ## Average F-score 
    Fs$average[4]
    Fs.r <- F.measure.single.over.classes(labels.r, predictions.r);
    # Average F-score for the regularized version of COSNet
    Fs.r$average[4]
    ## Computing AUC
    labels[labels <= 0] <- 0;
    ## reading similarity network W
    W <- 
    as.matrix(read.table(file=paste(sep="", "http://frasca.di.unimi.it/",
     "cosnetdata/u.sum.fly.txt"), sep=" "))
    ## reading GO annotations
    GO.ann.sel <- 
    as.matrix(read.table(file=paste(sep="", "http://frasca.di.unimi.it/",
    "cosnetdata/GO.ann.fly.15.5.13.3_300.txt"), sep = " ",))
    GO.classes <- colnames(GO.ann.sel)
    ## changing "." to ":"

    # --- A9 [] ---
    # Key functions: find.division.strat, set, function, COSNet, as.vector, AUC.single, precision.at.recall.level
    n<-nrow(W);
    ## selecting some classes to be predicted
    classes <- c("GO:0009605", "GO:0022414", "GO:0032504",
                "GO:0002376", "GO:0009888", "GO:0065003");
    labels <- GO.ann.sel[, classes]
    ## for COSNet negative labels must be -1
    labels[labels <= 0] <- -1;
    ## Determining a random partition for the class GO:0009605 in 3 folds
    ##    ensuring that each fold has a similar proportion of positives 
    folds <- find.division.strat(labels[, 1], 1:n, 3)
    library(PerfMeas);
    ## last predicted term
    term.ind <- 6;
    scores <- res[[term.ind]]$scores;
    test.genes <- names(scores);
    test.labels <- as.vector(GO.ann.sel[test.genes, term.ind]);
    pos.labels <- sum(test.labels > 0)
    pos.labels
    alpha <- res[[term.ind]]$alpha
    gamma <- res[[term.ind]]$c

    # --- A11 [] ---
    # Key functions: as.vector, find.division.strat, labels
    library(bionetdata);
    ## similarity matrix DD.chem.data
    data(DD.chem.data); 
    ## label matrix DrugBank.Cat
    data(DrugBank.Cat);
    n <- nrow(DD.chem.data);
    drugs <- rownames(DD.chem.data);
    drug.category <- c("Cephalosporins");
    labels <- as.vector(DrugBank.Cat[, drug.category]);
    names(labels) <- rownames(DrugBank.Cat);
    ## Determining a random partition in 5 folds ensuring that each 
    ##    fold has a similar proportion of positives
    folds <- find.division.strat(labels, 1:n, 5)
    labels[labels <= 0] <- -1;
    ## hiding the test labels (the fold of index 1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cosnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cosnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cosnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COSNET:", paste0("    cosnet: ", packageVersion("COSNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosnet_results.csv
    touch ${prefix}_cosnet_output.rds
    echo "BIOC_COSNET:" > versions.yml
    echo "    cosnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COSNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_COSNET(ch_input)

    emit:
    results  = BIOC_COSNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COSNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COSNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COSNET.out.versions  // channel: path(versions.yml)
}
