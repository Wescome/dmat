#lang racket/base
;; Family 9 — command line for external arms (specs/external-arms.md).
;;
;;   racket families/purchase/external-cli.rkt try COMMAND [SLOT=VALUE ...]
;;       run the arm once in one world (default: every slot at its reliable value) and
;;       print its transcript and claims. Shows replies only: no truth, no judgment.
;;   racket families/purchase/external-cli.rkt run ARM COMMAND [REVISION]
;;       run the arm in every world of every profile and store the runs in
;;       families/purchase/external/ARM.rktd.
;;   racket families/purchase/external-cli.rkt shard ARM COMMAND REVISION I K
;;       the same for every K-th world from the I-th (0-based), stored in
;;       families/purchase/external/ARM.part-I.rktd, so shards can run in parallel
;;   racket families/purchase/external-cli.rkt merge ARM K
;;       merge the K parts into ARM.rktd (every world present, one revision) and delete them

(require racket/list racket/string "../../core/family.rkt" "world.rkt" "external.rkt" "external-cache.rkt")

(define SLOTS '(stock alt auth void read capture deliver report scan))
(define RELIABLE '(kept within replied replied fresh replied on-time honest recorded))

(define (world-from args)
  (define h (for/hash ([a args]) (define kv (string-split a "=")) (values (string->symbol (car kv)) (string->symbol (cadr kv)))))
  (cons 'world (for/list ([s SLOTS] [v RELIABLE]) (hash-ref h s v))))

(define (all-worlds) (remove-duplicates (append* (for/list ([p (profile-names purchase)]) (support purchase p)))))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(and (pair? args) (equal? (car args) "try") (>= (length args) 2))
     (define w (world-from (cddr args)))
     (define run (run-one (cadr args) w "sandbox"))
     (printf "world ~s\nstatus ~a\n" w (hash-ref run 'status))
     (for ([c (hash-ref run 'calls)] [r (hash-ref run 'replies)] [i (in-naturals 1)])
       (printf "~a ~s -> ~s\n" i c r))
     (printf "claims ~s\nresult ~a\n" (hash-ref run 'claims) (hash-ref run 'result))
     ;; run-one also returns the truth; the sandbox never prints it
     (unless (string=? (hash-ref run 'stderr) "") (printf "stderr:\n~a\n" (hash-ref run 'stderr)))]
    [(and (pair? args) (equal? (car args) "run") (<= 3 (length args) 4))
     (define arm (string->symbol (cadr args)))
     (unless (memq arm EXTERNAL-ARMS) (error 'external "unknown external arm ~a" arm))
     (define ws (all-worlds))
     (define runs (run-external-arm! arm (caddr args) ws
                                     #:revision (and (= 4 (length args)) (cadddr args))
                                     #:progress (λ (i w) (when (zero? (modulo i 100)) (eprintf "~a/~a\n" i (length ws))))))
     (define st (for/fold ([h (hasheq)]) ([(k r) runs]) (hash-update h (hash-ref r 'status) add1 0)))
     (printf "~a: ~a worlds stored; status ~s\n" arm (hash-count runs) st)]
    [(and (pair? args) (equal? (car args) "shard") (= 6 (length args)))
     (define arm (string->symbol (list-ref args 1)))
     (unless (memq arm EXTERNAL-ARMS) (error 'external "unknown external arm ~a" arm))
     (define i (string->number (list-ref args 4))) (define k (string->number (list-ref args 5)))
     (define ws (for/list ([w (all-worlds)] [j (in-naturals)] #:when (= (modulo j k) i)) w))
     (define part (string->symbol (format "~a.part-~a" arm i)))
     (run-external-arm! part (list-ref args 2) ws #:revision (list-ref args 3)
                        #:progress (λ (j w) (when (zero? (modulo j 100)) (eprintf "~a/~a\n" j (length ws)))))
     (printf "~a: ~a worlds\n" part (length ws))]
    [(and (pair? args) (equal? (car args) "merge") (= 3 (length args)))
     (define arm (string->symbol (list-ref args 1)))
     (unless (memq arm EXTERNAL-ARMS) (error 'external "unknown external arm ~a" arm))
     (define k (string->number (list-ref args 2)))
     (define parts (for/list ([i k]) (load-arm-cache (string->symbol (format "~a.part-~a" arm i)))))
     (define revs (remove-duplicates (map (λ (c) (hash-ref c 'revision)) parts)))
     (unless (= 1 (length revs)) (error 'external "parts carry different revisions ~s" revs))
     (define runs (for*/hash ([c parts] [(w r) (hash-ref c 'runs)]) (values w (strip-run r))))
     (define missing (for/list ([w (all-worlds)] #:unless (hash-ref runs (format "~s" w) #f)) w))
     (unless (null? missing) (error 'external "~a worlds missing, e.g. ~s" (length missing) (car missing)))
     (save-arm-cache! arm (hasheq 'arm arm 'revision (car revs) 'runs runs))
     (for ([i k]) (delete-file (build-path cache-dir (format "~a.part-~a.rktd" arm i))))
     (printf "~a: ~a worlds stored, revision ~a\n" arm (hash-count runs) (car revs))]
    [(and (pair? args) (equal? (car args) "strip") (= 2 (length args)))
     (define arm (string->symbol (cadr args)))
     (define c (load-arm-cache arm))
     (save-arm-cache! arm (hash-set c 'runs (for/hash ([(w r) (hash-ref c 'runs)]) (values w (strip-run r)))))
     (printf "~a: stored runs stripped\n" arm)]
    [else (eprintf "usage: external-cli.rkt try COMMAND [SLOT=VALUE ...] | run ARM COMMAND [REVISION]\n") (exit 2)]))
