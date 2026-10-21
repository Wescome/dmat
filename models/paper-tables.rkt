#lang racket/base
;; Generates the LaTeX tables of the paper from the models (no hand transcription).
(require racket/list racket/string racket/format racket/file
         "core/family.rkt" "core/arm.rkt" "core/judge.rkt" "families.rkt" "propositions.rkt" "diff.rkt")
(define out (vector-ref (current-command-line-arguments) 0))
(define (f3 x) (~r (exact->inexact x) #:precision '(= 3)))
(define (f2 x) (~r (exact->inexact x) #:precision '(= 2)))
(define ARML (quote ((chor . "\\arm{Chor}") (fsm . "\\arm{Fsm}") (comm . "\\arm{Comm}") (hybrid . "\\arm{Hybrid}") (hybrid-noe . "\\arm{Hyb-noE}"))))
(define (tt s) (format "\\texttt{~a}" s))
(define M (make-hash))
(define (m fn an p) (hash-ref! M (list fn an p) (λ () (exact-metrics (family-by-name fn) (arm-of fn an) p))))
(define (write-tex name s) (with-output-to-file (build-path out name) #:exists 'replace (λ () (display s))))

;; T-adv: adversarial SFR per family × arm, with hybrid coverage
(write-tex "adversarial.tex"
  (string-append*
   (for/list ([fn family-names])
     (format "~a & ~a \\\\\n" (tt fn)
             (string-join (for/list ([an ARM-NAMES])
                            (if (eq? an 'hybrid)
                                (format "~a / ~a" (f2 (hash-ref (m fn an 'adversarial) 'SFR)) (f2 (hash-ref (m fn an 'adversarial) 'coverage)))
                                (f2 (hash-ref (m fn an 'adversarial) 'SFR)))) " & ")))))

;; T-worst: worst-profile SFR per family × arm
(write-tex "worst.tex"
  (string-append*
   (for/list ([fn family-names])
     (format "~a & ~a \\\\\n" (tt fn)
             (string-join (for/list ([an ARM-NAMES])
                            (define best (argmax (λ (p) (hash-ref (m fn an p) 'SFR)) (profile-names (family-by-name fn))))
                            (define v (hash-ref (m fn an best) 'SFR))
                            (if (zero? v) "0" (f2 v))) " & ")))))

;; T-ceiling: sound-judge ceiling (determinable) vs hybrid supported, per family, adversarial
(write-tex "ceiling.tex"
  (string-append*
   (for/list ([fn family-names])
     (define h (m fn 'hybrid 'adversarial)) (define c (m fn 'chor 'adversarial))
     (define fs (m fn 'fsm 'adversarial)) (define co (m fn 'comm 'adversarial))
     (format "~a & ~a & ~a & ~a & ~a & ~a & ~a \\\\\n" (tt fn)
             (f2 (hash-ref h 'determinable)) (f2 (hash-ref h 'supported)) (f2 (hash-ref h 'abstained-miss))
             (f2 (hash-ref c 'determinable)) (f2 (hash-ref fs 'determinable)) (f2 (hash-ref co 'determinable))))))

;; Full exact table (appendix)
(write-tex "exact-full.tex"
  (string-append*
   (for*/list ([fn family-names] [p (profile-names (family-by-name fn))] [an ARM-NAMES])
     (define x (m fn an p))
     (format "~a & ~a & ~a & ~a \\\\\n" (tt fn) (tt p) (cdr (assq an ARML))
             (string-join (for/list ([c METRIC-COLUMNS]) (f3 (hash-ref x c))) " & ")))))

;; P1: ambiguous classes summed over profiles per family × arm
(write-tex "p1.tex"
  (string-append*
   (for/list ([fa FAMILIES])
     (define f (car fa))
     (format "~a & ~a \\\\\n" (tt (family-name f))
             (string-join (for/list ([a (cdr fa)])
                            (~a (for/sum ([p (profile-names f)]) (length (p1-witnesses f a p))))) " & ")))))

;; P2
(write-tex "p2.tex"
  (string-append*
   (for*/list ([p (profile-names (family-by-name 'composition))] [row (p2-report p)])
     (format "~a & ~a & ~a & ~a & ~a \\\\\n" (tt p) (tt (first row)) (second row)
             (f2 (cdr (assq 'temporal (third row)))) (f2 (cdr (assq 'delivery (third row))))))))

;; P3: hybrid -> variant, totals over profiles
(write-tex "p3.tex"
  (string-append*
   (for/list ([fn family-names])
     (define f (family-by-name fn))
     (format "~a & ~a \\\\\n" (tt fn)
             (string-join
              (for/list ([to '(hybrid-noe chor fsm comm)])
                (define rs (for/list ([p (profile-names f)]) (p3-report f (arm-of fn 'hybrid) (arm-of fn to) p)))
                (format "~a/~a" (for/sum ([r rs]) (length (hash-ref r 'safety-lost)))
                        (for/sum ([r rs]) (length (hash-ref r 'observation-lost))))) " & ")))))

;; Diff counts
(write-tex "diff.tex"
  (string-append*
   (for/list ([fn family-names])
     (define inds (independent-arms fn)) (define f (family-by-name fn))
     (format "~a & ~a & ~a \\\\\n" (tt fn)
             (length (remove-duplicates (for*/list ([p (profile-names f)] [w (support f p)]) (deliveries-of f (arm-of fn 'hybrid) w))))
             (string-join (for/list ([an ARM-NAMES])
                            (~a (length (disagreements fn (arm-of fn an) (findf (λ (a) (eq? (arm-name a) an)) inds))))) " & ")))))

;; support sizes, profiles
(write-tex "families.tex"
  (string-append*
   (for/list ([fn family-names])
     (define f (family-by-name fn))
     (format "~a & ~a & ~a \\\\\n" (tt fn)
             (string-join (map (λ (p) (format "~a\\,(~a)" (tt p) (length (support f p)))) (profile-names f)) ", ")
             (for/sum ([p (profile-names f)]) (length (support f p)))))))
(printf "ok\n")
