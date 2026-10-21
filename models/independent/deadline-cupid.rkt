#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `deadline`.
;; Written from specs/commitments/deadline.md, specs/deadline.md,
;; specs/bspl/deadline.bspl and specs/commitments/README.md only.
;;
;; Information base (observer H):
;;   (msg DONE a s)          -> DONE, V, performance, s (V's clock)
;;   (msg ATTEST a t)        -> DONE, attester A, performance, t (trusted clock)
;;   (read-ok 19 (record ot))-> DONE, V, performance, ot (if ot);
;;                              coverage V through T-READ for DONE
;; Commitments: C_t = C(V, H, T, DONE by DEADLINE); C_c = C(V, H, T, DONE by T-EVAL).
;; Judgments: temporal <- C_t; completion <- C_c (expired cannot occur).
;; Debtor's clock unreliable: both commitments evaluated with #:debtor-clock? #f
;; (in both arms; it has no effect without the evidential layer).
;;
;; AMBIGUITY: the coverage is through T-READ (as the spec table says), not
;; through the read delivery's own instant; these coincide (19).
;; AMBIGUITY: a read-ok whose view is not `(record ot)` yields nothing.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/deadline/terms.rkt")
(provide cupid-arms)

(define (info-base ds)
  (define facts '())
  (define covs '())
  (for ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg)
       (define t (msg-asserted d))
       (case (cadr d)
         [(DONE) (set! facts (cons (fact 'DONE 'V 'performance t '() i) facts))]
         [(ATTEST) (set! facts (cons (fact 'DONE 'A 'performance t '() i) facts))]
         [else (void)])]
      [(read-ok)
       (define v (caddr d))
       (when (and (pair? v) (eq? (car v) 'record))
         (define ot (cadr v))
         (when ot (set! facts (cons (fact 'DONE 'V 'performance ot '() i) facts)))
         (set! covs (cons (coverage 'V T-READ '(DONE) i) covs)))]
      [else (void)]))
  (values (reverse facts) (reverse covs)))

(define (done? f) (eq? (fact-event f) 'DONE))
(define C_t (commitment 'C_t 'V 'H 'true 0 done? DEADLINE))
(define C_c (commitment 'C_c 'V 'H 'true 0 done? T-EVAL))

(define ((judge evidential?) ds)
  (define-values (facts covs) (info-base ds))
  (define-values (st ct) (commitment-state C_t facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(DONE) #:debtor-clock? #f))
  (define-values (sc cc) (commitment-state C_c facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(DONE) #:debtor-clock? #f))
  (claims (dep-claim 'temporal (state->judgment st) ct)
          (dep-claim 'completion (state->judgment sc) cc)))

(define PROTOCOL (hasheq))
(define INTERFACE (hasheq 'attest? #t))

(define cupid-arms
  (list (arm 'deadline 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'deadline 'cupid-e PROTOCOL INTERFACE (judge #t))))
