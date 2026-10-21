#!/usr/bin/env python3
"""Enactment driver: the model calls of specs/enactment.md.

Racket (enact.rkt) draws worlds, writes every prompt, assembles deliveries and
scores; this driver only sends prompts to models and records the responses.
It never sees the oracle truth.

  python3 harness/run.py parties   --plan plan.jsonl     --model SPEC --reps N --out parties.jsonl
  python3 harness/run.py observers --observe observe.jsonl --model SPEC --out claims.jsonl

SPEC is one of
  mock-faithful               parties send the faithful events; the observer echoes cupid-e
  mock-noisy                  seeded omissions and fabrications; the observer echoes cupid
  anthropic:MODEL             Anthropic Messages API        (ANTHROPIC_API_KEY)
  openai:MODEL                OpenAI Chat Completions       (OPENAI_API_KEY)
  openrouter:MODEL            OpenRouter, OpenAI-compatible (OPENROUTER_API_KEY)
  compat:MODEL                any OpenAI-compatible endpoint (COMPAT_BASE_URL, COMPAT_API_KEY)
MODEL may be `auto:NAME[|NAME...]`: for each NAME in order, a listed model
whose identifier equals NAME is used, else the shortest listed identifier that
starts with NAME; the resolved identifier is recorded with every call.

Every call is logged in the output line: prompts, response text, resolved
model, the model identifier the provider reports, sampling settings, time,
and token usage.
"""

import argparse, hashlib, json, os, random, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

TEMPERATURE = 1.0
MAX_TOKENS = 2048

# ------------------------------------------------------------------ providers

def http_json(url, payload=None, headers=None, timeout=180):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers or {}, method="GET" if payload is None else "POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

class Provider:
    def __init__(self, spec):
        self.spec = spec
        kind, _, model = spec.partition(":")
        self.kind, self.requested = kind, model
        if kind == "anthropic":
            self.base, self.key = "https://api.anthropic.com/v1", os.environ.get("ANTHROPIC_API_KEY")
        elif kind == "openai":
            self.base, self.key = "https://api.openai.com/v1", os.environ.get("OPENAI_API_KEY")
        elif kind == "openrouter":
            self.base, self.key = "https://openrouter.ai/api/v1", os.environ.get("OPENROUTER_API_KEY")
        elif kind == "compat":
            self.base, self.key = os.environ.get("COMPAT_BASE_URL", "").rstrip("/"), os.environ.get("COMPAT_API_KEY")
        else:
            raise SystemExit(f"unknown model spec {spec}")
        if not self.key:
            raise SystemExit(f"{spec}: no API key in the environment for provider {kind}")
        self.model = self.resolve(model)

    def headers(self):
        if self.kind == "anthropic":
            return {"x-api-key": self.key, "anthropic-version": "2023-06-01", "content-type": "application/json"}
        return {"Authorization": f"Bearer {self.key}", "content-type": "application/json"}

    def resolve(self, model):
        if not model.startswith("auto:"):
            return model
        prefixes = model[len("auto:"):].split("|")
        listing = http_json(f"{self.base}/models", headers=self.headers())
        ids = [m.get("id") for m in listing.get("data", []) if m.get("id")]
        for p in prefixes:
            if p in ids:
                return p
            hits = sorted((i for i in ids if i.startswith(p)), key=lambda i: (len(i), i))
            if hits:
                return hits[0]
        raise SystemExit(f"{self.spec}: no listed model matches {prefixes}; available: {', '.join(sorted(ids)[:80])}")

    def call(self, system, user):
        for attempt in range(6):
            try:
                if self.kind == "anthropic":
                    r = http_json(f"{self.base}/messages", {
                        "model": self.model, "max_tokens": MAX_TOKENS, "temperature": TEMPERATURE,
                        "system": system, "messages": [{"role": "user", "content": user}]}, self.headers())
                    text = "".join(b.get("text", "") for b in r.get("content", []) if b.get("type") == "text")
                    return text, {"reported_model": r.get("model"), "usage": r.get("usage")}
                r = http_json(f"{self.base}/chat/completions", {
                    "model": self.model, "max_tokens": MAX_TOKENS, "temperature": TEMPERATURE,
                    "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}, self.headers())
                text = r["choices"][0]["message"].get("content") or ""
                return text, {"reported_model": r.get("model"), "provider": r.get("provider"), "usage": r.get("usage")}
            except urllib.error.HTTPError as e:
                if e.code in (408, 409, 429, 500, 502, 503, 504, 529) and attempt < 5:
                    time.sleep(2 ** attempt + random.random())
                    continue
                body = e.read().decode(errors="replace")[:500]
                return None, {"error": f"HTTP {e.code}: {body}"}
            except Exception as e:  # network failure: retry, then record
                if attempt < 5:
                    time.sleep(2 ** attempt + random.random())
                    continue
                return None, {"error": repr(e)}

# ------------------------------------------------------------------ mocks

def seeded(*parts):
    return random.Random(int(hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()[:16], 16))

def mock_party(spec, run, rep, party):
    events = list(party["faithful"])
    if spec == "mock-noisy":
        rng = seeded(run["run"], rep, party["role"])
        events = [e for e in events if rng.random() >= 0.2]
        reports = [m["name"] for m in party["messages"] if m["kind"] == "report"]
        if reports and rng.random() < 0.2:
            events.append({"message": reports[0], "at": 5})
    return json.dumps({"events": events})

def mock_observer(spec, obs):
    ref = obs["reference"]["cupid-e" if spec == "mock-faithful" else "cupid"]
    return json.dumps({"claims": ref})

# ------------------------------------------------------------------ commands

def meta(provider, extra):
    m = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if provider:
        m.update({"spec": provider.spec, "model": provider.model, "temperature": TEMPERATURE, "max_tokens": MAX_TOKENS})
    m.update(extra)
    return m

def load(path):
    with open(path) as f:
        return [json.loads(l) for l in f if l.strip()]

def parties(args):
    plan = load(args.plan)
    mock = args.model.startswith("mock-")
    provider = None if mock else Provider(args.model)
    jobs = [(run, rep) for run in plan for rep in range(args.reps)]

    def one(job):
        run, rep = job
        responses, calls = {}, []
        for p in run["parties"]:
            if mock:
                text, info = mock_party(args.model, run, rep, p), {}
            else:
                text, info = provider.call(p["system"], p["user"])
            responses[p["role"]] = text
            calls.append({"role": p["role"], "system": p["system"], "user": p["user"], "response": text, "meta": meta(provider, info)})
        return {"run": run["run"], "model": args.model if mock else f"{provider.kind}:{provider.model}", "rep": rep,
                "family": run["family"], "profile": run["profile"], "seed": run["seed"], "world": run["world"],
                "responses": responses, "calls": calls}

    write_all(args.out, jobs, one, args.concurrency)

def observers(args):
    obs = load(args.observe)
    mock = args.model.startswith("mock-")
    provider = None if mock else Provider(args.model)
    conditions = args.conditions.split(",")
    jobs = [(o, c) for o in obs for c in conditions]

    def one(job):
        o, c = job
        p = o["observer"][c]
        if mock:
            text, info = mock_observer(args.model, o), {}
        else:
            text, info = provider.call(p["system"], p["user"])
        return {"run": o["run"], "model": o["model"], "rep": o["rep"], "condition": c,
                "observer_model": args.model if mock else f"{provider.kind}:{provider.model}",
                "text": text, "call": {"system": p["system"], "user": p["user"], "meta": meta(provider, info)}}

    write_all(args.out, jobs, one, args.concurrency)

def write_all(out, jobs, one, concurrency):
    done = 0
    with open(out, "w") as f, ThreadPoolExecutor(max_workers=concurrency) as ex:
        for res in ex.map(one, jobs):
            f.write(json.dumps(res) + "\n")
            done += 1
            if done % 50 == 0:
                print(f"{done}/{len(jobs)}", file=sys.stderr, flush=True)
    print(f"{done} lines written to {out}", file=sys.stderr)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("parties"); a.add_argument("--plan", required=True); a.add_argument("--model", required=True)
    a.add_argument("--reps", type=int, default=3); a.add_argument("--out", required=True); a.add_argument("--concurrency", type=int, default=8)
    b = sub.add_parser("observers"); b.add_argument("--observe", required=True); b.add_argument("--model", required=True)
    b.add_argument("--conditions", default="role,commitments,evidential"); b.add_argument("--out", required=True)
    b.add_argument("--concurrency", type=int, default=8)
    args = ap.parse_args()
    parties(args) if args.cmd == "parties" else observers(args)

if __name__ == "__main__":
    main()
