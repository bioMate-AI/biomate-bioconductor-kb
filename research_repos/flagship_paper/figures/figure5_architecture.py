"""Figure 5 — System architecture of BioMate's QC governance + auto-loop layer."""
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

fig, ax = plt.subplots(figsize=(11, 8.5), dpi=300)
ax.set_xlim(0, 100); ax.set_ylim(0, 100)
ax.set_aspect('equal'); ax.axis('off')

# Color palette
C_WORKFLOW = '#E8EAF6'  # workflow layer (lavender)
C_MONITOR  = '#FFE0B2'  # backend monitor (peach)
C_AUTOLOOP = '#C8E6C9'  # auto-loop (green)
C_GATEONLY = '#BBDEFB'  # gate-only (blue)
C_SSE      = '#FFF9C4'  # SSE event (yellow)
C_UI       = '#F8BBD0'  # UI layer (pink)
C_USER     = '#D7CCC8'  # user (brown)

def box(x, y, w, h, text, color, fontsize=9, fontweight='normal'):
    rect = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.5",
                          facecolor=color, edgecolor='black', linewidth=1.2)
    ax.add_patch(rect)
    ax.text(x + w/2, y + h/2, text, ha='center', va='center',
            fontsize=fontsize, fontweight=fontweight, wrap=True)

def arrow(x1, y1, x2, y2, color='black'):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle='->',
                                  mutation_scale=18, color=color, linewidth=1.5))

# Layer 1: Workflow
box(35, 88, 30, 7,
    'Nextflow workflow (one of 25 domains)\nemits qc_metrics.json',
    C_WORKFLOW, 10, 'bold')
arrow(50, 88, 50, 81)

# Layer 2: qc_trace_monitor
box(25, 73, 50, 7,
    'qc_trace_monitor.handle_process_completion\n(generic JSON fallback reads qc_metrics.json)',
    C_MONITOR, 10, 'bold')

# Layer 3: branch into auto-loop or gate-only
arrow(40, 73, 22, 60)
arrow(60, 73, 78, 60)

# Auto-loop branch
box(2, 47, 40, 13,
    'autoloop_bridge.evaluate_and_emit\n• 5 wired domains:\n  ADMET · CYP-DDI · NCA-PK\n  Docking · PBPK\n• Includes remediation rules',
    C_AUTOLOOP, 8)

# Gate-only branch
box(58, 47, 40, 13,
    'qc_gate_emit.emit_gate_only_event\n• 20 gate-only domains:\n  HTS · ICH-S5/S7 · BOIN · LNP\n  antibody · siRNA · polymorph etc.\n• Display + evidence only (no auto-tune)',
    C_GATEONLY, 8)

# Both converge to SSE
arrow(22, 47, 35, 38)
arrow(78, 47, 65, 38)

# Layer 4: SSE event
box(25, 30, 50, 8,
    'SSE event: "autoloop_gate_results"\nshape: {domain, gates[{gate, level, evidence[]}]}',
    C_SSE, 9, 'bold')
arrow(50, 30, 50, 22)

# Layer 5: Frontend
box(25, 14, 50, 8,
    'Frontend: auto-loop-panel.tsx\nrenders gate rows + colored status',
    C_UI, 10, 'bold')
arrow(50, 14, 50, 6)

# Layer 6: User
box(20, -1, 60, 7,
    'User hovers gate label → QCEvidenceTooltip shows:\nGOLD/SILVER/BRONZE badge · paper citation · DOI link · paper_supports',
    C_USER, 9, 'bold')

# Title
ax.text(50, 99, 'BioMate QC Governance + Auto-Loop System Architecture',
        ha='center', va='top', fontsize=13, fontweight='bold')

# Legend
legend_handles = [
    mpatches.Patch(color=C_WORKFLOW, label='Workflow execution'),
    mpatches.Patch(color=C_MONITOR, label='Backend QC monitor'),
    mpatches.Patch(color=C_AUTOLOOP, label='Auto-loop (5 domains, with remediation)'),
    mpatches.Patch(color=C_GATEONLY, label='Gate-only (20 domains, display + evidence)'),
    mpatches.Patch(color=C_SSE, label='SSE event channel'),
    mpatches.Patch(color=C_UI, label='Frontend rendering'),
    mpatches.Patch(color=C_USER, label='User-facing evidence tooltip'),
]
ax.legend(handles=legend_handles, loc='center left', bbox_to_anchor=(0.0, 0.4),
          frameon=False, fontsize=7)

plt.tight_layout()
plt.savefig('research_repos/flagship_paper/figures/figure5_architecture.png',
            dpi=300, bbox_inches='tight')
plt.savefig('research_repos/flagship_paper/figures/figure5_architecture.pdf',
            bbox_inches='tight')
print('Figure 5 saved (PNG + PDF, 300 DPI)')
