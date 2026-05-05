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
        CryoEM Viewer Test — Run 89c7f6a1 (EMPIAR-10028, 2 micrographs, beta-galactosidase D2)
      </h1>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24, marginBottom: 32 }}>
        <section data-testid="motion-viewer">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            Motion Correction Report (J2, 20 micrographs)
          </h2>
          <JsonViewer
            s3={`${S3}/02_motion_correction/batch_0000/motion_report_batch_0000.json`}
            title="Motion"
          />
        </section>

        <section data-testid="ctf-viewer">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            CTF Estimation Report (J3, 20 micrographs)
          </h2>
          <JsonViewer
            s3={`${S3}/03_ctf_estimation/batch_0000/ctf_report_batch_0000.json`}
            title="CTF Quality"
          />
        </section>

        <section data-testid="fsc-viewer">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            FSC Validation Curve (J20)
          </h2>
          <JsonViewer
            s3={`${S3}/19_validation_fsc/fsc_validation.json`}
            title="FSC Curve"
          />
        </section>

        <section data-testid="class2d-report">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            2D Classification Report (J6, 24,879 particles, 50 classes)
          </h2>
          <JsonViewer
            s3={`${S3}/09_classify_2d_round1/pbatch_0000/class2d_report_pbatch_0000.json`}
            title="Class2D"
          />
        </section>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
        <section data-testid="class-averages-mrc">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            2D Class Averages (128×128×50 stack — montage viewer)
          </h2>
          <MrcViewer
            s3={`${S3}/09_classify_2d_round1/pbatch_0003/cs_out_J9_020_class_averages.mrc`}
            title="class_averages (20 classes, pbatch_0003)"
          />
        </section>

        <section data-testid="volume-sharpened-mrc">
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: '#94a3b8' }}>
            Sharpened 3D Map (192×192×192 — 3-axis slicer)
          </h2>
          <MrcViewer
            s3={`${S3}/09_classify_2d_round1/pbatch_0002/cs_out_J9_020_class_averages.mrc`}
            title="class_averages (20 classes, pbatch_0002)"
          />
        </section>
      </div>
    </div>
  );
}
