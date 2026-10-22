#!/usr/bin/env bash
# Run one enactment request end to end (specs/enactment.md):
#   harness/pipeline.sh REQUEST.json OUTDIR
# REQUEST: {"id", "families", "profiles", "seeds", "reps", "models": [SPEC...],
#           "conditions" (default role,commitments,evidential), "concurrency" (default 8)}
# Writes into OUTDIR: plan.jsonl; per model: parties-*.jsonl, claims-*.jsonl;
# observe.jsonl, claims.jsonl, results.jsonl, enactment.txt, status.json.
set -uo pipefail
mkdir -p "$2"
REQ="$(realpath "$1")"; OUT="$(realpath "$2")"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
field() { python3 -c "import json,sys; r=json.load(open('$REQ')); v=r.get('$1', '$2'); print(' '.join(v) if isinstance(v, list) else v)"; }
FAMILIES=$(field families all); PROFILES=$(field profiles reliable,adversarial); SEEDS=$(field seeds 50)
REPS=$(field reps 3); MODELS=$(field models ""); CONDS=$(field conditions role,commitments,evidential); CONC=$(field concurrency 8)
status() { python3 -c "import json,time; json.dump({'request': json.load(open('$REQ')), 'state': '$1', 'detail': '''$2''', 'time': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}, open('$OUT/status.json','w'), indent=2)"; }
cp "$REQ" "$OUT/request.json"
status running ""
cd "$HERE"
racket enact.rkt plan "$FAMILIES" "$PROFILES" "$SEEDS" > "$OUT/plan.jsonl" || { status failed "plan"; exit 1; }
: > "$OUT/observe.jsonl"; : > "$OUT/claims.jsonl"
for M in $MODELS; do
  TAG=$(echo "$M" | tr ':/|' '___')
  python3 harness/run.py parties --plan "$OUT/plan.jsonl" --model "$M" --reps "$REPS" --concurrency "$CONC" --out "$OUT/parties-$TAG.jsonl" \
    || { status failed "parties $M"; exit 1; }
  racket enact.rkt assemble "$OUT/parties-$TAG.jsonl" > "$OUT/observe-$TAG.jsonl" || { status failed "assemble $M"; exit 1; }
  python3 harness/run.py observers --observe "$OUT/observe-$TAG.jsonl" --model "$M" --conditions "$CONDS" --concurrency "$CONC" --out "$OUT/claims-$TAG.jsonl" \
    || { status failed "observers $M"; exit 1; }
  cat "$OUT/observe-$TAG.jsonl" >> "$OUT/observe.jsonl"; cat "$OUT/claims-$TAG.jsonl" >> "$OUT/claims.jsonl"
done
racket enact.rkt score "$OUT/observe.jsonl" "$OUT/claims.jsonl" "$OUT/results.jsonl" > "$OUT/enactment.txt" || { status failed "score"; exit 1; }

# The purchasing agent in the family `purchase` (specs/enactment.md §11), when the request asks for it
PA_PROFILES=$(python3 -c "import json; r=json.load(open('$REQ')).get('purchase_agent'); print(r.get('profiles','reliable,adversarial') if r else '')")
if [ -n "$PA_PROFILES" ]; then
  PA_SEEDS=$(python3 -c "import json; print(json.load(open('$REQ'))['purchase_agent'].get('seeds', 50))")
  PA_CONDS=$(python3 -c "import json; print(' '.join(json.load(open('$REQ'))['purchase_agent'].get('conditions', 'role,commitments,evidential').split(',')))")
  : > "$OUT/purchase-agent.jsonl"
  for M in $MODELS; do
    for C in $PA_CONDS; do
      for R in $(seq 0 $((REPS - 1))); do
        racket purchase-agent.rkt sample "python3 harness/agent_arm.py --model '$M' --condition $C --log '$OUT/purchase-agent-log.jsonl'" \
          "$M/$C" "$PA_PROFILES" "$PA_SEEDS" "$R" "$OUT/purchase-agent.jsonl" || { status failed "purchase agent $M $C"; exit 1; }
      done
    done
  done
  racket purchase-agent.rkt report "$OUT/purchase-agent.jsonl" > "$OUT/purchase-agent.txt" || { status failed "purchase agent report"; exit 1; }
fi
status done ""
