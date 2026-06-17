#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msmsEDA
// Exploratory data analysis to assess the quality of a set of LC-MS/MS experiments, and visualize de i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msmsEDA/inst/doc/msmsData-Vignette.R
// Upstream  : none
// Downstream: msmsTests
//
// Install: BiocManager::install("msmsEDA")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MSMSEDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msmseda"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msmseda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msmseda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msmseda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("jsonlite", "msmsEDA")
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
    library(msmsEDA)
    library(jsonlite)

    # --- Chunk0 [] ---
    # Key functions: pData
    library(msmsEDA)
      data(msms.dataset)
      msms.dataset
      dim(msms.dataset)
      head(pData(msms.dataset))
    # --- Chunk1 [] ---
    # Key functions: processingData, setdiff, featureNames
    e <- pp.msms.data(msms.dataset)
    processingData(e)
    dim(e)
    setdiff(featureNames(msms.dataset), featureNames(e))
    # --- Chunk2 [] ---
    # Key functions: stats
    tfvnm <- count.stats(e)
    { cat("\nSample statistics after removing NAs and -R:\n\n")
      cat("SpC matrix dimension:",dim(e),"\n\n")
      print(tfvnm)
    }
    # --- Msmsdata Vignette.Rnw:160 164 [] ---
    # Key functions: barplots, exprs, pData, boxplots
    layout(mat=matrix(1:2,ncol=1),widths=1,heights=c(0.35,0.65))
    spc.barplots(exprs(e),fact=pData(e)\$treat)
    spc.boxplots(exprs(e),fact=pData(e)\$treat,minSpC=2,
                 main="UPS1 200fm vs 600fm")
    # --- Msmsdata Vignette.Rnw:172 174 [] ---
    # Key functions: densityplots, exprs, pData
    spc.densityplots(exprs(e),fact=pData(e)\$treat,minSpC=2,
                     main="UPS1 200fm vs 600fm")
    # --- Msmsdata Vignette.Rnw:189 196 [] ---
    # Key functions: pData, pca
    facs <- pData(e)
    snms <- substr(as.character(facs\$treat),1,2)
    snms <- paste(snms,as.integer(facs\$batch),sep=".")
    par(mar=c(4,4,0.5,2)+0.1)
    par(mfrow=c(2,1))
    # --- Chunkpca [] ---
    # Key functions: pData, pca
    facs <- pData(e)
    snms <- substr(as.character(facs\$treat),1,2)
    snms <- paste(snms,as.integer(facs\$batch),sep=".")
    pcares <- counts.pca(e)
    smpl.pca <- pcares\$pca
    # --- Msmsdata Vignette.Rnw:230 231 [] ---
    # Key functions: hc, pData
    counts.hc(e,facs=pData(e)[, "treat", drop = FALSE])
    # --- Msmsdata Vignette.Rnw:240 241 [] ---
    # Key functions: hc, pData
    counts.hc(e,facs=pData(e)[, "batch", drop = FALSE])
    # --- Msmsdata Vignette.Rnw:261 262 [] ---
    # Key functions: heatmap, pData
    counts.heatmap(e,etit="UPS1",fac=pData(e)[, "treat"])
    # --- Chunkmc [] ---
    # Key functions: exprs, pData, neutralize
    data(msms.dataset)
    msnset <- pp.msms.data(msms.dataset)
    spcm <- exprs(msnset)
    fbatch <- pData(msnset)\$batch
    spcm2 <- batch.neutralize(spcm, fbatch, half=TRUE, sqrt.trans=TRUE)
    # --- Msmsdata Vignette.Rnw:299 307 [] ---
    # Key functions: exprs, pData
    ###  Plot the PCA on the two first PC, and colour by treatment level
    ###  to visualize the improvement.
    exprs(msnset) <- spcm2
    facs <- pData(e)
    snms <- substr(as.character(facs\$treat),1,2)
    # --- Chunkmc2 [] ---
    # Key functions: density
    ###  Incidence of the correction
    summary(as.vector(spcm-spcm2))
    plot(density(as.vector(spcm-spcm2)))
    # --- Chunkpca [] ---
    # Key functions: estimates, signif
    dsp <- disp.estimates(e)
    signif(dsp,4)
    # --- Msmsdata Vignette.Rnw:361 364 [] ---
    # Key functions: estimates, pData
    par(mar=c(5,4,0.5,2)+0.1,cex.lab=0.8,cex.axis=0.8,cex.main=1.2)
    par(mfrow=c(2,1))
    disp.estimates(e,facs=pData(e)[, "batch", drop = FALSE])

    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_msmseda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_msmseda_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_msmseda_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSMSEDA:", paste0("    msmseda: ", as.character(packageVersion("msmsEDA")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msmseda_results.csv
    touch ${prefix}_msmseda_output.rds
    echo "BIOC_MSMSEDA:" > versions.yml
    echo "    msmseda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSMSEDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSMSEDA(ch_input)

    emit:
    results  = BIOC_MSMSEDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSMSEDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSMSEDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSMSEDA.out.versions  // channel: path(versions.yml)
}
