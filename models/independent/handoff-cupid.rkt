#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `handoff`.
;; Written from specs/commitments/handoff.md, specs/handoff.md,
;; specs/bspl/handoff.bspl and specs/commitments/README.md only.
;;
;; Information base (observer H):
;;   (msg ACCEPT a t)  -> ACCEPT, V, act, t
;;   (msg START a t)   -> START, V, performance, t           (V's report)
;;   (msg ATTEST a t)  -> START, attester A, performance, t  (independent)
;;   (read-ok 11 (full S oat ost c0 c1 wm))
;;                     -> ACCEPT V act oat (if oat); START V performance ost (if ost);
;;                        coverage V through wm for ACCEPT START
;; Commitments:
;;   C0 = C(V, H, T, ACCEPT by ACCEPT-DEADLINE)
;;   C1 = C(V, H, ACCEPT by DEADLINE, START by DEADLINE)
;; Judgments: flow <- C0; temporal <- C1, expired => Violated.
;;
;; AMBIGUITY: a read-ok whose view is not the `full` form (the hybrid interface
;; only produces `full`) is treated as yielding no facts and no coverage.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/handoff/terms.rkt")
(provide cupid-arms)

(define (info-base ds)
  (define facts '())
  (define covs '())
  (for ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg)
       (define t (msg-asserted d))
       (case (cadr d)
         [(ACCEPT) (set! facts (cons (fact 'ACCEPT 'V 'act t '() i) facts))]
         [(START) (set! facts (cons (fact 'START 'V 'performance t '() i) facts))]
         [(ATTEST) (set! facts (cons (fact 'START 'A 'performance t '() i) facts))]
         [else (void)])]
      [(read-ok)
       (define v (caddr d))
       (when (and (pair? v) (eq? (car v) 'full))
         ;; (full S oat ost c0 c1 wm)
         (define oat (list-ref v 2))
         (define ost (list-ref v 3))
         (define wm (list-ref v 6))
         (when oat (set! facts (cons (fact 'ACCEPT 'V 'act oat '() i) facts)))
         (when ost (set! facts (cons (fact 'START 'V 'performance ost '() i) facts)))
         (set! covs (cons (coverage 'V wm '(ACCEPT START) i) covs)))]
      [else (void)]))
  (values (reverse facts) (reverse covs)))

(define (ev? e) (λ (f) (eq? (fact-event f) e)))

(define C0 (commitment 'C0 'V 'H 'true 0 (ev? 'ACCEPT) ACCEPT-DEADLINE))
(define C1 (commitment 'C1 'V 'H (ev? 'ACCEPT) DEADLINE (ev? 'START) DEADLINE))

(define ((judge evidential?) ds)
  (define-values (facts covs) (info-base ds))
  (define-values (s0 c0) (commitment-state C0 facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(ACCEPT)))
  (define-values (s1 c1) (commitment-state C1 facts covs #:evidential? evidential?
                                           #:a-kinds '(ACCEPT) #:c-kinds '(START)))
  (claims (dep-claim 'flow (state->judgment s0) c0)
          (dep-claim 'temporal (state->judgment s1 #:expired 'Violated) c1)))

(define PROTOCOL (hasheq))
(define INTERFACE (hasheq 'notice? #t 'attest? #t 'view 'full))

(define cupid-arms
  (list (arm 'handoff 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'handoff 'cupid-e PROTOCOL INTERFACE (judge #t))))
