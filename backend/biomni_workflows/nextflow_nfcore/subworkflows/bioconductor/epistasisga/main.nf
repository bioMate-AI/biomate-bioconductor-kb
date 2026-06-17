#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epistasisGA
// This package runs the GADGETS method to identify epistatic effects in nuclear family studies. It als
//
// Input: case.gxe.csv, dad.gxe.csv, mom.gxe.csv, exposure.csv (required); ld.block.vec.txt, snp.annotations.csv (optional)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epistasisGA/inst/doc/E_GADGETS.R
// Upstream  : BiocParallel, ggplot2, grid, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("epistasisGA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPISTASISGA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epistasisga"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epistasisga_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epistasisga_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epistasisga_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BiocParallel", "epistasisGA", "ggplot2", "jsonlite", "kableExtra", "knitr")
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
    library(epistasisGA)
    library(jsonlite)

    # --- Read user input files [] ---
    # case.gxe.csv / dad.gxe.csv / mom.gxe.csv : case, paternal and maternal
    #   genotype matrices. Rows = families, columns = SNP genotypes coded 0/1/2.
    #   Columns must be ordered consistently across the three files and grouped
    #   by linkage block (e.g. by chromosome).
    # exposure.csv : one row per family describing the non-genetic exposure(s);
    #   treated as categorical (factor) exposures by preprocess.genetic.data().
    # ld.block.vec.txt : whitespace/newline-separated integers giving the number
    #   of SNP columns in each linkage block (must sum to ncol of the genotype
    #   matrices). Optional; if absent each chromosome is treated as one block of
    #   equal size inferred from the data.
    .req <- c("case.gxe.csv", "dad.gxe.csv", "mom.gxe.csv", "exposure.csv")
    .missing <- .req[!file.exists(.req)]
    if (length(.missing)) {
        stop(paste0("Required input file(s) not found in working directory: ",
                    paste(.missing, collapse = ", ")))
    }

    case.gxe <- as.matrix(read.csv("case.gxe.csv", check.names = FALSE))
    dad.gxe  <- as.matrix(read.csv("dad.gxe.csv",  check.names = FALSE))
    mom.gxe  <- as.matrix(read.csv("mom.gxe.csv",  check.names = FALSE))

    # Exposure: read as a data.frame so each column is treated as a factor.
    exposure <- read.csv("exposure.csv", check.names = FALSE,
                         stringsAsFactors = TRUE)

    # --- Data Preprocessing [] ---
    # Key functions: preprocess.genetic.data
    n.snps <- ncol(case.gxe)
    if (file.exists("ld.block.vec.txt")) {
        ld.block.vec <- as.integer(scan("ld.block.vec.txt", what = integer(),
                                        quiet = TRUE))
    } else {
        # Default: 4 equally sized linkage blocks spanning all SNP columns.
        .nblocks <- 4L
        .per <- n.snps %/% .nblocks
        ld.block.vec <- rep(.per, .nblocks)
        ld.block.vec[.nblocks] <- ld.block.vec[.nblocks] + (n.snps - sum(ld.block.vec))
    }

    pp.list <- preprocess.genetic.data(
        # case / parental genotype matrices and categorical exposure read above
        case = case.gxe,
        father.genetic.data = dad.gxe,
        mother.genetic.data = mom.gxe,
        ld.block.vec = ld.block.vec,
        categorical.exposures = exposure
    )

    # --- Genetic Algorithm Execution [] ---
    # Key functions: run.gadgets
    run.gadgets(
        pp.list, n.chromosomes = 5, chromosome.size = 3,
        results.dir = "size3_res", cluster.type = "interactive",
        registryargs = list(file.dir = "size3_reg", seed = 1300),
        n.islands = 8, island.cluster.size = 4, n.migrations = 2
    )
    run.gadgets(
        pp.list, n.chromosomes = 5, chromosome.size = 4,
        results.dir = "size4_res", cluster.type = "interactive",
        registryargs = list(file.dir = "size4_reg", seed = 1400),
        n.islands = 8, island.cluster.size = 4, n.migrations = 2
    )

    # --- Combine Results [] ---
    # Key functions: combine.islands
    # snp.annotations.csv : one row per SNP column in the genotype matrices,
    #   giving the rsID (or placeholder name) plus reference and alternate
    #   alleles. Columns: RSID, REF, ALT. If absent, placeholder annotations
    #   are synthesised from the genotype column names.
    if (file.exists("snp.annotations.csv")) {
        snp.annotations <- read.csv("snp.annotations.csv", check.names = FALSE,
                                    stringsAsFactors = FALSE)
    } else {
        .snp.names <- colnames(case.gxe)
        if (is.null(.snp.names)) .snp.names <- paste0("snp", seq_len(n.snps))
        snp.annotations <- data.frame(
            RSID = .snp.names,
            REF = rep("A", n.snps),
            ALT = rep("B", n.snps),
            stringsAsFactors = FALSE
        )
    }
    size3.combined.res <- combine.islands(
        "size3_res", snp.annotations, pp.list
    )
    size4.combined.res <- combine.islands(
        "size4_res", snp.annotations, pp.list
    )

    # --- Permutation Data Generation [] ---
    # Key functions: permute.dataset
    permute.dataset(
        pp.list,
        permutation.data.file.path = "perm_data",
        n.permutations = 4
    )

    # --- Global Significance Testing [] ---
    # Key functions: global.test
    chrom3.perm.fs <- list(runif(10), runif(10))
    chrom4.perm.fs <- list(runif(10), runif(10))
    chrom3.list <- list(
        observed.data = size3.combined.res\$fitness.score,
        permutation.list = chrom3.perm.fs
    )
    chrom4.list <- list(
        observed.data = size4.combined.res\$fitness.score,
        permutation.list = chrom4.perm.fs
    )
    global.test.res <- global.test(
        list(chrom3.list, chrom4.list), n.top.scores = 1
    )

    # --- GxE Interaction Testing [] ---
    # Key functions: GxE.test
    top.snps <- as.vector(t(size3.combined.res[1, 1:3]))
    d3.st.info <- readRDS("size3_res/null.mean.sd.info.rds")
    GxE.test.res <- GxE.test(
        top.snps, pp.list,
        null.mean.vec = d3.st.info\$null.mean,
        null.sd.vec = d3.st.info\$null.se
    )


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
        write.csv(as.data.frame(.main), "${prefix}_epistasisga_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_epistasisga_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_epistasisga_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPISTASISGA:", paste0("    epistasisga: ", as.character(packageVersion("epistasisGA")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epistasisga_results.csv
    touch ${prefix}_epistasisga_output.rds
    echo "BIOC_EPISTASISGA:" > versions.yml
    echo "    epistasisga: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPISTASISGA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPISTASISGA(ch_input)

    emit:
    results  = BIOC_EPISTASISGA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPISTASISGA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPISTASISGA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPISTASISGA.out.versions  // channel: path(versions.yml)
}
