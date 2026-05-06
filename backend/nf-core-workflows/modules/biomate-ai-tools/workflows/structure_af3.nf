#!/usr/bin/env nextflow
/*
 * AlphaFold 3 Structure Prediction Workflow
 *
 * Inputs
 *   --input_json     Path to fold_input.json (AF3 format) OR a plain FASTA/sequence
 *   --model_s3       S3 path to af3.bin (default: s3://biomate-nextflow-work/models/af3/af3.bin)
 *   --db_s3          S3 prefix for AF3 databases (optional; skip MSA if not provided)
 *   --num_seeds      Number of diffusion samples / random seeds (default: 5)
 *   --run_data_pipeline  true = run MSA+template search (requires db_s3); false = inference only
 *   --outdir         Output directory / S3 prefix
 *
 * Usage (inference-only, no MSA databases needed):
 *   nextflow run workflows/structure_af3.nf \
 *       --input_json   s3://biomate-nextflow-work/inputs/beta2ar.json \
 *       --model_s3     s3://biomate-nextflow-work/models/af3/af3.bin \
 *       --num_seeds    5 \
 *       --run_data_pipeline false \
 *       --outdir       s3://biomate-nextflow-work/outputs/af3/beta2ar/
 */

nextflow.enable.dsl=2

params.input_json          = null
params.model_s3            = "s3://biomate-nextflow-work/models/af3/af3.bin"
params.db_s3               = null
params.num_seeds           = 5
params.run_data_pipeline   = false
params.outdir              = './results'

include { AF3_PREDICT } from '../af3/main'

workflow {
    if (!params.input_json) {
        error "ERROR: --input_json is required (AF3 fold_input.json)"
    }

    def sample_id = file(params.input_json).baseName.replaceAll(/\.json$/, '')

    input_ch = Channel.of([
        [id: sample_id],
        file(params.input_json)
    ])

    AF3_PREDICT(
        input_ch,
        params.model_s3,
        params.db_s3 ?: '',
        params.num_seeds,
        params.run_data_pipeline
    )

    AF3_PREDICT.out.results
        .map { meta, dir -> dir }
        .collectFile(storeDir: "${params.outdir}")

    AF3_PREDICT.out.ranking
        .subscribe { meta, csv ->
            println "=== AF3 COMPLETE: ${meta.id} ==="
            println "  Ranking: ${params.outdir}/${meta.id}/ranking_scores.csv"
            println "  Results: ${params.outdir}/${meta.id}/"
        }
}
