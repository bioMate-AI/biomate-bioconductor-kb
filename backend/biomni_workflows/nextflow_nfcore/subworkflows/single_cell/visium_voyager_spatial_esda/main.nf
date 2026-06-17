#!/usr/bin/env nextflow
/*
 * single_cell/visium_voyager_spatial_esda
 *
 * End-to-end 10X Visium spatial ESDA. Composes nf-core/spatialvi (id 12783)
 * sub-workflow for Space Ranger → SpatialExperiment + VisiumIO (id 12616) for
 * SE → SpatialFeatureExperiment (SFE) conversion + Voyager (id 12618) for
 * univariate (Moran's I, Geary's C, Getis-Ord Gi*), bivariate (Lee's L) and
 * multivariate (MULTISPATI PCA) spatial statistics. Chains downstream to
 * iSEE (id 11653).
 *
 * IMPORTANT — UPSTREAM P0 DEPENDENCY:
 *   Voyager, SpatialFeatureExperiment, VisiumIO, SpatialExperiment and
 *   tidySpatialExperiment are all currently exec_error because the canonical
 *   bioc-domain-transcriptomics:3.20 ECR image is missing the Voyager R
 *   package + sf + spdep. The bioc-fix workstream must rebuild the image
 *   (tag :3.20-voyager) before this workflow can acceptance-test.
 *
 * Pipeline:
 *   1. Validate samplesheet + locate Space Ranger output dirs
 *   2. Sub-workflow call: nf-core/spatialvi (id 12783)
 *   3. Convert SpatialExperiment → SpatialFeatureExperiment (SFE)
 *   4. Per-spot QC + normalization + HVG selection
 *   5. Construct spatial neighborhood graph (findVisiumGraph / k-NN)
 *   6. Univariate spatial stats (Moran's I, Geary's C, Getis-Ord Gi*)
 *   7. Bivariate spatial correlation (Lee's L) for top HVGs
 *   8. MULTISPATI PCA via runMultivariate
 *   9. Spot clustering on MULTISPATI + per-cluster stratified ESDA
 *  10. Methods report; chain to iSEE (id 11653)
 *
 * References:
 *   - Moreno-Pachter Voyager 2024 Nat Methods
 *   - Righelli et al. 2022 SpatialExperiment (Bioinformatics)
 *   - 10X Visium platform (Stahl et al. 2016 Science)
 *
 * Spec doc: docs/20260617_VOYAGER_SPATIAL_WORKFLOW_IMPLEMENTATION_REQUIREMENT.md
 */

nextflow.enable.dsl = 2

params.outdir                      = './results'
params.spaceranger_dir             = 'null'           // required, multi-sample supported via samplesheet
params.samplesheet                 = 'null'           // sample,spaceranger_dir,condition[,patient]
params.tissue_image                = 'null'           // optional; falls back to spatial/tissue_lowres_image.png
params.species                     = 'human'
params.min_features_per_spot       = '200'
params.max_pct_mito                = '30'
params.n_hvgs                      = '2000'
params.cluster_n_clusters          = '8'
params.graph_type                  = 'visium'         // visium | knn | triangulation
params.univariate_stats            = 'moran,localG'   // comma list
params.bivariate_top_n_genes       = '50'
params.multispati_n_components     = '10'
params.swap_rownames               = 'symbol'

process VISIUM_VOYAGER_SPATIAL_ESDA {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-spatial:v1' \
        : 'biomate/bioc-spatial:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("sfe_with_multispati.rds"),    emit: sfe
    tuple val(meta), path("univariate_moran.csv"),       emit: moran
    tuple val(meta), path("univariate_localG.csv"),      emit: local_g
    tuple val(meta), path("lees_L_matrix.csv"),          emit: lees_l
    tuple val(meta), path("multispati_embedding.csv"),   emit: multispati
    tuple val(meta), path("spot_clusters.csv"),          emit: clusters
    tuple val(meta), path("per_cluster_moran.csv"),      emit: per_cluster
    tuple val(meta), path("qc_metrics.csv"),             emit: qc
    tuple val(meta), path("methods_report.html"),        emit: report
    tuple val(meta), path("voyager_results.tar.gz"),     emit: archive
    path "versions.yml",                                  emit: versions

    script:
    """
    # ---------------------------------------------------------------
    # STAGE 1 — Validate samplesheet + Space Ranger dirs
    # ---------------------------------------------------------------
    python /opt/biomate/voyager/validate_spaceranger.py \\
        --samplesheet ${params.samplesheet} \\
        --spaceranger_dir ${params.spaceranger_dir}

    # ---------------------------------------------------------------
    # STAGE 2 — Sub-workflow call: nf-core/spatialvi (id 12783)
    # Orchestrator stages spe.rds + multiqc_report.html into work dir.
    # ---------------------------------------------------------------

    # ---------------------------------------------------------------
    # STAGE 3 — SpatialExperiment → SFE
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/spe_to_sfe.R \\
        --spe spe.rds \\
        --tissue_image ${params.tissue_image} \\
        --out sfe.rds

    # ---------------------------------------------------------------
    # STAGE 4 — Per-spot QC + normalization + HVGs
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/spot_qc_norm.R \\
        --sfe sfe.rds \\
        --min_features ${params.min_features_per_spot} \\
        --max_pct_mito ${params.max_pct_mito} \\
        --n_hvgs ${params.n_hvgs} \\
        --out sfe_normalized.rds \\
        --qc qc_metrics.csv \\
        --plots qc_violins.png,qc_tissue_overlay.png

    # ---------------------------------------------------------------
    # STAGE 5 — Spatial neighborhood graph
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/build_graph.R \\
        --sfe sfe_normalized.rds \\
        --graph_type ${params.graph_type} \\
        --out sfe_with_graph.rds \\
        --plot spatial_graph.png

    # ---------------------------------------------------------------
    # STAGE 6 — Univariate spatial statistics
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/run_univariate.R \\
        --sfe sfe_with_graph.rds \\
        --stats ${params.univariate_stats} \\
        --swap_rownames ${params.swap_rownames} \\
        --out_moran univariate_moran.csv \\
        --out_localG univariate_localG.csv \\
        --plots top_moran_genes.png,local_hotspots.png

    # ---------------------------------------------------------------
    # STAGE 7 — Bivariate Lee's L
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/run_bivariate_lees_L.R \\
        --sfe sfe_with_graph.rds \\
        --top_n ${params.bivariate_top_n_genes} \\
        --out lees_L_matrix.csv \\
        --plot lees_L_heatmap.png

    # ---------------------------------------------------------------
    # STAGE 8 — MULTISPATI PCA
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/run_multispati.R \\
        --sfe sfe_with_graph.rds \\
        --n_components ${params.multispati_n_components} \\
        --out_embedding multispati_embedding.csv \\
        --out_sfe sfe_with_multispati.rds \\
        --plots multispati_eigen.png,multispati_pc12_spatial.png

    # ---------------------------------------------------------------
    # STAGE 9 — Spot clustering + per-cluster stratified ESDA
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/cluster_and_stratify.R \\
        --sfe sfe_with_multispati.rds \\
        --n_clusters ${params.cluster_n_clusters} \\
        --out_clusters spot_clusters.csv \\
        --out_per_cluster per_cluster_moran.csv \\
        --plots spatial_clusters.png,per_cluster_top_genes.png

    # ---------------------------------------------------------------
    # STAGE 10 — Methods report
    # Chained iSEE call (id 11653) handled by the orchestrator.
    # ---------------------------------------------------------------
    Rscript /opt/biomate/voyager/render_report.R \\
        --sfe sfe_with_multispati.rds \\
        --moran univariate_moran.csv \\
        --qc qc_metrics.csv \\
        --params params.json \\
        --out methods_report.html

    tar -czf voyager_results.tar.gz \\
        sfe_with_multispati.rds univariate_moran.csv univariate_localG.csv \\
        lees_L_matrix.csv multispati_embedding.csv spot_clusters.csv \\
        per_cluster_moran.csv methods_report.html \\
        qc_violins.png qc_tissue_overlay.png spatial_graph.png \\
        top_moran_genes.png local_hotspots.png lees_L_heatmap.png \\
        multispati_eigen.png multispati_pc12_spatial.png spatial_clusters.png \\
        per_cluster_top_genes.png

    cat <<EOF > versions.yml
    "${task.process}":
        Voyager: \$(Rscript -e "cat(as.character(packageVersion('Voyager')))")
        SpatialFeatureExperiment: \$(Rscript -e "cat(as.character(packageVersion('SpatialFeatureExperiment')))")
        SpatialExperiment: \$(Rscript -e "cat(as.character(packageVersion('SpatialExperiment')))")
        VisiumIO: \$(Rscript -e "cat(as.character(packageVersion('VisiumIO')))")
    EOF
    """
}
