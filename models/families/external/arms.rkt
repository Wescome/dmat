#lang racket/base
;; Family 6 — partial external execution. The five arms.

(require "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (internal-from-record ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (cond [(and v (eq? (cadr v) 'done)) (list 'internal 'Fulfilled (list ri))]
        [v (list 'internal 'Violated (list ri))]
        [else #f]))

;; DONE is V's report that the order is complete (both parts).

;; CHOR — H→V ORDER; V→H DONE. X's part is V's local step; the session ends
;; on DONE, which names the order's completion: both parts Fulfilled. Without
;; DONE, V's session log decides the internal part, and with no log the
;; session's wait for DONE timed out (Violated); X's part is outside H's
;; projection (Indeterminate).
(define (chor-judge ds)
  (define done (msg-indices ds 'DONE))
  (if (pair? done)
      (claims (list 'internal 'Fulfilled done) (list 'external 'Fulfilled done))
      (claims (or (internal-from-record ds) (list 'internal 'Violated '()))
              (list 'external 'Indeterminate '()))))

;; FSM — V: ordered → a-done → dispatched → reported. V's state record decides
;; the internal part; without it, H's machine: DONE received (Fulfilled), or
;; its timeout fired (Violated). The machine ends at 'dispatched', so the
;; external part has no state in it: Indeterminate.
(define (fsm-judge ds)
  (claims (or (internal-from-record ds)
              (let ([done (msg-indices ds 'DONE)])
                (if (pair? done) (list 'internal 'Fulfilled done) (list 'internal 'Violated '()))))
          (list 'external 'Indeterminate '())))

;; COMM — C(V,H, ordered, A ∧ B). V's DONE discharges the commitment: both
;; parts Fulfilled. Without DONE, V's ledger: A pending at the read leaves the
;; conjunction unmet (both Violated); A done without DONE leaves B open
;; (Indeterminate). With neither DONE nor ledger, the creditor has not seen the
;; commitment discharged by its deadline: both Violated.
(define (comm-judge ds)
  (define done (msg-indices ds 'DONE))
  (define ri (read-index ds)) (define v (read-view ds))
  (cond [(pair? done) (claims (list 'internal 'Fulfilled done) (list 'external 'Fulfilled done))]
        [(and v (eq? (cadr v) 'pending)) (claims (list 'internal 'Violated (list ri)) (list 'external 'Violated (list ri)))]
        [v (claims (list 'internal 'Fulfilled (list ri)) (list 'external 'Indeterminate '()))]
        [else (claims (list 'internal 'Violated '()) (list 'external 'Violated '()))]))

;; HYBRID — COMM's commitment split per part. A is V's own performance: V's
;; DONE and V's record entry 'done' are V's reports (E1) and establish nothing
;; positive; V's record showing A pending, complete past T-A, establishes the
;; negative. B is X's: X's signed receipt, or V's relayed copy of it when the
;; watermark covers T-X, decides it (complete: Fulfilled; partial: Violated);
;; a record complete past T-X relaying no outcome is a violation.
;; HYBRID-NOE: every report is evidence and a successful read is authoritative
;; over messages; with no read, the receipt, then DONE; where the hybrid would
;; abstain, the commitment rule applies (not seen discharged: Violated).
(define ((hybrid-judge evidence?) ds)
  (define ri (read-index ds)) (define v (read-view ds))
  (define-values (as xs wm) (if v (values (list-ref v 1) (list-ref v 2) (list-ref v 3)) (values #f #f #f)))
  (define (auth? due) (and v (or (not evidence?) (>= wm due))))
  (define done (msg-indices ds 'DONE))
  (define rc (for/first ([i (msg-indices ds 'RECEIPT)]) (cons i (car (msg-payload (list-ref ds i))))))
  (if evidence?
      (claims (cond [(and (auth? T-A) (eq? as 'pending)) (list 'internal 'Violated (list ri))]
                    [else (list 'internal 'Indeterminate '())])
              (cond [rc (list 'external (if (eq? (cdr rc) 'complete) 'Fulfilled 'Violated) (list (car rc)))]
                    [(and (auth? T-X) (eq? xs 'complete)) (list 'external 'Fulfilled (list ri))]
                    [(auth? T-X) (list 'external 'Violated (list ri))]
                    [else (list 'external 'Indeterminate '())]))
      (claims (cond [v (list 'internal (if (eq? as 'done) 'Fulfilled 'Violated) (list ri))]
                    [(pair? done) (list 'internal 'Fulfilled done)]
                    [else (list 'internal 'Violated '())])
              (cond [v (list 'external (if (eq? xs 'complete) 'Fulfilled 'Violated) (list ri))]
                    [rc (list 'external (if (eq? (cdr rc) 'complete) 'Fulfilled 'Violated) (list (car rc)))]
                    [(pair? done) (list 'external 'Fulfilled done)]
                    [else (list 'external 'Violated '())]))))

(define arms
  (list (arm 'external 'chor (hasheq) (hasheq 'receipt? #f 'view 'record) chor-judge)
        (arm 'external 'fsm (hasheq) (hasheq 'receipt? #f 'view 'record) fsm-judge)
        (arm 'external 'comm (hasheq) (hasheq 'receipt? #f 'view 'record) comm-judge)
        (arm 'external 'hybrid (hasheq) (hasheq 'receipt? #t 'view 'full) (hybrid-judge #t))
        (arm 'external 'hybrid-noe (hasheq) (hasheq 'receipt? #t 'view 'full) (hybrid-judge #f))))
