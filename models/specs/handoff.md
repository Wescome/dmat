# Family `handoff` — information handoff (Flow, Temporal)

Read `paradigms.md` first: it defines the arm contract and the five paradigms. Grammar and constants: `families/handoff/terms.rkt` (language `HANDOFF`).

## Scenario

A hospital H refers a patient to a home-care provider V at instant 0. V may accept the referral and is then expected to initiate care. The observer is H.

## Dependencies (claims in this order)

1. `flow` (Flow) — responsibility passed to V in time: V accepted the referral by `ACCEPT-DEADLINE` (3). Violated if V accepted late or never.
2. `temporal` (Temporal) — care was actually initiated by `DEADLINE` (10). (When care starts it starts at `T-START` = 5.)

## Constants (terms.rkt)

`T-ON-TIME` 1, `T-LATE` 4, `ACCEPT-DEADLINE` 3, `FAST` 1, `SLOW` 4, `T-START` 5, `T-NOTICE` 6, `T-ATTEST` 7, `DEADLINE` 10, `T-READ` 11, `T-EVAL` 12, `STALE-AS-OF` 0, `LAG-WATERMARK` 3.

## What can happen (fault model)

- V accepts on time (at 1), late (at 4), or never.
- An accepted V may initiate care at 5, or not; it may crash after accepting (then it neither starts nor reports anything further).
- An accepted, non-crashed V that did not start may still *report* a start (a premature report).
- V's ACCEPT reply may be delivered, dropped, or duplicated; its transit is fast (1) or slow (4).
- Optional messages (START notice, ATTEST) may be dropped.
- The read-back of V's record at 11 may be fresh (complete as of 11), stale (as of 0), or fail.
- V's record may lag: under lag a reported start is never recorded before evaluation, and the record is complete only through instant 3.

## Deliveries (to H, in arrival order)

- `(msg ACCEPT a t)` — if V accepted at `t`; `a = t + 1` (fast) or `t + 4` (slow). Absent if dropped; twice if duplicated.
- `(msg START 6 5)` — V's start notice, only if the interface has `notice? #t` and V reported a start (actual or premature); may be dropped. This is V's report.
- `(msg ATTEST 7 5)` — an independent attester's confirmation that care was initiated at 5, only if the interface has `attest? #t` and care actually started; may be dropped.
- `(read-ok 11 view)` or `(read-failed 11)` — the read-back of V's record (view kind per interface).

## Views of V's record (as of the read's as-of instant)

The record contains V's acceptance (at its instant, once as-of has reached it) and V's *reported* start (recorded at 5, or never under lag).

- `(last-message lm)` — the last message V's session log shows: `(START 5)`, `(ACCEPT t)`, or `none`.
- `(state S)` — V's protocol state: `started`, `accepted`, or `referred`.
- `(ledger c0 c1)` — V's commitments to H. `c0` = C(V, H, referred, accept by ACCEPT-DEADLINE): `none` (no acceptance recorded), `discharged` (accepted by 3), `late-discharged` (accepted after 3). `c1` = C(V, H, accepted, initiate care by DEADLINE): `none`, `detached` (accepted, no start recorded), `discharged` (start recorded).
- `(full S oat ost c0 c1 wm)` — the state, the recorded acceptance instant (`#f` if none), the recorded start instant (`#f` if none), both commitments, and `wm`, the instant through which the record is complete (as-of, or at most 3 under lag).

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq)` | `(hasheq 'notice? #t 'attest? #f 'view 'last-message)` |
| fsm | `(hasheq)` | `(hasheq 'notice? #f 'attest? #f 'view 'state)` |
| comm | `(hasheq)` | `(hasheq 'notice? #t 'attest? #f 'view 'ledger)` |
| hybrid | `(hasheq)` | `(hasheq 'notice? #t 'attest? #t 'view 'full)` |
| hybrid-noe | `(hasheq)` | `(hasheq 'notice? #t 'attest? #t 'view 'full)` |

Family symbol: `'handoff`.
