# Family `deadline` — deadline-bound service (Temporal, Flow)

Read `paradigms.md` first. Grammar and constants: `families/deadline/terms.rkt` (language `DEADLINE-SERVICE`).

## Scenario

A provider V owes a service to H by `DEADLINE`. V reports completion with a DONE message stamped by V's own clock; the report's transit may be short or long, and V's clock may run ahead or behind true time. Protocols that define it also receive an attestation from a trusted third party, stamped with the true completion instant. The observer is H.

## Dependencies (claims in this order)

1. `temporal` (Temporal) — the service was completed by `DEADLINE`, in true time.
2. `completion` (Flow) — the service was completed at all (by `T-EVAL`).

## Constants (terms.rkt)

`T-ON-TIME` 8, `T-LATE` 12, `DEADLINE` 10, `SHORT` 1, `LONG` 5, `SKEW` 3, `ATTEST-DELAY` 2, `T-READ` 19, `T-EVAL` 20.

## What can happen (fault model)

- V completes on time (true instant 8), late (12), or never.
- DONE's transit is 1 or 5.
- V's clock is correct, 3 ahead, or 3 behind; every stamp V produces (in DONE and in its record) is the true instant plus that skew.
- The ATTEST may be dropped.
- The read-back of V's record may fail.

## Deliveries (to H, in arrival order)

- `(msg DONE (c + transit) (c + skew))` — if V completed at true instant `c`. Its asserted instant is V's stamp.
- `(msg ATTEST (c + 2) c)` — if the interface has `attest? #t` and V completed; may be dropped. Asserted instant is the trusted stamp.
- `(read-ok 19 (record ot))` or `(read-failed 19)` — V's completion record: `ot` is V's stamp of completion, or `#f` if V never completed.

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq)` | `(hasheq 'attest? #f)` |
| fsm | `(hasheq)` | `(hasheq 'attest? #f)` |
| comm | `(hasheq)` | `(hasheq 'attest? #f)` |
| hybrid | `(hasheq)` | `(hasheq 'attest? #t)` |
| hybrid-noe | `(hasheq)` | `(hasheq 'attest? #t)` |

Family symbol: `'deadline`.
