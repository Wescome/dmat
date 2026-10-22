#lang racket/base
;; Family 9 — the stored runs of external arms (specs/external-arms.md §3).
;; Reads and writes families/purchase/external/<arm>.rktd. Holds what each
;; external arm did and claimed in each world: its calls, the replies it
;; received, its claims and its own result. No truth.

(require racket/runtime-path racket/file racket/list)
(provide (rename-out [DIR cache-dir]) arm-cache load-arm-cache save-arm-cache! cached-run transcript->claims-table EXTERNAL-ARMS)

(define-runtime-path DIR "external")

;; the external arms of the family, in reporting order
(define EXTERNAL-ARMS '(product-r product-o))

(define (path-of arm) (build-path DIR (format "~a.rktd" arm)))

;; cache: hasheq 'arm 'revision 'runs ; runs: hash world-string → hasheq
;;   'calls (call ...) 'replies (reply ...) 'claims claims-term 'result string 'status symbol
(define loaded (make-hasheq))
(define (load-arm-cache arm)
  (hash-ref! loaded arm
             (λ () (if (file-exists? (path-of arm))
                       (call-with-input-file (path-of arm) read)
                       (hasheq 'arm arm 'revision #f 'runs (hash))))))
(define (arm-cache arm) (load-arm-cache arm))
(define (save-arm-cache! arm c)
  (make-directory* DIR)
  (call-with-output-file (path-of arm) #:exists 'truncate (λ (o) (write c o) (newline o)))
  (hash-set! loaded arm c))

(define (cached-run arm w) (hash-ref (hash-ref (arm-cache arm) 'runs) (format "~s" w) #f))

;; transcript (list of (call reply)) → claims, over every stored run; an arm that
;; claims differently on the same transcript is nondeterministic, and is refused
(define tables (make-hasheq))
(define (transcript->claims-table arm)
  (hash-ref! tables arm
             (λ ()
               (define t (make-hash))
               (for ([(ws run) (hash-ref (arm-cache arm) 'runs)])
                 (define tr (map list (hash-ref run 'calls) (hash-ref run 'replies)))
                 (define prev (hash-ref t tr #f))
                 (when (and prev (not (equal? prev (hash-ref run 'claims))))
                   (error 'external "~a is nondeterministic: one transcript, two sets of claims" arm))
                 (hash-set! t tr (hash-ref run 'claims)))
               t)))
