#lang racket/base
;; Family 6 — partial external execution. Commitment arms over the client H's
;; information base (core/cupid.rkt), with the hybrid's protocol: X's signed
;; receipt, and V's record relaying it.
;;
;;   C_A = C(V, H, ⊤, A by T-DISPATCH)   → internal
;;   C_B = C(V, H, ⊤, B by T-X)          → external
;;        V owes the whole service; X is not a protocol participant. The
;;        deadlines are the protocol's schedule: V performs A (at T-A) before
;;        it dispatches B at T-DISPATCH, and X performs B at T-X, or not at all.
;;   A partial outcome of B, reported by X (directly or relayed by V's record
;;   complete past T-X), is a known non-performance of B in full: Violated.
;;
;; Information: V's DONE is V's report of its own performance of the service
;; (A and B); V's record entry A done is V's report; X's receipt (signed, so
;; X's report even when relayed) reports B's outcome; V's record is a coverage
;; of A and B through its watermark.
;; cupid: closed-world reading. cupid-e: E1–E3.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define-values (as xs wm) (if v (values (list-ref v 1) (list-ref v 2) (list-ref v 3)) (values #f #f #f)))
  (define receipts
    (for/list ([i (msg-indices ds 'RECEIPT)])
      (fact 'B 'X 'performance (msg-asserted (list-ref ds i)) (msg-payload (list-ref ds i)) i)))
  (define relayed (if (and v (memq xs '(complete partial))) (list (fact 'B 'X 'performance T-X (list xs) ri)) '()))
  (define facts
    (append
     (for*/list ([i (msg-indices ds 'DONE)] [e '(A B)])
       (fact e 'V 'performance (msg-asserted (list-ref ds i)) '(complete) i))
     (if (and v (eq? as 'done)) (list (fact 'A 'V 'performance T-A '() ri)) '())
     receipts relayed))
  (define covs (if v (list (coverage 'V wm '(A B) ri)) '()))
  (values facts covs))

(define (part e outcome) (λ (f) (and (eq? (fact-event f) e) (or (null? (fact-attrs f)) (eq? (car (fact-attrs f)) outcome)))))
(define C-A (commitment 'C-A 'V 'H 'true 0 (part 'A 'complete) T-DISPATCH))
(define C-B (commitment 'C-B 'V 'H 'true 0 (part 'B 'complete) T-X))

(define ((judge ev) ds)
  (define-values (facts covs) (info ds))
  (define-values (sa ca) (commitment-state C-A facts covs #:evidential? ev #:a-kinds '() #:c-kinds '(A)))
  (define-values (sb cb) (commitment-state C-B facts covs #:evidential? ev #:a-kinds '() #:c-kinds '(B)))
  (define partial (map fact-index (filter (part 'B 'partial) (filter (λ (f) (pair? (fact-attrs f))) facts))))
  (claims (dep-claim 'internal (state->judgment sa) ca)
          (if (and (pair? partial) (not (eq? sb 'discharged)))
              (dep-claim 'external 'Violated partial)
              (dep-claim 'external (state->judgment sb) cb))))

(define P (hasheq))
(define I (hasheq 'receipt? #t 'view 'full))
(define cupid-arms
  (list (arm 'external 'cupid P I (judge #f))
        (arm 'external 'cupid-e P I (judge #t))))
