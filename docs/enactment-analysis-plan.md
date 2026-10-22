---
id: DMAT-I3-ENACT-PLAN-2026-10
title: Enactment study — analysis plan (fixed before any model run)
date: 2026-10-21
status: fixed; changes after the first model run are recorded in §8 with their date and reason
parent: docs/brief-mas-instance.md (phase 3, step 3.4); models/specs/enactment.md
---

# Enactment study — analysis plan

This plan is fixed before any language-model run. The specification of the runs is `models/specs/enactment.md`; the code is `models/enact.rkt`, `models/families/<family>/enact.rkt` and `models/harness/run.py`, at models v0.4 plus the enactment harness.

## 1. Questions

- **Q1.** Do agents enacting the information protocols send messages the protocol and their conduct do not warrant — reports of performances they did not perform, acts they did not take, or the right messages with the wrong instants or parameters — and do they omit messages the protocol calls for?
- **Q2.** Is the evidential commitment judge (`cupid-e`) still sound on deliveries produced by agents, and when it is not, which party's message is responsible?
- **Q3.** Is an agent playing the observer sound, and do commitments and the evidential rules, given as instructions, make it sounder?

## 2. Design

- Families: all eight. Profiles: `reliable` and `adversarial` of each. Seeds 0–49 per (family, profile), drawn by the keyed draw of `core/family.rkt`. Repetitions: 3 per seed and model. That is 2,400 enacted runs per model.
- Models (decision M2, as recommended): one Anthropic model, one OpenAI model, one open-weights model, each the provider's most capable generally available model at the run date, resolved and recorded by identifier. One model plays every role in a run, and the observer conditions use the same model.
- Sampling: temperature 1.0, at most 2,048 output tokens per call, no system-prompt variation, no retries on content (retries only on transport errors).
- Observer conditions: `role`, `commitments`, `evidential` (specification §7), all on the same enacted deliveries.

## 3. Hypotheses

- **H-E1 (party conduct).** In at least one family, party agents produce fabricated performance reports at a rate above zero. Families with a premature-report or crash fault (handoff, external, composition) are where we expect them. *Measure:* fabricated reports per run, per (model, family, profile), with a 95% interval from a bootstrap over runs (10,000 resamples, seeds as the resampling unit, repetitions kept together).
- **H-E2 (evidential judge under enactment).** Every false claim `cupid-e` makes on enacted deliveries traces to a fabricated or altered message from a party independent of the commitment's debtor (the attester A, the resource R, the external executor X); fabrications by debtor-side parties cause none, because E1 discounts them. *Measure:* the attribution table of `enact.rkt score`. The hypothesis fails if any `cupid-e` false claim is attributed to a debtor-side party or to no party failure.
- **H-E3 (observer agents).** The observer agent under `role` is unsafe (SFR > 0) in at least one family, and `evidential` is sounder than `role`: fewer runs unsafe under `evidential` and not `role` than the reverse. *Test:* exact two-sided sign test on the discordant runs, per (model, family), Holm–Bonferroni across the eight families of each model, α = 0.05.
- **H-E4 (cost of the rules).** `evidential` lowers coverage relative to `role`. *Measure:* coverage per condition with its spread across repetitions; reported, not tested.

- **H-E5 (purchasing agent).** In the family `purchase`, a language-model purchasing agent leaves at least one dependency in fact failed in some runs of the `adversarial` profile (operational inadequacy: for example a second hold after a stale record read as current), and its claims under `role` include false ones; under `evidential` its SFR is lower. *Test:* exact two-sided sign test on runs paired by (seed, repetition) between `role` and `evidential`, per model, α = 0.05; the failed-dependency share is reported, not tested. Added 2026-10-22, before any model run (§8).

## 4. Classification and metrics

As in specification §8–§9: for enacted deliveries equal to the coded deliveries of the run's world, the full claim classes (supported, lucky, false, abstained-ok, abstained-miss); otherwise correct, false or abstained. SFR (share of runs with a false claim), FCR (false or unsupported Fulfilled claims over Fulfilled claims), coverage. Party failures: fabricated report, fabricated act, omitted message, parameter error, malformed.

## 5. Exclusions and missing data

- A model call that fails after six transport attempts yields no response; the role is treated as having sent nothing and its run is flagged. Runs with any failed call are reported in a separate count and excluded from H-E1–H-E3; if they exceed 2% of a model's runs, the run is repeated for those seeds before analysis.
- Malformed outputs are not excluded: they are a measured outcome (specification §4, §7).

## 6. Pilot

Before the full runs: `handoff`, both profiles, seeds 0–4, one repetition, one model. The pilot checks prompts, parsing and cost. Its results are not part of the analysis. A change to prompts after the pilot is allowed and recorded in §8; after the first full run, prompts are frozen.

## 7. Outputs

`enactment.txt` (the report), `results.jsonl` (one line per run, judge and repetition), and the raw call logs (`parties.jsonl`, `claims.jsonl`), committed under `models/enactment/runs/<run-id>/`. Tables for the paper are generated from `results.jsonl`.

## 8. Changes

- 2026-10-22, before any model run: H-E5 and the purchasing-agent runs added with step 3.7 (the family `purchase`). The design, models, sampling and exclusions of §2–§5 apply to them; determinacy is not defined for an agent arm, so its claims are classified correct, false or abstained.
