#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowMerge — automated_gating_and_cluster_merging
// Perform automated gating of flow cytometry data by fitting mixture models, merging redundant components, and selecting the optimal population representation.
// Input: sample.fcs
// Container: quay.io/biocontainers/bioconductor-flowmerge:2.58.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Rgraphviz, flowCore, flowMerge
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and flow cytometry data
//  * 2. [Core Analysis] Run initial clustering across a range of cluster numbers (K) using flowClust
//  * 3. [Core Analysis] Extract the maximum BIC solution
//  * 4. [Input & Preparation] Create a flowObj and merge clusters using the entropy metric
//  * 5. [Core Analysis] Fit a piecewise linear regression to find the optimal number of merged clusters
//  * 6. [Visualization & Output] Extract and plot the optimal merged solution
//  * 7. [Core Analysis] Subset a specific cell population (e.g., lymphocytes) and perform a second round of clustering and merging
//  * 8. [Visualization & Output] Visualize the merging process as a tree using ptree

nextflow.enable.dsl = 2

process BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowCore", "flowMerge", "Rgraphviz")
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
        
        # 1. Load the packages and flow cytometry data
        library(flowCore)
        library(flowMerge)
        
        # Read the user-provided FCS file
        rituximab <- read.FCS("sample.fcs")
        summary(rituximab)
        
        # 2. Run initial clustering across a range of cluster numbers (K) using flowClust
        flowClust.res <- flowClust(rituximab, varNames=c(colnames(rituximab)[1:2]), K=1:6,trans=1,nu.est=1,randomStart=20);
        
        # Save the BIC plot to a PDF file
        pdf("BIC_solutions.pdf")
        plot(flowMerge:::BIC(flowClust.res),
        main="BIC for 1 through 5 cluster flowClust solutions",xlab="K",ylab="BIC",type="o");
        dev.off()
        
        # 3. Extract the maximum BIC solution
        flowClust.maxBIC<-flowClust.res[[which.max(BIC(flowClust.res))]];
        
        # 4. Create a flowObj and merge clusters using the entropy metric
        flowClust.flowobj<-flowObj(flowClust.maxBIC,rituximab);
        flowClust.merge<-merge(flowClust.flowobj,metric="entropy");
        
        # 5. Fit a piecewise linear regression to find the optimal number of merged clusters
        i<-fitPiecewiseLinreg(flowClust.merge);
        
        # 6. Extract and plot the optimal merged solution
        pdf("merged_solutions.pdf")
        par(mfrow=c(2,2));
        flowClust.mergeopt<-flowClust.merge[[i]];
        plot(flowClust.maxBIC,data=rituximab,main="Max BIC solution");
        plot(flowClust.res[[which.max(flowMerge:::ICL(flowClust.res))]],data=rituximab,main="Max ICL solution");
        plot(flowClust.mergeopt,level=0.75,pch=20,main="Merged Solution");
        dev.off()
        
        # 7. Subset a specific cell population (e.g., lymphocytes) and perform a second round of clustering and merging
        pop<-which.max(getEstimates(flowClust.mergeopt)\$proportions);
        lymphocytes<-split(flowClust.mergeopt,population=list("lymphocytes"=pop))\$lymphocytes;
        
        target_cols <- colnames(lymphocytes)[-c(1:2)]
        if(length(target_cols) > 2) target_cols <- target_cols[1:2]
        if(length(target_cols) == 0) target_cols <- colnames(lymphocytes)
        
        lymphocytes<-lymphocytes[,target_cols];
        l.flowC<-flowClust(lymphocytes,varNames=target_cols,K=1:8,B=1000,B.init=100,tol=1e-5,tol.init=1e-2,randomStart=50,nu=4,nu.est=1,trans=1);
        
        pdf("lymphocyte_clustering.pdf")
        par(mfrow=c(2,2));
        l.flowO<-flowObj(l.flowC[[which.max(flowMerge:::BIC(l.flowC))]],lymphocytes);
        plot(l.flowO,main="max BIC solution",new.window=F,pch=20,level=0.9);
        plot(flowObj(l.flowC[[which.max(flowMerge:::ICL(l.flowC))]],lymphocytes),main="max ICL solution",new.window=F,pch=20,level=0.9);
        l.flowM<-merge(l.flowO);
        i<-fitPiecewiseLinreg(l.flowM,plot=T);
        plot(l.flowM[[i]],new.window=F,main="Best Merged Solution",pch=20,level=0.9);
        dev.off()
        
        # Save meaningful results to disk
        saveRDS(flowClust.mergeopt, "flowClust_mergeopt.rds")
        saveRDS(l.flowM, "l_flowM.rds")
        write.csv(getEstimates(flowClust.mergeopt)\$locations, "lymphocyte_locations.csv", row.names=FALSE)
        
        # 8. Visualize the merging process as a tree using ptree (wrapped in tryCatch for robustness)
        tryCatch({
          if (require(Rgraphviz, quietly=TRUE)) {
            pdf("ptree_plots.pdf")
            f<-ptree("l.flowM",fitPiecewiseLinreg(l.flowM));
            par(mfrow=c(1,2))
            f(1);
            f(2);
            dev.off()
          } else {
            message("Rgraphviz is not available. Skipping tree visualization.")
          }
        }, error = function(e) {
          warning("An error occurred during tree visualization: ", e\$message)
        })

    writeLines(c(
        '"BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING":',
        paste0('    flowMerge: ', as.character(packageVersion('flowMerge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_gating_and_cluster_merging.csv versions.yml
    """
}

workflow BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.fcs ] ]

    main:
    BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING(ch_input)

    emit:
    tables   = BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING.out.tables
    plots    = BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING.out.plots
    objects  = BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING.out.objects
    versions = BIOC_FLOWMERGE_AUTOMATED_GATING_AND_CLUSTER_MERGING.out.versions
}
