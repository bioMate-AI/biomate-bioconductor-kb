#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planet — cell_composition_estimation
// Estimate cell type proportions in placental villi DNAm samples using first or third trimester reference CpGs.
// Input: DNAm_betas.rds
// Container: quay.io/biocontainers/bioconductor-planet:1.18.0--r45hdfd78af_0
// R packages: dplyr, EpiDISH, ggplot2, minfi, planet, tidyr
// Bioconductor: 3.20 | R: 4.4
// Requires: EpiDISH, dplyr, ggplot2, minfi, planet, scales, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the appropriate trimester-specific reference CpGs (plCellCpGsThird or plCellCpGsFirst)
//  * 2. [Core Analysis] Estimate cell composition using minfi's projectCellType or EpiDISH's epidish function

nextflow.enable.dsl = 2

process BIOC_PLANET_CELL_COMPOSITION_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("dplyr", "EpiDISH", "ggplot2", "minfi", "planet", "tidyr")
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
    library(minfi)
    library(EpiDISH)
    library(dplyr)
    library(ggplot2)
    library(tidyr)
    library(planet)
    
    # 1. Read user input DNAm betas
    if (!file.exists("DNAm_betas.rds")) {
      stop("Error: Input file 'DNAm_betas.rds' not found in the working directory.")
    }
    plBetas <- readRDS("DNAm_betas.rds")
    
    # 2. Load reference CpGs and colors directly from the package
    plCellCpGsThird <- planet::plCellCpGsThird
    plColors <- planet::plColors
    
    # Align reference CpGs with available CpGs in the user's beta matrix
    common_cpgs <- intersect(rownames(plBetas), rownames(plCellCpGsThird))
    if (length(common_cpgs) == 0) {
      stop("Error: No overlapping CpGs found between input DNAm_betas.rds and plCellCpGsThird reference.")
    }
    plCellCpGsThird <- plCellCpGsThird[common_cpgs, , drop = FALSE]
    
    # 3. Estimate cell composition using minfi (Constrained Projection)
    houseman_estimates <- minfi:::projectCellType(
      plBetas[rownames(plCellCpGsThird), ],
      plCellCpGsThird,
      lessThanOne = FALSE
    )
    
    # 4. Estimate cell composition using EpiDISH (RPC, CBS, and CP methods)
    epidish_RPC <- epidish(
      beta.m = plBetas[rownames(plCellCpGsThird), ],
      ref.m = plCellCpGsThird,
      method = "RPC"
    )
    
    epidish_CBS <- epidish(
      beta.m = plBetas[rownames(plCellCpGsThird), ],
      ref.m = plCellCpGsThird,
      method = "CBS"
    )
    
    epidish_CP <- epidish(
      beta.m = plBetas[rownames(plCellCpGsThird), ],
      ref.m = plCellCpGsThird,
      method = "CP"
    )
    
    # 5. Save meaningful results to CSV files
    write.csv(as.data.frame(houseman_estimates), "houseman_estimates.csv", row.names = TRUE)
    write.csv(as.data.frame(epidish_RPC\$estF), "epidish_RPC_estimates.csv", row.names = TRUE)
    write.csv(as.data.frame(epidish_CBS\$estF), "epidish_CBS_estimates.csv", row.names = TRUE)
    write.csv(as.data.frame(epidish_CP\$estF), "epidish_CP_estimates.csv", row.names = TRUE)
    
    # Save the raw R objects for downstream analysis
    saveRDS(houseman_estimates, "houseman_estimates.rds")
    saveRDS(epidish_RPC, "epidish_RPC.rds")
    saveRDS(epidish_CBS, "epidish_CBS.rds")
    saveRDS(epidish_CP, "epidish_CP.rds")
    
    # 6. Generate and save comparison plot
    plot_df <- bind_rows(
      houseman_estimates %>% as.data.frame() %>% mutate(algorithm = "CP (Houseman)"),
      epidish_RPC\$estF %>% as.data.frame() %>% mutate(algorithm = "RPC"),
      epidish_CBS\$estF %>% as.data.frame() %>% mutate(algorithm = "CBS"),
      epidish_CP\$estF %>% as.data.frame() %>% mutate(algorithm = "CP (EpiDISH)")
    ) %>%
      mutate(sample = rep(rownames(houseman_estimates), 4)) %>%
      as_tibble() %>%
      pivot_longer(
        cols = -c(algorithm, sample),
        names_to = "component",
        values_to = "estimate"
      ) %>%
      mutate(component = factor(component,
                                levels = c(
                                  "nRBC", "Endothelial", "Hofbauer",
                                  "Stromal", "Trophoblasts",
                                  "Syncytiotrophoblast"
                                )
      ))
    
    p <- ggplot(plot_df, aes(x = sample, y = estimate, fill = component)) +
      geom_bar(stat = "identity") +
      facet_wrap(~algorithm, ncol = 1) +
      scale_fill_manual(values = plColors) +
      scale_y_continuous(
        limits = c(-0.1, 1.1), breaks = c(0, 0.5, 1),
        labels = scales::percent
      ) +
      theme(axis.text.x = element_text(angle = 90, vjust = 0.5)) +
      coord_cartesian(ylim = c(0, 1)) +
      labs(x = "", fill = "")
    
    ggsave("cell_composition_comparison.pdf", plot = p, width = 10, height = 12)

    writeLines(c(
        '"BIOC_PLANET_CELL_COMPOSITION_ESTIMATION":',
        paste0('    planet: ', as.character(packageVersion('planet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_composition_estimation.csv versions.yml
    """
}

workflow BIOC_PLANET_CELL_COMPOSITION_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DNAm_betas.rds ] ]

    main:
    BIOC_PLANET_CELL_COMPOSITION_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_PLANET_CELL_COMPOSITION_ESTIMATION.out.tables
    plots    = BIOC_PLANET_CELL_COMPOSITION_ESTIMATION.out.plots
    objects  = BIOC_PLANET_CELL_COMPOSITION_ESTIMATION.out.objects
    versions = BIOC_PLANET_CELL_COMPOSITION_ESTIMATION.out.versions
}
