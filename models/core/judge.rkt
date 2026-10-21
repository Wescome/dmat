#lang racket/base
;; DMAT executable models — the adequacy judge, generic over families.
;;
;; For one run (family, arm, environment, world) the judge holds three records
;; apart and never passes truth to an arm:
;;   oracle truth            : the family's execution of the arm's protocol in the world
;;   participant observation : the deliveries the arm's observer receives
;;   protocol claim          : the arm's judgment over those deliveries
;;
;; Determinacy (DMAT P1, operational): a dependency is determined for an arm in
;; a run when every world of the environment's support that gives the arm the
;; same deliveries has the same truth for that arm's execution.
;;
;; Classes: supported | lucky | false | abstained-ok | abstained-miss

(require racket/list "grammar.rkt" "arm.rkt" "family.rkt")
(provide execution deliveries-of truth-of determinacy-table classify-run
         metrics-from-rows exact-metrics METRIC-COLUMNS)

(define exec-cache (make-hash))
(define (execution f a w)
  (hash-ref! exec-cache (list (family-name f) (arm-name a) w)
             (λ () ((family-execute f) (arm-protocol a) (arm-interface a) w))))

(define (truth-of f a w dep) (hash-ref (hash-ref (execution f a w) 'truth) dep))

(define ds-cache (make-hash))
(define (deliveries-of f a w)
  (hash-ref! ds-cache (list (family-name f) (arm-name a) w)
             (λ ()
               (define ds ((family-deliveries f) (arm-protocol a) (arm-interface a) w))
               (unless ((family-ds-term? f) ds)
                 (error 'deliveries "~a/~a: not a deliveries term: ~s" (family-name f) (arm-name a) ds))
               ds)))

(define det-cache (make-hash))
(define (determinacy-table f a pname)
  (hash-ref! det-cache (list (family-name f) (arm-name a) pname)
             (λ ()
               (define tbl (make-hash))
               (for* ([w (support f pname)] [d (family-deps f)])
                 (define dep (dependency-name d))
                 (define t (truth-of f a w dep))
                 (hash-update! tbl (cons (deliveries-of f a w) dep)
                               (λ (s) (if (member t s) s (cons t s))) '()))
               tbl)))

(define (classify-run f a pname w #:seed [seed #f])
  (define tbl (determinacy-table f a pname))
  (define ds (deliveries-of f a w))
  (define cls ((arm-judge a) ds))
  (unless (claims-term? cls) (error 'judge "~a/~a: not a claims term: ~s" (family-name f) (arm-name a) cls))
  (define deps (map dependency-name (family-deps f)))
  (unless (equal? (map cadr cls) deps)
    (error 'judge "~a/~a: claims ~s do not cover the dependencies ~s in order" (family-name f) (arm-name a) (map cadr cls) deps))
  (define ex (execution f a w))
  (define per-dep
    (for/list ([c cls])
      (define dep (list-ref c 1))
      (define j (list-ref c 2))
      (define cites (list-ref c 3))
      (define t (truth-of f a w dep))
      (define det (= 1 (length (hash-ref tbl (cons ds dep)))))
      (define cites-ok (and (pair? cites) (for/and ([i cites]) (< i (length ds)))))
      (define class
        (cond [(memq j DEFINITIVE)
               (cond [(not (eq? j t)) 'false]
                     [(and det cites-ok) 'supported]
                     [else 'lucky])]
              [det 'abstained-miss]
              [else 'abstained-ok]))
      (hasheq 'dep dep 'truth t 'claim j 'cites cites 'determined det 'class class)))
  (hasheq 'family (family-name f) 'arm (arm-name a) 'profile pname 'seed seed 'world w
          'deliveries ds 'claims cls 'deps per-dep
          'gap (hash-ref ex 'gap 0) 'required (hash-ref ex 'required 0)))

(define METRIC-COLUMNS '(SFR FCR AGR coverage supported lucky false abstained-ok abstained-miss determinable))

;; rows+weights: list of (row . weight)
(define (metrics-from-rows rows+weights)
  (define (sum f) (for/sum ([rw rows+weights]) (* (cdr rw) (f (car rw)))))
  (define (per-claim pred) (sum (λ (r) (for/sum ([d (hash-ref r 'deps)]) (if (pred d) 1 0)))))
  (define (cls? . cs) (λ (d) (memq (hash-ref d 'class) cs)))
  (define total (sum (λ (r) 1)))
  (define claims-n (per-claim (λ (d) #t)))
  (define fulfilled (per-claim (λ (d) (eq? (hash-ref d 'claim) 'Fulfilled))))
  (define bad-fulfilled (per-claim (λ (d) (and (eq? (hash-ref d 'claim) 'Fulfilled) (memq (hash-ref d 'class) '(false lucky))))))
  (define unsafe (sum (λ (r) (if (ormap (cls? 'false) (hash-ref r 'deps)) 1 0))))
  (define required (sum (λ (r) (hash-ref r 'required))))
  (define gap (sum (λ (r) (hash-ref r 'gap))))
  (define (ratio a b) (if (zero? b) 0 (/ a b)))
  (hasheq 'runs total
          'SFR (ratio unsafe total)
          'FCR (ratio bad-fulfilled fulfilled)
          'AGR (ratio gap required)
          'coverage (ratio (per-claim (cls? 'supported 'lucky 'false)) claims-n)
          'supported (ratio (per-claim (cls? 'supported)) claims-n)
          'lucky (ratio (per-claim (cls? 'lucky)) claims-n)
          'false (ratio (per-claim (cls? 'false)) claims-n)
          'abstained-ok (ratio (per-claim (cls? 'abstained-ok)) claims-n)
          'abstained-miss (ratio (per-claim (cls? 'abstained-miss)) claims-n)
          'determinable (ratio (per-claim (λ (d) (hash-ref d 'determined))) claims-n)))

(define (exact-metrics f a pname)
  (metrics-from-rows
   (for/list ([w (support f pname)])
     (cons (classify-run f a pname w) (probability f pname w)))))
