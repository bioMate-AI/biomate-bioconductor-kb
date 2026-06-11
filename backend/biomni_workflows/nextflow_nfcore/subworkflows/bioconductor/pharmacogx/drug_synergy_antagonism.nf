#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PharmacoGx — drug_synergy_antagonism
// Analyze drug combination screening data to compute synergy scores and visualize synergy landscapes.
// Input: mathews_griner.csv.tar.gz
// Container: quay.io/biocontainers/bioconductor-pharmacogx:3.14.0--r45ha27e39d_0
// R packages: CoreGx, PharmacoGx, data.table, ggplot2, scales
// Bioconductor: 3.20 | R: 4.4
// Requires: CoreGx, PharmacoGx, data.table, ggplot2, scales
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define experimental design mapping and handle technical replicates. 2. Create a TREDataMapper and construct a TreatmentResponseExp

nextflow.enable.dsl = 2

process BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM {
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
    .bm_deps <- c("CoreGx", "PharmacoGx", "data.table", "ggplot2", "scales")
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
    library(PharmacoGx)
    library(CoreGx)
    library(data.table)
    library(ggplot2)
    library(scales)
    
    # 1. Read raw drug combination screening data from the working directory
    input_file <- "mathews_griner.csv.tar.gz"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing in the working directory:", input_file))
    }
    mathews_griner <- fread(input_file)
    
    # 2. Define experimental design mapping and handle technical replicates
    groups <- list(
      rowDataMap=c(
        treatment1id="RowName",
        treatment2id="ColName",
        treatment1dose="RowConcs",
        treatment2dose="ColConcs"
      ),
      colDataMap=c("sampleid")
    )
    groups[["assayMap"]] <- c(groups\$rowDataMap, groups\$colDataMap)
    
    mathews_griner[, tech_rep := seq_len(.N), by=c(groups[["assayMap"]])]
    if (max(mathews_griner[["tech_rep"]]) > 1) {
      groups[["colDataMap"]] <- c(groups[["colDataMap"]], "tech_rep")
      groups[["assayMap"]] <- c(groups[["assayMap"]], "tech_rep")
    } else {
      message("No technical replicates in this dataset!")
      mathews_griner[["tech_reps"]] <- NULL
    }
    
    # 3. Create a TREDataMapper and construct a TreatmentResponseExperiment using metaConstruct
    treMapper <- TREDataMapper(rawdata=mathews_griner)
    guess <- guessMapping(treMapper, groups, subset=TRUE)
    metadataMap(treMapper) <- list(experiment_metadata=guess\$metadata\$mapped_columns)
    rowDataMap(treMapper) <- guess\$rowDataMap
    colDataMap(treMapper) <- guess\$colDataMap
    assayMap(treMapper) <- list(raw=guess\$assayMap)
    tre <- metaConstruct(treMapper)
    
    # 4. Normalize viability data against untreated controls
    raw <- tre[["raw"]]
    raw[, viability := viability / .SD[treatment1dose == 0 & treatment2dose == 0, viability],
        by=c("treatment1id", "treatment2id", "sampleid", "tech_rep") ]
    raw[, viability := pmax(0, viability)]
    tre[["raw"]] <- raw
    
    bad_treatments <- tre[["raw"]][viability > 2, unique(treatment1id)]
    tre <- subset(tre, !(treatment1id %in% bad_treatments))
    
    # 5. Fit monotherapy dose-response curves using logLogisticRegression via endoaggregate
    tre_qc <- tre |> endoaggregate(
      subset=treatment2dose == 0,
      assay="raw",
      target="mono_viability",
      mean_viability=pmin(1, mean(viability)),
      by=c("treatment1id", "treatment1dose", "sampleid")
    )
    
    tre_fit <- tre_qc |> endoaggregate(
      {
        fit <- PharmacoGx::logLogisticRegression(treatment1dose, mean_viability, viability_as_pct=FALSE)
        ic50 <- PharmacoGx::computeIC50(treatment1dose, Hill_fit=fit)
        aac <- PharmacoGx::computeAUC(treatment1dose, Hill_fit=fit)
        list(
          HS=fit[["HS"]],
          E_inf = fit[["E_inf"]],
          EC50 = fit[["EC50"]],
          Rsq=as.numeric(unlist(attributes(fit))),
          aac_recomputed=aac,
          ic50_recomputed=ic50
        )
      },
      assay="mono_viability",
      target="mono_profiles",
      enlist=FALSE,
      by=c("treatment1id", "sampleid"),
      nthread=2
    )
    
    # 6. Merge monotherapy fits and compute expected responses under HSA, Bliss, Loewe, and ZIP models
    tre_combo <- tre_fit |> endoaggregate(
      assay="raw",
      target="combo_viability",
      mean(viability),
      by=c("treatment1id", "treatment2id", "treatment1dose", "treatment2dose", "sampleid")
    )
    
    tre_combo <- tre_combo |>
      mergeAssays(x="combo_viability", y="mono_profiles", by=c("treatment1id", "sampleid")) |>
      mergeAssays(x="combo_viability", y="mono_profiles", by.x=c("treatment2id", "sampleid"), by.y=c("treatment1id", "sampleid"), suffixes=c("_1", "_2"))
    
    tre_combo <- tre_combo |>
      endoaggregate(viability_1=.SD[treatment2dose == 0, mean_viability], assay="combo_viability", by=c("treatment1id", "treatment1dose", "sampleid")) |>
      endoaggregate(viability_2=.SD[treatment1dose == 0, mean_viability], assay="combo_viability", by=c("treatment1id", "treatment2dose", "sampleid"))
    
    tre_synergy <- tre_combo |> endoaggregate(
      assay="combo_viability",
      HSA_ref=PharmacoGx::computeHSA(viability_1, viability_2),
      Bliss_ref=PharmacoGx::computeBliss(viability_1, viability_2),
      Loewe_ref=PharmacoGx::computeLoewe(
        treatment1dose, HS_1=HS_1, EC50_1=EC50_1, E_inf_1=E_inf_1,
        treatment2dose, HS_2=HS_2, EC50_2=EC50_2, E_inf_2=E_inf_2
      ),
      ZIP_ref=computeZIP(
        treatment1dose, HS_1=HS_1, EC50_1=EC50_1, E_inf_1=E_inf_1,
        treatment2dose, HS_2=HS_2, EC50_2=EC50_2, E_inf_2=E_inf_2
      ),
      by=assayKeys(tre_combo, "combo_viability"),
      nthread=2
    )
    
    # 7. Compute synergy scores and ZIP delta
    tre_synergy <- tre_synergy |> endoaggregate(
      assay="combo_viability",
      HSA_score=HSA_ref - mean_viability,
      Bliss_score=Bliss_ref - mean_viability,
      Loewe_score=Loewe_ref - mean_viability,
      ZIP_score=ZIP_ref - mean_viability,
      by=assayKeys(tre_synergy, "combo_viability")
    )
    
    tre_zip <- tre_synergy |> endoaggregate(
      assay="combo_viability",
      subset=treatment2dose != 0,
      {
        zip_fit <- estimateProjParams(
          dose_to=treatment1dose,
          combo_viability=mean_viability,
          dose_add=unique(treatment2dose),
          EC50_add=unique(EC50_2),
          HS_add=unique(HS_2),
          E_inf_add=unique(E_inf_2)
        )
        setNames(zip_fit, paste0(names(zip_fit), "_2_to_1"))
      },
      enlist=FALSE,
      by=c("treatment1id", "treatment2id", "treatment2dose", "sampleid"),
      nthread=2
    )
    
    tre_zip <- tre_zip |> endoaggregate(
      assay="combo_viability",
      subset=treatment1dose != 0,
      {
        zip_fit <- estimateProjParams(
          dose_to=treatment2dose,
          combo_viability=mean_viability,
          dose_add=unique(treatment1dose),
          EC50_add=unique(EC50_1),
          HS_add=unique(HS_1),
          E_inf_add=unique(E_inf_1)
        )
        setNames(zip_fit, paste0(names(zip_fit), "_1_to_2"))
      },
      enlist=FALSE,
      by=c("treatment1id", "treatment2id", "treatment1dose", "sampleid"),
      nthread=2
    )
    
    tre_zip <- tre_zip |> endoaggregate(
      assay="combo_viability",
      ZIP_delta=.deltaScore(
        EC50_1_to_2=EC50_proj_1_to_2, EC50_2_to_1=EC50_proj_2_to_1,
        EC50_1=EC50_1, EC50_2=EC50_2,
        HS_1_to_2=HS_proj_1_to_2, HS_2_to_1=HS_proj_2_to_1,
        HS_1=HS_1, HS_2=HS_2,
        E_inf_1_to_2=E_inf_proj_1_to_2, E_inf_2_to_1=E_inf_proj_2_to_1,
        E_inf_1=E_inf_1, E_inf_2=E_inf_2,
        treatment1dose=treatment1dose, treatment2dose=treatment2dose,
        ZIP=ZIP_ref
      ),
      by=assayKeys(tre_zip, "combo_viability")
    )
    
    # 8. Filter for high-quality curve fits and visualize synergy landscapes using ggplot2
    combo_viab <- tre_zip[["combo_viability"]]
    
    top_15_combo <- combo_viab[
      Rsq_1 > 0.5 & Rsqr_1_to_2 > 0.5 & Rsqr_2_to_1 > 0.5,
      .(
        max_delta=max(ZIP_delta, na.rm=TRUE),
        mean_delta=mean(ZIP_delta, na.rm=TRUE),
        max_bliss=max(Bliss_score, na.rm=TRUE),
        mean_bliss=mean(Bliss_score, na.rm=TRUE)
      ),
      by=.(treatment1id, treatment2id, sampleid)
    ][ order(-max_delta), unique(.SD) ][1:15]
    
    top_15_combo_df <- combo_viab[top_15_combo, on=c('treatment1id', 'treatment2id', 'sampleid')]
    setnafill(top_15_combo_df, type="locf", cols="ZIP_delta")
    
    # 9. Save outputs
    # Save the TreatmentResponseExperiment object
    saveRDS(tre_zip, "tre_synergy_results.rds")
    
    # Save tables
    fwrite(top_15_combo, "top_15_synergistic_combinations.csv")
    fwrite(top_15_combo_df, "top_15_combinations_detailed_data.csv")
    
    # Save plots to PDF
    pdf("synergy_landscapes.pdf", width=14, height=10)
    
    p1 <- top_15_combo_df |> ggplot(aes(x=treatment1dose, y=treatment2dose, z=ZIP_delta * 100)) +
      scale_x_log10(oob=scales::squish_infinite) +
      scale_y_log10(oob=scales::squish_infinite) +
      geom_contour_filled( breaks=c(-100, -80, -40, -20, -10, -1, 1, 10, 20, 40, 80, 100) ) +
      facet_wrap(~ treatment1id, nrow=3, ncol=5) +
      scale_fill_brewer(palette="RdBu", direction=-1, drop=FALSE) +
      theme_minimal() +
      labs(
        title="ZIP Delta Synergy Landscapes (Contour Plot)",
        subtitle="Top 15 Synergistic Combinations",
        x="Treatment 1 Dose",
        y="Treatment 2 Dose",
        fill="ZIP Delta * 100"
      )
    print(p1)
    
    p2 <- top_15_combo_df |> ggplot(aes(x=factor(treatment1dose), y=factor(treatment2dose))) +
      geom_tile(aes(fill=ZIP_delta * 100)) +
      facet_wrap(~treatment1id, nrow=3, ncol=5) +
      scale_fill_gradient2(low="blue", mid="white", high="red", midpoint=0) +
      theme_minimal() +
      labs(
        title="ZIP Delta Synergy Landscapes (Heatmap)",
        subtitle="Top 15 Synergistic Combinations",
        x="Treatment 1 Dose (Factor)",
        y="Treatment 2 Dose (Factor)",
        fill="ZIP Delta * 100"
      )
    print(p2)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: tre_synergy_results.rds, top_15_synergistic_combinations.csv, top_15_combinations_detailed_data.csv, synergy_landscapes.pdf")

    writeLines(c(
        '"BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM":',
        paste0('    PharmacoGx: ', as.character(packageVersion('PharmacoGx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drug_synergy_antagonism.csv versions.yml
    """
}

workflow BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mathews_griner.csv.tar.gz ] ]

    main:
    BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM(ch_input)

    emit:
    tables   = BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM.out.tables
    plots    = BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM.out.plots
    objects  = BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM.out.objects
    versions = BIOC_PHARMACOGX_DRUG_SYNERGY_ANTAGONISM.out.versions
}
