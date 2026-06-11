#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiGGR
// This package provides an interface to simulate metabolic reconstruction from the BiGG database(http:
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiGGR/inst/doc/BiGGR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BiGGR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BIGGR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biggr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biggr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biggr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biggr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiGGR)
    library(jsonlite)

    # --- LIM Constraint Formulation [] ---
    # Key functions: createLIMFromSBML
    maximize <- "R_ATPS4m - R_NDPK1m -R_HEX1 - R_PFK - R_PGK + R_PYK"
    externals <- c("M_glc_DASH_D_e", "M_lac_DASH_L_e", "M_ala_DASH_L_e",
                   "M_gln_DASH_L_e", "M_h2o_e", "M_co2_e", "M_o2_e")
    data(lying.tunell.data, package="BiGGR")
    equation.vars <- c("R_GLCt1r", "R_L_LACt2r", "R_GLNtN1", "R_PYRt2r")
    equation.values <- as.character(lying.tunell.data[
        c("glucose", "lactate", "glutamine", "pyruvate"), "median"])
    eqns <- list(equation.vars, equation.values)
    limfile.path <- tempfile()
    createLIMFromSBML(sbml.model, maximize, equations=eqns,
                      externals=externals, file.name=limfile.path)


    # --- Flux Estimation [] ---
    # Key functions: getRates
    rates <- getRates(limfile.path)


    # --- Flux Ensemble Sampling [] ---
    # Key functions: createLIMFromSBML, sampleFluxEnsemble
    uncertain.vars <- data.frame(
        var=equation.vars,
        value=as.numeric(equation.values),
        sd=lying.tunell.data[c("glucose", "lactate", "glutamine",
                               "pyruvate"), "sd"]
    )
    limfile.path.ens <- tempfile()
    equations <- list(c("R_G6PDH2r", "R_GLUDC"),
                      c("R_GLCt1r * 0.069", "R_GLCt1r * 0.32"))
    createLIMFromSBML(sbml.model, maximize, externals=externals,
                      file.name=limfile.path.ens, equations=equations)
    ensemble <- sampleFluxEnsemble(limfile.path.ens, uncertain.vars,
                                   x0=rates, iter=1000, burninlength=100,
                                   outputlength=100, type="mirror", jmp=0.1)


    # --- Network Visualization [] ---
    # Key functions: sbml2hyperdraw
    relevant.species <- c("M_glc_DASH_D_c", "M_g6p_c", "M_f6p_c")
    relevant.reactions <- c("R_HEX1", "R_PGI", "R_PFK")
    hd <- sbml2hyperdraw(sbml.model, rates=rates,
                         relevant.species=relevant.species,
                         relevant.reactions=relevant.reactions,
                         layoutType="dot", plt.margins=c(20, 0, 20, 80))
    plot(hd)

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
        write.csv(as.data.frame(.main), "${prefix}_biggr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_biggr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_biggr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIGGR:", paste0("    biggr: ", as.character(packageVersion("BiGGR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biggr_results.csv
    touch ${prefix}_biggr_output.rds
    echo "BIOC_BIGGR:" > versions.yml
    echo "    biggr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIGGR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIGGR(ch_input)

    emit:
    results  = BIOC_BIGGR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIGGR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIGGR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIGGR.out.versions  // channel: path(versions.yml)
}
