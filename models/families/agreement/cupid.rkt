#lang racket/base
;; Family 3 — multi-party agreement. Commitment arms over the buyer B's
;; information base (core/cupid.rkt), with the hybrid's protocol: B checks the
;; terms before confirming, and is bound on S's acknowledgement or on a
;; read-back of S's record showing S bound.
;;
;;   C_S = C(S, B, CONFIRM by T-CONFIRM, BIND by T-S-PROCESS)
;;         discharged → S bound; violated, expired or released (S's REVOKE) →
;;         S not bound; B's REJECT → S not bound (the protocol binds S only on
;;         a confirmation); unknown → S's binding is not established
;;   mutual : B's binding (B's own state under the protocol) against S's
;;   fit    : B's CONFIRM of terms that do not fit B's requirement violates it
;;
;; Information: ACCEPT (S's act, with the terms), REVOKE (S's act), B's own
;; CONFIRM or REJECT (acts; B's outbox is a record of B's acts complete through
;; the read), ACK (S's act of binding, as asserted at S's processing), and S's
;; record: state bound gives a BIND fact, revoked a REVOKE fact; the record is
;; a coverage of BIND and REVOKE through its as-of instant.
;; cupid: closed-world reading. cupid-e: E1–E3 (binding is an act, so S's own
;; record of it counts; absence needs S's record complete through T-S-PROCESS).

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define (from M ev src t) (for/list ([i (msg-indices ds M)]) (fact ev src 'act t '() i)))
  (define facts
    (append (for/list ([i (msg-indices ds 'ACCEPT)])
              (fact 'ACCEPT 'S 'act (msg-asserted (list-ref ds i)) (msg-payload (list-ref ds i)) i))
            (from 'CONFIRM 'CONFIRM 'B T-CONFIRM)
            (from 'REJECT 'REJECT 'B T-CONFIRM)
            (from 'REVOKE 'REVOKE 'S T-CONFIRM)
            (from 'ACK 'BIND 'S T-S-PROCESS)
            (if v
                (case (cadr v)
                  [(bound) (list (fact 'BIND 'S 'act T-S-PROCESS '() ri))]
                  [(revoked) (list (fact 'REVOKE 'S 'act T-S-PROCESS '() ri))]
                  [else '()])
                '())))
  (define covs
    (append (list (coverage 'B T-READ '(CONFIRM REJECT) #f))
            (if v (list (coverage 'S (cadddr v) '(BIND REVOKE) ri)) '())))
  (values facts covs v ri))

(define (is e) (λ (f) (eq? (fact-event f) e)))
(define C-S (commitment 'C-S 'S 'B (is 'CONFIRM) T-CONFIRM (is 'BIND) T-S-PROCESS))

(define ((judge ev) ds)
  (define-values (facts covs v ri) (info ds))
  (define-values (st cites) (commitment-state C-S facts covs #:evidential? ev #:a-kinds '(CONFIRM) #:c-kinds '(BIND)))
  (define revokes (map fact-index (filter (is 'REVOKE) facts)))
  (define rejects (map fact-index (filter (is 'REJECT) facts)))
  ;; S's binding: (cons bound? cites) or #f
  (define s
    (cond [(eq? st 'discharged) (cons #t cites)]
          [(pair? revokes) (cons #f revokes)]
          ;; the protocol binds S only on B's confirmation: B's REJECT settles it
          [(pair? rejects) (cons #f rejects)]
          [(memq st '(violated expired)) (cons #f (append cites (map fact-index (filter (is 'REJECT) facts))))]
          [else #f]))
  ;; B's binding under the protocol: the ACK, or a read-back of S's record,
  ;; complete past S's processing, showing S bound
  (define acks (msg-indices ds 'ACK))
  (define reconciled (and v (eq? (cadr v) 'bound) (or (not ev) (>= (cadddr v) T-S-PROCESS))))
  (define b-bound (or (pair? acks) (and reconciled #t)))
  (define b-cites (append acks (if reconciled (list ri) '())))
  (define accept (findf (is 'ACCEPT) facts))
  (define confirm (filter (is 'CONFIRM) facts))
  (define fit-cites (append (list (fact-index accept)) (map fact-index confirm)
                            (map fact-index (filter (is 'REJECT) facts))))
  (claims (dep-claim 'fit (if (and (pair? confirm) (eq? (car (fact-attrs accept)) 'altered)) 'Violated 'Fulfilled) fit-cites)
          (if s
              (dep-claim 'mutual (if (eq? b-bound (car s)) 'Fulfilled 'Violated) (filter values (append b-cites (cdr s))))
              (dep-claim 'mutual 'Indeterminate '()))))

(define P (hasheq 'fit-check #t 'bind 'ack-reconcile))
(define I (hasheq 'view 'full))
(define cupid-arms
  (list (arm 'agreement 'cupid P I (judge #f))
        (arm 'agreement 'cupid-e P I (judge #t))))
