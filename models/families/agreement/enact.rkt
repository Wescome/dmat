#lang racket/base
;; Family 3 — multi-party agreement. Enactment adapter (specs/enactment.md):
;; party agent S (the seller); observer B (the buyer), whose CONFIRM or REJECT
;; is the world's. Protocol: the hybrid's fit check and acknowledgement with
;; reconciliation.
;;
;; S's record (state, terms) is S's system of record and holds S's conduct.
;; Truth: B's binding is B's state on receiving S's acknowledgement, so it is
;; recomputed from the enacted deliveries (specs/enactment.md §5).

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide agreement-enactment)

(define PROTOCOL (hasheq 'fit-check #t 'bind 'ack-reconcile))
(define IFACE (hasheq 'view 'full))

(define S (role-spec 'S "the seller S"
                     (list (msg-spec 'Accept 'act '((terms as-proposed altered)) "accept B's proposal, stating the terms you accept with (the instant you sent it)")
                           (msg-spec 'Revoke 'act '() "revoke your offer (the instant you revoked it)")
                           (msg-spec 'Ack 'act '() "acknowledge that you are bound, having processed B's confirmation (the instant you processed it)"))))

(define (brief w role)
  (define r (run PROTOCOL w))
  (append
   (list (format "You accepted B's proposal at instant ~a, with terms ~a."
                 T-ACCEPT-SENT (if (eq? (ref w 'terms) 'as-proposed) "as proposed" "altered (they do not fit B's requirement)")))
   (cond [(not (hash-ref r 'confirm-sent)) (list "B rejected your terms.")]
         [(eq? (ref w 'confirm) 'dropped) (list "No confirmation from B reached you.")]
         [else (list (format "B's confirmation reached you; you processed it at instant ~a." T-S-PROCESS))])
   (cond [(and (ref w 'revoke) (hash-ref r 's-revoked))
          (list (format "You revoked your offer at instant ~a; you are not bound." T-CONFIRM))]
         [(ref w 'revoke)
          (list (format "You decided at instant ~a to revoke your offer, but you processed B's confirmation first: you did not revoke." T-CONFIRM))]
         [else '()])
   (if (hash-ref r 's-bound) (list (format "You are bound to the agreement from instant ~a." T-S-PROCESS)) (list "You are not bound to the agreement."))))

(define (faithful w role)
  (define r (run PROTOCOL w))
  (append (list (make-ev S 'Accept T-ACCEPT-SENT 'terms (ref w 'terms)))
          (if (hash-ref r 's-revoked) (list (make-ev S 'Revoke T-CONFIRM)) '())
          (if (hash-ref r 's-bound) (list (make-ev S 'Ack T-S-PROCESS)) '())))

(define (assemble w events)
  (define r (run PROTOCOL w))
  (define s-evs (evs-of events 'S))
  (define acc (for/list ([e (msg-of s-evs 'Accept)])
                (list 'msg 'ACCEPT (+ (ev-at e) (- T-ACCEPT-ARR T-ACCEPT-SENT)) (ev-at e) (ev-field e 'terms))))
  (define own (if (hash-ref r 'confirm-sent)
                  (list (list 'msg 'CONFIRM T-CONFIRM T-CONFIRM))
                  (list (list 'msg 'REJECT T-CONFIRM T-CONFIRM))))
  (define rev (for/list ([e (msg-of s-evs 'Revoke)])
                (list 'msg 'REVOKE (+ (ev-at e) (- T-S-PROCESS T-CONFIRM)) (ev-at e))))
  (define ack (for/list ([e (msg-of s-evs 'Ack)]
                         #:when (or (not (hash-ref r 's-bound)) (eq? (ref w 'ack) 'delivered)))
                (list 'msg 'ACK (+ (ev-at e) (- T-ACK-ARR T-S-PROCESS)) (ev-at e))))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
            (list 'read-ok T-READ (list 'full ((hash-ref r 's-state-at) as-of) (ref w 'terms) as-of))]))
  (values (by-arrival (append acc own rev ack (list rd))) '()))

(define (truth w ds)
  (define r (run PROTOCOL w))
  (define s-bound (and (hash-ref r 's-bound) #t))
  (define b-bound (or (and (findf (λ (d) (and (eq? (car d) 'msg) (eq? (cadr d) 'ACK))) ds) #t)
                      (and (eq? (ref w 'read) 'fresh) s-bound)))
  (hasheq 'fit (if (and (or b-bound s-bound) (eq? (ref w 'terms) 'altered)) 'Violated 'Fulfilled)
          'mutual (if (eq? b-bound s-bound) 'Fulfilled 'Violated)))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (case (cadr d)
               [(ACCEPT) (format "[~a] arrived at ~a: ACCEPT from S, sent at ~a, terms ~a" i (caddr d) (cadddr d) (list-ref d 4))]
               [(CONFIRM REJECT) (format "[~a] at ~a: your own ~a, sent to S" i (caddr d) (cadr d))]
               [else (format "[~a] arrived at ~a: ~a from S, for instant ~a" i (caddr d) (cadr d) (cadddr d))])]
      [(read-failed) (format "[~a] at ~a: the read-back of S's record failed" i (cadr d))]
      [(read-ok) (define v (caddr d))
                 (format "[~a] at ~a: read-back of S's record as of instant ~a — S's state ~a, terms ~a" i (cadr d) (cadddr v) (cadr v) (caddr v))])))

(define texts
  (hasheq
   'scenario (format (string-append
                      "You are a buyer B. You proposed terms to a seller S. S accepts, with your proposed terms or with altered terms that do not fit your requirement; S's acceptance is sent at ~a and arrives at ~a. "
                      "You confirm only terms that fit, and reject others, at ~a. S binds when it processes your confirmation at ~a and acknowledges (ACK), which arrives at ~a. "
                      "S may revoke its offer concurrently with your confirmation; S processes the two in either order. You are bound when you receive S's ACK, or, failing it, when a read-back of S's record complete past ~a shows S bound. "
                      "At ~a you read back S's record.")
                     T-ACCEPT-SENT T-ACCEPT-ARR T-CONFIRM T-S-PROCESS T-ACK-ARR T-S-PROCESS T-READ)
   'deps (list (cons 'fit "no party is bound to terms that do not fit your requirement")
               (cons 'mutual "you and S agree on whether you are bound (neither bound alone)"))
   'commitments (format "C_S = C(S, B, your CONFIRM by ~a, S bound by ~a): S is bound iff C_S is discharged; S is not bound if C_S is violated or expired, if S revoked, or if you rejected (S binds only on a confirmation). mutual holds iff your binding equals S's; fit is violated iff you confirmed terms that do not fit."
                        T-CONFIRM T-S-PROCESS)
   'evidence "S's ACCEPT, REVOKE and ACK are S's own acts and are evidence of themselves; binding is an act, so S's record showing S bound is evidence of it. Your own CONFIRM or REJECT is your act. S's record is complete only through its as-of instant: it shows that S is not bound only if it is complete through the instant S processes your confirmation."
   'render render))

(define agreement-enactment
  (enactment 'agreement (list S) 'B T-EVAL brief faithful assemble truth texts))
