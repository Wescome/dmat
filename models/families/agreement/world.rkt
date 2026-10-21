#lang racket/base
;; Family 3 — multi-party agreement. Environment, execution, deliveries.
;; Protocol features: 'fit-check (does B check S's terms before confirming)
;; and 'bind (when B considers itself bound: 'send, on sending CONFIRM; 'ack,
;; on receiving S's acknowledgement; 'ack-reconcile, on the acknowledgement or,
;; failing it, on a read-back of S's record showing S bound).

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide agreement)

(define SLOTS '(terms revoke order confirm ack read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (canonical w)
  (list 'world (ref w 'terms) (ref w 'revoke)
        (if (ref w 'revoke) (ref w 'order) 'confirm-first)
        (ref w 'confirm) (ref w 'ack) (ref w 'read)))

(define BASE (hash 'terms '((as-proposed . 3) (altered . 1))
                   'revoke '((#f . 1))
                   'order '((confirm-first . 1))
                   'confirm '((delivered . 1))
                   'ack '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'lossy (hash 'confirm '((delivered . 1) (dropped . 1)) 'ack '((delivered . 1) (dropped . 1))))
        (cons 'concurrent-revoke (hash 'revoke '((#f . 1) (#t . 1)) 'order '((confirm-first . 1) (revoke-first . 1))))
        (cons 'stale-read (hash 'ack '((delivered . 1) (dropped . 1)) 'read '((fresh . 1) (stale . 1) (unavailable . 1))))
        (cons 'adversarial (hash 'revoke '((#f . 1) (#t . 1)) 'order '((confirm-first . 1) (revoke-first . 1))
                                 'confirm '((delivered . 1) (dropped . 1)) 'ack '((delivered . 1) (dropped . 1))
                                 'read '((fresh . 1) (stale . 1) (unavailable . 1))))))

;; → hasheq with the run's facts
(define (run protocol w)
  (define fit-ok (or (eq? (ref w 'terms) 'as-proposed) (not (hash-ref protocol 'fit-check))))
  (define confirm-sent fit-ok)
  (define confirm-arrives (and confirm-sent (eq? (ref w 'confirm) 'delivered)))
  (define revoke-first (and (ref w 'revoke) (eq? (ref w 'order) 'revoke-first)))
  (define s-bound (and confirm-arrives (not revoke-first)))
  (define s-revoked (and (ref w 'revoke) (not s-bound)))
  (define ack-arrives (and s-bound (eq? (ref w 'ack) 'delivered)))
  (define s-state-at (λ (as-of) (cond [(< as-of T-S-PROCESS) 'offered] [s-bound 'bound] [s-revoked 'revoked] [else 'offered])))
  (define read-auth (eq? (ref w 'read) 'fresh))
  (define b-bound
    (case (hash-ref protocol 'bind)
      [(send) confirm-sent]
      [(ack) ack-arrives]
      [(ack-reconcile) (or ack-arrives (and read-auth s-bound))]))
  (hasheq 'confirm-sent confirm-sent 's-bound s-bound 's-revoked s-revoked 'ack-arrives ack-arrives
          'b-bound b-bound 's-state-at s-state-at))

(define (execute protocol iface w)
  (define r (run protocol w))
  (define bound-any (or (hash-ref r 'b-bound) (hash-ref r 's-bound)))
  (hasheq 'truth (hasheq 'fit (if (and bound-any (eq? (ref w 'terms) 'altered)) 'Violated 'Fulfilled)
                         'mutual (if (eq? (and (hash-ref r 'b-bound) #t) (and (hash-ref r 's-bound) #t)) 'Fulfilled 'Violated))
          'gap 0 'required 0))

(define (deliveries protocol iface w)
  (define r (run protocol w))
  (define msgs
    (append (list (list 'msg 'ACCEPT T-ACCEPT-ARR T-ACCEPT-SENT (ref w 'terms)))
            (if (hash-ref r 'confirm-sent)
                (list (list 'msg 'CONFIRM T-CONFIRM T-CONFIRM))
                (list (list 'msg 'REJECT T-CONFIRM T-CONFIRM)))
            (if (hash-ref r 's-revoked) (list (list 'msg 'REVOKE T-S-PROCESS T-CONFIRM)) '())
            (if (hash-ref r 'ack-arrives) (list (list 'msg 'ACK T-ACK-ARR T-S-PROCESS)) '())))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else
       (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
       (define ss ((hash-ref r 's-state-at) as-of))
       (list 'read-ok T-READ
             (case (hash-ref iface 'view)
               [(last-message) (list 'last-message (case ss [(bound) 'ACK] [(revoked) 'REVOKE] [else 'ACCEPT]))]
               [(state) (list 'state ss)]
               [(ledger) (list 'ledger (case ss [(bound) 'active] [(revoked) 'released] [else 'none]))]
               [(full) (list 'full ss (ref w 'terms) as-of)]))]))
  (append msgs (list rd)))

(define agreement
  (family 'agreement
          (list (dependency 'fit 'Fit) (dependency 'mutual 'Flow))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))
