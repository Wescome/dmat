# Versions

Every number in a paper or instance comes from a fixed version of the models. Versions are pinned by commit; tags of the same name are created on the repository when the hosting permits.

| Version | Commit | Contents | Used by |
| --- | --- | --- | --- |
| `models-v0.3` | `acf508a` | Eight families, five arms, independent arms, differential check | — |
| `paper-v1` | `ffc271f` | WP-2026-DM-01 first release, arXiv package; models as at this commit (adds `paper-tables.rkt`, `paper-heat.rkt`; numbers identical to `models-v0.3`) | WP-2026-DM-01 |
| `models-v0.4` | `28aaf09` | Adds the commitment arms of instance I-3: `core/cupid.rkt`, BSPL protocols and commitment specs, `cupid` and `cupid-e` in all eight families, independent commitment arms and their adjudication; hub arms and numbers unchanged | I-3 (multiagent systems) |
| `models-v0.4.1` | `2c13ae6` | Adds the enactment harness (phase 3, step 3.4): enactment adapters for the eight families, pipeline, model driver, workflow; makes the agreement commitment arm total on deliveries without an ACCEPT. All v0.4 numbers unchanged | Enactment study (`docs/enactment-analysis-plan.md`) |
