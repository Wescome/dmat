# Family `delegation` — conditional delegation (Flow with responsibility continuity, Temporal)

Read `paradigms.md` first. Grammar and constants: `families/delegation/terms.rkt` (language `DELEGATION`).

## Scenario

A hospital H refers a patient to provider V; V accepts at `T-ACCEPT`. If V lacks capacity it delegates to a subcontractor S at `T-DELEGATE`; S accepts or declines at `T-S-RESPONSE`. Whoever is responsible then initiates care, or fails to. The observer is H.

## Dependencies (claims in this order)

1. `continuity` (Flow) — at no instant between V's acceptance and care initiation (or evaluation, if care never starts) is the obligation owned by nobody.
2. `temporal` (Temporal) — care initiated by `DEADLINE`.

## Constants (terms.rkt)

`T-ACCEPT` 1, `T-DELEGATE` 2, `T-S-RESPONSE` 3, `T-START` 5, `T-RESUME-START` 8, `DEADLINE` 10, `T-READ` 11, `T-EVAL` 12, `STALE-AS-OF` 2, `NOTICE-DELAY` 1, `ATTEST-DELAY` 2.

## Protocol feature `'on-delegate` (decides conduct — the truth depends on it)

- `release` — V's responsibility ends when it delegates. If S accepts, S owns the obligation from `T-S-RESPONSE`; between `T-DELEGATE` and S's response nobody owns it. If S declines, nobody owns it thereafter and nobody initiates care.
- `retain` — V remains responsible until S accepts; if S declines, V's responsibility is reactivated and V itself initiates care at `T-RESUME-START` (8). No ownership gap arises.

## What can happen (fault model)

- V has capacity (initiates care itself at 5) or delegates.
- S accepts (and initiates care at 5) or declines.
- The responsible performer may fail to initiate care at all.
- V's DELEGATED message to H, the START notice and the ATTEST may each be dropped.
- The read-back of V's record may be fresh (as of 11), stale (as of 2), or fail.

## Deliveries (to H, in arrival order)

- `(msg ACCEPT 2 1)` — always.
- `(msg DELEGATED 3 2)` — if V delegated, unless dropped.
- `(msg START (s+1) s)` — the performer's start notice, if the interface has `notice? #t` and care started at `s`; may be dropped. A performer's report.
- `(msg ATTEST (s+2) s)` — independent attestation of care initiation at `s`, if the interface has `attest? #t`; may be dropped.
- `(read-ok 11 view)` or `(read-failed 11)`.

## Views of V's record (as of the read's as-of)

V's state `vs`: `accepted` (before delegating, or with capacity before starting), `delegating` (delegated, S not yet responded), `delegated` (S accepted, not yet started), `released` (delegated under `release`), `resumed` (S declined, V retained, not yet started), `started` (V initiated care), `sub-started` (S initiated care).

- `(last-message lm)` — `START` (care started), `DELEGATED` (in `delegating`, `delegated` or `released`), else `ACCEPT`.
- `(state vs)`.
- `(ledger c1 c2)` — `c1` = C(V, H, accepted, initiate care by DEADLINE): `active`, `pending` (suspended while S's commitment is active), `discharged` (care started), `released` (V released it on delegating). `c2` = C(S, V, delegated, initiate care): `none`, `active`, `declined`, `discharged`.
- `(full vs c1 c2 stage as-of)` — state, both commitments, S's stage as relayed in V's record (`none`, `committed`, `declined`, `started`), and the as-of instant (the record's completeness watermark).

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq 'on-delegate 'release)` | `(hasheq 'notice? #t 'attest? #f 'view 'last-message)` |
| fsm | `(hasheq 'on-delegate 'retain)` | `(hasheq 'notice? #f 'attest? #f 'view 'state)` |
| comm | `(hasheq 'on-delegate 'retain)` | `(hasheq 'notice? #t 'attest? #f 'view 'ledger)` |
| hybrid | `(hasheq 'on-delegate 'retain)` | `(hasheq 'notice? #t 'attest? #t 'view 'full)` |
| hybrid-noe | `(hasheq 'on-delegate 'retain)` | `(hasheq 'notice? #t 'attest? #t 'view 'full)` |

Family symbol: `'delegation`.
