# Commitment arms — `purchase`

Read `README.md` here, `../paradigms.md` and `../purchase.md` first. Both arms judge the transcript of the `hybrid` mechanism (protocol `(hasheq 'mechanism 'hybrid)`, interface `(hasheq 'watermark #t)`).

## Information base

| delivery | fact | coverage |
| --- | --- | --- |
| `authorize S a k` answered `(ok AUTHORIZED)` | `HELD S`, source X, act, time `n` | — |
| `void S k` answered `(ok VOIDED)` | `RELEASED S`, X, act | — |
| `capture S k` answered `(ok CAPTURED)` | `CHARGED S`, X, act, time `n` | — |
| `refund S k` answered `(ok REFUNDED)` | `REFUNDED S`, X, act, time `n` | — |
| `deliver S k` answered `(ok (at t))` | `DELIVERED`, source the seller S, performance, time `t`, attrs `(S)` | — |
| `carrier-scan` answered `(ok (at t))` | `DELIVERED`, source carrier, performance, time `t` | carrier, through `T-LATE`, events `DELIVERED` |
| `carrier-scan` answered `(ok (at none))` | — | carrier, through `T-LATE`, events `DELIVERED` |

The carrier's record is its whole record of the parcel: when read, it is complete through `T-LATE`, the last instant a delivery can happen.

The hold states for `funds` and `fit` are read as `hybrid`'s judge reads them (`../purchase.md` §9, `families/purchase/arms.rkt`): replies to the processor's acts establish the state they report; a payment record establishes a seller's hold only when its completeness point covers the last payment call to that seller (`cupid-e`), or always (`cupid`, closed world).

## Commitments

- `C_S = C(S, P, CHARGED S by T-LATE, DELIVERED by DEADLINE)` for the seller `S` charged last; antecedent kinds `CHARGED`, consequent kinds `DELIVERED`. Every instant of the transcript's calls precedes `T-LATE`, so a charge reply always detaches by its deadline.

## Judgments

- `funds`, `fit`: as `hybrid`'s judge, with the reading above.
- `temporal` ← state of `C_S`: discharged → Fulfilled; violated → Violated; expired (nothing was charged, so nothing was delivered) → Violated; unknown → Indeterminate. With no charge in the transcript, `temporal` is Violated (the arm's own acts show that nothing was bought).
- `flow`: Fulfilled when no seller's charge stands (every `CHARGED S` is followed by `REFUNDED S`); otherwise ← `C_S`'s consequent status: delivered at any instant (held or late) → Fulfilled; absent → Violated; unknown → Indeterminate.

Debtor's clock: reliable (default). The seller's delivery report is the debtor's report of its own performance (E1).
