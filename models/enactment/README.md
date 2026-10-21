# Enactment runs

Requests and outputs of the enactment study (`../specs/enactment.md`, analysis plan `../../docs/enactment-analysis-plan.md`).

- `requests/<id>.json` — pushing a request here runs it (`.github/workflows/enactment.yml`); the outputs are committed to `runs/<id>/`.
- `queued/` — requests prepared and not yet run, in the order of the analysis plan: `pilot.json` (handoff, 5 seeds, one model), then `full-anthropic.json`, `full-openai.json`, `full-openweights.json` (all families, both profiles, 50 seeds, 3 repetitions; one model each, so each fits one workflow run).
- `runs/<id>/` — `enactment.txt` (the report), `results.jsonl` (one line per run, judge and repetition), `status.json`, `pipeline.log`, and the compressed plan, call logs and assembled deliveries.

Model identifiers given as `auto:NAME|NAME...` are resolved against the provider's model list when the run starts; the resolved identifier is recorded with every call.

Local run of the same pipeline: `harness/pipeline.sh requests/<id>.json OUTDIR` from `models/`, with the provider keys in the environment. `test-mock.json` exercises everything without model calls.
