#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `external`.
;; Written from specs/commitments/external.md, specs/external.md,
;; specs/bspl/external.bspl and specs/commitments/README.md only.
;;
;; Information base (observer H):
;;   (msg DONE 6 5)          -> A and B, each V, performance, 5, (complete)
;;   (msg RECEIPT 8 7 xs)    -> B, X, performance, 7, (xs)
;;   (read-ok 11 (full as xs wm))
;;                           -> as = done: A, V, performance, T-A, ();
;;                              xs complete|partial: B, X, performance, T-X, (xs);
;;                              coverage V through wm for A B
;; Commitments:
;;   C_A = C(V, H, T, A by T-DISPATCH), consequent: A fact with attrs () or (complete)
;;   C_B = C(V, H, T, B by T-X),        consequent: B fact with attrs () or (complete)
;; Judgments:
;;   internal <- C_A.
;;   external: a B fact with attrs (partial) => Violated (cite it) unless C_B is
;;             discharged; otherwise <- C_B.
;;
;; AMBIGUITY: "cite it" for the partial rule cites every delivery yielding a
;; partial B fact (receipt and/or read).
;; AMBIGUITY: a read-ok whose view is the `record` form (not the hybrid's
;; `full`) is read as `(full as none ?)` without coverage: as = done yields
;; the A fact; no B fact and no coverage, since it carries no watermark.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/external/terms.rkt")
(provide cupid-arms)

(define (info-base ds)
  (define facts '())
  (define covs '())
  (define (add! f) (set! facts (cons f facts)))
  (for ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg)
       (define t (msg-asserted d))
       (case (cadr d)
         [(DONE) (add! (fact 'A 'V 'performance t '(complete) i))
                 (add! (fact 'B 'V 'performance t '(complete) i))]
         [(RECEIPT) (add! (fact 'B 'X 'performance t (msg-payload d) i))]
         [else (void)])]
      [(read-ok)
       (define v (caddr d))
       (when (pair? v)
         (case (car v)
           [(full)
            (define as (list-ref v 1))
            (define xs (list-ref v 2))
            (define wm (list-ref v 3))
            (when (eq? as 'done) (add! (fact 'A 'V 'performance T-A '() i)))
            (when (memq xs '(complete partial)) (add! (fact 'B 'X 'performance T-X (list xs) i)))
            (set! covs (cons (coverage 'V wm '(A B) i) covs))]
           [(record)
            (when (eq? (cadr v) 'done) (add! (fact 'A 'V 'performance T-A '() i)))]
           [else (void)]))]
      [else (void)]))
  (values (reverse facts) (reverse covs)))

(define ((part-done? e) f)
  (and (eq? (fact-event f) e)
       (member (fact-attrs f) '(() (complete)))
       #t))

(define C_A (commitment 'C_A 'V 'H 'true 0 (part-done? 'A) T-DISPATCH))
(define C_B (commitment 'C_B 'V 'H 'true 0 (part-done? 'B) T-X))

(define ((judge evidential?) ds)
  (define-values (facts covs) (info-base ds))
  (define-values (sa ca) (commitment-state C_A facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(A)))
  (define-values (sb cb) (commitment-state C_B facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(B)))
  (define partials
    (map fact-index (filter (λ (f) (and (eq? (fact-event f) 'B) (equal? (fact-attrs f) '(partial))))
                            facts)))
  (claims (dep-claim 'internal (state->judgment sa) ca)
          (if (and (pair? partials) (not (eq? sb 'discharged)))
              (dep-claim 'external 'Violated partials)
              (dep-claim 'external (state->judgment sb) cb))))

(define PROTOCOL (hasheq))
(define INTERFACE (hasheq 'receipt? #t 'view 'full))

(define cupid-arms
  (list (arm 'external 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'external 'cupid-e PROTOCOL INTERFACE (judge #t))))
