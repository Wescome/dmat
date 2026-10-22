#lang racket/base
;; Family 9 — command line for external arms (specs/external-arms.md).
;;
;;   racket families/purchase/external-cli.rkt try COMMAND [SLOT=VALUE ...]
;;       run the arm once in one world (default: every slot at its reliable value) and
;;       print its transcript and claims. Shows replies only: no truth, no judgment.
;;   racket families/purchase/external-cli.rkt run ARM COMMAND [REVISION]
;;       run the arm in every world of every profile and store the runs in
;;       families/purchase/external/ARM.rktd.

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
     (define runs (run-external-arm! 'sandbox (cadr args) (list w) #:save? #f))
     (define run (hash-ref runs (format "~s" w)))
     (printf "world ~s\nstatus ~a\n" w (hash-ref run 'status))
     (for ([c (hash-ref run 'calls)] [r (hash-ref run 'replies)] [i (in-naturals 1)])
       (printf "~a ~s -> ~s\n" i c r))
     (printf "claims ~s\nresult ~a\n" (hash-ref run 'claims) (hash-ref run 'result))
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
    [else (eprintf "usage: external-cli.rkt try COMMAND [SLOT=VALUE ...] | run ARM COMMAND [REVISION]\n") (exit 2)]))
