#lang racket/base
;; Family 2 — resource reservation. The five arms.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (log-events v) (cddr v))
(define (log-wm v) (cadr v))
(define (grant-time evs who) (for/first ([e evs] #:when (and (eq? (car e) 'GRANT) (eq? (cadr e) who))) (caddr e)))
(define (release-time evs) (for/first ([e evs] #:when (eq? (car e) 'RELEASE)) (cadr e)))
(define (expire-time evs) (for/first ([e evs] #:when (eq? (car e) 'EXPIRE)) (cadr e)))

;; CHOR — global type: H1 REQ; V GRANT H1; H1 RELEASE; V GRANT H2. V regrants
;; only on RELEASE (the choreography has no timeout). Conformance of the
;; recorded message trace establishes exclusivity (GRANT h2 only after
;; RELEASE); GRANT h2 by D2 fulfils temporal. The log is V's session as of the
;; read, taken as current (the paradigm has no notion of staleness); the read
;; is after D2, so no GRANT h2 by D2 means the grant's timer fired: Violated.
(define (chor-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (cond
    [(not v) (claims (list 'sharing 'Indeterminate '()) (list 'temporal 'Indeterminate '()))]
    [else
     (define evs (log-events v))
     (define g2 (grant-time evs 'h2)) (define rel (release-time evs))
     (define conform (or (not g2) (and rel (<= rel g2))))
     (claims (if conform (list 'sharing 'Fulfilled (list ri)) (list 'sharing 'Violated (list ri)))
             (if (and g2 (<= g2 D2)) (list 'temporal 'Fulfilled (list ri)) (list 'temporal 'Violated (list ri))))]))

;; FSM — lease state machine at V: free → held(h1) → (release | expiry at
;; LEASE-END) → held(h2). V's lease records are authoritative: leases that do
;; not overlap mean exclusive use; no GRANT h2 by D2 in the record is a violation.
(define (fsm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (cond
    [(not v) (claims (list 'sharing 'Indeterminate '()) (list 'temporal 'Indeterminate '()))]
    [else
     (define evs (log-events v))
     (define g2 (grant-time evs 'h2))
     (define h1-end (let ([r (release-time evs)] [x (expire-time evs)]) (cond [(and r x) (min r x)] [else (or r x)])))
     (define disjoint (or (not g2) (and h1-end (<= h1-end g2))))
     (claims (if disjoint (list 'sharing 'Fulfilled (list ri)) (list 'sharing 'Violated (list ri)))
             (if (and g2 (<= g2 D2)) (list 'temporal 'Fulfilled (list ri)) (list 'temporal 'Violated (list ri))))]))

;; COMM — C1 = C(V,H1, granted, exclusive use until H1 releases); C2 = C(V,H2,
;; requested, grant by D2). V discharges C2 only after C1 is released. The
;; creditor's view is V's commitment ledger (GRANT and RELEASE events).
;; Exclusivity holds when C1 was released before C2 was discharged; C2 is
;; violated when D2 passes without its discharge.
(define (comm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (cond
    [(not v) (claims (list 'sharing 'Indeterminate '()) (list 'temporal 'Indeterminate '()))]
    [else
     (define evs (log-events v))
     (define g2 (grant-time evs 'h2)) (define rel (release-time evs))
     (claims (if (or (not g2) (and rel (<= rel g2))) (list 'sharing 'Fulfilled (list ri)) (list 'sharing 'Violated (list ri)))
             (if (and g2 (<= g2 D2)) (list 'temporal 'Fulfilled (list ri)) (list 'temporal 'Violated (list ri))))]))

;; HYBRID — lease with expiry and fencing tokens: V regrants at release or
;; expiry, and the resource rejects any access carrying a superseded token.
;; Exclusivity is judged from the resource's own access log (USE, REJECT), an
;; independent source: an overlap of uses is a violation; otherwise the fencing
;; tokens, checked by the resource, guarantee exclusivity, so a log that is
;; stale still shows no overlap it could hide (Fulfilled). The grant to h2 is
;; V's own act, and V's GRANT entry is V's report of it (E1): the grant is
;; evidenced by the resource's records — a USE by h2 starting by D2, or a
;; REJECT of h1 by D2 (h1's token is refused only once a newer one exists).
;; Its absence is a violation only when V's record is complete through D2 (E2).
;; HYBRID-NOE: lease with expiry, no fencing; judges exclusivity from the
;; access log and V's allocation records (a release recorded after h2's grant
;; means h1 held past it), and every read is authoritative.
(define ((hybrid-judge evidence?) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (cond
    [(not v) (claims (list 'sharing 'Indeterminate '()) (list 'temporal 'Indeterminate '()))]
    [else
     (define evs (log-events v)) (define wm (log-wm v))
     (define (auth? due) (or (not evidence?) (>= wm due)))
     (define g2 (grant-time evs 'h2))
     (define uses (filter (λ (e) (eq? (car e) 'USE)) evs))
     (define overlap
       (for*/or ([a uses] [b uses] #:unless (eq? (cadr a) (cadr b)))
         (and (< (caddr a) (cadddr b)) (< (caddr b) (cadddr a)))))
     (define sharing
       (if evidence?
           (if overlap (list 'sharing 'Violated (list ri)) (list 'sharing 'Fulfilled (list ri)))
           (let ([h1-end (let ([r (release-time evs)] [x (expire-time evs)]) (cond [(and r x) (min r x)] [else (or r x)]))]
                 [rel (release-time evs)])
             (if (or overlap (and g2 (not (and h1-end (<= h1-end g2)))) (and g2 rel (> rel g2)))
                 (list 'sharing 'Violated (list ri))
                 (list 'sharing 'Fulfilled (list ri))))))
     (define granted
       (if evidence?
           (for/or ([e evs])
             (or (and (eq? (car e) 'USE) (eq? (cadr e) 'h2) (<= (caddr e) D2))
                 (and (eq? (car e) 'REJECT) (eq? (cadr e) 'h1) (<= (caddr e) D2))))
           (and g2 (<= g2 D2))))
     (claims sharing
             (cond [granted (list 'temporal 'Fulfilled (list ri))]
                   [(and (auth? D2) (not (and g2 (<= g2 D2)))) (list 'temporal 'Violated (list ri))]
                   [else (list 'temporal 'Indeterminate '())]))]))

(define arms
  (list (arm 'reservation 'chor (hasheq 'regrant 'on-release) (hasheq 'records '(GRANT RELEASE)) chor-judge)
        (arm 'reservation 'fsm (hasheq 'regrant 'expiry) (hasheq 'records '(GRANT RELEASE EXPIRE)) fsm-judge)
        (arm 'reservation 'comm (hasheq 'regrant 'on-release) (hasheq 'records '(GRANT RELEASE)) comm-judge)
        (arm 'reservation 'hybrid (hasheq 'regrant 'expiry-fenced) (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT)) (hybrid-judge #t))
        (arm 'reservation 'hybrid-noe (hasheq 'regrant 'expiry) (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT)) (hybrid-judge #f))))
