#lang racket/base
;; Differential check: the reference arms against independently authored arms.
;;
;;   racket diff.rkt                       summary for every family with independent/<family>-arms.rkt
;;   racket diff.rkt detail FAMILY         every distinct deliveries list on which the two disagree
;;   racket diff.rkt cupid                 the same for the commitment arms (independent/<family>-cupid.rkt)
;;   racket diff.rkt cupid detail FAMILY
;;
;; The independent arms were written from specs/paradigms.md, specs/<family>.md
;; and the family's terms.rkt alone, by authors who did not see the reference
;; arms or the world modules. Protocol features and interfaces are fixed by the
;; spec, so both arms of a name see the same deliveries in every world; any
;; difference is in judgment. The comparison runs over the union of every
;; profile's support; judges depend only on deliveries, so disagreements are
;; listed once per distinct deliveries list.

(require racket/list racket/format racket/string racket/runtime-path
         "core/family.rkt" "core/arm.rkt" "core/judge.rkt" "families.rkt")
(provide independent-arms independent-cupid-arms disagreements)

(define-runtime-path INDEP "independent")

(define (independent-arms fname)
  (define p (build-path INDEP (format "~a-arms.rkt" fname)))
  (and (file-exists? p) (dynamic-require p 'arms)))

(define (independent-cupid-arms fname)
  (define p (build-path INDEP (format "~a-cupid.rkt" fname)))
  (and (file-exists? p) (dynamic-require p 'cupid-arms)))

;; the two arm sets: (loader names label)
(define HUB (list independent-arms ARM-NAMES "arms"))
(define CUPID (list independent-cupid-arms CUPID-NAMES "commitment arms"))
(define current-set (make-parameter HUB))

(define (judgments a ds) (map (λ (c) (list (cadr c) (caddr c))) ((arm-judge a) ds)))

;; → list of (deliveries ref-judgments indep-judgments)
(define (disagreements fname ref ind)
  (define f (family-by-name fname))
  (define dss (remove-duplicates
               (for*/list ([p (profile-names f)] [w (support f p)]) (deliveries-of f ref w))))
  (for*/list ([ds dss]
              [jr (in-value (judgments ref ds))]
              [ji (in-value (judgments ind ds))]
              #:unless (equal? jr ji))
    (list ds jr ji)))

(define (fmt x) (~r (exact->inexact x) #:precision '(= 3)))

(define (summary)
  (define-values (load names label) (apply values (current-set)))
  (printf "Reference ~a vs independent ~a:" label label)
  (printf " distinct deliveries lists judged differently; exact SFR and false rate per profile (reference → independent)\n")
  (for ([fname family-names])
    (define inds (load fname))
    (cond
      [(not inds) (printf "~a: no independent ~a\n" fname label)]
      [else
       (define f (family-by-name fname))
       (for ([aname names])
         (define ref (arm-of fname aname))
         (define ind (or (findf (λ (a) (eq? (arm-name a) aname)) inds) (error 'diff "~a: independent arms lack ~a" fname aname)))
         (unless (and (equal? (arm-protocol ref) (arm-protocol ind)) (equal? (arm-interface ref) (arm-interface ind)))
           (error 'diff "~a/~a: protocol or interface differs from the spec" fname aname))
         (define dss (remove-duplicates (for*/list ([p (profile-names f)] [w (support f p)]) (deliveries-of f ref w))))
         (define dis (disagreements fname ref ind))
         (printf "~a ~a disagree on ~a of ~a\n" (~a fname #:width 12) (~a aname #:width 11)
                 (~a (length dis) #:width 3 #:align 'right) (length dss))
         (for ([p (profile-names f)])
           (define mr (exact-metrics f ref p))
           (define mi (exact-metrics f ind p))
           (unless (and (= (hash-ref mr 'SFR) (hash-ref mi 'SFR)) (= (hash-ref mr 'false) (hash-ref mi 'false))
                        (= (hash-ref mr 'coverage) (hash-ref mi 'coverage)))
             (printf "    ~a SFR ~a → ~a  false ~a → ~a  coverage ~a → ~a\n" (~a p #:width 22)
                     (fmt (hash-ref mr 'SFR)) (fmt (hash-ref mi 'SFR)) (fmt (hash-ref mr 'false)) (fmt (hash-ref mi 'false))
                     (fmt (hash-ref mr 'coverage)) (fmt (hash-ref mi 'coverage))))))])))

(define (detail fname)
  (define-values (load names label) (apply values (current-set)))
  (define inds (load fname))
  (for ([aname names])
    (define ref (arm-of fname aname))
    (define ind (findf (λ (a) (eq? (arm-name a) aname)) inds))
    (define f (family-by-name fname))
    (for ([x (disagreements fname ref ind)])
      (define ds (first x))
      ;; the truth values this deliveries list can carry, over all profiles
      (define truths (remove-duplicates
                      (for*/list ([p (profile-names f)] [w (support f p)] #:when (equal? (deliveries-of f ref w) ds))
                        (for/list ([d (family-deps f)]) (truth-of f ref w (dependency-name d))))))
      (printf "~a ~a\n  deliveries  ~s\n  reference   ~s\n  independent ~s\n  truth       ~s\n"
              fname aname ds (second x) (third x) truths))))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (define-values (set rest) (if (and (pair? args) (equal? (car args) "cupid")) (values CUPID (cdr args)) (values HUB args)))
  (parameterize ([current-set set])
    (cond [(null? rest) (summary)]
          [(and (= 2 (length rest)) (equal? (car rest) "detail")) (detail (string->symbol (cadr rest)))]
          [else (eprintf "usage: racket diff.rkt [cupid] | racket diff.rkt [cupid] detail FAMILY\n") (exit 2)])))
