#lang racket/base
;; DMAT propositions P1–P3 as executable searches, generic over families.
;;
;; P1  Compliance evidence can be insufficient despite identical visible traces.
;;     Search: worlds of a profile's support that give an arm identical
;;     deliveries but differ in truth for a dependency. Each pair is a witness
;;     that no judge over that arm's observations decides both runs correctly.
;;
;; P2  Compliance-decidable composition requires distinguishability.
;;     The composition family (H ← V ← S) is run under each observation model H
;;     may have of V's case — coarse, staged, staged with an attestation of S's
;;     stage — holding the arm's protocol fixed. The report counts ambiguous
;;     observation classes and the probability mass for which each dependency
;;     is determined. Only deliveries enter: no judge is consulted.
;;
;; P3  Refinement preserves adequacy only conditionally.
;;     For a mechanism A and a variant A', the worlds where A' makes a false
;;     claim A does not (safety lost) and where a dependency determined for A is
;;     not determined for A' (observation lost).

(require racket/list "core/family.rkt" "core/arm.rkt" "core/judge.rkt" "families.rkt")
(provide p1-witnesses p2-report P2-MODELS p3-report)

;; ------------------------------------------------------------------ P1

;; → list of (list dep deliveries world-Fulfilled world-Violated), one per ambiguous class
(define (p1-witnesses f a pname)
  (define classes (make-hash))
  (for* ([w (support f pname)] [d (family-deps f)])
    (hash-update! classes (cons (deliveries-of f a w) (dependency-name d)) (λ (l) (cons w l)) '()))
  (sort
   (for*/list ([(k ws) classes]
               #:when (> (length (remove-duplicates (map (λ (w) (truth-of f a w (cdr k))) ws))) 1))
     (define dep (cdr k))
     (define ws* (reverse ws))
     (list dep (car k)
           (findf (λ (w) (eq? (truth-of f a w dep) 'Fulfilled)) ws*)
           (findf (λ (w) (eq? (truth-of f a w dep) 'Violated)) ws*)))
   string<? #:key (λ (x) (format "~s" x))))

;; ------------------------------------------------------------------ P2

(define P2-MODELS
  (list (cons 'coarse (hasheq 'obs 'coarse 'attest? #f))
        (cons 'staged (hasheq 'obs 'staged 'attest? #f))
        (cons 'staged+attest (hasheq 'obs 'staged 'attest? #t))))

;; an arm with the same protocol and judge, observing V under model m
(define (under-model a m)
  (struct-copy arm a
               [name (string->symbol (format "~a@~a" (arm-name a) m))]
               [interface (cdr (assq m P2-MODELS))]))

;; → list of (list model ambiguous-classes (dep . determined-mass) ...)
(define (p2-report pname [aname 'hybrid])
  (define f (family-by-name 'composition))
  (define a (arm-of 'composition aname))
  (for/list ([m (map car P2-MODELS)])
    (define a* (under-model a m))
    (define tbl (determinacy-table f a* pname))
    (define ambiguous (for/sum ([(k ts) tbl]) (if (> (length ts) 1) 1 0)))
    (list m ambiguous
          (for/list ([d (family-deps f)])
            (define dep (dependency-name d))
            (cons dep (for/sum ([w (support f pname)])
                        (if (= 1 (length (hash-ref tbl (cons (deliveries-of f a* w) dep))))
                            (probability f pname w) 0)))))))

;; ------------------------------------------------------------------ P3

(define (p3-report f a a* pname)
  (define safety-lost '())
  (define observation-lost '())
  (for ([w (support f pname)])
    (define ra (classify-run f a pname w))
    (define rb (classify-run f a* pname w))
    (for ([da (hash-ref ra 'deps)] [db (hash-ref rb 'deps)])
      (when (and (eq? (hash-ref db 'class) 'false) (not (eq? (hash-ref da 'class) 'false)))
        (set! safety-lost (cons (list (hash-ref da 'dep) w) safety-lost)))
      (when (and (hash-ref da 'determined) (not (hash-ref db 'determined)))
        (set! observation-lost (cons (list (hash-ref da 'dep) w) observation-lost)))))
  (hasheq 'family (family-name f) 'from (arm-name a) 'to (arm-name a*) 'profile pname
          'safety-lost (reverse safety-lost) 'observation-lost (reverse observation-lost)))
