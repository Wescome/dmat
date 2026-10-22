#lang racket/base
;; Phase 3, step 3.7: the composite family `purchase` (specs/purchase.md).
;;   racket purchase.rkt > purchase.txt
;;
;; Every arm of the family under every profile: exact claim metrics; the share of
;; runs in which each dependency in fact failed (operational adequacy: here the
;; arm's own conduct makes the truth); P1 witnesses; P3 between hybrid and its
;; ablation; the completeness point removed (P2-style); and every false claim of
;; every arm, traced to its world and transcript.

(require racket/format racket/list "core/family.rkt" "core/arm.rkt" "core/judge.rkt"
         "families.rkt" "propositions.rkt"
         (only-in "families/purchase/external-cache.rkt" arm-cache))

(define f (car (car COMPOSITE)))
(define DEPS (map dependency-name (family-deps f)))
(define (num x) (~r (exact->inexact x) #:precision '(= 3)))
(define (col s w) (~a s #:width w))
(define (rcol s w) (~a s #:width w #:align 'right))

(define (present? a)
  (or (not (eq? (hash-ref (arm-protocol a) 'mechanism) 'external))
      (positive? (hash-count (hash-ref (arm-cache (hash-ref (arm-protocol a) 'arm)) 'runs)))))
(define ARMS (filter present? (composite-arms)))

(printf "Family purchase (models v0.4.2): exact expected metrics, every world of each profile's support\n")
(printf "Arms with stored runs: ~a; external arms without stored runs are left out.\n"
        (map arm-name ARMS))
(for ([a (composite-arms)] #:when (eq? (hash-ref (arm-protocol a) 'mechanism) 'external))
  (define c (arm-cache (hash-ref (arm-protocol a) 'arm)))
  (printf "  ~a: ~a stored runs, revision ~a\n" (arm-name a) (hash-count (hash-ref c 'runs)) (hash-ref c 'revision)))
(printf "\n~a~a~a~a\n" (col "profile" 17) (col "arm" 12) "" (apply string-append (for/list ([c METRIC-COLUMNS]) (rcol (~a c) 10))))
(for* ([p (profile-names f)] [a ARMS])
  (define m (exact-metrics f a p))
  (printf "~a~a~a\n" (col p 17) (col (arm-name a) 12)
          (apply string-append (for/list ([c METRIC-COLUMNS]) (rcol (num (hash-ref m c)) 10)))))

(printf "\nOperational adequacy: probability that each dependency in fact failed (the arm's conduct makes the truth)\n")
(printf "~a~a~a\n" (col "profile" 17) (col "arm" 12) (apply string-append (for/list ([d DEPS]) (rcol (~a d) 10))))
(for* ([p (profile-names f)] [a ARMS])
  (printf "~a~a~a\n" (col p 17) (col (arm-name a) 12)
          (apply string-append
                 (for/list ([d DEPS])
                   (rcol (num (for/sum ([w (support f p)])
                                (if (eq? (truth-of f a w d) 'Violated) (probability f p w) 0)))
                         10)))))

(printf "\nP1 — identical transcripts, different truth (adversarial): ambiguous transcript classes per dependency\n")
(for ([a ARMS])
  (define ws (p1-witnesses f a 'adversarial))
  (printf "  ~a: ~a\n" (col (arm-name a) 12)
          (apply string-append (add-between (for/list ([d DEPS]) (format "~a ~a" d (count (λ (x) (eq? (car x) d)) ws))) ", "))))

(printf "\nP3 — hybrid → hybrid-noe: (dependency, world) pairs where safety or observation is lost\n")
(for ([p (profile-names f)])
  (define r (p3-report f (composite-arm 'hybrid) (composite-arm 'hybrid-noe) p))
  (printf "  ~a safety-lost ~a   observation-lost ~a\n" (col p 17)
          (rcol (length (hash-ref r 'safety-lost)) 4) (length (hash-ref r 'observation-lost))))

(printf "\nThe completeness point removed: hybrid with interface (watermark #f)\n")
(define nowm (struct-copy arm (composite-arm 'hybrid) [name 'hybrid@nowm] [interface (hasheq 'watermark #f)]))
(for ([p (profile-names f)])
  (define m (exact-metrics f nowm p))
  (define h (exact-metrics f (composite-arm 'hybrid) p))
  (printf "  ~a SFR ~a  coverage ~a (with the point: ~a)  determinable ~a (with: ~a)\n" (col p 17)
          (num (hash-ref m 'SFR)) (num (hash-ref m 'coverage)) (num (hash-ref h 'coverage))
          (num (hash-ref m 'determinable)) (num (hash-ref h 'determinable))))

(printf "\nFalse claims, adversarial profile: every distinct (arm, dependency, transcript), with one world that produces it\n")
(for ([a ARMS])
  (define seen (make-hash))
  (for ([w (support f 'adversarial)])
    (define r (classify-run f a 'adversarial w))
    (for ([d (hash-ref r 'deps)] #:when (eq? (hash-ref d 'class) 'false))
      (define k (cons (hash-ref d 'dep) (hash-ref r 'deliveries)))
      (unless (hash-ref seen k #f)
        (hash-set! seen k (list w (hash-ref d 'claim) (hash-ref d 'truth) (hash-ref r 'deliveries))))))
  (printf "  ~a: ~a distinct\n" (arm-name a) (hash-count seen))
  (for ([(k v) seen] [i (in-naturals)] #:when (< i 6))
    (printf "    ~a claimed ~a, truth ~a, world ~s\n" (car k) (cadr v) (caddr v) (car v))
    (for ([d (cadddr v)]) (printf "      ~s -> ~s\n" (list-ref d 4) (list-ref d 5)))))
