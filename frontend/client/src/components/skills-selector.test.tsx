/**
 * RTL tests for <SkillsSelector> — the composer's expert/skill pack picker
 * (spec 06 §6.5 / §0.9.2). Covers: rendering injected packs, toggling packs
 * on/off, the "N on" summary count, and the HONEST empty state when no packs
 * are available (no fabricated toggles).
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { SkillsSelector, normalizeSkillPack, type SkillPack } from "./skills-selector"

const PACKS: SkillPack[] = [
  { id: "genomics-expert", label: "Genomics Expert", description: "Variant interpretation, GRCh38 conventions." },
  { id: "clinical-expert", label: "Clinical Expert", description: "Trial design and endpoints." },
  { id: "proteomics-expert", label: "Proteomics Expert" },
]

describe("<SkillsSelector>", () => {
  it("renders each injected pack with its label and description", () => {
    render(<SkillsSelector selectedIds={[]} onChange={() => {}} packs={PACKS} />)
    fireEvent.click(screen.getByTestId("composer-experts-toggle"))
    expect(screen.getByText("Genomics Expert")).toBeInTheDocument()
    expect(screen.getByText("Clinical Expert")).toBeInTheDocument()
    expect(screen.getByText("Proteomics Expert")).toBeInTheDocument()
    expect(screen.getByText("Variant interpretation, GRCh38 conventions.")).toBeInTheDocument()
    for (const p of PACKS) {
      expect(screen.getByTestId(`composer-expert-pack-${p.id}`)).toBeInTheDocument()
    }
  })

  it("toggles a pack on and calls onChange with its id", () => {
    const onChange = vi.fn()
    render(<SkillsSelector selectedIds={[]} onChange={onChange} packs={PACKS} />)
    fireEvent.click(screen.getByTestId("composer-experts-toggle"))
    fireEvent.click(screen.getByTestId("composer-expert-pack-genomics-expert"))
    expect(onChange).toHaveBeenCalledWith(["genomics-expert"])
  })

  it("toggles a pack off when it is already selected", () => {
    const onChange = vi.fn()
    render(<SkillsSelector selectedIds={["clinical-expert"]} onChange={onChange} packs={PACKS} />)
    fireEvent.click(screen.getByTestId("composer-experts-toggle"))
    fireEvent.click(screen.getByTestId("composer-expert-pack-clinical-expert"))
    expect(onChange).toHaveBeenCalledWith([])
  })

  it("shows the 'N on' count reflecting available selected packs", () => {
    render(<SkillsSelector selectedIds={["genomics-expert", "clinical-expert"]} onChange={() => {}} packs={PACKS} />)
    expect(screen.getByTestId("composer-experts-count")).toHaveTextContent("2 on")
  })

  it("does not count selected ids that map to no available pack (honest count)", () => {
    render(<SkillsSelector selectedIds={["genomics-expert", "ghost-pack"]} onChange={() => {}} packs={PACKS} />)
    expect(screen.getByTestId("composer-experts-count")).toHaveTextContent("1 on")
  })

  it("hides the count chip when nothing is on", () => {
    render(<SkillsSelector selectedIds={[]} onChange={() => {}} packs={PACKS} />)
    expect(screen.queryByTestId("composer-experts-count")).not.toBeInTheDocument()
  })

  it("marks a selected pack as active via data-active", () => {
    render(<SkillsSelector selectedIds={["proteomics-expert"]} onChange={() => {}} packs={PACKS} />)
    fireEvent.click(screen.getByTestId("composer-experts-toggle"))
    expect(screen.getByTestId("composer-expert-pack-proteomics-expert")).toHaveAttribute("data-active", "true")
    expect(screen.getByTestId("composer-expert-pack-genomics-expert")).toHaveAttribute("data-active", "false")
  })

  it("renders an HONEST empty state and no toggles when packs=[]", () => {
    render(<SkillsSelector selectedIds={[]} onChange={() => {}} packs={[]} />)
    fireEvent.click(screen.getByTestId("composer-experts-toggle"))
    expect(screen.getByTestId("composer-experts-empty")).toHaveTextContent("No expert packs available yet.")
    expect(screen.queryByTestId(/composer-expert-pack-/)).not.toBeInTheDocument()
    // No network fetch when packs are injected.
    expect(screen.queryByTestId("composer-experts-loading")).not.toBeInTheDocument()
  })

  it("does not fetch when packs are injected", () => {
    const fetchSpy = vi.fn()
    ;(globalThis as any).fetch = fetchSpy
    render(<SkillsSelector selectedIds={[]} onChange={() => {}} packs={PACKS} />)
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})

describe('SkillsSelector portal interaction', () => {
  it('opens outside a clipping composer and keeps selection changes open', () => {
    const changed = vi.fn();
    const { container } = render(<div style={{ overflow: 'hidden', width: 220 }}><SkillsSelector packs={PACKS} selectedIds={[]} onChange={changed} /></div>);
    fireEvent.click(screen.getByTestId('composer-experts-toggle'));
    const content = screen.getByRole('dialog', { name: 'Skills & experts' });
    expect(container).not.toContainElement(content);
    expect(document.body).toContainElement(content);
    fireEvent.click(screen.getByTestId('composer-expert-pack-genomics-expert'));
    expect(changed).toHaveBeenCalledWith(['genomics-expert']);
    expect(screen.getByTestId('composer-experts-popover')).toBeVisible();
  });
  it('supports keyboard dismissal and returns focus to its trigger', async () => {
    render(<SkillsSelector packs={PACKS} selectedIds={[]} onChange={() => {}} />);
    const trigger = screen.getByTestId('composer-experts-toggle');
    fireEvent.click(trigger);
    const dialog = screen.getByTestId('composer-experts-popover');
    fireEvent.keyDown(dialog, { key: 'Escape', code: 'Escape' });
    await waitFor(() => expect(screen.queryByTestId('composer-experts-popover')).toBeNull());
    await waitFor(() => expect(trigger).toHaveFocus());
  });
});

describe("normalizeSkillPack", () => {
  it("maps title→label and keeps a real description", () => {
    expect(normalizeSkillPack({ id: "x", title: " Genomics ", description: " does stuff " })).toEqual({
      id: "x",
      label: "Genomics",
      description: "does stuff",
    })
  })

  it("falls back to joined domains when description is empty (expert packs)", () => {
    expect(normalizeSkillPack({ id: "x", title: "T", description: "", domains: ["genomics", "clinical"] })).toEqual({
      id: "x",
      label: "T",
      description: "genomics · clinical",
    })
  })

  it("falls back to the id when there is no title", () => {
    expect(normalizeSkillPack({ id: "pack-1" })).toEqual({ id: "pack-1", label: "pack-1", description: undefined })
  })
})
