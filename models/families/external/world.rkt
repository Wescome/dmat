#lang racket/base
;; Family 6 — partial external execution. Conduct is exogenous; the protocol
;; decides only what H can observe (an external receipt or not).

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide external)

(define SLOTS '(a-done b-outcome report receipt read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (canonical w)
  (list 'world (ref w 'a-done) (ref w 'b-outcome)
        (if (ref w 'a-done) 'honest (ref w 'report))
        (if (eq? (ref w 'b-outcome) 'none) 'dropped (ref w 'receipt))
        (ref w 'read)))

(define BASE (hash 'a-done '((#t . 3) (#f . 1))
                   'b-outcome '((complete . 1))
                   'report '((honest . 1))
                   'receipt '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'external-failure (hash 'b-outcome '((complete . 2) (partial . 1) (none . 1))))
        (cons 'premature (hash 'report '((honest . 1) (premature . 1))
                               'b-outcome '((complete . 2) (partial . 1) (none . 1))))
        (cons 'adversarial (hash 'report '((honest . 1) (premature . 1))
                                 'b-outcome '((complete . 2) (partial . 1) (none . 1))
                                 'receipt '((delivered . 3) (dropped . 1))
                                 'read '((fresh . 2) (lag . 1) (unavailable . 1))))))

(define (execute protocol iface w)
  (hasheq 'truth (hasheq 'internal (if (ref w 'a-done) 'Fulfilled 'Violated)
                         'external (if (eq? (ref w 'b-outcome) 'complete) 'Fulfilled 'Violated))
          'gap 0 'required 0))

(define (deliveries protocol iface w)
  (define a (ref w 'a-done)) (define b (ref w 'b-outcome))
  (define msgs
    (append (if (or a (eq? (ref w 'report) 'premature)) (list (list 'msg 'DONE T-DONE T-DISPATCH)) '())
            (if (and (hash-ref iface 'receipt? #f) (not (eq? b 'none)) (eq? (ref w 'receipt) 'delivered))
                (list (list 'msg 'RECEIPT T-RECEIPT T-X b)) '())))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else
       (define wm (if (eq? (ref w 'read) 'lag) LAG-WATERMARK T-READ))
       (define as (if (and a (<= T-A wm)) 'done 'pending))
       (define xs (if (and (hash-ref iface 'receipt? #f) (<= T-X wm)) b 'none))
       (list 'read-ok T-READ (if (eq? (hash-ref iface 'view) 'full) (list 'full as xs wm) (list 'record as)))]))
  (sort (append msgs (list rd)) < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))

(define external
  (family 'external
          (list (dependency 'internal 'Flow) (dependency 'external 'Flow))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))
