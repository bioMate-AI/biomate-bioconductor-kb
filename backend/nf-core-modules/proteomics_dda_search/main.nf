#!/usr/bin/env nextflow
// ============================================================
// proteomics_dda_search — license-clean DDA peptide-spectrum-match search
//
// License-clean stack (safe for BioMate commercial hosting):
//   * Comet (Apache) via OpenMS CometAdapter — the search engine
//   * OpenMS (BSD) — DecoyDatabase, PeptideIndexer
// Container: biocontainers/openms-thirdparty (bundles Comet; OpenMS BSD + Comet Apache)
//
// Cohort fan-out (engine-agnostic pattern, see docs/20260908_DIANN_COHORT_SCALE_DIAGNOSIS.md):
//   build target+decoy DB ONCE  ->  per-run Comet search (fans out on Batch CPU nodes)
//   ->  PeptideIndexer annotates target/decoy per run.
//
// Output: indexed idXML per run (target/decoy annotated). FDR/reporting is a
// deliberate follow-on: NO OpenMS FalseDiscoveryRate/Percolator module is vendored
// yet, so 1% FDR is computed downstream by scripts/score_proteomics_search_benchmark.py
// (target-decoy q-values) after idXML->PSM-table normalization. This subworkflow is
// the license-clean SEARCH core; quant/FDR wraps it next.
//
// Design/build: docs/20260908_PROTEOMICS_DDA_SEARCH_CAPABILITY.md
// ============================================================
nextflow.enable.dsl = 2

include { OPENMS_DECOYDATABASE          } from '../modules/nf-core/openms/decoydatabase/main'
include { OPENMSTHIRDPARTY_COMETADAPTER } from '../modules/nf-core/openmsthirdparty/cometadapter/main'
include { OPENMS_PEPTIDEINDEXER         } from '../modules/nf-core/openms/peptideindexer/main'

params.input     = null          // samplesheet.csv with columns: sample,mzml
params.fasta     = null          // target protein FASTA (e.g. human SwissProt + cRAP)
params.add_decoys = true         // append reversed decoys via OpenMS DecoyDatabase
params.outdir    = './results'

workflow {
    // ---- target FASTA (single item, broadcast) ----
    ch_fasta = Channel.fromPath(params.fasta ?: "${projectDir}/examples/placeholder.fasta")
        .map { f -> [ [id: 'searchdb'], f ] }

    // ---- 1. build target+decoy database ONCE ----
    if (params.add_decoys) {
        OPENMS_DECOYDATABASE(ch_fasta)
        ch_searchdb = OPENMS_DECOYDATABASE.out.decoy_fasta.map { meta, f -> f }.first()
    } else {
        ch_searchdb = ch_fasta.map { meta, f -> f }.first()   // value channel -> broadcast to every run
    }

    // ---- 2. per-run Comet search (fans out across Batch CPU nodes) ----
    ch_runs = Channel.fromPath(params.input ?: "${projectDir}/examples/samplesheet_example.csv")
        .splitCsv(header: true)
        .map { row -> [ [id: row.sample], file(row.mzml) ] }

    OPENMSTHIRDPARTY_COMETADAPTER(
        ch_runs.combine(ch_searchdb).map { meta, mzml, db -> [ meta, mzml, db ] }
    )

    // ---- 3. annotate target/decoy per run ----
    OPENMS_PEPTIDEINDEXER(
        OPENMSTHIRDPARTY_COMETADAPTER.out.idxml.combine(ch_searchdb).map { meta, idxml, db -> [ meta, idxml, db ] }
    )

    // indexed idXML per run -> hand off to FDR/normalization+scoring (follow-on)
    OPENMS_PEPTIDEINDEXER.out.indexed_idxml
        .view { meta, f -> "indexed PSMs: ${meta.id} -> ${f}" }

    emit_versions = OPENMSTHIRDPARTY_COMETADAPTER.out.versions
        .mix(OPENMS_PEPTIDEINDEXER.out.versions)
}
