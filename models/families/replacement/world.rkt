#lang racket/base
;; Family 8 — dynamic participant replacement. Protocol feature
;; 'on-withdraw: 'release (V's responsibility ends at withdrawal) |
;; 'retain (V stays responsible until V2 accepts, and resumes if V2 declines).

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide replacement)

(define SLOTS '(withdraw v2-accepts start ghost notice attest read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (canonical w)
  (define wd (ref w 'withdraw))
  (list 'world wd (and wd (ref w 'v2-accepts)) (ref w 'start) (and wd (ref w 'ghost))
        (ref w 'notice) (ref w 'attest) (ref w 'read)))

(define BASE (hash 'withdraw '((#t . 1) (#f . 1))
                   'v2-accepts '((#t . 3) (#f . 1))
                   'start '((#t . 3) (#f . 1))
                   'ghost '((#f . 1))
                   'notice '((delivered . 1))
                   'attest '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'ghost (hash 'ghost '((#f . 1) (#t . 1))))
        (cons 'stale-read (hash 'notice '((delivered . 1) (dropped . 1)) 'read '((fresh . 1) (stale . 1) (unavailable . 1))))
        (cons 'adversarial (hash 'ghost '((#f . 1) (#t . 1)) 'notice '((delivered . 1) (dropped . 1))
                                 'attest '((delivered . 3) (dropped . 1)) 'read '((fresh . 1) (stale . 1) (unavailable . 1))))))

(define (run protocol w)
  (define retain (eq? (hash-ref protocol 'on-withdraw) 'retain))
  (define wd (ref w 'withdraw))
  (define v2 (and wd (ref w 'v2-accepts)))
  (define performer (cond [(not wd) 'V] [v2 'V2] [retain 'V] [else #f]))
  (define start-at (and performer (ref w 'start)
                        (cond [(not wd) T-V-START] [v2 T-V2-START] [else T-RESUME])))
  (define end (or start-at T-EVAL))
  (define gap (cond [(not wd) 0] [retain 0] [v2 (- T-V2 T-WITHDRAW)] [else (- end T-WITHDRAW)]))
  (hasheq 'wd wd 'v2 v2 'retain retain 'performer performer 'start-at start-at
          'gap gap 'required (- end T-ACCEPT)))

;; the registry of the role holder and whether care started, as of as-of
(define (registry r as-of)
  (define wd (hash-ref r 'wd)) (define v2 (hash-ref r 'v2)) (define retain (hash-ref r 'retain))
  (define st (hash-ref r 'start-at))
  (define holder
    (cond [(or (not wd) (< as-of T-WITHDRAW)) 'V]
          [(< as-of T-V2) (if retain 'V 'none)]
          [v2 'V2]
          [retain 'V]
          [else 'none]))
  (values holder (and st (<= st as-of) #t)))

(define (execute protocol iface w)
  (define r (run protocol w))
  (hasheq 'truth (hasheq 'continuity (if (zero? (hash-ref r 'gap)) 'Fulfilled 'Violated)
                         'temporal (if (and (hash-ref r 'start-at) (<= (hash-ref r 'start-at) DEADLINE)) 'Fulfilled 'Violated))
          'gap (hash-ref r 'gap) 'required (hash-ref r 'required)))

(define (deliveries protocol iface w)
  (define r (run protocol w))
  (define st (hash-ref r 'start-at)) (define who (if (eq? (hash-ref r 'performer) 'V2) 'V2 'V))
  (define msgs
    (append (list (list 'msg 'ACCEPT (+ 1 T-ACCEPT) T-ACCEPT))
            (if (hash-ref r 'wd) (list (list 'msg 'WITHDRAW (+ 1 T-WITHDRAW) T-WITHDRAW)) '())
            (if (and st (eq? (ref w 'notice) 'delivered)) (list (list 'msg 'START (+ st NOTICE-DELAY) st who)) '())
            (if (ref w 'ghost) (list (list 'msg 'START (+ T-V-START NOTICE-DELAY) T-V-START 'V)) '())
            (if (and st (hash-ref iface 'attest? #f) (eq? (ref w 'attest) 'delivered))
                (list (list 'msg 'ATTEST (+ st ATTEST-DELAY) st who)) '())))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else
       (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
       (define-values (holder started) (registry r as-of))
       (list 'read-ok T-READ (if (eq? (hash-ref iface 'view) 'full)
                                 (list 'full holder started as-of)
                                 (list 'registry holder started)))]))
  (sort (append msgs (list rd)) < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))

(define replacement
  (family 'replacement
          (list (dependency 'continuity 'Flow) (dependency 'temporal 'Temporal))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))
