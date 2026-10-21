# Commitment arms — `handoff`

Read `README.md` here, `../paradigms.md` and `../handoff.md` first. Protocol: `../bspl/handoff.bspl`. Protocol and interface: those of `hybrid` — `(hasheq)` and `(hasheq 'notice? #t 'attest? #t 'view 'full)`.

## Information base

| delivery | fact | coverage |
|---|---|---|
| `(msg ACCEPT a t)` | `ACCEPT`, source V, act, time `t` | — |
| `(msg START a t)` | `START`, source V, performance, time `t` | — |
| `(msg ATTEST a t)` | `START`, source attester, performance, time `t` | — |
| `(read-ok 11 (full S oat ost c0 c1 wm))` | if `oat`: `ACCEPT`, V, act, time `oat`; if `ost`: `START`, V, performance, time `ost` | V, through `wm`, events `ACCEPT START` |

## Commitments

- `C0 = C(V, H, ⊤, ACCEPT by ACCEPT-DEADLINE)`; consequent kinds `ACCEPT`.
- `C1 = C(V, H, ACCEPT by DEADLINE, START by DEADLINE)`; antecedent kinds `ACCEPT`, consequent kinds `START`.

## Judgments

- `flow` ← state of `C0` (expired cannot occur).
- `temporal` ← state of `C1`; expired means V never accepted, so care was never initiated: **Violated**.

Debtor's clock: reliable (default).
