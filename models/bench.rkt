#lang racket/base
;; DMBench over the executable models: eight scenario families, each with its
;; own fault profiles, five arms.
;;
;;   racket bench.rkt exact                    exact expected metrics per family × profile × arm
;;   racket bench.rkt sampled N [OUT.jsonl]    N seeds per (family, profile); every run written as
;;                                             one JSON line (oracle truth, deliveries, claims and
;;                                             classification kept apart); prints the sampled
;;                                             metrics and each one's deviation from the exact value
;;   racket bench.rkt propositions             P1 witnesses, P2 report, P3 reports
;;
;; Every arm runs on the same world for a given (family, seed, profile):
;; common random numbers. Output is deterministic: the same arguments print the
;; same bytes.

(require racket/list racket/string racket/format racket/math json
         "core/family.rkt" "core/arm.rkt" "core/judge.rkt" "families.rkt" "propositions.rkt")
(provide exact-table sampled-rows sampled-summary)

(define (fmt x) (~r (exact->inexact x) #:precision '(= 3)))

(define (print-table title rows) ; rows: (list family profile arm metrics)
  (printf "~a\n" title)
  (printf "~a\n" (string-join (append (list (~a "family" #:width 12) (~a "profile" #:width 22) (~a "arm" #:width 11))
                                      (map (λ (c) (~a c #:width 9 #:align 'right #:limit-marker "")) METRIC-COLUMNS)) " "))
  (for ([r rows])
    (printf "~a\n" (string-join (append (list (~a (first r) #:width 12) (~a (second r) #:width 22) (~a (third r) #:width 11))
                                        (map (λ (c) (~a (fmt (hash-ref (fourth r) c)) #:width 9 #:align 'right)) METRIC-COLUMNS))
                                " "))))

(define (exact-table)
  (for*/list ([fa FAMILIES] [p (profile-names (car fa))] [a (cdr fa)])
    (list (family-name (car fa)) p (arm-name a) (exact-metrics (car fa) a p))))

(define (sampled-rows n)
  (for*/list ([fa FAMILIES] [p (profile-names (car fa))] [a (cdr fa)] [seed (in-range 1 (+ n 1))])
    (classify-run (car fa) a p (draw (car fa) seed p) #:seed seed)))

(define (sampled-summary rows)
  (for*/list ([fa FAMILIES] [p (profile-names (car fa))] [a (cdr fa)])
    (define fname (family-name (car fa)))
    (define rs (filter (λ (r) (and (eq? (hash-ref r 'family) fname) (eq? (hash-ref r 'profile) p)
                                   (eq? (hash-ref r 'arm) (arm-name a)))) rows))
    (list fname p (arm-name a) (metrics-from-rows (map (λ (r) (cons r 1)) rs)))))

;; per-run SFR deviation from its exact value, in standard errors of the mean
(define (sfr-deviations rows n)
  (for*/list ([fa FAMILIES] [p (profile-names (car fa))] [a (cdr fa)])
    (define f (car fa))
    (define exact (hash-ref (exact-metrics f a p) 'SFR))
    (define sampled
      (/ (for/sum ([r rows] #:when (and (eq? (hash-ref r 'family) (family-name f)) (eq? (hash-ref r 'profile) p)
                                        (eq? (hash-ref r 'arm) (arm-name a))))
           (if (ormap (λ (d) (eq? (hash-ref d 'class) 'false)) (hash-ref r 'deps)) 1 0))
         n))
    (define se (sqrt (/ (* exact (- 1 exact)) n)))
    (cond [(zero? se) (if (= sampled exact) 0 +inf.0)]
          [else (/ (abs (- sampled exact)) se)])))

(define (->jsexpr x)
  (cond [(hash? x) (for/hasheq ([(k v) x]) (values k (->jsexpr v)))]
        [(list? x) (map ->jsexpr x)]
        [(symbol? x) (symbol->string x)]
        [(boolean? x) x]
        [(exact-integer? x) x]
        [else x]))
(define (row->json r)
  (jsexpr->string (->jsexpr (hash-set (hash-set (hash-set r 'world (format "~s" (hash-ref r 'world)))
                                                'deliveries (format "~s" (hash-ref r 'deliveries)))
                                      'claims (format "~s" (hash-ref r 'claims))))))

(define (print-propositions)
  (printf "P1 — identical deliveries, different truth: ambiguous observation classes per dependency\n")
  (for* ([fa FAMILIES] [p (profile-names (car fa))])
    (define f (car fa))
    (printf "  ~a ~a" (~a (family-name f) #:width 12) (~a p #:width 22))
    (for ([a (cdr fa)])
      (define ws (p1-witnesses f a p))
      (printf " ~a ~a" (arm-name a)
              (string-join (for/list ([d (family-deps f)])
                             (~a (count (λ (x) (eq? (car x) (dependency-name d))) ws))) "/")))
    (newline))
  (printf "  dependency order per family: ~a\n"
          (string-join (for/list ([fa FAMILIES]) (format "~a ~a" (family-name (car fa)) (map dependency-name (family-deps (car fa))))) "; "))
  (let* ([f (family-by-name 'handoff)] [ws (p1-witnesses f (arm-of 'handoff 'chor) 'stale-read)])
    (printf "  example (handoff, chor, stale-read): ~s\n" (and (pair? ws) (car ws))))
  (printf "P2 — composition H ← V ← S under H's observation models of V (hybrid's protocol); determined mass per dependency\n")
  (for ([p (profile-names (family-by-name 'composition))])
    (for ([row (p2-report p)])
      (printf "  ~a ~a ambiguous classes ~a ~a\n" (~a p #:width 12) (~a (first row) #:width 14) (~a (second row) #:width 3)
              (string-join (for/list ([dm (third row)]) (format "~a ~a" (car dm) (fmt (cdr dm)))) "  "))))
  (printf "P3 — variant against mechanism: (dependency, world) pairs where safety or observation is lost\n")
  (for* ([fa FAMILIES] [to '(hybrid-noe fsm comm chor)] [p (profile-names (car fa))])
    (define f (car fa))
    (define r (p3-report f (arm-of (family-name f) 'hybrid) (arm-of (family-name f) to) p))
    (printf "  ~a hybrid → ~a ~a safety-lost ~a observation-lost ~a\n"
            (~a (family-name f) #:width 12) (~a to #:width 11) (~a p #:width 22)
            (~a (length (hash-ref r 'safety-lost)) #:width 3) (length (hash-ref r 'observation-lost)))))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(equal? args '("exact"))
     (print-table "Exact expected metrics (every world of each profile's support, weighted by its probability)" (exact-table))]
    [(and (pair? args) (equal? (car args) "sampled") (<= 2 (length args) 3))
     (define n (string->number (cadr args)))
     (define rows (sampled-rows n))
     (when (= (length args) 3)
       (with-output-to-file (caddr args) #:exists 'replace
         (λ () (for ([r rows]) (displayln (row->json r))))))
     (print-table (format "Sampled DMBench: ~a seeds per (family, profile), ~a runs" n (length rows)) (sampled-summary rows))
     (define devs (sfr-deviations rows n))
     (printf "SFR sampled vs exact: worst deviation ~a standard errors over ~a cells; ~a cells beyond 3\n"
             (fmt (apply max devs)) (length devs) (count (λ (x) (> x 3)) devs))]
    [(equal? args '("propositions")) (print-propositions)]
    [else (eprintf "usage: racket bench.rkt exact | sampled N [OUT.jsonl] | propositions\n") (exit 2)]))
