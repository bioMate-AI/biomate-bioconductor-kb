#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowbin — multitube_flow_integration
// Integrate multitube flow cytometry data with shared markers into a single expression matrix using quantile normalization and binning.
// Input: fs1
// Container: quay.io/biocontainers/bioconductor-flowbin:1.46.0--r45hdfd78af_0
// R packages: flowCore, flowBin, flowFP
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-flowbin:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("flowCore", "flowBin", "flowFP")
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
    
    library(flowBin)
    library(flowFP)
    library(flowCore)
    
    # Read user input
    if (file.exists("fs1")) {
      fs1 <- readRDS("fs1")
    } else if (file.exists("fs1.rds")) {
      fs1 <- readRDS("fs1.rds")
    } else {
      stop("Error: Input file 'fs1' or 'fs1.rds' not found in the working directory.")
    }
    
    # 1. Create a FlowSample object defining binning and measurement parameters
    aml.sample <- new('FlowSample',
                      name='Example flowSample', 
                      tube.set=as.list(fs1@frames), 
                      control.tubes=c(1), 
                      bin.pars=c(1,2,5), 
                      measure.pars=list(c(3,4,6,7)))
    
    # 2. Perform quantile normalization on the binning markers across tubes
    normed.sample <- quantileNormalise(aml.sample)
    
    # 3. Verify normalization quality using standard deviation of bin densities
    qnorm.check <- checkQNorm(aml.sample, normed.sample, do.plot=F)
    
    # Save QNorm check plot
    pdf("qnorm_check_plot.pdf")
    plot(qnorm.check\$sd.before, type='l', lwd=2, 
         ylim=c(0, max(qnorm.check\$sd.before)), 
         xlab='Tubes', 
         ylab='Standard deviation of bin densities', 
         main='SD before and after normalisation')
    lines(qnorm.check\$sd.after, lwd=2, col='blue')
    legend(x=5.5, y=0.35, legend=c('Before', 'After'), lwd=2, col=c('black', 'blue'))
    dev.off()
    
    # 4. Run flowBin to combine tubes into an expression matrix using 'medianFIDist'
    tube.combined <- flowBin(tube.list=aml.sample@tube.set, 
                             bin.pars=aml.sample@bin.pars, 
                             control.tubes=aml.sample@control.tubes, 
                             expr.method='medianFIDist', 
                             scale.expr=T)
    
    # 5. Visualize the integrated expression matrix using a heatmap
    pdf("heatmap_medianFIDist.pdf")
    heatmap(tube.combined, scale='none')
    dev.off()
    
    # Run flowBin using 'propPos' method
    tube.propPos <- flowBin(tube.list=aml.sample@tube.set, 
                            bin.pars=aml.sample@bin.pars, 
                            control.tubes=aml.sample@control.tubes, 
                            expr.method='propPos', 
                            scale.expr=T)
    
    # Visualize the propPos integrated expression matrix
    pdf("heatmap_propPos.pdf")
    heatmap(tube.propPos, scale='none')
    dev.off()
    
    # Save outputs
    saveRDS(tube.combined, "tube_combined.rds")
    saveRDS(tube.propPos, "tube_propPos.rds")
    
    tryCatch({
      write.csv(as.matrix(tube.combined), "tube_combined.csv")
      write.csv(as.matrix(tube.propPos), "tube_propPos.csv")
    }, error = function(e) {
      tryCatch({
        write.csv(as.data.frame(tube.combined), "tube_combined.csv")
        write.csv(as.data.frame(tube.propPos), "tube_propPos.csv")
      }, error = function(err) {
        warning("Could not write CSV files directly; objects saved as RDS.")
      })
    })

    writeLines(c(
        '"BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION":',
        paste0('        flowbin: ', as.character(packageVersion("flowbin")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multitube_flow_integration.csv versions.yml
    """
}

workflow BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fs1 ] ]

    main:
    BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION.out.tables
    plots    = BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION.out.plots
    objects  = BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION.out.objects
    versions = BIOC_FLOWBIN_MULTITUBE_FLOW_INTEGRATION.out.versions
}
