#lang racket/base
;; Family 9 — external arms: the process protocol of specs/external-arms.md, and
;; the replay of a stored run against the world.
;;
;; (run-external-arm! arm command worlds) runs the arm's command once per world,
;; answers its calls from fresh providers, and stores calls, replies, claims and
;; result in the arm's cache. (replay-external arm w call) resends a stored run's
;; calls through `call` (the world's providers) and checks that every reply is
;; the stored one, so a stale cache cannot pass for a run.

(require racket/list racket/string racket/port json "terms.rkt" "providers.rkt" "external-cache.rkt")
(provide run-external-arm! run-one strip-run replay-external call->json reply->json json->call json->claims START-JSON)

;; ------------------------------------------------------------------ JSON forms

(define (name->json s) (string-replace (symbol->string s) "-" "_"))
(define (json->name s) (string->symbol (string-replace s "_" "-")))

(define OPS '(reserve alternatives authorize confirm accept void capture refund cancel ship deliver
              payment-record order-state shipment-state carrier-scan reconcile))
(define ARGS (hasheq 'reserve '(seller) 'alternatives '() 'authorize '(seller amount key) 'confirm '(seller)
                     'accept '(seller key) 'void '(seller key) 'capture '(seller key) 'refund '(seller key)
                     'cancel '(seller key) 'ship '(seller key) 'deliver '(seller key) 'payment-record '()
                     'order-state '(seller) 'shipment-state '() 'carrier-scan '() 'reconcile '()))

(define (json->call js)
  (define op (and (hash? js) (string? (hash-ref js 'op #f)) (string->symbol (hash-ref js 'op))))
  (define args (and (hash? js) (hash-ref js 'args (hasheq))))
  (cond
    [(not (and op (memq op OPS) (hash? args))) '(invalid)]
    [else
     (define vals
       (for/list ([a (hash-ref ARGS op)])
         (define v (hash-ref args a #f))
         (case a
           [(seller) (and (member v '("A" "B")) (string->symbol v))]
           [(amount) (and (exact-nonnegative-integer? v) v)]
           [(key) (and (string? v) (positive? (string-length v)) v)])))
     (if (andmap values vals) (cons op vals) '(invalid))]))

(define (call->json c)
  (if (eq? (car c) 'invalid)
      (hasheq 'op "invalid" 'args (hasheq))
      (hasheq 'op (symbol->string (car c))
              'args (for/hasheq ([a (hash-ref ARGS (car c))] [v (cdr c)])
                      (values a (if (symbol? v) (symbol->string v) v))))))

(define (record->json r)
  (hasheq 'complete_through (or (cadr r) (json-null))
          'holds (for/list ([h (caddr r)]) (hasheq 'seller (symbol->string (car h)) 'state (name->json (cadr h)) 'amount (caddr h)))))

(define (value->json v)
  (cond
    [(symbol? v) (name->json v)]
    [(eq? (car v) 'offers) (for/list ([o (cdr v)]) (hasheq 'seller (symbol->string (car o)) 'price (cadr o)))]
    [(eq? (car v) 'at) (hasheq 'delivered_at (if (eq? (cadr v) 'none) (json-null) (cadr v)))]
    [(eq? (car v) 'record) (record->json v)]
    [(eq? (car v) 'report)
     (hasheq 'payment (record->json (cadr v))
             'orders (for/hasheq ([o (cdr (caddr v))]) (values (car o) (name->json (cadr o))))
             'shipment (name->json (cadddr v))
             'charges (list-ref v 4))]))

(define (reply->json n r)
  (if (eq? (car r) 'ok)
      (hasheq 'type "reply" 'seq n 'ok #t 'value (value->json (cadr r)))
      (hasheq 'type "reply" 'seq n 'ok #f 'failure (name->json (cadr r)) 'code (symbol->string (caddr r)))))

(define DEPS '(funds fit flow temporal))
;; JSON claims → claims term (cites: call sequence numbers → delivery indices); #f if malformed
(define (json->claims js ncalls)
  (and (list? js)
       (let ([cls (for/list ([d DEPS])
                    (define it (findf (λ (x) (and (hash? x) (equal? (hash-ref x 'dependency #f) (symbol->string d)))) js))
                    (define j (and it (member (hash-ref it 'judgment #f) '("Fulfilled" "Violated" "Indeterminate"))
                                   (string->symbol (hash-ref it 'judgment))))
                    (define cites (and it (hash-ref it 'cites '())))
                    (and j (list? cites) (andmap (λ (c) (and (exact-positive-integer? c) (<= c ncalls))) cites)
                         (list 'claim d j (if (eq? j 'Indeterminate) '() (sort (remove-duplicates (map sub1 cites)) <)))))])
         (and (andmap values cls) cls))))

(define (all-indeterminate) (for/list ([d DEPS]) (list 'claim d 'Indeterminate '())))

(define START-JSON
  (hasheq 'type "start" 'family "purchase"
          'principal (hasheq 'cap CAP 'deadline DEADLINE) 'primary (hasheq 'seller "A" 'price PRICE-A)
          'interface (hasheq 'watermark #t)))

;; ------------------------------------------------------------------ running an arm

(define TIMEOUT 60)

;; one world → hasheq 'calls 'replies 'claims 'result 'status 'stderr
(define (run-one command w run-id)
  (define p (new-providers w (hasheq 'watermark #t)))
  (define-values (proc out in err)
    (subprocess #f #f #f "/bin/sh" "-c" command))
  (define err-text (box ""))
  (define err-thread (thread (λ () (set-box! err-text (port->string err)))))
  (define (send! js) (write-json js in) (newline in) (flush-output in))
  (define (receive)
    (define ready (sync/timeout TIMEOUT out))
    (and ready (let ([l (read-line out)]) (and (string? l) (with-handlers ([exn:fail? (λ (e) 'bad-json)]) (string->jsexpr l))))))
  (define calls '()) (define replies '())
  (define (finish status claims result)
    (with-handlers ([exn:fail? void]) (close-output-port in))
    (sync/timeout 5 proc)
    (when (eq? (subprocess-status proc) 'running) (subprocess-kill proc #t))
    (thread-wait err-thread)
    (close-input-port out) (close-input-port err)
    ;; 'truth is oracle data: it is never stored in an arm's cache
    (hasheq 'calls (reverse calls) 'replies (reverse replies) 'claims claims
            'result result 'status status 'stderr (unbox err-text) 'truth (provider-truth p)))
  (send! (hash-set START-JSON 'run run-id))
  (let loop ([n 0])
    (define msg (receive))
    (cond
      [(not msg) (finish 'timeout (all-indeterminate) "")]
      [(eq? msg 'bad-json) (finish 'malformed (all-indeterminate) "")]
      [(and (hash? msg) (equal? (hash-ref msg 'type #f) "end"))
       (define cls (json->claims (hash-ref msg 'claims #f) n))
       (finish (if cls 'ended 'malformed-claims) (or cls (all-indeterminate))
               (jsexpr->string (hash-ref msg 'result (json-null))))]
      [(and (hash? msg) (equal? (hash-ref msg 'type #f) "call"))
       (cond
         [(>= n CALL-LIMIT) (finish 'call-limit (all-indeterminate) "")]
         [else
          (define c (json->call msg))
          (define r (provider-call! p c))
          (set! calls (cons c calls)) (set! replies (cons r replies))
          (send! (reply->json (add1 n) r))
          (loop (add1 n))])]
      [else (finish 'malformed (all-indeterminate) "")])))

;; what a stored run keeps: calls, replies, claims, status
(define (strip-run r) (for/fold ([r r]) ([k '(truth stderr result)]) (hash-remove r k)))

;; run `command` in every world; store the runs in the arm's cache
(define (run-external-arm! arm command worlds #:revision [revision #f] #:progress [progress void] #:save? [save? #t])
  (define runs
    (for/hash ([w worlds] [i (in-naturals)])
      (progress i w)
      ;; the cache keeps what the arm did and claimed: no truth, and not the arm's own
      ;; diagnostics or result, which describe the product's internals (external-arms.md §3)
      (values (format "~s" w) (strip-run (run-one command w (format "~a-~a" arm i))))))
  (when save? (save-arm-cache! arm (hasheq 'arm arm 'revision revision 'runs runs)))
  runs)

;; replay a stored run's calls through the world's providers (world.rkt)
(define (replay-external arm w call)
  (define run (cached-run arm w))
  (unless run (error 'external "~a has no stored run for ~s" arm w))
  (for ([c (hash-ref run 'calls)] [r (hash-ref run 'replies)] [i (in-naturals 1)])
    (define got (call c))
    (unless (equal? got r)
      (error 'external "~a: stored run for ~s differs from the world at call ~a: stored ~s, world ~s" arm w i r got))))
