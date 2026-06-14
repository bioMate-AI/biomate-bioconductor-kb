#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: zenith — zenith_gsa_workflow
// Perform gene set enrichment analysis on differential expression results from a linear mixed model fit with dream and visualize the results.
// Input: geneCounts, df_metadata
// Container: quay.io/biocontainers/bioconductor-zenith:1.12.0--r45hdfd78af_0
// R packages: edgeR, EnrichmentBrowser, kableExtra, knitr, tweeDEseqCountData, variancePartition, zenith
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, kableExtra, tweeDEseqCountData, variancePartition, zenith
// Visualizations: plot (ggplot/base)
// QC: filter low-expression genes, TMM normalization, voom mean-variance modelling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-expressed genes using edgeR::filterByExpr
//  * 2. [Core Analysis] Compute library size normalization using edgeR::calcNormFactors
//  * 3. [Core Analysis] Estimate precision weights using variancePartition::voomWithDreamWeights
//  * 4. [Core Analysis] Fit linear (mixed) model using variancePartition::dream and limma::eBayes
//  * 5. [Input & Preparation] Load gene sets using get_MSigDB or get_GeneOntology
//  * 6. [Core Analysis] Run zenith gene set analysis using zenith_gsa
//  * 7. [Visualization & Output] Plot results using plotZenithResults

nextflow.enable.dsl = 2

process BIOC_ZENITH_ZENITH_GSA_WORKFLOW {
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
    .bm_deps <- c("edgeR", "EnrichmentBrowser", "kableExtra", "knitr", "tweeDEseqCountData", "variancePartition", "zenith")
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
        
        # Load packages
        library(zenith)
        library(edgeR)
        library(variancePartition)
        library(tweeDEseqCountData)
        library(kableExtra)
        
        # Load RNA-seq data from user input files
        if (file.exists("geneCounts.rds")) {
          geneCounts = readRDS("geneCounts.rds")
        } else if (file.exists("geneCounts.csv")) {
          geneCounts = as.matrix(read.csv("geneCounts.csv", row.names=1, check.names=FALSE))
        } else if (file.exists("geneCounts.tsv")) {
          geneCounts = as.matrix(read.delim("geneCounts.tsv", row.names=1, check.names=FALSE))
        } else {
          stop("Error: geneCounts file not found in the working directory (expected geneCounts.rds, geneCounts.csv, or geneCounts.tsv).")
        }
        
        if (file.exists("df_metadata.rds")) {
          df_metadata = readRDS("df_metadata.rds")
        } else if (file.exists("df_metadata.csv")) {
          df_metadata = read.csv("df_metadata.csv", row.names=1, check.names=FALSE)
        } else if (file.exists("df_metadata.tsv")) {
          df_metadata = read.delim("df_metadata.tsv", row.names=1, check.names=FALSE)
        } else {
          stop("Error: df_metadata file not found in the working directory (expected df_metadata.rds, df_metadata.csv, or df_metadata.tsv).")
        }
        
        # Filter genes
        # Note this is low coverage data, so just use as code example
        covariate = colnames(df_metadata)[1]
        form = as.formula(paste0("~ `", covariate, "`"))
        dsgn = model.matrix(form, df_metadata)
        keep = filterByExpr(geneCounts, dsgn, min.count=5)
        
        # Compute library size normalization
        dge = DGEList(counts = geneCounts[keep,])
        dge = calcNormFactors(dge)
        
        # Estimate precision weights using voom
        vobj = voomWithDreamWeights(dge, form, df_metadata)
        
        # Apply dream analysis
        fit = dream(vobj, form, df_metadata)
        fit = eBayes(fit)
        
        # Load get_MSigDB database, Hallmark genes
        # use gene 'SYMBOL', or 'ENSEMBL' id
        # use get_GeneOntology() to load Gene Ontology
        msdb.gs = get_MSigDB("H", to="ENSEMBL")
           
        # Run zenith analysis, and specific which coefficient to evaluate
        coef_name = colnames(dsgn)[2]
        res.gsa = zenith_gsa(fit, msdb.gs, coef_name, progressbar=FALSE )
        
        # Show top gene sets: head(res.gsa)
        kable_res = kable_styling(kable(head(res.gsa), row.names=FALSE))
        
        # Save tabular results
        write.csv(res.gsa, "zenith_results.csv", row.names=FALSE)
        saveRDS(res.gsa, "zenith_results.rds")
        writeLines(as.character(kable_res), "top_genesets.html")
        
        # for each cell type select 3 genesets with largest t-statistic
        # and 1 geneset with the lowest
        # Grey boxes indicate the gene set could not be evaluted because
        #    to few genes were represented
        pdf("zenith_results_plot.pdf", width=10, height=8)
        print(plotZenithResults(res.gsa))
        dev.off()

    writeLines(c(
        '"BIOC_ZENITH_ZENITH_GSA_WORKFLOW":',
        paste0('    zenith: ', as.character(packageVersion('zenith')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zenith_gsa_workflow.csv versions.yml
    """
}

workflow BIOC_ZENITH_ZENITH_GSA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneCounts, df_metadata ] ]

    main:
    BIOC_ZENITH_ZENITH_GSA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.tables
    plots    = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.plots
    objects  = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.objects
    versions = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.versions
}
