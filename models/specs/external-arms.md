# External arms

An external arm is a mechanism that is not written in the models: a product, or any program in any language, that acts in an interactive family's world (today: `purchase.md`) through the family's provider interface. The models run it as a separate process, answer its calls from the world, and record its transcript. The arm never sees the world, its slots, the truth or the judge.

## 1. Process protocol

The runner starts the arm's command once per world and exchanges JSON lines over the arm's standard input and output (one JSON object per line, UTF-8). Standard error is the arm's own log and is kept with the run.

1. Runner → arm, once:

       {"type": "start", "family": "purchase", "run": RUN-ID,
        "principal": {"cap": CAP}, "primary": {"seller": "A", "price": PRICE-A},
        "interface": {"watermark": true}}

2. Arm → runner, any number of times, one at a time:

       {"type": "call", "op": OP, "args": {...}}

   `args` per operation (`purchase.md` §3): `seller` ("A" | "B"), `amount` (a number), `key` (a string). Operations without arguments send `{}`.

3. Runner → arm, after each call:

       {"type": "reply", "seq": N, "ok": true, "value": VALUE}
       {"type": "reply", "seq": N, "ok": false, "failure": CLASS, "code": CODE}

   `N` is the call's sequence number. Values (JSON forms of `purchase.md` §3): state names and codes as strings; `alternatives` as `[{"seller": "B", "price": P}]`; `payment-record` as `{"complete_through": C, "holds": [{"seller": S, "state": T, "amount": A}]}` with `complete_through` `null` when the interface has no watermark; `reconcile` as `{"payment": RECORD, "orders": {"A": T, "B": T}, "shipment": T, "charges": K}`; `deliver` and `carrier-scan` as `{"delivered_at": T}` (`null` for none).

4. Arm → runner, once, to end the run:

       {"type": "end",
        "claims": [{"dependency": D, "judgment": J, "cites": [N, ...]}, ...],
        "result": ANY}

   One claim per dependency of the family, `J` ∈ {`Fulfilled`, `Violated`, `Indeterminate`}, cites as call sequence numbers. `result` is the mechanism's own account of its ending (free form); it is stored with the run and not judged.

The runner stops an arm that exceeds `CALL-LIMIT` calls, sends malformed JSON, names an unknown operation, or does not answer within 60 seconds per message; such a run ends with every claim `Indeterminate` and is reported with its cause.

## 2. The arm's claims

An external arm's claims are what the mechanism itself establishes at its end, stated in the family's dependency vocabulary by a **claim mapping** that is part of the arm. A claim is `Fulfilled` when the mechanism's final state asserts that the dependency holds, `Violated` when it asserts that it does not, and `Indeterminate` when the mechanism records the matter as unresolved or does not speak to it. The mapping reads only the mechanism's own state; it does not consult the world, and it is written before any result is seen.

## 3. Deliveries, determinacy and caching

The transcript is the arm's deliveries (`purchase.md` §8). A mechanism is deterministic given its replies, so its claims are a function of its transcript. The runner checks this: two worlds that give the same transcript must give the same claims, or the arm is reported nondeterministic.

Runs are cached in `families/purchase/external/<arm>.rktd`: for every world of every profile, the transcript, the claims and the `result`, with the arm's source revision. The judge reads the cache, so the benchmark can be scored without the product present. When the product is present (`DMBENCH_ARM_<NAME>` names its command), the runner reruns it and the tests require the cache to be reproduced exactly.

## 4. Independence

An external arm's bridge (the code that maps the provider interface onto the mechanism's own ports, and the claim mapping) is written from this file and `purchase.md` alone, by an author who sees neither the world, the judge, the reference arms nor any result. The mechanism itself is the product as its developers wrote it, at a pinned revision. Where the bridge's author finds the specification silent or wrong, the question is recorded and adjudicated as for every family (`adjudication.md`).
