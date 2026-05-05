/**
 * Development-only page: renders all CryoEM viewers with real run data.
 * Access at /dev/cryo-viewers (only in dev mode)
 */
import React, { useEffect, useState } from 'react';
import { FscCurveChart } from '@/components/viewers/fsc-curve-chart';
import { MotionHistogramChart } from '@/components/viewers/motion-histogram-chart';
import { CtfQualityChart } from '@/components/viewers/ctf-quality-chart';
import { DensityMapViewer } from '@/components/viewers/density-map-viewer';

const RUN_ID = '89c7f6a1-e444-4809-bd45-59f96f76d189';
const S3 = 's3://biomate-nextflow-work/nextflow/outputs/5832459d-633c-4d0c-9756-b577241d5fce/e02a238c';

function sfUrl(s3: string) {
  const name = s3.split('/').pop()!;
  return `/api/workflows/runs/${RUN_ID}/step-file?path=${encodeURIComponent(s3)}&name=${encodeURIComponent(name)}`;
}

function JsonViewer({ s3, title }: { s3: string; title: string }) {
  const [data, setData] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    fetch(sfUrl(s3))
      .then(r => r.json())
      .then(setData)
      .catch(e => setErr(String(e)));
  }, [s3]);
  if (err) return <div className="text-red-500 text-xs">Error: {err}</div>;
  if (!data) return <div className="text-muted-foreground text-xs">Loading {title}…</div>;
  return <>{title.includes('FSC') ? <FscCurveChart data={data} />
    : title.includes('Motion') ? <MotionHistogramChart data={data} />
    : title.includes('CTF') ? <CtfQualityChart data={data} />
    : <pre className="text-xs overflow-auto max-h-48">{JSON.stringify(data, null, 2)}</pre>
  }</>;
}

function MrcViewer({ s3, title }: { s3: string; title: string }) {
  const url = sfUrl(s3);
  return (
    <div>
      <p className="text-xs text-muted-foreground mb-1">{title}</p>
      <DensityMapViewer
        src={url}
        filename={s3.split('/').pop()!}
        runId={RUN_ID}
      />
    </div>
  );
}

export default function CryoViewerTest() {
  return (
    <div style={{ background: '#0f172a', minHeight: '100vh', padding: 24, color: '#e2e8f0' }}>
      <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 24 }}>
        CryoEM Viewer — β-galactosidase D2 (EMPIAR-10028, 20 mics, 28,477 particles)
      </h1>

      {/* Row 1: 2D class averages — R1 and R2 */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24, marginBottom: 32 }}>
        <section data-testid="class-averages-r1">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            2D Class Averages Round 1 — 128×128×20 montage
          </h2>
          <MrcViewer
            s3={`${S3}/09_classify_2d_round1/pbatch_0003/cs_out_J9_020_class_averages.mrc`}
            title="class_averages_r1 (20 classes)"
          />
        </section>

        <section data-testid="class-averages-r2">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            2D Class Averages Round 2 — 128×128×20 montage (template-picked)
          </h2>
          <MrcViewer
            s3={`${S3}/14_classify_2d_round2/pbatch_0003/cs_out_J12_020_class_averages.mrc`}
            title="class_averages_r2 (20 classes, pbatch_0003)"
          />
        </section>
      </div>

      {/* Row 1b: All 3 homogeneous refinement volumes */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 24, marginBottom: 32 }}>
        <section data-testid="volume-3d-k1">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            3D Map — Homo Refinement vol_1 (J22, D2)
          </h2>
          <MrcViewer s3={`${S3}/17_homogeneous_refinement/vol_1/cs_out_J22_003_volume_precision.mrc`} title="vol_1 (4.3 MB)" />
        </section>
        <section data-testid="volume-3d-k2">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            3D Map — Homo Refinement vol_2 (J21, D2)
          </h2>
          <MrcViewer s3={`${S3}/17_homogeneous_refinement/vol_2/cs_out_J21_004_volume_precision.mrc`} title="vol_2 (4.3 MB)" />
        </section>
        <section data-testid="volume-3d-homo">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            3D Map — Homo Refinement vol_3 (J20, D2, 28,477 ptcls)
          </h2>
          <MrcViewer s3={`${S3}/17_homogeneous_refinement/vol_3/cs_out_J20_003_volume_precision.mrc`} title="vol_3 (4.3 MB)" />
        </section>
      </div>

      {/* Row 2: Motion + CTF reports */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24, marginBottom: 32 }}>
        <section data-testid="motion-viewer">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            Motion Correction (J2) — mean beam-induced motion
          </h2>
          <JsonViewer s3={`${S3}/02_motion_correction/batch_0000/motion_report_batch_0000.json`} title="Motion" />
        </section>

        <section data-testid="ctf-viewer">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            CTF Estimation (J3) — defocus & fit resolution
          </h2>
          <JsonViewer s3={`${S3}/03_ctf_estimation/batch_0000/ctf_report_batch_0000.json`} title="CTF Quality" />
        </section>
      </div>
    </div>
  );
}
