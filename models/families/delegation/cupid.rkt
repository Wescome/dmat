#lang racket/base
;; Family 4 — conditional delegation. Commitment arms over the hospital H's
;; information base (core/cupid.rkt), with the hybrid's protocol: V retains
;; responsibility when it delegates (outsourcing), so S performs as V's
;; delegate and C1 stays V's until discharged.
;;
;;   C1 = C(V, H, ACCEPT by T-ACCEPT, START by DEADLINE)   → temporal
;;        (expired: V never accepted, care never initiated → Violated)
;;   continuity: Violated only if V's ledger shows C1 released (responsibility
;;        handed to nobody); otherwise Fulfilled, since retention keeps C1
;;        V's from acceptance to discharge
;;
;; Information: ACCEPT is V's act; a START notice (from V or from S, V's
;; delegate) is the debtor side's report of its own performance; ATTEST is a
;; third party's report; V's record (state, ledger, S's stage) is a coverage of
;; START through its as-of instant, and a ledger entry C1 discharged is V's
;; report that care was initiated within C1's deadline.
;; cupid: closed-world reading. cupid-e: E1–E3.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define facts
    (append
     (for/list ([i (msg-indices ds 'ACCEPT)]) (fact 'ACCEPT 'V 'act (msg-asserted (list-ref ds i)) '() i))
     (for/list ([i (msg-indices ds 'START)]) (fact 'START 'V 'performance (msg-asserted (list-ref ds i)) '() i))
     (for/list ([i (msg-indices ds 'ATTEST)]) (fact 'START 'attester 'performance (msg-asserted (list-ref ds i)) '() i))
     (if (and v (eq? (list-ref v 2) 'discharged))
         (list (fact 'START 'V 'performance (min (list-ref v 5) DEADLINE) '() ri))
         '())))
  (define covs (if v (list (coverage 'V (list-ref v 5) '(START) ri)) '()))
  (values facts covs v ri))

(define (is e) (λ (f) (eq? (fact-event f) e)))
(define C1 (commitment 'C1 'V 'H (is 'ACCEPT) T-ACCEPT (is 'START) DEADLINE))

(define ((judge ev) ds)
  (define-values (facts covs v ri) (info ds))
  (define-values (s1 c1) (commitment-state C1 facts covs #:evidential? ev #:a-kinds '(ACCEPT) #:c-kinds '(START)))
  (define accept (map fact-index (filter (is 'ACCEPT) facts)))
  (claims (if (and v (eq? (list-ref v 2) 'released))
              (dep-claim 'continuity 'Violated (list ri))
              (dep-claim 'continuity 'Fulfilled accept))
          (dep-claim 'temporal (state->judgment s1 #:expired 'Violated) c1)))

(define P (hasheq 'on-delegate 'retain))
(define I (hasheq 'notice? #t 'attest? #t 'view 'full))
(define cupid-arms
  (list (arm 'delegation 'cupid P I (judge #f))
        (arm 'delegation 'cupid-e P I (judge #t))))
