#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `delegation`.
;; Written from specs/commitments/delegation.md, specs/delegation.md,
;; specs/bspl/delegation.bspl and specs/commitments/README.md only.
;;
;; Information base (observer H):
;;   (msg ACCEPT 2 1)   -> ACCEPT, V, act, 1
;;   (msg START a s)    -> START, V, performance, s   (the performer reports on V's side)
;;   (msg ATTEST a s)   -> START, attester A, performance, s
;;   (msg DELEGATED ..) -> nothing
;;   (read-ok 11 (full vs c1 c2 stage as-of))
;;                      -> c1 = discharged: START, V, performance, min(as-of, DEADLINE);
;;                         coverage V through as-of for START
;; Commitment: C1 = C(V, H, ACCEPT by T-ACCEPT, START by DEADLINE) (retained).
;; Judgments:
;;   continuity: Violated if a read shows c1 = released (cite it); else Fulfilled
;;               (cite the ACCEPT).
;;   temporal <- C1; expired => Violated.
;;
;; AMBIGUITY: "a read shows c1 = released" is checked on the `full` view (the
;; hybrid interface) and also on a `ledger` view, the other view form carrying
;; c1; any read, whatever its as-of, counts.
;; AMBIGUITY: a read-ok whose view is not `full` yields no facts and no coverage.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/delegation/terms.rkt")
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
         ;; (full vs c1 c2 stage as-of)
         (define c1 (list-ref v 2))
         (define as-of (list-ref v 5))
         (when (eq? c1 'discharged)
           (set! facts (cons (fact 'START 'V 'performance (min as-of DEADLINE) '() i) facts)))
         (set! covs (cons (coverage 'V as-of '(START) i) covs)))]
      [else (void)]))
  (values (reverse facts) (reverse covs)))

(define (ev? e) (λ (f) (eq? (fact-event f) e)))
(define C1 (commitment 'C1 'V 'H (ev? 'ACCEPT) T-ACCEPT (ev? 'START) DEADLINE))

(define (read-shows-released? v)
  (and (pair? v)
       (case (car v)
         [(full) (eq? (caddr v) 'released)]     ; (full vs c1 c2 stage as-of)
         [(ledger) (eq? (cadr v) 'released)]    ; (ledger c1 c2)
         [else #f])))

(define ((judge evidential?) ds)
  (define-values (facts covs) (info-base ds))
  (define ri (read-index ds))
  (define rv (read-view ds))
  (define accepts (map car (msgs ds 'ACCEPT)))
  (define continuity
    (if (and ri (read-shows-released? rv))
        (dep-claim 'continuity 'Violated (list ri))
        (dep-claim 'continuity 'Fulfilled accepts)))
  (define-values (s1 c1) (commitment-state C1 facts covs #:evidential? evidential?
                                           #:a-kinds '(ACCEPT) #:c-kinds '(START)))
  (claims continuity
          (dep-claim 'temporal (state->judgment s1 #:expired 'Violated) c1)))

(define PROTOCOL (hasheq 'on-delegate 'retain))
(define INTERFACE (hasheq 'notice? #t 'attest? #t 'view 'full))

(define cupid-arms
  (list (arm 'delegation 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'delegation 'cupid-e PROTOCOL INTERFACE (judge #t))))
