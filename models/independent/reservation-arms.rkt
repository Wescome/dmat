#lang racket/base
;; Family `reservation` — resource reservation (Sharing, Temporal).
;; Independent arms: chor, fsm, comm, hybrid, hybrid-noe.
;;
;; The observer is an auditor that reads the allocator V's allocation log once,
;; at T-READ. Its deliveries are a single element:
;;   (read-ok T-READ (log as-of e ...))   or   (read-failed T-READ)
;; Log events: (GRANT who t) (RELEASE t) (EXPIRE t) — V's own entries;
;;             (USE who from to) (REJECT who t)   — the resource's access log.
;; Dependencies, in family order: sharing, temporal.
;;
;; Use intervals are read half-open, [from, to): a holder that releases (or is
;; rejected) at t has stopped using the resource at t, and the next holder may
;; start at t. Two uses overlap iff a.from < b.to and b.from < a.to.

(require "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/reservation/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Shared, paradigm-neutral reading of the single delivery.

;; The log view, or #f when the read failed or the view is not a log.
(define (the-log ds)
  (define v (read-view ds))
  (and (pair? v) (eq? (car v) 'log) (pair? (cdr v)) (real? (cadr v))
       (list? (cddr v))
       v))
(define (log-as-of v) (cadr v))
(define (log-events v) (cddr v))

;; Index of the read-ok delivery, as a citation list.
(define (cite-read ds)
  (define i (read-index ds))
  (if i (list i) '()))

(define (ev? e k n) (and (pair? e) (eq? (car e) k) (list? e) (= (length e) n)))
(define (grant? e) (and (ev? e 'GRANT 3) (real? (caddr e))))
(define (release? e) (and (ev? e 'RELEASE 2) (real? (cadr e))))
(define (expire? e) (and (ev? e 'EXPIRE 2) (real? (cadr e))))
(define (use? e) (and (ev? e 'USE 4) (real? (caddr e)) (real? (cadddr e))))
(define (reject? e) (and (ev? e 'REJECT 3) (real? (caddr e))))

(define (grants-to who es)
  (for/list ([e es] #:when (and (grant? e) (eq? (cadr e) who))) (caddr e)))
(define (releases es) (for/list ([e es] #:when (release? e)) (cadr e)))
(define (uses-of who es)
  (for/list ([e es] #:when (and (use? e) (eq? (cadr e) who)))
    (cons (caddr e) (cadddr e))))
(define (rejects-of who es)
  (for/list ([e es] #:when (and (reject? e) (eq? (cadr e) who))) (caddr e)))

(define (earliest ts) (and (pair? ts) (apply min ts)))

;; half-open overlap of [a1,a2) and [b1,b2)
(define (overlap? a b) (and (< (car a) (cdr b)) (< (car b) (cdr a))))
;; do the resource's recorded uses show two different holders at once?
(define (uses-overlap? es)
  (for*/or ([a (uses-of 'h1 es)] [b (uses-of 'h2 es)]) (overlap? a b)))

;; Was the handover to h2 well-formed — h2 granted only after h1 released?
(define (h2-granted-after-release? es)
  (define g2 (earliest (grants-to 'h2 es)))
  (define r (earliest (releases es)))
  (or (not g2) (and r (<= r g2))))

(define (indeterminate-both)
  (claims (list 'sharing 'Indeterminate '())
          (list 'temporal 'Indeterminate '())))

;; ---------------------------------------------------------------------------
;; CHOR — protocol 'regrant on-release; records GRANT RELEASE.
;;
;; The global type is: V -> h1 : GRANT ; h2 -> V : REQUEST ;
;; h1 -> V : RELEASE ; V -> h2 : GRANT. Ownership of the resource is passed
;; through the session: V's projection sends GRANT to h2 only after it has
;; received h1's RELEASE, and in this paradigm a message is the event it
;; names — RELEASE means h1 has let go. The auditor holds one read-back of V's
;; session log, which it takes as V's session as it stands at the read (the
;; paradigm has no notion of a record being stale).
;;  - sharing: if the log is a conforming trace (no GRANT to h2 before a
;;    RELEASE) the session passed ownership linearly, so no two holders at
;;    once: Fulfilled. A GRANT to h2 with no prior RELEASE breaks the global
;;    type's ordering: Violated (overcommit).
;;  - temporal: the GRANT to h2 is in V's session. If it is there at or before
;;    D2: Fulfilled. If it is later than D2, or absent from V's session when
;;    read at T-READ > D2 (the awaited message did not come by the bound):
;;    Violated.
;;  - no read-back: nothing of the session is observable: Indeterminate.
(define (judge-chor ds)
  (define v (the-log ds))
  (cond
    [(not v) (indeterminate-both)]
    [else
     (define es (log-events v))
     (define c (cite-read ds))
     (define g2 (earliest (grants-to 'h2 es)))
     (claims (list 'sharing (if (h2-granted-after-release? es) 'Fulfilled 'Violated) c)
             (list 'temporal (if (and g2 (<= g2 D2)) 'Fulfilled 'Violated) c))]))

;; ---------------------------------------------------------------------------
;; FSM — protocol 'regrant expiry; records GRANT RELEASE EXPIRE.
;;
;; V runs a state machine: IDLE --grant h1--> HELD(h1); HELD(h1) --RELEASE-->
;; HELD(h2); HELD(h1) --timeout LEASE-END / EXPIRE--> HELD(h2). In HELD(h2) a
;; late RELEASE from h1 is an ignored input. The machine is in exactly one
;; state, and each state names exactly one holder. The auditor reads V's
;; record and replays it; the record is authoritative and current at the
;; read (no staleness, no completeness, no obligations of h1 beyond V's
;; machine).
;;  - sharing: the machine never occupies a two-holder state; the only
;;    breach of its own discipline is a GRANT to h2 taken from HELD(h1)
;;    without a RELEASE or EXPIRE transition before it: Violated. Otherwise
;;    Fulfilled.
;;  - temporal: HELD(h2) entered at or before D2: Fulfilled. Entered later,
;;    or the machine still not in HELD(h2) at the read (T-READ > D2):
;;    Violated.
;;  - no record: Indeterminate.
(define (judge-fsm ds)
  (define v (the-log ds))
  (cond
    [(not v) (indeterminate-both)]
    [else
     (define es (log-events v))
     (define c (cite-read ds))
     (define g2 (earliest (grants-to 'h2 es)))
     (define end1 (earliest (append (releases es)
                                    (for/list ([e es] #:when (expire? e)) (cadr e)))))
     (define legal-handover? (or (not g2) (and end1 (<= end1 g2))))
     (claims (list 'sharing (if legal-handover? 'Fulfilled 'Violated) c)
             (list 'temporal (if (and g2 (<= g2 D2)) 'Fulfilled 'Violated) c))]))

;; ---------------------------------------------------------------------------
;; COMM — protocol 'regrant on-release; records GRANT RELEASE.
;;
;; Commitments: C(h1, V, granted(h1), release by LEASE-END) — h1's lease;
;; C(V, h2, released(h1), grant(h2)) — V's conditional promise to h2, which
;; detaches on h1's release; and the dependency's deadline puts the grant to
;; h2 at D2. The auditor reads V's ledger and judges each commitment as its
;; creditor holds it.
;;  - sharing: exclusivity is carried by V's conditional commitment — V may
;;    grant h2 only once the antecedent (h1's release, which discharges h1's
;;    hold) holds. A GRANT to h2 seen before any RELEASE means V acted on an
;;    undetached commitment while h1's hold was live: Violated. Otherwise
;;    Fulfilled. (h1 overrunning its lease violates h1's own commitment to V,
;;    but with no second holder that is not an overcommit.)
;;  - temporal: the grant commitment is discharged if h2's grant is visible
;;    in the ledger at or before D2: Fulfilled. Not visible discharged by D2
;;    (later, or absent while the read is past D2): Violated.
;;  - no ledger: the commitment states are unknown: Indeterminate.
(define (judge-comm ds)
  (define v (the-log ds))
  (cond
    [(not v) (indeterminate-both)]
    [else
     (define es (log-events v))
     (define c (cite-read ds))
     (define g2 (earliest (grants-to 'h2 es)))
     (define detached-before-grant? (h2-granted-after-release? es))
     (claims (list 'sharing (if detached-before-grant? 'Fulfilled 'Violated) c)
             (list 'temporal (if (and g2 (<= g2 D2)) 'Fulfilled 'Violated) c))]))

;; ---------------------------------------------------------------------------
;; HYBRID — protocol 'regrant expiry-fenced; records all five kinds.
;;
;; Commitments as in COMM, V's state machine with the LEASE-END timeout as in
;; FSM, and every grant carries a fencing token that the resource itself
;; checks: once h2 holds the newer token, h1's use is refused (REJECT). The
;; auditor reads V's log, which interleaves V's own entries (GRANT, RELEASE,
;; EXPIRE: V's reports) with the resource's access log (USE, REJECT: an
;; independent source). The log's as-of is its completeness watermark.
;;  - sharing: if the resource's own log shows h1 and h2 using at once:
;;    Violated. Otherwise Fulfilled: exclusivity is enforced by the resource's
;;    token check, independent of h1's conduct and of V's reports, so what the
;;    log omits (E2) cannot hide an overlap. With no read-back there is no
;;    delivery to stand on: Indeterminate (E3).
;;  - temporal: the performer of the grant is V, so V's GRANT entry alone is
;;    not evidence (E1). Independent evidence that h2 held a valid token by
;;    D2: a resource USE by h2 starting at or before D2, or a resource REJECT
;;    of h1 at or before D2 (the resource only refuses h1's token once a
;;    newer one has been issued): Fulfilled. Negative: V's own record, complete
;;    through D2 (as-of >= D2), shows no grant to h2 by D2: Violated. Anything
;;    else — e.g. a stale log (as-of < D2) whose grant has no resource
;;    corroboration yet: Indeterminate (E2, E3).
(define (judge-hybrid ds)
  (define v (the-log ds))
  (cond
    [(not v) (indeterminate-both)]
    [else
     (define es (log-events v))
     (define w (log-as-of v))
     (define c (cite-read ds))
     (define sharing-j (if (uses-overlap? es) 'Violated 'Fulfilled))
     (define h2-use-start (earliest (map car (uses-of 'h2 es))))
     (define h1-reject (earliest (rejects-of 'h1 es)))
     (define g2 (earliest (grants-to 'h2 es)))
     (define temporal-j
       (cond
         [(or (and h2-use-start (<= h2-use-start D2))
              (and h1-reject (<= h1-reject D2)))
          'Fulfilled]
         [(and (>= w D2) (not (and g2 (<= g2 D2)))) 'Violated]
         [else 'Indeterminate]))
     (claims (list 'sharing sharing-j c)
             (list 'temporal temporal-j (if (eq? temporal-j 'Indeterminate) '() c)))]))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE — protocol 'regrant expiry (no fencing); records all five kinds.
;;
;; The hybrid's commitments and state machine without its evidentiary
;; component (and, in this family, without fencing tokens). Every report is
;; evidence of what it reports and the read-back is authoritative and
;; complete: what the log does not show did not happen.
;;  - sharing: the log shows two holders at once if the resource's USE
;;    entries overlap, or if h1 reports its RELEASE after V granted h2 (h1
;;    says it held the resource until then): Violated. Otherwise Fulfilled.
;;  - temporal: V's GRANT to h2 at or before D2: Fulfilled. No such grant in
;;    the authoritative log: Violated.
;;  - no read-back: Indeterminate.
(define (judge-hybrid-noe ds)
  (define v (the-log ds))
  (cond
    [(not v) (indeterminate-both)]
    [else
     (define es (log-events v))
     (define c (cite-read ds))
     (define g2 (earliest (grants-to 'h2 es)))
     (define late-release?
       (and g2 (for/or ([r (releases es)]) (> r g2))))
     (define sharing-j (if (or (uses-overlap? es) late-release?) 'Violated 'Fulfilled))
     (claims (list 'sharing sharing-j c)
             (list 'temporal (if (and g2 (<= g2 D2)) 'Fulfilled 'Violated) c))]))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm 'reservation 'chor
        (hasheq 'regrant 'on-release)
        (hasheq 'records '(GRANT RELEASE))
        judge-chor)
   (arm 'reservation 'fsm
        (hasheq 'regrant 'expiry)
        (hasheq 'records '(GRANT RELEASE EXPIRE))
        judge-fsm)
   (arm 'reservation 'comm
        (hasheq 'regrant 'on-release)
        (hasheq 'records '(GRANT RELEASE))
        judge-comm)
   (arm 'reservation 'hybrid
        (hasheq 'regrant 'expiry-fenced)
        (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT))
        judge-hybrid)
   (arm 'reservation 'hybrid-noe
        (hasheq 'regrant 'expiry)
        (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT))
        judge-hybrid-noe)))
