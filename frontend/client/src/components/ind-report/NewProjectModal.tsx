/**
 * NewProjectModal — replaces the "TODO wire new-project dialog" stub in
 * pages/ind-report.tsx so that `+ New project` actually creates a project.
 *
 * Flow:
 *   1. Customer fills molecule / target / indication / sponsor / regions
 *   2. POST /api/ind-report/projects (auth-required, JWT bearer in cookies)
 *   3. On 200: caller selects the new project id and closes the modal.
 *   4. On error: inline message, modal stays open.
 *
 * Field layout mirrors the Project Setup card in `ind/Steps.jsx` (reference)
 * so the look is consistent with the rest of the IND surface.
 */
import { useState } from "react";
import { X } from "lucide-react";
import { createProject, type IndProjectRow } from "@/lib/ind-report-api";

type Region = "FDA" | "EMA" | "NMPA" | "PMDA";
const ALL_REGIONS: Region[] = ["FDA", "EMA", "NMPA", "PMDA"];

export function NewProjectModal({
  onClose,
  onCreated,
  orgId = null,
}: {
  onClose: () => void;
  onCreated: (p: IndProjectRow) => void;
  orgId?: string | null;
}) {
  const [molecule, setMolecule] = useState("");
  const [target, setTarget] = useState("");
  const [indication, setIndication] = useState("");
  const [sponsor, setSponsor] = useState("Acme Therapeutics");
  const [regions, setRegions] = useState<Region[]>(["FDA"]);
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string>("");

  const canSubmit =
    !submitting && molecule.trim().length > 0 && target.trim().length > 0 &&
    indication.trim().length > 0 && sponsor.trim().length > 0 && regions.length > 0;

  const toggleRegion = (r: Region) => {
    setRegions((prev) => (prev.includes(r) ? prev.filter((x) => x !== r) : [...prev, r]));
  };

  const submit = async () => {
    if (!canSubmit) return;
    setSubmitting(true);
    setErr("");
    try {
      const p = await createProject(
        {
          molecule: molecule.trim(),
          target: target.trim(),
          indication: indication.trim(),
          sponsor: sponsor.trim(),
          regions,
          status: "draft",
        },
        orgId,
      );
      onCreated(p);
      onClose();
    } catch (e: any) {
      const msg = e?.message ?? "Could not create project.";
      setErr(msg.includes("401") ? "Sign in to create a project." : msg);
      setSubmitting(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose} style={{ zIndex: 60 }}>
      <div
        className="modal"
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "white", borderRadius: 10, padding: 20,
          maxWidth: 480, width: "92%",
        }}
        data-testid="new-project-modal"
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
          <h3 style={{ fontSize: 15, fontWeight: 700 }}>New IND project</h3>
          <button
            onClick={onClose}
            style={{ background: "none", border: "none", cursor: "pointer" }}
            aria-label="Close"
          >
            <X size={16} />
          </button>
        </div>

        <div style={{ display: "grid", gap: 10 }}>
          <Field label="Molecule"
                 value={molecule} onChange={setMolecule} placeholder="BM-0042" />
          <Field label="Target"
                 value={target} onChange={setTarget} placeholder="EGFR L858R / T790M" />
          <Field label="Indication"
                 value={indication} onChange={setIndication} placeholder="NSCLC, 2L after TKI failure" />
          <Field label="Sponsor"
                 value={sponsor} onChange={setSponsor} placeholder="Acme Therapeutics" />

          <div>
            <label style={{ fontSize: 12, fontWeight: 600, color: "var(--ind-text-muted)" }}>Target regions</label>
            <div style={{ display: "flex", gap: 6, marginTop: 4, flexWrap: "wrap" }}>
              {ALL_REGIONS.map((r) => (
                <button
                  key={r}
                  type="button"
                  onClick={() => toggleRegion(r)}
                  className={`r-toggle ${regions.includes(r) ? "on " + r.toLowerCase() : ""}`}
                >
                  {r}
                </button>
              ))}
            </div>
          </div>
        </div>

        {err && (
          <div style={{ marginTop: 12, padding: 8, background: "#fef2f2", color: "#dc2626", fontSize: 12, borderRadius: 6 }}>
            {err}
          </div>
        )}

        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 16 }}>
          <button className="ind-btn" onClick={onClose}>Cancel</button>
          <button className="ind-btn primary" onClick={submit} disabled={!canSubmit}>
            {submitting ? "Creating…" : "Create project"}
          </button>
        </div>
      </div>
    </div>
  );
}

function Field({
  label, value, onChange, placeholder,
}: {
  label: string; value: string; onChange: (v: string) => void; placeholder?: string;
}) {
  return (
    <label style={{ display: "block" }}>
      <span style={{ fontSize: 12, fontWeight: 600, color: "var(--ind-text-muted)" }}>{label}</span>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          display: "block", width: "100%", marginTop: 4, padding: "6px 10px",
          border: "1px solid var(--ind-border-strong)", borderRadius: 6,
          fontSize: 13, fontFamily: "inherit",
        }}
      />
    </label>
  );
}
