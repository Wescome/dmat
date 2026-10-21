#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `agreement`.
;; Written from specs/commitments/agreement.md, specs/agreement.md,
;; specs/bspl/agreement.bspl and specs/commitments/README.md only.
;;
;; Information base (observer B):
;;   (msg ACCEPT 2 1 terms) -> ACCEPT, S, act, 1, (terms)
;;   (msg CONFIRM 2 2)      -> CONFIRM, B, act, T-CONFIRM
;;   (msg REJECT 2 2)       -> REJECT, B, act, T-CONFIRM
;;   (msg REVOKE 3 2)       -> REVOKE, S, act, T-CONFIRM
;;   (msg ACK 4 3)          -> BIND, S, act, T-S-PROCESS
;;   (read-ok 11 (full ss terms as-of))
;;                          -> bound: BIND S act T-S-PROCESS; revoked: REVOKE S act T-S-PROCESS;
;;                             coverage S through as-of for BIND REVOKE
;;   B's own log            -> coverage B through T-READ for CONFIRM REJECT, index #f
;; Commitment: C_S = C(S, B, CONFIRM by T-CONFIRM, BIND by T-S-PROCESS).
;; S bound: C_S discharged -> bound; REVOKE fact -> not bound; REJECT fact ->
;;   not bound; C_S violated/expired -> not bound; else unknown.
;; B bound: an ACK, or a read with ss = bound (cupid-e: only if as-of >= T-S-PROCESS).
;; fit: Violated iff B sent CONFIRM and ACCEPT carried `altered`.
;; mutual: Indeterminate if S's binding unknown; else agreement of both bindings.
;;
;; AMBIGUITY: "cite it" for the REVOKE / REJECT rules cites every delivery that
;; yields a REVOKE (resp. REJECT) fact (the message and/or the read).
;; AMBIGUITY: when B is not bound, B's binding cites nothing (no ACK and no read
;; was used); `mutual` then cites S's binding citations only.
;; AMBIGUITY: when S is "not bound" by C_S violated/expired, S's binding cites
;; the state's citations.
;; AMBIGUITY: a read-ok whose view is not the `full` form yields no facts, no
;; coverage, and does not establish B's binding.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/agreement/terms.rkt")
(provide cupid-arms)

(define (info-base ds)
  (define facts '())
  (define covs (list (coverage 'B T-READ '(CONFIRM REJECT) #f)))
  (for ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg)
       (case (cadr d)
         [(ACCEPT) (set! facts (cons (fact 'ACCEPT 'S 'act (msg-asserted d) (msg-payload d) i) facts))]
         [(CONFIRM) (set! facts (cons (fact 'CONFIRM 'B 'act T-CONFIRM '() i) facts))]
         [(REJECT) (set! facts (cons (fact 'REJECT 'B 'act T-CONFIRM '() i) facts))]
         [(REVOKE) (set! facts (cons (fact 'REVOKE 'S 'act T-CONFIRM '() i) facts))]
         [(ACK) (set! facts (cons (fact 'BIND 'S 'act T-S-PROCESS '() i) facts))]
         [else (void)])]
      [(read-ok)
       (define v (caddr d))
       (when (and (pair? v) (eq? (car v) 'full))
         (define ss (cadr v))
         (define as-of (cadddr v))
         (case ss
           [(bound) (set! facts (cons (fact 'BIND 'S 'act T-S-PROCESS '() i) facts))]
           [(revoked) (set! facts (cons (fact 'REVOKE 'S 'act T-S-PROCESS '() i) facts))]
           [else (void)])
         (set! covs (append covs (list (coverage 'S as-of '(BIND REVOKE) i)))))]
      [else (void)]))
  (values (reverse facts) covs))

(define (ev? e) (λ (f) (eq? (fact-event f) e)))
(define C_S (commitment 'C_S 'S 'B (ev? 'CONFIRM) T-CONFIRM (ev? 'BIND) T-S-PROCESS))

(define (indices-of facts e) (map fact-index (filter (ev? e) facts)))

(define ((judge evidential?) ds)
  (define-values (facts covs) (info-base ds))
  (define-values (st st-cites)
    (commitment-state C_S facts covs #:evidential? evidential?
                      #:a-kinds '(CONFIRM) #:c-kinds '(BIND)))
  (define revokes (indices-of facts 'REVOKE))
  (define rejects (indices-of facts 'REJECT))
  ;; S's binding: 'bound | 'unbound | 'unknown, with citations
  (define-values (s-bind s-cites)
    (cond
      [(eq? st 'discharged) (values 'bound st-cites)]
      [(pair? revokes) (values 'unbound revokes)]
      [(pair? rejects) (values 'unbound rejects)]
      [(memq st '(violated expired)) (values 'unbound st-cites)]
      [else (values 'unknown '())]))
  ;; B's binding under ack-reconcile
  (define acks (map car (msgs ds 'ACK)))
  (define ri (read-index ds))
  (define rv (read-view ds))
  (define read-used
    (if (and ri (pair? rv) (eq? (car rv) 'full) (eq? (cadr rv) 'bound)
             (or (not evidential?) (>= (cadddr rv) T-S-PROCESS)))
        (list ri)
        '()))
  (define b-cites (append acks read-used))
  (define b-bound? (pair? b-cites))
  ;; fit
  (define accepts (msgs ds 'ACCEPT))
  (define confirms (map car (msgs ds 'CONFIRM)))
  (define altered? (for/or ([p accepts]) (memq 'altered (msg-payload (cdr p)))))
  (define fit
    (dep-claim 'fit (if (and (pair? confirms) altered?) 'Violated 'Fulfilled)
               (append (map car accepts) confirms (map car (msgs ds 'REJECT)))))
  (define mutual
    (if (eq? s-bind 'unknown)
        (dep-claim 'mutual 'Indeterminate '())
        (dep-claim 'mutual
                   (if (eq? b-bound? (eq? s-bind 'bound)) 'Fulfilled 'Violated)
                   (append b-cites s-cites))))
  (claims fit mutual))

(define PROTOCOL (hasheq 'fit-check #t 'bind 'ack-reconcile))
(define INTERFACE (hasheq 'view 'full))

(define cupid-arms
  (list (arm 'agreement 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'agreement 'cupid-e PROTOCOL INTERFACE (judge #t))))
