# Family `composition` — multi-organization composition (Temporal, Flow)

Read `paradigms.md` first. Grammar and constants: `families/composition/terms.rkt` (language `COMPOSITION`).

## Scenario

H orders a service from V. V subcontracts the first stage to S, a third organization, then assembles and delivers to H. H has no protocol with S. S self-reports its stage to V — honestly, or prematurely claiming an on-time start — and V's case record can relay what S reported. The observer is H.

## Dependencies (claims in this order)

1. `temporal` (Temporal) — S initiated its stage by `DEADLINE`, in true time.
2. `delivery` (Flow) — V delivered the assembled result (by `T-EVAL`).

## Constants (terms.rkt)

`T-COMMIT` 2, `T-S-ON-TIME` 6, `T-S-LATE` 12, `DEADLINE` 10, `T-DELIVER` 14, `ATTEST-DELAY` 2, `T-READ` 16, `T-EVAL` 17.

## What can happen (fault model)

- S starts on time (6), starts late (12), commits but never starts, or declines.
- S reports honestly, or prematurely reports a start at 6 that did not happen then.
- V assembles and delivers at 14 only if S started (at any time); V may still fail to assemble.
- V's DELIVERED message may be dropped; the ATTEST may be dropped; the read-back may fail.

## Deliveries (to H, in arrival order)

- `(msg DELIVERED 15 14)` — if V delivered; may be dropped.
- `(msg ATTEST (s+2) s)` — independent attestation of S's start at true instant `s`, if the interface has `attest? #t` and S started; may be dropped.
- `(read-ok 16 view)` or `(read-failed 16)` — V's case record.

## Observation models of V's case (interface `'obs`)

- `coarse` → `(case cs)`: `closed` if V delivered, else `open`.
- `staged` → `(staged cs ss ot)`: the case status, S's stage as S reported it to V (`none`, `committed`, `declined`, `started`), and the start instant S reported (`#f` if none).

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq)` | `(hasheq 'obs 'coarse 'attest? #f)` |
| fsm | `(hasheq)` | `(hasheq 'obs 'coarse 'attest? #f)` |
| comm | `(hasheq)` | `(hasheq 'obs 'coarse 'attest? #f)` |
| hybrid | `(hasheq)` | `(hasheq 'obs 'staged 'attest? #t)` |
| hybrid-noe | `(hasheq)` | `(hasheq 'obs 'staged 'attest? #t)` |

Write every judge so it accepts both view forms (the benchmark also runs each arm under the other observation models). Family symbol: `'composition`.
