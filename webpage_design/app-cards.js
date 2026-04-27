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
      photo: 'images/photo-pharmaceutical.png'
    },
    {
      id: 'screening',
      meta: 'Lead optimization',
      title: 'Virtual screen, with provenance',
      desc: 'Score compound libraries against your target pocket using structure‑based docking and pharmacophore filtering &mdash; with every hit traced back to its source.',
      photo: 'images/photo-data-foundation.png'
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
      photo: 'images/photo-precision-medicine.png'
    },
    {
      id: 'omics',
      meta: 'Multi‑omics',
      title: 'Differential expression that holds up to QC',
      desc: 'Cluster RNA‑seq, proteomics and metabolomics with row‑scaled heatmaps that link every gene set back to its primary citation.',
      photo: 'images/photo-multiomics.png'
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
