/**
 * SimulatedUser — context-aware simulated user for BioMate E2E tests.
 *
 * Replaces the naive "send fixed query then click buttons" pattern with a
 * goal-driven user model that:
 *  - Maintains a goal state across the conversation
 *  - Generates contextually appropriate replies to clarification questions
 *    using Claude Haiku as the "simulated user brain"
 *  - Provides realistic-looking data when asked (PDB IDs, SMILES, file paths, etc.)
 *  - Never exits early on a clarification prompt
 *
 * Priority scenarios:
 *  - Drug discovery (ADMET, docking, MD simulation, lead design, RBFE)
 *  - Cryo-EM (SPA, helical, focused refinement)
 *  - Cryo-ET (subtomogram averaging, tilt alignment, full pipeline)
 *
 * Usage:
 *   const user = new SimulatedUser(page, SIMULATED_USER_SCENARIOS.admet_ibuprofen);
 *   await user.reachWorkflowCard({ maxRounds: 5 });
 */

import { Page, expect } from "@playwright/test";
import Anthropic from "@anthropic-ai/sdk";

export interface SimulatedUserConfig {
  /** The goal the user is trying to accomplish */
  goal: string;
  /** Scientific persona description */
  persona?: string;
  /** Primary domain */
  domain?: string;
  /** Initial message to send — if omitted, derived from goal */
  initialQuery?: string;
  /** Extra context the user "knows" */
  context?: Record<string, string>;
}

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

function detectsClarificationRequest(responseText: string): boolean {
  const text = responseText.toLowerCase();
  const questionIndicators = [
    "could you please", "can you provide", "please provide", "please specify",
    "what type of", "which genome", "what organism", "do you have",
    "could you share", "what would you like", "please tell me",
    "what is the", "which analysis", "what format", "do you want",
    "would you like me to", "what pdb", "which protein", "what compound",
    "please upload", "please share", "what ligand", "which receptor",
    "do you need", "what target", "what resolution",
  ];
  return questionIndicators.some((phrase) => text.includes(phrase));
}

async function getLatestAssistantMessage(page: Page): Promise<string> {
  const latestMsg = page.locator('[data-is-latest-assistant="true"]');
  if ((await latestMsg.count()) > 0) {
    return (await latestMsg.last().textContent()) ?? "";
  }
  const allMsgs = page.locator('[data-testid^="chat-message-assistant"]');
  const msgCount = await allMsgs.count();
  if (msgCount > 0) {
    return (await allMsgs.last().textContent()) ?? "";
  }
  return (await page.locator("body").textContent()) ?? "";
}

async function sendMessage(page: Page, message: string): Promise<void> {
  const chatInput = page.locator("textarea").first();
  await expect(chatInput).toBeVisible({ timeout: 10_000 });
  await chatInput.fill(message);
  await chatInput.press("Enter");
}

async function waitForResponse(page: Page, timeoutMs = 120_000): Promise<void> {
  const thinkingSelectors = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing request",
    "text=AI is typing",
  ];

  await Promise.race(
    thinkingSelectors.map((sel) =>
      page.waitForSelector(sel, { state: "visible", timeout: 30_000 }).catch(() => null)
    )
  );
  await Promise.all(
    thinkingSelectors.map((sel) =>
      page.waitForSelector(sel, { state: "hidden", timeout: timeoutMs }).catch(() => null)
    )
  );
  await page
    .waitForFunction(
      () => {
        const latest = document.querySelector('[data-is-latest-assistant="true"]');
        if (!latest) return false;
        const text = latest.textContent ?? "";
        return text.trim().length > 30 && !text.includes("BioMate is thinking");
      },
      { timeout: timeoutMs }
    )
    .catch(() => {});
  await page.waitForTimeout(500);
}

async function hasWorkflowCard(page: Page): Promise<boolean> {
  return page
    .getByTestId("button-run-workflow-panel")
    .first()
    .isVisible({ timeout: 3_000 })
    .catch(() => false);
}

/**
 * Generate a contextually appropriate reply using Claude Haiku.
 * Falls back to rule-based when no API key.
 */
async function generateClarificationReply(
  clarificationQuestion: string,
  config: SimulatedUserConfig,
  conversationHistory: string[],
  anthropicApiKey?: string
): Promise<string> {
  const apiKey = anthropicApiKey || process.env.ANTHROPIC_API_KEY;
  if (apiKey) {
    try {
      const client = new Anthropic({ apiKey });
      const systemPrompt = buildSystemPrompt(config);
      const response = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 120,
        temperature: 0.3,
        system: systemPrompt,
        messages: [{
          role: "user",
          content: `BioMate asked: "${clarificationQuestion.slice(0, 400)}"\n\nConversation so far:\n${conversationHistory.slice(-4).join("\n")}\n\nReply in 1-2 sentences, giving a specific answer that moves toward your goal.`,
        }],
      });
      const text = response.content[0].type === "text" ? response.content[0].text.trim() : "";
      if (text.length > 5) return text;
    } catch {
      // fall through
    }
  }
  return generateFallbackReply(clarificationQuestion, config);
}

function buildSystemPrompt(config: SimulatedUserConfig): string {
  const domain = config.domain || "life sciences";
  const persona = config.persona || "life science researcher";
  const ctxLines = config.context
    ? Object.entries(config.context).map(([k, v]) => `  ${k}: ${v}`).join("\n")
    : "  (none)";

  return `You are a ${persona} using BioMate, a bioinformatics workflow AI.
Your goal: ${config.goal}
Domain: ${domain}
Your known data/parameters:
${ctxLines}

When BioMate asks for clarification, give a SHORT, specific answer (1-2 sentences).
Use these defaults when asked:
- Human genome: hg38 / GRCh38
- Mouse genome: mm10
- Protein structures: provide a PDB ID or say "I'll upload the PDB file"
- SMILES: provide the one from your context, or a plausible drug-like SMILES
- SRA accession: SRR1518169
- CryoEM: micrographs from K2/K3 detector, 300 kV, ~2 Å/pixel
- CryoET: tilt series from Titan Krios, ±60° range, 3° increment
- File paths: provide plausible S3 paths like s3://biomate-pilot/[filename]
Never ask for help. Never say you don't have data. Provide plausible values.`;
}

function generateFallbackReply(question: string, config: SimulatedUserConfig): string {
  const q = question.toLowerCase();
  const ctx = config.context || {};

  // Drug discovery specifics
  if (q.includes("smiles") || q.includes("compound") || q.includes("molecule") || q.includes("ligand")) {
    return ctx["smiles"] || ctx["ligand_smiles"] || "CC(C)Cc1ccc(cc1)C(C)C(=O)O (ibuprofen)";
  }
  if (q.includes("pdb") || q.includes("protein") || q.includes("receptor") || q.includes("target")) {
    return ctx["pdb_id"] ? `PDB ID: ${ctx["pdb_id"]}` : "I'll provide the PDB file. Use the structure at s3://biomate-pilot/receptor.pdb";
  }
  if (q.includes("docking") || q.includes("binding") || q.includes("active site")) {
    return "Please use the default active site detection. The binding pocket is near residue 286.";
  }
  if (q.includes("force field") || q.includes("forcefield") || q.includes("md") || q.includes("simulation")) {
    return "Use AMBER99SB-ILDN force field, GAFF2 for the ligand, 10 ns simulation.";
  }

  // Cryo-EM/ET specifics
  if (q.includes("micrograph") || q.includes("movie") || q.includes("mrc") || q.includes("tiff")) {
    return ctx["data_path"] || "The micrographs are at s3://biomate-pilot/micrographs/. K3 detector, super-resolution mode.";
  }
  if (q.includes("tilt") || q.includes("tomogram") || q.includes("tilt series")) {
    return ctx["tiltseries_path"] || "Tilt series are at s3://biomate-pilot/tiltseries/. ±60° range, 3° increment, 300 kV.";
  }
  if (q.includes("pixel") || q.includes("apix") || q.includes("angstrom per")) {
    return "Pixel size is 1.06 Å/pixel (physical), 0.53 Å/pixel super-resolution.";
  }
  if (q.includes("symmetry") || q.includes("c2") || q.includes("icosahedral")) {
    return ctx["symmetry"] || "C1 symmetry (no imposed symmetry).";
  }
  if (q.includes("particle") || q.includes("box size")) {
    return "Box size 256 pixels, particle size approximately 200 Å.";
  }
  if (q.includes("resolution") || q.includes("target resolution")) {
    return "Target resolution around 3.5 Å.";
  }

  // General genomics
  if (q.includes("genome") || q.includes("reference")) {
    return ctx["genome"] || "Use hg38 (GRCh38).";
  }
  if (q.includes("organism") || q.includes("species")) {
    return ctx["organism"] || "Homo sapiens.";
  }
  if (q.includes("accession") || q.includes("sra") || q.includes("geo")) {
    return ctx["accession"] || "Use accession SRR1518169.";
  }

  // Generic push-forward
  if (q.includes("confirm") || q.includes("proceed") || q.includes("ready")) {
    return "Yes, please proceed with those settings.";
  }
  return "Please proceed with the default parameters for my use case.";
}

// ---------------------------------------------------------------------------
// Main SimulatedUser class
// ---------------------------------------------------------------------------

export class SimulatedUser {
  private page: Page;
  private config: SimulatedUserConfig;
  private conversationHistory: string[] = [];
  private clarificationRoundsUsed = 0;
  private anthropicApiKey?: string;

  constructor(page: Page, config: SimulatedUserConfig, anthropicApiKey?: string) {
    this.page = page;
    this.config = config;
    this.anthropicApiKey = anthropicApiKey || process.env.ANTHROPIC_API_KEY;
  }

  async sendInitialQuery(): Promise<boolean> {
    const query = this.config.initialQuery || this.config.goal;
    await sendMessage(this.page, query);
    this.conversationHistory.push(`User: ${query}`);
    await waitForResponse(this.page);
    const responseText = await getLatestAssistantMessage(this.page);
    this.conversationHistory.push(`BioMate: ${responseText.slice(0, 300)}`);
    return hasWorkflowCard(this.page);
  }

  async handleClarifications(options: { maxRounds?: number; timeoutPerRound?: number } = {}): Promise<boolean> {
    const maxRounds = options.maxRounds ?? 5;
    const timeoutPerRound = options.timeoutPerRound ?? 90_000;

    for (let round = 0; round < maxRounds; round++) {
      if (await hasWorkflowCard(this.page)) return true;

      const latestMsg = await getLatestAssistantMessage(this.page);

      if (!detectsClarificationRequest(latestMsg)) {
        const isError = latestMsg.toLowerCase().includes("cannot") ||
          latestMsg.toLowerCase().includes("sorry, i") ||
          latestMsg.toLowerCase().includes("not able to");
        if (isError && round > 0) return false;

        const nudge = "Please proceed with the most appropriate workflow for my request.";
        await sendMessage(this.page, nudge);
        this.conversationHistory.push(`User: ${nudge}`);
        await waitForResponse(this.page, timeoutPerRound);
        continue;
      }

      const reply = await generateClarificationReply(
        latestMsg, this.config, this.conversationHistory, this.anthropicApiKey
      );
      await sendMessage(this.page, reply);
      this.conversationHistory.push(`User: ${reply}`);
      this.clarificationRoundsUsed++;

      await waitForResponse(this.page, timeoutPerRound);
      const responseText = await getLatestAssistantMessage(this.page);
      this.conversationHistory.push(`BioMate: ${responseText.slice(0, 300)}`);

      if (await hasWorkflowCard(this.page)) return true;
    }
    return hasWorkflowCard(this.page);
  }

  async reachWorkflowCard(options: { maxRounds?: number; requireWorkflowCard?: boolean } = {}): Promise<void> {
    const requireCard = options.requireWorkflowCard ?? true;
    const immediateCard = await this.sendInitialQuery();
    if (immediateCard) return;

    const gotCard = await this.handleClarifications({ maxRounds: options.maxRounds ?? 5 });
    if (requireCard && !gotCard) {
      throw new Error(
        `SimulatedUser: failed to reach workflow card after ${options.maxRounds ?? 5} clarification rounds.\n` +
        `Goal: ${this.config.goal}\nConversation:\n${this.conversationHistory.slice(-10).join("\n")}`
      );
    }
  }

  getConversationHistory(): string[] { return [...this.conversationHistory]; }
  getClarificationRoundsUsed(): number { return this.clarificationRoundsUsed; }
}

// ---------------------------------------------------------------------------
// Pre-built user scenarios — drug discovery and cryo-EM/ET first
// ---------------------------------------------------------------------------

export const SIMULATED_USER_SCENARIOS = {
  // ── Drug Discovery ────────────────────────────────────────────────────────
  admet_ibuprofen: {
    goal: "Run ADMET analysis on ibuprofen to check hERG toxicity, DILI risk, and metabolic stability",
    persona: "medicinal chemist",
    domain: "drug_discovery",
    initialQuery: "Run ADMET analysis on ibuprofen. SMILES: CC(C)Cc1ccc(cc1)C(C)C(=O)O",
    context: { smiles: "CC(C)Cc1ccc(cc1)C(C)C(=O)O", molecule: "ibuprofen" },
  } as SimulatedUserConfig,

  admet_novel_compound: {
    goal: "ADMET profile for a novel kinase inhibitor with SMILES CC1=CC2=C(N1)N=CC(=C2)C(=O)NCC3=CC=CC=C3",
    persona: "drug discovery scientist at a biotech",
    domain: "drug_discovery",
    initialQuery: "I need full ADMET profiling for a novel kinase inhibitor candidate. SMILES: CC1=CC2=C(N1)N=CC(=C2)C(=O)NCC3=CC=CC=C3. Check hERG, DILI, solubility, and blood-brain barrier permeability.",
    context: { smiles: "CC1=CC2=C(N1)N=CC(=C2)C(=O)NCC3=CC=CC=C3", target: "kinase" },
  } as SimulatedUserConfig,

  molecular_docking: {
    goal: "Run AutoDock Vina molecular docking of a ligand against the EGFR kinase domain (PDB: 1IEP)",
    persona: "computational chemist",
    domain: "drug_discovery",
    initialQuery: "Dock imatinib against the EGFR kinase domain. PDB ID: 1IEP, ligand SMILES: Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C",
    context: { pdb_id: "1IEP", ligand_smiles: "Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C", protein: "EGFR/ABL1 kinase" },
  } as SimulatedUserConfig,

  gromacs_md: {
    goal: "Run GROMACS molecular dynamics simulation of the EGFR-imatinib complex for 10 ns",
    persona: "structural biophysicist",
    domain: "drug_discovery",
    initialQuery: "I need to run molecular dynamics simulation of a protein-ligand complex. Protein PDB at s3://biomate-pilot/1iep_receptor.pdb, ligand imatinib SMILES: Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C. Run 10 ns MD with AMBER99SB-ILDN.",
    context: {
      pdb_id: "1IEP",
      protein_pdb: "s3://biomate-pilot/1iep_receptor.pdb",
      ligand_smiles: "Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C",
      simulation_time: "10 ns",
    },
  } as SimulatedUserConfig,

  pocket_detection: {
    goal: "Detect druggable binding pockets in the KRAS G12C mutant structure (PDB: 6OIM)",
    persona: "medicinal chemist",
    domain: "drug_discovery",
    initialQuery: "Find druggable binding pockets in KRAS G12C mutant. PDB ID: 6OIM. I want to identify allosteric pockets beyond the orthosteric GTP site.",
    context: { pdb_id: "6OIM", target: "KRAS G12C", mutation: "G12C" },
  } as SimulatedUserConfig,

  lead_optimization: {
    goal: "Run REINVENT4 scaffold decoration to optimize a fragment hit against PD-1",
    persona: "medicinal chemist working on immuno-oncology",
    domain: "drug_discovery",
    initialQuery: "I have a fragment hit against PD-1 and want to use AI-driven lead optimization. Core scaffold SMILES: c1ccc(cc1)c2ccc(cc2)N. Run scaffold decoration to generate analogs with improved binding.",
    context: { smiles: "c1ccc(cc1)c2ccc(cc2)N", target: "PD-1", mode: "scaffold_decoration" },
  } as SimulatedUserConfig,

  cyp_ddi: {
    goal: "Run CYP DDI panel analysis for ibuprofen to check drug-drug interaction risk",
    persona: "clinical pharmacologist",
    domain: "drug_discovery",
    initialQuery: "I need to assess CYP-mediated drug-drug interaction risk for ibuprofen. SMILES: CC(C)Cc1ccc(cc1)C(C)C(=O)O. Run the full CYP inhibition panel (CYP1A2, 2C9, 2C19, 2D6, 3A4).",
    context: { smiles: "CC(C)Cc1ccc(cc1)C(C)C(=O)O", drug: "ibuprofen" },
  } as SimulatedUserConfig,

  // ── Cryo-EM ───────────────────────────────────────────────────────────────
  cryoem_spa_standard: {
    goal: "Run CryoSPARC standard single particle analysis on micrographs from EMPIAR-10025",
    persona: "structural biologist",
    domain: "cryo_em",
    initialQuery: "Run standard CryoEM SPA processing on my micrograph dataset. Movies are at s3://biomate-pilot/empiar10025/. K3 detector, 300 kV, 0.53 Å/pixel (super-res), protein complex ~200 Å.",
    context: {
      data_path: "s3://biomate-pilot/empiar10025/",
      detector: "K3",
      voltage: "300 kV",
      apix: "0.53",
      symmetry: "C1",
    },
  } as SimulatedUserConfig,

  cryoem_helical: {
    goal: "Run helical reconstruction for a filamentous protein using CryoSPARC",
    persona: "structural biologist studying cytoskeleton",
    domain: "cryo_em",
    initialQuery: "I have cryo-EM data of an actin filament and want to do helical reconstruction. Micrographs at s3://biomate-pilot/actin_filament/. K2 detector, 200 kV, 1.06 Å/pixel. Helical rise ~27 Å, twist ~-166°.",
    context: {
      data_path: "s3://biomate-pilot/actin_filament/",
      detector: "K2",
      voltage: "200 kV",
      apix: "1.06",
      filament_type: "actin",
      helical_rise: "27.3",
      helical_twist: "-166.0",
    },
  } as SimulatedUserConfig,

  cryoem_focused_refinement: {
    goal: "Run focused refinement on a specific domain of a ribosome complex after standard SPA",
    persona: "structural biochemist",
    domain: "cryo_em",
    initialQuery: "I've done standard SPA on a ribosome complex and want to do focused refinement on the peptidyl transferase center. I have particles at s3://biomate-pilot/ribosome_particles.cs. The PTC mask is at s3://biomate-pilot/ptc_mask.mrc.",
    context: {
      particles_path: "s3://biomate-pilot/ribosome_particles.cs",
      mask_path: "s3://biomate-pilot/ptc_mask.mrc",
      region: "peptidyl transferase center",
    },
  } as SimulatedUserConfig,

  // ── Cryo-ET ───────────────────────────────────────────────────────────────
  cryoet_full_pipeline: {
    goal: "Run a complete cryo-ET pipeline: tilt alignment, tomogram reconstruction, and subtomogram averaging",
    persona: "cell biologist studying organelle structure",
    domain: "cryo_et",
    initialQuery: "I have cryo-ET tilt series data and want to run the full processing pipeline. Tilt series at s3://biomate-pilot/tiltseries/. Titan Krios, ±60° tilt range, 3° increment, 300 kV, 1.35 Å/pixel. Target: mitochondrial ATP synthase complexes.",
    context: {
      tiltseries_path: "s3://biomate-pilot/tiltseries/",
      microscope: "Titan Krios",
      voltage: "300 kV",
      tilt_range: "±60°",
      increment: "3°",
      apix: "1.35",
      target: "ATP synthase",
    },
  } as SimulatedUserConfig,

  cryoet_subtomogram_averaging: {
    goal: "Run subtomogram averaging on pre-extracted ribosomes in a tomogram",
    persona: "structural biologist",
    domain: "cryo_et",
    initialQuery: "I have a tomogram with ribosome positions annotated and want to run subtomogram averaging. Tomogram at s3://biomate-pilot/tomogram.mrc, coordinates at s3://biomate-pilot/ribosome_coords.csv. Target resolution 12 Å.",
    context: {
      tomogram_path: "s3://biomate-pilot/tomogram.mrc",
      coords_path: "s3://biomate-pilot/ribosome_coords.csv",
      target: "ribosome 80S",
      target_resolution: "12",
    },
  } as SimulatedUserConfig,

  cryoet_tilt_alignment: {
    goal: "Align tilt series and reconstruct tomograms using IMOD/AreTomo",
    persona: "cryo-ET practitioner",
    domain: "cryo_et",
    initialQuery: "I need to align my cryo-ET tilt series and reconstruct tomograms. Raw tilt series at s3://biomate-pilot/raw_ts/. 300 kV, ±60°, 3° step, 2.7 Å/pixel (binned 2). Use patch-based alignment.",
    context: {
      tiltseries_path: "s3://biomate-pilot/raw_ts/",
      apix: "2.7",
      alignment_method: "patch-based",
    },
  } as SimulatedUserConfig,

  // ── Genomics (secondary priority) ─────────────────────────────────────────
  rnaseq_human: {
    goal: "Run RNA-seq differential expression analysis on human tumor samples",
    persona: "cancer biologist",
    domain: "genomics",
    initialQuery: "I have RNA-seq data from human tumor vs normal samples and want DEG analysis. Paired-end Illumina reads, hg38 genome.",
    context: { genome: "hg38", accession: "SRR1518169" },
  } as SimulatedUserConfig,

  variant_calling_germline: {
    goal: "Run germline variant calling on WGS data with GATK HaplotypeCaller",
    persona: "clinical genomics researcher",
    domain: "genomics",
    initialQuery: "Run germline variant calling on WGS data from a patient with suspected hereditary disease. Human genome hg38, paired-end WGS.",
    context: { genome: "hg38", accession: "SRR1518169" },
  } as SimulatedUserConfig,

  protein_structure_alphafold: {
    goal: "Predict the 3D structure of a human kinase from FASTA sequence using AlphaFold",
    persona: "structural bioinformatician",
    domain: "structural_biology",
    initialQuery: "Predict the 3D structure of a human DYRK1A kinase using AlphaFold. I have the FASTA sequence ready. Template cutoff 2022-01-01.",
    context: { organism: "Homo sapiens", target: "DYRK1A kinase" },
  } as SimulatedUserConfig,

  // ── Session 7: De Novo Drug Generation ──────────────────────────────────
  de_novo_drug_generation: {
    goal: "Generate novel PD-1 inhibitor molecules de novo using REINVENT4, starting from a known fragment scaffold",
    persona: "medicinal chemist running AI-guided drug discovery",
    domain: "drug_discovery",
    initialQuery: "I want to generate new PD-1 inhibitor candidates de novo using REINVENT4. Starting scaffold SMILES: c1ccc(cc1)c2ccc(cc2)N. Run generative drug design to explore the chemical space around this scaffold, optimizing for drug-likeness (QED > 0.6) and predicted PD-1 binding.",
    context: {
      smiles: "c1ccc(cc1)c2ccc(cc2)N",
      target: "PD-1",
      mode: "de_novo",
      optimization_goal: "QED > 0.6, PD-1 binding affinity",
    },
  } as SimulatedUserConfig,

  // ── Session 7: Cryo-EM Knowledge System Validation ──────────────────────
  cryoem_knowledge_validation: {
    goal: "Validate that CryoSPARC SPA for a GPCR-saposin nanodisc complex triggers the full knowledge system (best practices, QC thresholds, RAG context)",
    persona: "structural biologist studying GPCR signaling",
    domain: "cryo_em",
    initialQuery: "I need to run CryoSPARC single particle analysis for a GPCR-G protein complex. The complex is in a saposin nanodisc. Micrographs at s3://biomate-pilot/gpcr_gprotein/. Titan Krios, 300 kV, 0.83 Å/pixel (the complex is ~250 kDa), C1 symmetry. I need the best pixel size and defocus settings for this MW range.",
    context: {
      data_path: "s3://biomate-pilot/gpcr_gprotein/",
      detector: "Krios",
      voltage: "300 kV",
      apix: "0.83",
      sample_class: "gpcr",
      complex_mw: "250 kDa",
      nanodisc_type: "saposin",
    },
  } as SimulatedUserConfig,
} as const;
