#lang racket/base
;; Phase 3, steps 3.1–3.2: the commitment arms against the hub's hybrid and its
;; ablation, the evidential-layer ablation (cupid-e → cupid), and every run
;; where cupid-e and the hybrid differ in what they decide.
;;   racket commitments.rkt > commitments.txt

(require racket/format racket/list "core/family.rkt" "core/arm.rkt" "core/judge.rkt"
         "families.rkt" "propositions.rkt")

(define SHOWN '(hybrid hybrid-noe cupid cupid-e))
(define (num x) (~r (exact->inexact x) #:precision '(= 3)))
(define (col s w) (~a s #:width w))
(define (rcol s w) (~a s #:width w #:align 'right))

(printf "Commitment arms (models v0.4): exact expected metrics, every world of each profile's support\n")
(printf "~a~a~a~a\n" (col "family" 13) (col "profile" 23) (col "arm" 12)
        (apply string-append (for/list ([c METRIC-COLUMNS]) (rcol (~a c) 10))))
(for* ([n family-names] [p (profile-names (family-by-name n))] [an SHOWN])
  (define m (exact-metrics (family-by-name n) (arm-of n an) p))
  (printf "~a~a~a~a\n" (col n 13) (col p 23) (col an 12)
          (apply string-append (for/list ([c METRIC-COLUMNS]) (rcol (num (hash-ref m c)) 10)))))

(printf "\nSummary per family: worst-profile SFR, and mean coverage over profiles\n")
(printf "~a~a~a~a~a~a~a\n" (col "family" 13) (rcol "SFR hybrid" 12) (rcol "SFR cupid" 12) (rcol "SFR cupid-e" 12)
        (rcol "cov hybrid" 12) (rcol "cov cupid" 12) (rcol "cov cupid-e" 12))
(for ([n family-names])
  (define f (family-by-name n)) (define ps (profile-names f))
  (define (ms an) (for/list ([p ps]) (exact-metrics f (arm-of n an) p)))
  (define (worst an k) (apply max (map (λ (m) (hash-ref m k)) (ms an))))
  (define (mean an k) (/ (apply + (map (λ (m) (hash-ref m k)) (ms an))) (length ps)))
  (printf "~a~a~a~a~a~a~a\n" (col n 13)
          (rcol (num (worst 'hybrid 'SFR)) 12) (rcol (num (worst 'cupid 'SFR)) 12) (rcol (num (worst 'cupid-e 'SFR)) 12)
          (rcol (num (mean 'hybrid 'coverage)) 12) (rcol (num (mean 'cupid 'coverage)) 12) (rcol (num (mean 'cupid-e 'coverage)) 12)))

(printf "\nP3 — evidential layer removed (cupid-e → cupid): (dependency, world) pairs where safety or observation is lost\n")
(for* ([n family-names] [p (profile-names (family-by-name n))])
  (define r (p3-report (family-by-name n) (arm-of n 'cupid-e) (arm-of n 'cupid) p))
  (define by-dep (λ (k) (for/list ([d (map dependency-name (family-deps (family-by-name n)))])
                          (format "~a ~a" d (count (λ (x) (eq? (car x) d)) (hash-ref r k))))))
  (printf "~a~a safety-lost ~a (~a)   observation-lost ~a\n" (col n 13) (col p 23)
          (rcol (length (hash-ref r 'safety-lost)) 4) (apply string-append (add-between (by-dep 'safety-lost) ", "))
          (length (hash-ref r 'observation-lost))))

(printf "\ncupid-e against the hub's hybrid: runs where one decides correctly and the other abstains\n")
(printf "(the two arms have the same protocol and interface, so the difference is in judgment alone)\n")
(for ([n family-names])
  (define f (family-by-name n))
  (define h (arm-of n 'hybrid)) (define e (arm-of n 'cupid-e))
  (define diffs
    (remove-duplicates
     (for*/list ([p (profile-names f)] [w (support f p)]
                 [dh (hash-ref (classify-run f h p w) 'deps)]
                 [de (in-value (findf (λ (d) (eq? (hash-ref d 'dep) (hash-ref dh 'dep))) (hash-ref (classify-run f e p w) 'deps)))]
                 #:unless (eq? (hash-ref dh 'class) (hash-ref de 'class)))
       (list (hash-ref dh 'dep) w (hash-ref dh 'class) (hash-ref de 'class)))))
  (if (null? diffs)
      (printf "  ~a: none\n" n)
      (for ([d diffs])
        (printf "  ~a ~a: hybrid ~a, cupid-e ~a, world ~s\n" n (car d) (caddr d) (cadddr d) (cadr d)))))

(printf "\nCauses of the differences above\n")
(printf "  deadline completion — C_c's deadline is the evaluation instant T-EVAL; V's record is complete only through\n")
(printf "    T-READ, so under E2 it cannot establish that the service was never completed. The hybrid decides from the\n")
(printf "    family's schedule (no completion in (T-READ, T-EVAL]), which the commitment does not declare.\n")
(printf "  replacement temporal — V withdrew, V2 declined, V resumed and reported its start at T-RESUME, after the\n")
(printf "    deadline. Under E1 the role holder's report of its own late performance is an admission (the family's clocks\n")
(printf "    are reliable), so cupid-e decides Violated; the hybrid counts only attested performances and abstains when\n")
(printf "    the attestation is dropped and the registry is stale or unavailable.\n")
