#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biomvRCNS — dmr_detection
// Identify differentially methylated regions (DMRs) by combining methylation differences and statistical significance levels.
// Input: variosm.RData
// Container: quay.io/biocontainers/bioconductor-biomvrcns:1.50.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, biomvRCNS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load methylation data
//  * 2. [Core Analysis] Run univariate biomvRhsmm on both profiles using cluster-based emission priors
//  * 3. [Input & Preparation] Intersect high methylation difference segments with low p-value segments to define DMRs
//  * 4. [Core Analysis] Alternatively, run multivariate biomvRhsmm using a multivariate Normal emission distribution to model covariance
//  * 5. [Visualization & Output] Extract high-confidence DMRs and plot results

nextflow.enable.dsl = 2

process BIOC_BIOMVRCNS_DMR_DETECTION {
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
    .bm_deps <- c("biomvRCNS", "GenomicRanges")
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
        library(biomvRCNS)
        library(GenomicRanges)
        
        # 1. Load methylation data
        load("variosm.RData")
        
        # 2. Run univariate biomvRhsmm on both profiles using cluster-based emission priors
        rhsmm<-biomvRhsmm(x=variosm, maxbp=100, prior.m='cluster', maxgap=100)
        
        # 3. Intersect high methylation difference segments with low p-value segments to define DMRs
        hiDiffgr<-rhsmm@res[mcols(rhsmm@res)[,'STATE']!=2 
        	& mcols(rhsmm@res)[,'SAMPLE']=='meth.diff']
        dirNo<-mcols(hiDiffgr)[,'STATE']=='1' & mcols(hiDiffgr)[,'AVG']>0 |
        	mcols(hiDiffgr)[,'STATE']=='3' & mcols(hiDiffgr)[,'AVG']<0	
        hiDiffgr<- hiDiffgr[!dirNo]
        loPgr<-rhsmm@res[mcols(rhsmm@res)[,'STATE']==1
        	& mcols(rhsmm@res)[,'SAMPLE']=='p.val']
        DMRs<-reduce(intersect(hiDiffgr, loPgr), min.gapwidth=100)
        idx<-findOverlaps(variosm, DMRs, type='within')
        mcols(DMRs)<-DataFrame(cbind(TYPE='DMR', aggregate(as.data.frame(mcols(variosm[queryHits(idx)])), 
        	by=list(DMR=subjectHits(idx)), FUN=median)[,-1]))
        names(DMRs)<-paste0('DMRs', seq_along(DMRs))	
        
        # Save univariate DMRs
        write.csv(as.data.frame(DMRs), "DMRs_univariate.csv", row.names=TRUE)
        
        # Plot univariate DMRs
        pdf("dmr_plot_univariate.pdf")
        plot(rhsmm, gmgr=DMRs, tofile=FALSE)
        dev.off()
        
        # 4. Alternatively, run multivariate biomvRhsmm using a multivariate Normal emission distribution to model covariance
        rhsmm<-biomvRhsmm(x=variosm, J=6, maxbp=100, emis.type='mvnorm',
         prior.m='cluster', maxgap=100, com.emis=T)
        
        # Plot multivariate model
        pdf("dmr_plot_multivariate_all.pdf")
        plot(rhsmm, tofile=FALSE)
        dev.off()
        
        # 5. Extract high-confidence DMRs and plot results
        DMRs<-reduce(rhsmm@res[mcols(rhsmm@res)[,'STATE']=='6'], min.gapwidth=100)
        idx<-findOverlaps(variosm, DMRs, type='within')
        mcols(DMRs)<-DataFrame(cbind(TYPE='DMR', aggregate(as.data.frame(mcols(variosm[queryHits(idx)])), 
        	by=list(DMR=subjectHits(idx)), FUN=median)[,-1], stringsAsFactors=F))
        names(DMRs)<-paste0('DMRs', seq_along(DMRs))
        
        cDMRs<-reduce(rhsmm@res[mcols(rhsmm@res)[,'STATE']=='5'], min.gapwidth=100)
        idx<-findOverlaps(variosm, cDMRs, type='within')
        mcols(cDMRs)<-DataFrame(cbind(TYPE='cDMR', aggregate(as.data.frame(mcols(variosm[queryHits(idx)])), 
        	by=list(cDMRs=subjectHits(idx)), FUN=median)[,-1], stringsAsFactors=F))
        names(cDMRs)<-paste0('cDMRs', seq_along(cDMRs))
        
        # Save multivariate DMRs and cDMRs
        write.csv(as.data.frame(DMRs), "DMRs_multivariate.csv", row.names=TRUE)
        write.csv(as.data.frame(cDMRs), "cDMRs_multivariate.csv", row.names=TRUE)
        
        # Save parameters
        sink("parameters.txt")
        chr_name <- rownames(rhsmm@param\$emis.par)[1]
        cat("Emission parameters:\n")
        print(rhsmm@param\$emis.par[chr_name,][[1]])
        cat("\nSojourn parameters:\n")
        print(rhsmm@param\$soj.par[chr_name,][[1]])
        sink()
        
        # Plot multivariate DMRs and cDMRs
        pdf("dmr_plot_multivariate_dmrs.pdf")
        plot(rhsmm, gmgr=c(DMRs, cDMRs), tofile=FALSE)
        dev.off()

    writeLines(c(
        '"BIOC_BIOMVRCNS_DMR_DETECTION":',
        paste0('    biomvRCNS: ', as.character(packageVersion('biomvRCNS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmr_detection.csv versions.yml
    """
}

workflow BIOC_BIOMVRCNS_DMR_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ variosm.RData ] ]

    main:
    BIOC_BIOMVRCNS_DMR_DETECTION(ch_input)

    emit:
    tables   = BIOC_BIOMVRCNS_DMR_DETECTION.out.tables
    plots    = BIOC_BIOMVRCNS_DMR_DETECTION.out.plots
    objects  = BIOC_BIOMVRCNS_DMR_DETECTION.out.objects
    versions = BIOC_BIOMVRCNS_DMR_DETECTION.out.versions
}
