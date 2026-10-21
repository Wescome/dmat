#lang racket/base
;; The registry of scenario families and their arms. The benchmark, the
;; propositions and the tests reach families only through this module.

(require racket/list "core/family.rkt" "core/arm.rkt"
         (only-in "families/handoff/world.rkt" handoff)
         (rename-in (only-in "families/handoff/arms.rkt" arms) [arms handoff-arms])
         (only-in "families/reservation/world.rkt" reservation)
         (rename-in (only-in "families/reservation/arms.rkt" arms) [arms reservation-arms])
         (only-in "families/agreement/world.rkt" agreement)
         (rename-in (only-in "families/agreement/arms.rkt" arms) [arms agreement-arms])
         (only-in "families/delegation/world.rkt" delegation)
         (rename-in (only-in "families/delegation/arms.rkt" arms) [arms delegation-arms])
         (only-in "families/deadline/world.rkt" deadline)
         (rename-in (only-in "families/deadline/arms.rkt" arms) [arms deadline-arms])
         (only-in "families/external/world.rkt" external)
         (rename-in (only-in "families/external/arms.rkt" arms) [arms external-arms])
         (only-in "families/composition/world.rkt" composition)
         (rename-in (only-in "families/composition/arms.rkt" arms) [arms composition-arms])
         (only-in "families/replacement/world.rkt" replacement)
         (rename-in (only-in "families/replacement/arms.rkt" arms) [arms replacement-arms]))
(provide FAMILIES family-names family-by-name arms-of arm-of ARM-NAMES)

;; DMBench's eight scenario families, in benchmark order
(define FAMILIES
  (list (cons handoff handoff-arms)
        (cons reservation reservation-arms)
        (cons agreement agreement-arms)
        (cons delegation delegation-arms)
        (cons deadline deadline-arms)
        (cons external external-arms)
        (cons composition composition-arms)
        (cons replacement replacement-arms)))

(define ARM-NAMES '(chor fsm comm hybrid hybrid-noe))

(define family-names (map (λ (p) (family-name (car p))) FAMILIES))
(define (entry n) (or (findf (λ (p) (eq? (family-name (car p)) n)) FAMILIES)
                      (error 'families "no family ~a" n)))
(define (family-by-name n) (car (entry n)))
(define (arms-of n) (cdr (entry n)))
(define (arm-of fname aname)
  (or (findf (λ (a) (eq? (arm-name a) aname)) (arms-of fname))
      (error 'families "~a has no arm ~a" fname aname)))

(for ([p FAMILIES])
  (unless (equal? (map arm-name (cdr p)) ARM-NAMES)
    (error 'families "~a: arms ~s" (family-name (car p)) (map arm-name (cdr p))))
  (for ([a (cdr p)])
    (unless (eq? (arm-family a) (family-name (car p)))
      (error 'families "~a: arm ~a is written for ~a" (family-name (car p)) (arm-name a) (arm-family a)))))
