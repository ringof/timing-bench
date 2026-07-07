# timing-bench — working agreement (CLAUDE.md)

These instructions OVERRIDE default behavior and must be followed exactly.
This is a **hardware bench bringup**: a physical ZED-F9T-20B and a host machine
are driven by the user, one step at a time. Claude runs in a remote container
and **cannot see or touch the hardware** — it proposes; the user executes and
reports back the actual output. Nothing advances on prediction; it advances on
observed results.

## Working Cadence (step-by-step)

- Work **one step at a time.** Propose a single next action — one command, or
  one question — then STOP and wait for the user's real output before deciding
  the next step. Do not chain multiple steps in one turn.
- An approved plan is **not** a license to execute its steps back-to-back. The
  plan sets direction; each step is still gated on the observed result of the
  previous one.
- Never assume the outcome of a step you have not seen run. Look at the actual
  output the user pastes back, then reason from it.
- If you find yourself about to say "next, do X and then Y and then Z" —
  stop. Hand over X only.
- Prefer the smallest diagnostic that moves us forward over the most thorough
  one. We are building a reliable basis, not racing to a result.

## Code Authoring Policy

- **Do not write, edit, or scaffold code until we have explicitly agreed that
  writing that specific code is the current step.** Authorization to
  investigate, plan, or debug is NOT authorization to write code.
- This gate is on *authoring* (Write/Edit of any file in the tree), not just on
  committing. Uncommitted code written ahead of agreement is exactly the
  "jumping ahead" this repo is trying to prevent.
- Empirical validation comes before patches. Do not write code whose
  justification rests on un-tested theory (see Hypothesis Validation Policy).
- Treat the existing stubs, docs, and TODOs in this repo as **unvalidated
  guesses**, not ground truth, until hardware confirms them. Do not build on a
  stub as if it were known-correct.

## Hypothesis Validation Policy

- Before proposing a patch or claiming a root cause, state the hypothesis
  as falsifiable: "X is the cause; if so, Y would change."
- If the falsifier (Y) can be tested without committing or building,
  test it FIRST and report the result. Do not propose code changes
  whose justification rests on un-tested theory.
- When an existing empirical observation contradicts a new theory
  (e.g., "manual works, harness fails" vs "the avahi bounce is the
  cause"), the existing observation wins until the new theory directly
  explains it.
- Do not generalize a negative across surfaces. "Docker-exec polling
  didn't slow setup" does NOT rule out "docker exec sh -c invocation
  affects the spawned process" — different mechanisms, different evidence.
- Do not call fixes "decisive" or "this'll do it" before validation.
  Predictions are noise; results are signal.

## Claims of Fact / System State

- Do not assert that a hardware or system state has been achieved unless the
  observed output shows it. "The F9T is in timing mode," "survey-in is
  complete," "UBX-TIM-TP is enabled," "the PPS is present" are **claims of
  fact** — each requires a specific observation, not an inference from a
  command having been sent.
- Distinguish clearly between: (a) what we asked the device to do, (b) what a
  command returned, and (c) what we have actually confirmed to be true. Only
  (c) may be stated as fact.
- "The command ran without error" is not "the thing is configured." Name the
  concrete evidence that would confirm the state, and get it before claiming it.
- When state is unconfirmed, say so plainly and propose the check that would
  confirm it.

## Bench / Container Debugging

- Do not hand over one-off scripts for manual investigation unless asked.
  Single diagnostic commands the user has asked for are fine; multi-step
  scripts that hide steps from view are not — they defeat the step-by-step
  cadence.
- Because Claude cannot touch the hardware, every hardware fact enters the
  session through output the user pastes back. Do not fill gaps with assumed
  device behavior; ask for the reading.

## Commit and Push Policy

- **Always ask before committing and pushing.** Never commit or push without explicit user approval.

## Git Branch Discipline

**Do not create new git branches unless I have explicitly told you to
create that specific branch.** Authorization to do work is NOT
authorization to make a branch.

- When making any change, use the currently checked-out branch. Do not
  `git checkout -b`, `git branch`, or otherwise create a new branch
  without my explicit instruction naming it.
- Conceptual "scope cleanliness" is not a reason for a new branch.
  Commits manage scope; branches do not. An 8-line fix unrelated to
  the current branch's purpose still goes on the current branch unless
  I say otherwise.
- If I have told you to keep a specific branch focused on one topic,
  that means "don't open a PR with mixed scope," NOT "spawn a new
  branch for anything else that comes up." Carry the unrelated work
  on the same branch as separate commits, or ASK.
- If you genuinely think a change should land somewhere other than
  the current branch, ASK. Do not preemptively create or switch
  branches and present the result as a fait accompli.
- This applies recursively: if you've already created an unauthorized
  branch, do not propose moving the work to *another* new branch.
  Move it to a branch that already exists, or ask.

## Planning Policy

- For tasks that generate multiple needs or planned changes, **write a plan first** and add it to a document (e.g., `PLAN.md` or a specifically named Markdown file) before beginning implementation.
- Get user approval on the plan before proceeding with changes.
- An approved plan still executes under the Working Cadence above: one step at
  a time, each gated on the previous step's observed result.

## Change Documentation Requirements

Before any approved commit, provide the user — in the chat — with a **copy-pastable block** containing all of the following:

1. **Detailed description of the change** — what was changed and why.
2. **Build/update instructions** — how to build or update after applying the change. If the process is identical to the documented build instructions, state that explicitly. If it differs, provide the exact steps.
3. **Validation test** — a concrete procedure to demonstrate the change works as intended. If a runtime validation test is not feasible, provide a clear rationale explaining why code inspection is sufficient.
4. **Regression test** — a procedure or set of checks demonstrating that other functions of the code remain unaffected by the change.

## Issue Filing Policy

- **Always audit the codebase before filing issues.** Issue descriptions must be derived from actual findings, not speculation about what might be wrong.
- Never assume a problem exists — verify it with concrete evidence (grep, file reads, build output) before writing it up.

## GitHub Issues from Plans

- When a plan contains many changes/tasks, offer to generate a **run-once shell script** that uses the local `gh` CLI to populate each planned task as a GitHub issue in the repository.
- The script should be self-contained, idempotent where practical, and use `gh issue create` with appropriate titles, bodies, and labels derived from the plan document.
