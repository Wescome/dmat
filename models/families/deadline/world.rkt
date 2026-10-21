#lang racket/base
;; Family 5 — deadline-bound service. V's conduct is exogenous.

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide deadline)

(define SLOTS '(done delay skew attest read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (canonical w)
  (define never (eq? (ref w 'done) 'never))
  (list 'world (ref w 'done) (if never 'short (ref w 'delay)) (if never 'none (ref w 'skew))
        (if never 'dropped (ref w 'attest)) (ref w 'read)))

(define BASE (hash 'done '((on-time . 3) (late . 1) (never . 1))
                   'delay '((short . 1))
                   'skew '((none . 1))
                   'attest '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'transit (hash 'delay '((short . 1) (long . 1))))
        (cons 'clock-skew (hash 'skew '((none . 1) (ahead . 1) (behind . 1))))
        (cons 'adversarial (hash 'delay '((short . 1) (long . 1)) 'skew '((none . 1) (ahead . 1) (behind . 1))
                                 'attest '((delivered . 3) (dropped . 1)) 'read '((fresh . 2) (unavailable . 1))))))

(define (true-done w) (case (ref w 'done) [(on-time) T-ON-TIME] [(late) T-LATE] [else #f]))
(define (v-stamp w) (let ([t (true-done w)])
                      (and t (+ t (case (ref w 'skew) [(ahead) SKEW] [(behind) (- SKEW)] [else 0])))))

(define (execute protocol iface w)
  (define t (true-done w))
  (hasheq 'truth (hasheq 'temporal (if (and t (<= t DEADLINE)) 'Fulfilled 'Violated)
                         'completion (if t 'Fulfilled 'Violated))
          'gap 0 'required 0))

(define (deliveries protocol iface w)
  (define t (true-done w))
  (define msgs
    (append (if t (list (list 'msg 'DONE (+ t (if (eq? (ref w 'delay) 'long) LONG SHORT)) (v-stamp w))) '())
            (if (and t (hash-ref iface 'attest? #f) (eq? (ref w 'attest) 'delivered))
                (list (list 'msg 'ATTEST (+ t ATTEST-DELAY) t)) '())))
  (define rd (if (eq? (ref w 'read) 'fresh)
                 (list 'read-ok T-READ (list 'record (v-stamp w)))
                 (list 'read-failed T-READ)))
  (sort (append msgs (list rd)) < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))

(define deadline
  (family 'deadline
          (list (dependency 'temporal 'Temporal) (dependency 'completion 'Flow))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))

;; for the enactment adapter (enact.rkt) only
(module+ internals (provide ref true-done v-stamp))
