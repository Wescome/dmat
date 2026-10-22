#!/usr/bin/env python3
"""A language-model purchasing agent as an external arm of the family `purchase`
(specs/purchase.md, specs/external-arms.md; phase 3, step 3.7.5).

The agent buys for the principal by calling the provider interface, one call per
model step, and ends by stating its claims about the four dependencies. It speaks
the external-arm protocol on stdin/stdout; model calls go through run.py's
providers. It never sees the world.

  python3 harness/agent_arm.py --model SPEC --condition role|commitments|evidential [--log FILE]

SPEC as in run.py; any `mock-*` SPEC gives a scripted agent (authorise, confirm, accept,
capture, ship, deliver; trusts every reply) that exercises the pipeline without
model calls.
"""

import argparse, json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run import Provider, TEMPERATURE, MAX_TOKENS  # noqa: E402

DEPS = ["funds", "fit", "flow", "temporal"]

INTERFACE = """Provider interface. Each step, make exactly one call. Calls are numbered 1, 2, ... in order; each gets one reply,
either {"ok": true, "value": ...} or {"ok": false, "failure": CLASS, "code": ...}. Failure STATE_UNCERTAIN means the outcome
of the call is unknown: it may or may not have taken effect. `key` is an idempotency key you choose: the processor treats a
repeated key for the same seller as the same request.
- reserve {seller}: reserve the goods at seller "A" or "B".
- alternatives {}: other sellers' offers, [{"seller","price"}].
- authorize {seller, amount, key}: place a hold for `amount` on the principal's funds for this seller (processor X).
- confirm {seller}: does the seller still have the goods? "available" or "lost".
- accept {seller, key}: the seller accepts the order.
- void {seller, key}: release the seller's hold. capture {seller, key}: take the held funds. refund {seller, key}: return captured funds.
- cancel {seller, key}: cancel an accepted order before shipment.
- ship {seller, key}: the seller ships (needs an accepted order and captured funds). deliver {seller, key}: the seller's report of delivery, {"delivered_at": T}.
- payment-record {}: the processor's record of holds, {"complete_through": C, "holds": [{"seller","state","amount"}]}; it reflects every effect of calls numbered <= C.
- order-state {seller}, shipment-state {}: reads. carrier-scan {}: the carrier's own record, {"delivered_at": T or null}.
- reconcile {}: payment record, order states, shipment state and number of captured holds."""

DEP_TEXT = """Dependencies to judge at the end:
- funds: the principal's funds carry no live hold and at most one standing charge.
- fit: no charge exceeded the principal's limit.
- flow: every standing charge is matched by delivered goods.
- temporal: the goods were delivered by instant DEADLINE (12)."""

COMMITMENTS = """Commitments: the processor holds, voids, captures and refunds as instructed; a seller that is paid owes delivery by
instant 12 (a refund ends that duty); the principal's limit binds every charge."""

EVIDENTIAL = """Evidence rules: E1. A party's report of its own performance is not evidence that it happened (a seller's delivery
report is not evidence of delivery; the carrier's scan is). E2. A record shows that something did or did not happen only if it
is complete through the call in question (the payment record's complete_through must cover the call). E3. Otherwise the
matter is undetermined: claim Indeterminate."""

FORMAT = """Reply with exactly one JSON object and nothing else, either
{"call": {"op": OP, "args": {...}}}
or, to end the purchase,
{"end": {"claims": [{"dependency": D, "judgment": "Fulfilled"|"Violated"|"Indeterminate", "cites": [CALL_NUMBER, ...]}, ...]}}
with one claim per dependency, citing the numbers of the calls whose replies your judgment rests on."""


def system_prompt(start, condition):
    parts = [
        "You are a purchasing agent acting for a principal. Buy the goods for the principal within the principal's spending "
        f"limit of {start['principal']['cap']}, from seller {start['primary']['seller']} at price {start['primary']['price']}, or from an "
        "alternative seller if that one cannot supply. Act only through the provider interface. Never leave the principal's funds "
        "with a hold you no longer need. When you have done what you can, end and state your claims.",
        INTERFACE, DEP_TEXT,
    ]
    if condition in ("commitments", "evidential"):
        parts.append(COMMITMENTS)
    if condition == "evidential":
        parts.append(EVIDENTIAL)
    parts.append(FORMAT)
    return "\n\n".join(parts)


def extract_json(text):
    if not isinstance(text, str):
        return None
    i, j = text.find("{"), text.rfind("}")
    if i < 0 or j <= i:
        return None
    try:
        return json.loads(text[i:j + 1])
    except ValueError:
        return None


def chat_call(provider, system, messages):
    """One model call over the conversation so far."""
    if provider.kind == "anthropic":
        from run import http_json
        r = http_json(f"{provider.base}/messages", {
            "model": provider.model, "max_tokens": MAX_TOKENS, "temperature": TEMPERATURE,
            "system": system, "messages": messages}, provider.headers())
        return "".join(b.get("text", "") for b in r.get("content", []) if b.get("type") == "text")
    from run import http_json
    r = http_json(f"{provider.base}/chat/completions", {
        "model": provider.model, "max_tokens": MAX_TOKENS, "temperature": TEMPERATURE,
        "messages": [{"role": "system", "content": system}] + messages}, provider.headers())
    return r["choices"][0]["message"].get("content") or ""


def mock_steps(start):
    """A scripted agent: the nominal path, trusting every reply."""
    s, p = start["primary"]["seller"], start["primary"]["price"]
    script = [("reserve", {"seller": s}), ("authorize", {"seller": s, "amount": p, "key": "auth-" + s}),
              ("confirm", {"seller": s}), ("accept", {"seller": s, "key": "acc-" + s}),
              ("capture", {"seller": s, "key": "cap-" + s}), ("ship", {"seller": s, "key": "ship-" + s}),
              ("deliver", {"seller": s, "key": "del-" + s})]
    replies = []
    for op, args in script:
        reply = yield {"call": {"op": op, "args": args}}
        replies.append(reply)
        if not reply.get("ok"):
            break
    ok = all(r.get("ok") for r in replies) and len(replies) == len(script)
    n = len(replies)
    j = "Fulfilled" if ok else "Indeterminate"
    yield {"end": {"claims": [{"dependency": d, "judgment": j, "cites": [n] if ok else []} for d in DEPS]}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--condition", default="role", choices=["role", "commitments", "evidential"])
    ap.add_argument("--log", default=None, help="append the conversation as one JSON line to this file")
    ap.add_argument("--max-steps", type=int, default=40)
    args = ap.parse_args()

    start = json.loads(sys.stdin.readline())
    out = lambda obj: (sys.stdout.write(json.dumps(obj) + "\n"), sys.stdout.flush())
    log = {"run": start.get("run"), "model": args.model, "condition": args.condition, "steps": [],
           "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}

    if args.model.startswith("mock-"):
        gen = mock_steps(start)
        step = next(gen)
        while "call" in step:
            out({"type": "call", **step["call"]})
            reply = json.loads(sys.stdin.readline())
            log["steps"].append({"action": step, "reply": reply})
            step = gen.send(reply)
        out({"type": "end", "claims": step["end"]["claims"], "result": {"agent": "mock"}})
        return

    provider = Provider(args.model)
    log["resolved_model"] = provider.model
    system = system_prompt(start, args.condition)
    messages = [{"role": "user", "content": "Begin. " + json.dumps({"principal": start["principal"], "primary": start["primary"]})}]
    claims = None
    for _ in range(args.max_steps):
        try:
            text = chat_call(provider, system, messages)
        except Exception as e:  # transport failure after the provider's own retries
            log["error"] = repr(e)
            break
        messages.append({"role": "assistant", "content": text})
        act = extract_json(text)
        log["steps"].append({"text": text})
        if isinstance(act, dict) and isinstance(act.get("end"), dict):
            claims = act["end"].get("claims")
            break
        if isinstance(act, dict) and isinstance(act.get("call"), dict):
            out({"type": "call", "op": act["call"].get("op"), "args": act["call"].get("args", {})})
            reply = json.loads(sys.stdin.readline())
            messages.append({"role": "user", "content": json.dumps(reply)})
        else:
            messages.append({"role": "user", "content": "Reply with one JSON object as specified."})
    if args.log:
        with open(args.log, "a") as f:
            f.write(json.dumps({**log, "messages": messages, "system": system}) + "\n")
    out({"type": "end", "claims": claims if isinstance(claims, list) else [], "result": {"steps": len(log["steps"]),
                                                                                         "error": log.get("error")}})


if __name__ == "__main__":
    main()
