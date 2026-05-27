/**
 * SMILES list editor modal — replaces the no-op "12 SMILES uploaded · Edit"
 * link in Step1ProjectSetup. Closes punch list P1-5.
 *
 * Today: client-side only — manages a SMILES list in local state, returns the
 * updated list on save. Doesn't persist server-side yet (the project registry
 * doesn't carry compounds; that's a future schema extension).
 *
 * Validates each SMILES with a minimal lexical check:
 *   - non-empty after trim
 *   - contains at least one letter (not whitespace/punctuation only)
 *   - no internal whitespace
 *   - length ≤ 200 (long-tail SMILES like macrocycles can be ~150 chars)
 *
 * Real chemical validation needs RDKit (server-side); deliberately out of
 * scope for the editor UI.
 */
import { useState } from "react";
import { Plus, Trash2, X, Check } from "lucide-react";

export type SmilesEntry = {
  id: string;
  smiles: string;
  label?: string;
};

function validateSmiles(s: string): string | null {
  const t = s.trim();
  if (t.length === 0) return "empty";
  if (t.length > 200) return "too long (>200 chars)";
  if (/\s/.test(t)) return "contains whitespace";
  if (!/[A-Za-z]/.test(t)) return "no atom letters";
  return null;
}

function genId(): string {
  return `c-${Math.random().toString(36).slice(2, 10)}`;
}

export function SmilesListModal({
  initial,
  leadId,
  onClose,
  onSave,
}: {
  initial: SmilesEntry[];
  leadId?: string;
  onClose: () => void;
  onSave: (entries: SmilesEntry[], newLeadId: string | null) => void;
}) {
  const [entries, setEntries] = useState<SmilesEntry[]>(initial.length ? initial : []);
  const [activeLead, setActiveLead] = useState<string | null>(leadId ?? initial[0]?.id ?? null);
  const [newSmiles, setNewSmiles] = useState("");
  const [newLabel, setNewLabel] = useState("");
  const [addErr, setAddErr] = useState<string>("");

  const addEntry = () => {
    const err = validateSmiles(newSmiles);
    if (err) {
      setAddErr(`Invalid SMILES — ${err}`);
      return;
    }
    const id = genId();
    setEntries((prev) => [...prev, { id, smiles: newSmiles.trim(), label: newLabel.trim() || undefined }]);
    if (!activeLead) setActiveLead(id);
    setNewSmiles("");
    setNewLabel("");
    setAddErr("");
  };

  const removeEntry = (id: string) => {
    setEntries((prev) => prev.filter((e) => e.id !== id));
    if (activeLead === id) {
      // Pick the first remaining as the new lead
      const next = entries.find((e) => e.id !== id);
      setActiveLead(next?.id ?? null);
    }
  };

  const updateSmiles = (id: string, smiles: string) => {
    setEntries((prev) => prev.map((e) => (e.id === id ? { ...e, smiles } : e)));
  };

  const save = () => {
    // Re-validate everything; refuse to save if any are bad.
    const bad = entries.find((e) => validateSmiles(e.smiles) !== null);
    if (bad) {
      setAddErr(`Cannot save — ${bad.id} has invalid SMILES`);
      return;
    }
    onSave(entries, activeLead);
    onClose();
  };

  return (
    <div className="modal-backdrop" onClick={onClose} style={{ zIndex: 60 }}>
      <div
        className="modal"
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "white", borderRadius: 10, padding: 20,
          maxWidth: 640, width: "94%", maxHeight: "85vh",
          display: "flex", flexDirection: "column",
        }}
        data-testid="smiles-list-modal"
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
          <h3 style={{ fontSize: 15, fontWeight: 700 }}>Edit compound library</h3>
          <button
            onClick={onClose}
            style={{ background: "none", border: "none", cursor: "pointer" }}
            aria-label="Close"
          >
            <X size={16} />
          </button>
        </div>

        <div style={{ fontSize: 12, color: "var(--ind-text-muted)", marginBottom: 12 }}>
          {entries.length} compound{entries.length === 1 ? "" : "s"} ·{" "}
          {activeLead ? `lead: ${entries.find((e) => e.id === activeLead)?.label ?? activeLead}` : "no lead selected"}
        </div>

        {/* Existing entries */}
        <div style={{ flex: 1, overflowY: "auto", marginBottom: 12, display: "flex", flexDirection: "column", gap: 6 }}>
          {entries.length === 0 && (
            <div style={{ fontSize: 12.5, color: "var(--ind-text-muted)", padding: "16px", textAlign: "center" }}>
              No compounds yet — add a SMILES below.
            </div>
          )}
          {entries.map((e) => {
            const err = validateSmiles(e.smiles);
            const isLead = activeLead === e.id;
            return (
              <div
                key={e.id}
                data-testid={`smiles-row-${e.id}`}
                style={{
                  display: "grid",
                  gridTemplateColumns: "auto 1fr auto auto",
                  gap: 8, alignItems: "center",
                  padding: "6px 8px",
                  background: isLead ? "var(--ind-ok-soft, #f0fdf4)" : "var(--ind-bg-sub, #fafafa)",
                  border: `1px solid ${err ? "#fca5a5" : "var(--ind-border, #e5e7eb)"}`,
                  borderRadius: 6,
                }}
              >
                <label style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 11 }}>
                  <input
                    type="radio"
                    name="lead"
                    checked={isLead}
                    onChange={() => setActiveLead(e.id)}
                    aria-label={`Set ${e.id} as lead`}
                  />
                  lead
                </label>
                <input
                  type="text"
                  value={e.smiles}
                  onChange={(ev) => updateSmiles(e.id, ev.target.value)}
                  style={{
                    fontFamily: "JetBrains Mono, monospace",
                    fontSize: 11.5,
                    padding: "4px 6px",
                    border: "1px solid var(--ind-border, #e5e7eb)",
                    borderRadius: 4,
                    width: "100%",
                  }}
                  spellCheck={false}
                />
                <span style={{ fontSize: 11, color: err ? "#dc2626" : "var(--ind-text-muted)" }}>
                  {err ? `⚠ ${err}` : (e.label ?? "")}
                </span>
                <button
                  onClick={() => removeEntry(e.id)}
                  aria-label={`Remove ${e.id}`}
                  style={{
                    background: "none", border: "none", cursor: "pointer",
                    color: "var(--ind-text-muted)",
                  }}
                >
                  <Trash2 size={13} />
                </button>
              </div>
            );
          })}
        </div>

        {/* Add new */}
        <div style={{
          borderTop: "1px solid var(--ind-border, #e5e7eb)",
          paddingTop: 12, marginBottom: 8,
          display: "grid",
          gridTemplateColumns: "1fr 140px auto",
          gap: 6, alignItems: "center",
        }}>
          <input
            type="text"
            value={newSmiles}
            onChange={(e) => { setNewSmiles(e.target.value); setAddErr(""); }}
            placeholder="SMILES (e.g. CC(=O)Nc1ccc(O)cc1)"
            style={{
              fontFamily: "JetBrains Mono, monospace", fontSize: 12,
              padding: "5px 8px",
              border: "1px solid var(--ind-border-strong, #d1d5db)",
              borderRadius: 4,
            }}
            spellCheck={false}
            onKeyDown={(e) => { if (e.key === "Enter") addEntry(); }}
            data-testid="smiles-add-input"
          />
          <input
            type="text"
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
            placeholder="Label (optional)"
            style={{
              fontSize: 12,
              padding: "5px 8px",
              border: "1px solid var(--ind-border-strong, #d1d5db)",
              borderRadius: 4,
            }}
            onKeyDown={(e) => { if (e.key === "Enter") addEntry(); }}
          />
          <button
            onClick={addEntry}
            className="ind-btn sm"
            style={{ display: "inline-flex", alignItems: "center", gap: 4 }}
            data-testid="smiles-add-btn"
          >
            <Plus size={12} /> Add
          </button>
        </div>
        {addErr && (
          <div style={{ fontSize: 12, color: "#dc2626", marginBottom: 8 }}>{addErr}</div>
        )}

        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 6 }}>
          <button className="ind-btn" onClick={onClose}>Cancel</button>
          <button
            className="ind-btn primary"
            onClick={save}
            disabled={entries.length === 0}
            data-testid="smiles-save-btn"
            style={{ display: "inline-flex", alignItems: "center", gap: 4 }}
          >
            <Check size={12} /> Save ({entries.length})
          </button>
        </div>
      </div>
    </div>
  );
}
