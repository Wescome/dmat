# Commitment arms — `deadline`

Read `README.md` here, `../paradigms.md` and `../deadline.md` first. Protocol: `../bspl/deadline.bspl`. Protocol and interface: those of `hybrid` — `(hasheq)` and `(hasheq 'attest? #t)`.

## Information base

| delivery | fact | coverage |
|---|---|---|
| `(msg DONE a s)` | `DONE`, source V, performance, time `s` (V's clock) | — |
| `(msg ATTEST a t)` | `DONE`, source attester, performance, time `t` (trusted clock) | — |
| `(read-ok 19 (record ot))` | if `ot`: `DONE`, V, performance, time `ot` | V, through `T-READ`, events `DONE` |

## Commitments

- `C_t = C(V, H, ⊤, DONE by DEADLINE)`; consequent kinds `DONE`.
- `C_c = C(V, H, ⊤, DONE by T-EVAL)`; consequent kinds `DONE`.

## Judgments

- `temporal` ← state of `C_t`.
- `completion` ← state of `C_c`.

Debtor's clock: **unreliable** — evaluate with `#:debtor-clock? #f`. V's clock may be skewed, so V's stamps admit nothing.

## Expected cost of the evidential layer

`C_c`'s deadline is the dependency's evaluation instant `T-EVAL` (20), and V's record is complete only through `T-READ` (19). Under E2 the record cannot establish that the service was never completed, so `cupid-e` abstains on `completion` where nothing reports a completion. The hub's `hybrid` arm decides those runs because the family's schedule admits no completion in (19, 20]; the commitment declares no such schedule, since a late completion has no protocol instant.
