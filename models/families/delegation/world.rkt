#lang racket/base
;; Family 4 — conditional delegation. Protocol feature 'on-delegate: 'release | 'retain.

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide delegation)

(define SLOTS '(capacity s-accepts start delegated-msg notice attest read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (canonical w)
  (define cap (ref w 'capacity))
  (list 'world cap (if cap #f (ref w 's-accepts)) (ref w 'start)
        (if cap 'dropped (ref w 'delegated-msg)) (ref w 'notice) (ref w 'attest) (ref w 'read)))

(define BASE (hash 'capacity '((#t . 1) (#f . 1))
                   's-accepts '((#t . 3) (#f . 1))
                   'start '((#t . 3) (#f . 1))
                   'delegated-msg '((delivered . 1))
                   'notice '((delivered . 1))
                   'attest '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'lossy (hash 'delegated-msg '((delivered . 1) (dropped . 1)) 'notice '((delivered . 1) (dropped . 1))))
        (cons 'stale-read (hash 'notice '((delivered . 1) (dropped . 1)) 'read '((fresh . 1) (stale . 1) (unavailable . 1))))
        (cons 'adversarial (hash 'delegated-msg '((delivered . 1) (dropped . 1)) 'notice '((delivered . 1) (dropped . 1))
                                 'attest '((delivered . 3) (dropped . 1)) 'read '((fresh . 1) (stale . 1) (unavailable . 1))))))

(define (run protocol w)
  (define retain (eq? (hash-ref protocol 'on-delegate) 'retain))
  (define cap (ref w 'capacity))
  (define s-acc (and (not cap) (ref w 's-accepts)))
  (define performer (cond [cap 'V] [s-acc 'S] [retain 'V-resumed] [else #f]))
  (define start-at (and performer (ref w 'start) (if (eq? performer 'V-resumed) T-RESUME-START T-START)))
  (define end (or start-at T-EVAL))
  ;; unowned interval
  (define gap
    (cond [cap 0]
          [retain 0]
          [s-acc (- (min T-S-RESPONSE end) T-DELEGATE)]
          [else (- end T-DELEGATE)]))
  (hasheq 'cap cap 's-acc s-acc 'retain retain 'performer performer 'start-at start-at
          'gap gap 'required (- end T-ACCEPT)))

(define (record-at r as-of)
  ;; V's state, V's commitment ledger and S's stage as recorded by as-of
  (define cap (hash-ref r 'cap)) (define retain (hash-ref r 'retain)) (define s-acc (hash-ref r 's-acc))
  (define st (hash-ref r 'start-at)) (define performer (hash-ref r 'performer))
  (define started (and st (<= st as-of)))
  (define responded (<= T-S-RESPONSE as-of))
  (define delegated (and (not cap) (<= T-DELEGATE as-of)))
  (define vs (cond [(and started (eq? performer 'S)) 'sub-started]
                   [started 'started]
                   [(not delegated) 'accepted]
                   [(not retain) 'released]
                   [(not responded) 'delegating]
                   [s-acc 'delegated]
                   [else 'resumed]))
  (define c1 (cond [started 'discharged]
                   [(and delegated (not retain)) 'released]
                   [(and delegated responded s-acc) 'pending]
                   [else 'active]))
  (define c2 (cond [(not delegated) 'none]
                   [(not responded) 'none]
                   [(not s-acc) 'declined]
                   [(and started (eq? performer 'S)) 'discharged]
                   [else 'active]))
  (define stage (cond [(not delegated) 'none]
                      [(not responded) 'none]
                      [(not s-acc) 'declined]
                      [(and started (eq? performer 'S)) 'started]
                      [else 'committed]))
  (values vs c1 c2 stage))

(define (execute protocol iface w)
  (define r (run protocol w))
  (hasheq 'truth (hasheq 'continuity (if (zero? (hash-ref r 'gap)) 'Fulfilled 'Violated)
                         'temporal (if (and (hash-ref r 'start-at) (<= (hash-ref r 'start-at) DEADLINE)) 'Fulfilled 'Violated))
          'gap (hash-ref r 'gap) 'required (hash-ref r 'required)))

(define (deliveries protocol iface w)
  (define r (run protocol w))
  (define st (hash-ref r 'start-at))
  (define msgs
    (append (list (list 'msg 'ACCEPT (+ 1 T-ACCEPT) T-ACCEPT))
            (if (and (not (hash-ref r 'cap)) (eq? (ref w 'delegated-msg) 'delivered))
                (list (list 'msg 'DELEGATED (+ 1 T-DELEGATE) T-DELEGATE)) '())
            (if (and st (hash-ref iface 'notice? #f) (eq? (ref w 'notice) 'delivered))
                (list (list 'msg 'START (+ st NOTICE-DELAY) st)) '())
            (if (and st (hash-ref iface 'attest? #f) (eq? (ref w 'attest) 'delivered))
                (list (list 'msg 'ATTEST (+ st ATTEST-DELAY) st)) '())))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else
       (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
       (define-values (vs c1 c2 stage) (record-at r as-of))
       (list 'read-ok T-READ
             (case (hash-ref iface 'view)
               [(last-message) (list 'last-message (cond [(memq vs '(started sub-started)) 'START]
                                                         [(memq vs '(delegating delegated released)) 'DELEGATED]
                                                         [else 'ACCEPT]))]
               [(state) (list 'state vs)]
               [(ledger) (list 'ledger c1 c2)]
               [(full) (list 'full vs c1 c2 stage as-of)]))]))
  (sort (append msgs (list rd)) < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))

(define delegation
  (family 'delegation
          (list (dependency 'continuity 'Flow) (dependency 'temporal 'Temporal))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))

;; for the enactment adapter (enact.rkt) only
(module+ internals (provide ref run record-at))
