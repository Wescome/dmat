#lang racket/base
;; Family 7 — multi-organization composition. Conduct is exogenous; the
;; interface's observation model ('obs: coarse | staged) decides what V's case
;; record shows H. P2 varies only that.

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide composition)

(define SLOTS '(s-stage s-report assemble delivered-msg attest read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (s-start w) (case (ref w 's-stage) [(on-time) T-S-ON-TIME] [(late) T-S-LATE] [else #f]))
(define (canonical w)
  (define st (s-start w))
  (define assembles (and st (ref w 'assemble)))
  (list 'world (ref w 's-stage)
        (if (eq? (ref w 's-stage) 'on-time) 'honest (ref w 's-report))
        assembles
        (if assembles (ref w 'delivered-msg) 'dropped)
        (if st (ref w 'attest) 'dropped)
        (ref w 'read)))

(define BASE (hash 's-stage '((on-time . 3) (late . 1) (committed . 1) (declined . 1))
                   's-report '((honest . 1))
                   'assemble '((#t . 4) (#f . 1))
                   'delivered-msg '((delivered . 1))
                   'attest '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'lossy (hash 'delivered-msg '((delivered . 1) (dropped . 1)) 'read '((fresh . 2) (unavailable . 1))))
        (cons 'self-report (hash 's-report '((honest . 1) (premature . 1))))
        (cons 'adversarial (hash 's-report '((honest . 1) (premature . 1))
                                 'delivered-msg '((delivered . 1) (dropped . 1))
                                 'attest '((delivered . 3) (dropped . 1))
                                 'read '((fresh . 2) (unavailable . 1))))))

(define (delivers? w) (and (s-start w) (ref w 'assemble)))

(define (execute protocol iface w)
  (define st (s-start w))
  (hasheq 'truth (hasheq 'temporal (if (and st (<= st DEADLINE)) 'Fulfilled 'Violated)
                         'delivery (if (delivers? w) 'Fulfilled 'Violated))
          'gap 0 'required 0))

;; S's stage as S reported it to V, by as-of
(define (reported-stage w as-of)
  (define premature (eq? (ref w 's-report) 'premature))
  (define st (if premature T-S-ON-TIME (s-start w)))
  (cond [(and st (<= st as-of)) (values 'started st)]
        [(eq? (ref w 's-stage) 'declined) (values (if (<= T-COMMIT as-of) 'declined 'none) #f)]
        [else (values (if (<= T-COMMIT as-of) 'committed 'none) #f)]))

(define (deliveries protocol iface w)
  (define st (s-start w))
  (define msgs
    (append (if (and (delivers? w) (eq? (ref w 'delivered-msg) 'delivered))
                (list (list 'msg 'DELIVERED (+ 1 T-DELIVER) T-DELIVER)) '())
            (if (and st (hash-ref iface 'attest? #f) (eq? (ref w 'attest) 'delivered))
                (list (list 'msg 'ATTEST (+ st ATTEST-DELAY) st)) '())))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else
       (define cs (if (and (delivers? w) (<= T-DELIVER T-READ)) 'closed 'open))
       (define-values (ss ot) (reported-stage w T-READ))
       (list 'read-ok T-READ (case (hash-ref iface 'obs)
                               [(coarse) (list 'case cs)]
                               [(staged) (list 'staged cs ss ot)]))]))
  (sort (append msgs (list rd)) < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))

(define composition
  (family 'composition
          (list (dependency 'temporal 'Temporal) (dependency 'delivery 'Flow))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))

;; for the enactment adapter (enact.rkt) only
(module+ internals (provide ref s-start delivers? reported-stage))
