# Commitment arms — `replacement`

Read `README.md` here, `../paradigms.md` and `../replacement.md` first. Protocol: `../bspl/replacement.bspl`. Protocol and interface: those of `hybrid` — `(hasheq 'on-withdraw 'retain)` and `(hasheq 'attest? #t 'view 'full)`. V retains the role until V2 accepts, and resumes it if V2 declines.

## Responsibility at an instant

Let `holder` and `as-of` come from the read `(read-ok 12 (full holder started as-of))`, if any; the registry speaks for the holder after `T-V2` when it is authoritative there: in `cupid-e` if `as-of ≥ T-V2`, in `cupid` for any read. A START or ATTEST naming performer `who` at instant `t` is from the responsible party if

- `who = V2` and `t ≥ T-V2`; or
- `who = V` and any of: no `WITHDRAW` was delivered; `t < T-V2`; the registry, authoritative after `T-V2`, shows `holder = V`; `t ≥ T-RESUME`.

## Information base

| delivery | fact | coverage |
|---|---|---|
| `(msg START a t who)`, from the responsible party | `START`, source `role` (the role holder's report of its own performance), performance, time `t`, attrs `(who)` | — |
| `(msg ATTEST a t who)`, from the responsible party | `START`, source attester, performance, time `t`, attrs `(who)` | — |
| `(read-ok 12 (full holder started as-of))` with `started = #f` | — | registry, through `as-of`, events `START` |

A registry showing `started = #t` reports the event and yields no coverage. Its `started` flag is untimed and yields no fact: a query for START by the deadline needs an instant. Messages from a party not responsible at their instant (a withdrawn V's ghost START) yield nothing.

## Commitments

- `C = C(role, H, ⊤, START by DEADLINE)`; kinds `START`. The debtor is the role.

## Judgments

- `continuity`: Violated if a read shows `holder = none` (cite it); otherwise Fulfilled (cite the ACCEPT, and the read when authoritative after `T-V2`).
- `temporal`: discharged → Fulfilled, violated → Violated (cite the state's citations); otherwise, if a `WITHDRAW` was delivered and the registry, authoritative after `T-V2`, shows `holder = V`, V resumes the role and the protocol schedules care at `T-RESUME`, after the deadline: Violated (cite the read and the WITHDRAW); otherwise Indeterminate.

Debtor's clock: reliable (default).
