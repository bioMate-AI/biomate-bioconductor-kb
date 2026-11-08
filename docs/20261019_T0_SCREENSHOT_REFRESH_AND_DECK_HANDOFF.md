# t0 "Getting started" — screenshot refresh + deck handoff (2026-10-19)

Response to review feedback: t0 is stale — wrong/old screenshots, a removed
feature still narrated ("see how it's handled"), no concrete query→answer, and
5 of 9 scenes are concept-only redundancy. The staleness is on the capture/
content pipeline, not on the design pass. This doc tracks **what changed in the
product**, **what I revised**, and **what Claude Code must update on top of
design's restructured version**.

## 1. What changed in the product since t0's screenshots (tracked)
- `7c32387a2` cold-start **double-composer removed** — the cold start is now the
  heading + 4 cards with ONE pinned bottom composer (old `t0-composer` predates this).
- `2c14b2d6f` / `4651754e2` / `5892a01f2` chat progress simplified, citations
  grounded, routing-stage progress — the **"see how it's handled" pre-send preview
  was removed**; the current affordance is the composer's **route/lane preview**
  (`lane-preview`), shown live as you type.
- `b4cef6dd5` / `d0bc47f01` cold-start chrome localized (EN+ZH).
- Label drift: the design module card is **"Molecule design & generate"** in ZH
  (分子设计与生成) but was never updated in EN — fixed this session (EN now matches).
- `6fcdee0b0` manual screenshots regenerated against dev — but the **t0 deck was
  never refreshed from that pass**.

## 2. What I revised (my responsibility)
- **Code:** EN label `Molecule design & generate` (common.json `mod_design_name`
  + `design_generate`; dashboard MODULES `k`) — matches ZH. (committed; synced to dev)
- **Screenshots** — fresh, real, end-to-end, into
  `reference/claude_design/tutorials_handoff/assets/live/` via
  `frontend/e2e/t0-getting-started-capture.e2e.ts` (tight element/clip crops, no
  full-page, sidebar never in frame, DPR 2):
  - `t0-coldstart.png` — real cold start: heading + 4 cards incl. corrected label
  - `t0-composer.png` — the pinned composer with the goal typed
  - `t0-lane.png` — the live **route/lane preview** (replaces "see how it's handled")
  - `t0-answer.png` — the **real cited evidence answer** (was entirely missing)

## 3. What Claude Code must update after design returns the restructured deck
Apply these on top of design's version (design handles layout/merge; these are
content/asset corrections only design cannot know):

| Scene (old) | Problem | Fix |
|---|---|---|
| 2, 4, 5 | concept-only, no screenshot → redundant | merge into ONE "how it works" slide |
| 3 | caption "cold start / intent bar" but shows `s1-1-sidebar.png` (a SIDEBAR) | use `t0-coldstart.png` |
| 6 | stale composer shot (pre double-composer fix) | use refreshed `t0-composer.png` |
| 7 | title "**see how it's handled** before you send" — removed feature | reword to "see the detected route"; use `t0-lane.png` |
| 8 | describes the cited answer but has **no image** | add `t0-answer.png` (the real answer) |
| 9 | recap says "**see how it's handled**" | reword: "type → see the route → review → send → read the result" |
| any | names "Design & generate" | → "Molecule design & generate" |

Net: 9 scenes → ~5 (title · how-it-works · cold start+cards · type+route · answer),
each carrying a real screenshot, with a concrete query ("What is the evidence
linking JAK1 to rheumatoid arthritis?") AND its real cited answer.

## 4. Sidebar redundant-chats check
Fixture `lifeifei163361@163.com` has only **2 chat sessions** (clean at the chat
level). The sidebar clutter is the fixture's **project list** (many E2E/committee
projects); every t0 capture crops the sidebar out, so no deck shot shows it. If a
future nav tutorial must show the sidebar, the fixture's project list needs a
cleanup pass first (separate task).

## 5. Status
Label synced to dev; re-capture runs against dev once the sync lands healthy
(local dev is down, so dev is the only live target). Screenshot filenames above
are the committed asset slots the deck references (`../assets/live/…`).
