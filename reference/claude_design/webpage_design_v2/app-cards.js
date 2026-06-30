/* App cards renderer — renders the six application cards into a mount node.
   Mode 'illustration' uses SVG illustrations from BM_ILLUS;
   mode 'photo' falls back to the original product photographs. */

(function () {
  const APPS = [
    {
      id: 'binding',
      meta: 'Target discovery',
      title: 'Binding‑pose triage in minutes',
      desc: 'Rank co‑crystal and AlphaFold‑predicted poses by computed ΔG and proximity to known hot‑spots, with the SAR rationale written for you.',
      photo: 'images/photo-target-discovery.png'
    },
    {
      id: 'screening',
      meta: 'Lead optimization',
      title: 'Virtual screen, with provenance',
      desc: 'Score compound libraries against your target pocket using structure‑based docking and pharmacophore filtering &mdash; with every hit traced back to its source.',
      photo: 'images/photo-lead-optimization.png'
    },
    {
      id: 'admet',
      meta: 'ADMET / DMPK',
      title: 'A drug‑likeness profile that argues with itself',
      desc: 'See six‑axis ADMET predictions side‑by‑side with experimental neighbors, flagged where the structure leaves the model\'s domain of applicability.',
      photo: 'images/photo-admet-dmpk.png'
    },
    {
      id: 'pbpk',
      meta: 'PBPK simulation',
      title: 'Predicted vs. observed, on the same axes',
      desc: 'Plot in‑silico plasma profiles against historical clinical data with auto‑sourced compartment parameters &mdash; ready for your DMPK reviewer.',
      photo: 'images/photo-pbpk-simulation.png'
    },
    {
      id: 'trial',
      meta: 'Clinical pharmacology',
      title: 'Dose simulation, before the first patient',
      desc: 'Run dose‑escalation simulations, population PK models, and exposure‑response analyses to inform trial design and dose selection.',
      photo: 'images/photo-clinical-trial.png'
    },
    {
      id: 'omics',
      meta: 'Multi‑omics',
      title: 'Differential expression that holds up to QC',
      desc: 'Cluster RNA‑seq, proteomics and metabolomics with row‑scaled heatmaps that link every gene set back to its primary citation.',
      photo: 'images/photo-multiomics.png'
    },
    {
      id: 'rnaseq',
      meta: 'Transcriptomics',
      title: 'RNA&#8209;seq from count matrix to pathway enrichment',
      desc: 'DESeq2, edgeR, or limma differential expression on bulk RNA&#8209;seq data &mdash; QC&#8209;graded results with volcano plots, heatmaps, and clusterProfiler pathway enrichment.',
      photo: 'images/photo-data-foundation.png'
    },
    {
      id: 'singlecell',
      meta: 'Single&#8209;cell',
      title: 'Cell types and trajectories from your scRNA&#8209;seq',
      desc: 'Seurat or Scanpy clustering, SingleR and CellTypist cell&#8209;type annotation, and trajectory analysis with Monocle3 and scVelo &mdash; from count matrix to annotated UMAP.',
      photo: 'images/photo-lab-bench.png'
    },
    {
      id: 'variants',
      meta: 'Variant calling',
      title: 'WGS variant calling with GATK4 and DeepVariant',
      desc: 'Germline and somatic variant calling on whole&#8209;genome or targeted panel data &mdash; filtered, annotated, and delivered as audit&#8209;ready VCF with clinical interpretation.',
      photo: 'images/photo-precision-medicine.png'
    },
    {
      id: 'cryoem',
      meta: 'Structural biology',
      title: 'High&#8209;resolution structure from raw micrographs',
      desc: 'CryoSPARC single&#8209;particle analysis: motion correction, CTF estimation, particle picking, 2D/3D classification, and final refinement on GPU &mdash; publication&#8209;ready density map.',
      photo: 'images/photo-binding-pose.png'
    },
    {
      id: 'epigenomics',
      meta: 'Epigenomics',
      title: 'Methylation, chromatin access, and binding sites',
      desc: 'WGBS bisulfite sequencing, ATAC&#8209;seq chromatin accessibility, and ChIP&#8209;seq peak calling &mdash; DMR detection and motif enrichment cited to published thresholds.',
      photo: 'images/photo-virtual-screening.png'
    },
    {
      id: 'microbiome',
      meta: 'Microbiome',
      title: 'Microbiome composition from 16S or shotgun reads',
      desc: 'QIIME 2 amplicon and shotgun metagenomics &mdash; taxonomy classification, alpha/beta diversity analysis, and differential abundance with reproducible parameter logs.',
      photo: 'images/photo-pharmaceutical.png'
    }
  ];

  function cardHTML(app, mode) {
    const viz = mode === 'photo'
      ? `<div class="bm-app-viz"><img src="${app.photo}" alt="" loading="lazy"/></div>`
      : `<div class="bm-app-viz">${(window.BM_ILLUS && window.BM_ILLUS[app.id]) || ''}</div>`;
    return `
      <article class="bm-app-card ${mode === 'photo' ? 'photo' : ''}">
        ${viz}
        <div class="bm-app-body">
          <div class="bm-app-meta">${app.meta}</div>
          <h4>${app.title}</h4>
          <p>${app.desc}</p>
        </div>
      </article>`;
  }

  window.renderAppCards = function (mountId, mode) {
    const mount = document.getElementById(mountId);
    if (!mount) return;
    mount.innerHTML = APPS.map(a => cardHTML(a, mode || 'illustration')).join('');
  };
})();
