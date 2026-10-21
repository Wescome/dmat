# Family `replacement` — dynamic participant replacement (Flow with responsibility continuity, Temporal)

Read `paradigms.md` first. Grammar and constants: `families/replacement/terms.rkt` (language `REPLACEMENT`).

## Scenario

V accepts H's order at `T-ACCEPT`. V may withdraw at `T-WITHDRAW`; a replacement provider V2 is then offered the role and accepts or declines at `T-V2`. The responsible party initiates care. A withdrawn V may still emit a stale START from its outbound queue — a *ghost*: a message from a party that is no longer responsible, about care that did not happen. The observer is H.

## Dependencies (claims in this order)

1. `continuity` (Flow) — some party was responsible at every instant from acceptance until care initiation (or evaluation).
2. `temporal` (Temporal) — the responsible party initiated care by `DEADLINE`.

## Constants (terms.rkt)

`T-ACCEPT` 1, `T-WITHDRAW` 3, `T-V2` 5, `T-V-START` 6, `T-V2-START` 8, `T-RESUME` 11, `DEADLINE` 10, `T-READ` 12, `T-EVAL` 13, `STALE-AS-OF` 4, `NOTICE-DELAY` 1, `ATTEST-DELAY` 2.

## Protocol feature `'on-withdraw` (decides conduct — the truth depends on it)

- `release` — V's responsibility ends at withdrawal. If V2 accepts, V2 owns the role from 5 (gap 3–5); if V2 declines, nobody owns it and nobody initiates care.
- `retain` — V stays responsible until V2 accepts; if V2 declines, V resumes and initiates care at `T-RESUME` (11, after the deadline). No ownership gap.

## What can happen (fault model)

- V withdraws or not. If not, V initiates care at 6. If V2 takes over, V2 initiates care at 8.
- V2 accepts or declines.
- The responsible performer may fail to initiate care.
- A withdrawn V may emit a ghost START.
- START notices and the ATTEST may be dropped; the read-back may be fresh (as of 12), stale (as of 4), or fail.

## Deliveries (to H, in arrival order)

- `(msg ACCEPT 2 1)` — always.
- `(msg WITHDRAW 4 3)` — if V withdrew.
- `(msg START (s+1) s who)` — the performer `who` (`V` or `V2`) reports care initiated at `s`; may be dropped.
- `(msg START 7 6 V)` — a ghost, if one was emitted.
- `(msg ATTEST (s+2) s who)` — independent attestation that `who` initiated care at `s`, if the interface has `attest? #t`; may be dropped.
- `(read-ok 12 view)` or `(read-failed 12)` — the role registry.

## Views of the role registry (as of the read's as-of)

The holder is `V` before 3; after a withdrawal and before 5 it is `V` under `retain` and `none` under `release`; from 5 it is `V2` if V2 accepted, otherwise `V` under `retain` and `none` under `release`. `started` is `#t` if the responsible party's care initiation is at or before as-of.

- `(registry holder started)`.
- `(full holder started as-of)` — with the as-of instant (the registry's completeness watermark).

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq 'on-withdraw 'release)` | `(hasheq 'attest? #f 'view 'registry)` |
| fsm | `(hasheq 'on-withdraw 'retain)` | `(hasheq 'attest? #f 'view 'registry)` |
| comm | `(hasheq 'on-withdraw 'retain)` | `(hasheq 'attest? #f 'view 'registry)` |
| hybrid | `(hasheq 'on-withdraw 'retain)` | `(hasheq 'attest? #t 'view 'full)` |
| hybrid-noe | `(hasheq 'on-withdraw 'retain)` | `(hasheq 'attest? #t 'view 'full)` |

Family symbol: `'replacement`.
