#lang racket/base
;; Phase 3, step 3.7.5: a language-model purchasing agent in the family `purchase`.
;;
;;   racket purchase-agent.rkt sample COMMAND LABEL PROFILES SEEDS REP OUT.jsonl
;;       run COMMAND (an external arm, e.g. harness/agent_arm.py) in the world drawn for
;;       each (profile, seed) and append one line per run: the transcript, the agent's
;;       claims, the truth and the classification of each claim
;;   racket purchase-agent.rkt report RUNS.jsonl ...
;;       metrics per (label, profile), mean and sample s.d. across repetitions
;;
;; An agent's runs are sampled, not exhaustive, and an agent is not deterministic,
;; so determinacy is not defined for them: a claim is correct, false or abstained.

(require racket/list racket/string racket/format racket/math json
         "core/family.rkt" "families.rkt" "families/purchase/external.rkt")

(define f (car (car COMPOSITE)))

(define (classify claims truth)
  (for/list ([c claims])
    (define j (caddr c)) (define t (hash-ref truth (cadr c)))
    (cons (cadr c) (cond [(eq? j 'Indeterminate) 'abstained] [(eq? j t) 'correct] [else 'false]))))

(define (sample command label profiles nseeds rep out)
  (with-output-to-file out #:exists 'append
    (λ ()
      (for* ([p (string-split profiles ",")] [seed (in-range nseeds)])
        (define pn (string->symbol p))
        (define w (draw f seed pn))
        (define run (run-one command w (format "~a-~a-~a-~a" label p seed rep)))
        (define cls (classify (hash-ref run 'claims) (hash-ref run 'truth)))
        (write-json
         (hasheq 'label label 'profile p 'seed seed 'rep rep 'world (format "~s" w)
                 'status (symbol->string (hash-ref run 'status))
                 'calls (map (λ (c) (format "~s" c)) (hash-ref run 'calls))
                 'replies (map (λ (r) (format "~s" r)) (hash-ref run 'replies))
                 'claims (for/list ([c (hash-ref run 'claims)]) (hasheq 'dependency (symbol->string (cadr c)) 'judgment (symbol->string (caddr c))))
                 'truth (for/hasheq ([(k v) (hash-ref run 'truth)]) (values k (symbol->string v)))
                 'classes (for/hasheq ([x cls]) (values (car x) (symbol->string (cdr x))))
                 'result (hash-ref run 'result)))
        (newline)))))

(define (mean xs) (if (null? xs) 0 (/ (apply + xs) (length xs))))
(define (sd xs) (if (< (length xs) 2) 0 (let ([m (mean xs)]) (sqrt (/ (apply + (map (λ (x) (sqr (- x m))) xs)) (sub1 (length xs)))))))
(define (num x) (~r (exact->inexact x) #:precision '(= 3)))

(define (report files)
  (define rows (append* (for/list ([fl files]) (for/list ([l (in-lines (open-input-file fl))] #:unless (string=? (string-trim l) "")) (string->jsexpr l)))))
  (define groups (make-hash))
  (for ([r rows]) (hash-update! groups (list (hash-ref r 'label) (hash-ref r 'profile) (hash-ref r 'rep)) (λ (l) (cons r l)) '()))
  (define (metrics rs)
    (define cls (append* (map (λ (r) (hash-values (hash-ref r 'classes))) rs)))
    (define (share v) (/ (count (λ (c) (equal? c v)) cls) (max 1 (length cls))))
    (define failed (λ (r) (for/or ([(d t) (hash-ref r 'truth)]) (equal? t "Violated"))))
    (hasheq 'SFR (/ (count (λ (r) (for/or ([(d c) (hash-ref r 'classes)]) (equal? c "false"))) rs) (max 1 (length rs)))
            'coverage (- 1 (share "abstained")) 'false (share "false")
            'failed (/ (count failed rs) (max 1 (length rs)))
            'malformed (/ (count (λ (r) (not (equal? (hash-ref r 'status) "ended"))) rs) (max 1 (length rs)))))
  (printf "Purchasing agent in the family purchase: per (label, profile), mean ± s.d. across repetitions\n")
  (printf "SFR: runs with a false claim; coverage: definitive claims; failed: runs in which some dependency in fact failed\n\n")
  (printf "~a~a~a~a~a~a~a\n" (~a "label" #:width 40) (~a "profile" #:width 16) (~a "SFR" #:width 15) (~a "coverage" #:width 15)
          (~a "false" #:width 15) (~a "failed" #:width 15) (~a "not ended" #:width 10))
  (for ([k (sort (remove-duplicates (map (λ (g) (take g 2)) (hash-keys groups))) string<? #:key (λ (x) (format "~a" x)))])
    (define reps (for/list ([(g rs) groups] #:when (equal? (take g 2) k)) (metrics rs)))
    (define (cell m) (let ([xs (map (λ (x) (hash-ref x m)) reps)]) (format "~a±~a" (num (mean xs)) (num (sd xs)))))
    (printf "~a~a~a~a~a~a~a\n" (~a (car k) #:width 40) (~a (cadr k) #:width 16) (~a (cell 'SFR) #:width 15) (~a (cell 'coverage) #:width 15)
            (~a (cell 'false) #:width 15) (~a (cell 'failed) #:width 15) (~a (cell 'malformed) #:width 10))))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(and (= 7 (length args)) (equal? (car args) "sample"))
     (apply (λ (cmd label profiles seeds rep out) (sample cmd label profiles (string->number seeds) (string->number rep) out)) (cdr args))]
    [(and (>= (length args) 2) (equal? (car args) "report")) (report (cdr args))]
    [else (eprintf "usage: racket purchase-agent.rkt sample COMMAND LABEL PROFILES SEEDS REP OUT | report RUNS...\n") (exit 2)]))
