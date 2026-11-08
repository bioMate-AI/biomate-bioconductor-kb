#!/usr/bin/env nextflow
// ============================================================
// proteomics_db_search — license-clean DDA peptide-spectrum-match search
//   with a fast fragment-indexed engine option and semi-supervised rescoring.
//
// (Registered historically as proteomics_dda_search; this file now backs the
//  extended proteomics_db_search capability — engine + rescoring toggles.)
//
// The user need: matching input spectra against a LARGE protein DB is SLOW and has
// LOW identification RECALL. Two proven levers from the survey close both gaps:
//   * SPEED  -> Sage (Lazear JPR 2023): fragment-ion indexing, ~2500 PSMs/CPU-sec,
//              Rust, MIT license, cloud-friendly (clean-room MSFragger reimpl).
//   * RECALL -> Mokapot (Fondrie & Noble JPR 2021): Percolator-style semi-supervised
//              rescoring — a "free" sensitivity boost, Apache-2.0.
// See docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md §11.4, §11.8, §12.
//
// License-clean stack (safe for BioMate commercial hosting):
//   * Comet (Apache) via OpenMS CometAdapter  — the slow/low-recall BASELINE engine
//   * Sage  (MIT)                             — the fast fragment-indexed engine
//   * OpenMS (BSD): DecoyDatabase, PeptideIndexer
//   * Mokapot (Apache-2.0)                    — the recall (rescoring) lever
//   (NO MSFragger — academic license only; Sage is the license-clean fast engine.)
//
// Toggles:
//   --engine     comet | sage           (default: SAGE — see below)
//   --rescoring  none  | mokapot        (default: MOKAPOT — applies to sage's pin)
//
// DEFAULT = sage + mokapot (made the live default 2026-09-30). Benchmarked on the
// staged validation data (docs/20260929_PROTEOMICS_SEARCH_SPEED_RECALL.md):
//   * Sage is ~5.3x FASTER than the Comet baseline (fragment-ion indexing).
//   * Sage + Mokapot yields +222% PSMs @1% FDR vs the Comet default (recall lever).
// To reproduce the old baseline exactly: `--engine comet --rescoring none`.
//
// DAG:
//   build target+decoy DB ONCE
//     engine=comet:  per-run CometAdapter -> PeptideIndexer (indexed idXML)
//     engine=sage :  per-run SAGE (fragment index) -> results.sage.tsv + pin
//                    rescoring=mokapot: pin -> MOKAPOT -> q-valued PSMs/peptides
//
// FDR/reporting: for comet, 1% FDR is computed downstream (target-decoy q-values in
// scripts/score_proteomics_search_benchmark.py). For sage+mokapot, mokapot emits
// calibrated q-values directly. Both feed the same benchmark scorer.
//
// Design/build: docs/20260908_PROTEOMICS_DDA_SEARCH_CAPABILITY.md
//               docs/20260929_PROTEOMICS_SEARCH_SPEED_RECALL.md
// ============================================================
nextflow.enable.dsl = 2

include { OPENMS_DECOYDATABASE          } from '../modules/nf-core/openms/decoydatabase/main'
include { OPENMSTHIRDPARTY_COMETADAPTER } from '../modules/nf-core/openmsthirdparty/cometadapter/main'
include { OPENMS_PEPTIDEINDEXER         } from '../modules/nf-core/openms/peptideindexer/main'
include { SAGE                          } from '../modules/local/sage/main'
include { MOKAPOT                       } from '../modules/local/mokapot/main'

params.input     = null          // samplesheet.csv with columns: sample,mzml
params.fasta     = null          // target protein FASTA (e.g. human SwissProt + cRAP)
params.add_decoys = true         // append reversed decoys via OpenMS DecoyDatabase
params.engine    = 'sage'        // comet | sage      (default: sage — 5.3x faster)
params.rescoring = 'mokapot'     // none | mokapot    (default: mokapot — +222% PSMs)
params.container = null          // combined OpenMS+Sage+Mokapot image; when null, each
                                 // module falls back to its per-tool biocontainer. Under
                                 // BioMate's executor this is set to the combined image so
                                 // the single forced process.container has all 3 tools.
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

    // ---- per-run inputs (fan out across Batch CPU nodes) ----
    ch_runs = Channel.fromPath(params.input ?: "${projectDir}/examples/samplesheet_example.csv")
        .splitCsv(header: true)
        .map { row -> [ [id: row.sample], file(row.mzml) ] }

    if (params.engine == 'sage') {
        // ---- 2a. Sage fragment-indexed search (fast engine) ----
        SAGE(
            ch_runs.combine(ch_searchdb).map { meta, mzml, db -> [ meta, mzml, db ] }
        )
        SAGE.out.psms.view { meta, f -> "sage PSMs: ${meta.id} -> ${f}" }

        // ---- 3a. Mokapot rescoring (recall lever), toggled ----
        if (params.rescoring == 'mokapot') {
            MOKAPOT(SAGE.out.pin)
            MOKAPOT.out.peptides.view { meta, f -> "mokapot peptides@1%FDR: ${meta.id} -> ${f}" }
            emit_versions = SAGE.out.versions.mix(MOKAPOT.out.versions)
        } else {
            emit_versions = SAGE.out.versions
        }
    } else {
        // ---- 2b. Comet baseline (slow, no fragment index) ----
        OPENMSTHIRDPARTY_COMETADAPTER(
            ch_runs.combine(ch_searchdb).map { meta, mzml, db -> [ meta, mzml, db ] }
        )
        // ---- 3b. annotate target/decoy per run ----
        OPENMS_PEPTIDEINDEXER(
            OPENMSTHIRDPARTY_COMETADAPTER.out.idxml.combine(ch_searchdb).map { meta, idxml, db -> [ meta, idxml, db ] }
        )
        OPENMS_PEPTIDEINDEXER.out.indexed_idxml
            .view { meta, f -> "indexed PSMs: ${meta.id} -> ${f}" }

        emit_versions = OPENMSTHIRDPARTY_COMETADAPTER.out.versions
            .mix(OPENMS_PEPTIDEINDEXER.out.versions)
    }
}
