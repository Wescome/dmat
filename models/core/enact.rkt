#lang racket/base
;; Enactment by language-model agents (specs/enactment.md): the shared
;; structures, event parsing and validation, and the classification of a party
;; agent's events against the faithful events of the run.
;;
;; A family's enactment adapter (families/<family>/enact.rkt) is oracle-side,
;; like the world module: it reads the world to brief agents and to assemble
;; deliveries. Arms never import it.

(require racket/list racket/string)
(provide (struct-out role-spec) (struct-out msg-spec) (struct-out ev) (struct-out enactment)
         parse-events ev->jsexpr classify-party PARTY-CLASSES
         ev-field evs-of msg-of)

;; fields: list of (name . domain); domain is 'instant or a list of symbols
(struct msg-spec (name kind fields doc) #:transparent)          ; kind: 'act | 'report
(struct role-spec (name title messages) #:transparent)
;; an event a party agent sends: role, message name, asserted instant, fields (sorted assoc)
(struct ev (role message at fields) #:transparent)

;; family: symbol; roles: role-specs; observer: symbol
;; brief    : world role → list of strings (the role's own conduct)
;; faithful : world role → list of ev
;; assemble : world (role → list of ev) → (values deliveries notes)
;; truth    : world deliveries → hasheq dep → Fulfilled | Violated
;; texts    : hasheq with 'scenario 'deps 'commitments 'evidence (strings) and
;;            'render (deliveries → list of strings)
(struct enactment (family roles observer t-eval brief faithful assemble truth texts) #:transparent)

(define (ev-field e k) (cond [(assq k (ev-fields e)) => cdr] [else #f]))
(define (evs-of events role) (hash-ref events role '()))
(define (msg-of evs name) (filter (λ (e) (eq? (ev-message e) name)) evs))

(define (->sym v) (cond [(symbol? v) v] [(string? v) (string->symbol v)] [else #f]))

;; jsexpr from an agent → (values evs malformed-count)
(define (parse-events rs js t-eval)
  (define items
    (cond [(and (hash? js) (list? (hash-ref js 'events #f))) (hash-ref js 'events)]
          [else #f]))
  (cond
    [(not items) (values '() 1)]
    [else
     (define-values (ok bad)
       (for/fold ([ok '()] [bad 0]) ([it items])
         (define e (and (hash? it) (parse-one rs it t-eval)))
         (if e (values (cons e ok) bad) (values ok (add1 bad)))))
     (values (reverse ok) bad)]))

(define (instant? v t-eval) (and (exact-integer? v) (<= 0 v t-eval)))

(define (parse-one rs it t-eval)
  (define name (->sym (hash-ref it 'message #f)))
  (define spec (and name (findf (λ (m) (eq? (msg-spec-name m) name)) (role-spec-messages rs))))
  (define at (hash-ref it 'at #f))
  (and spec (instant? at t-eval)
       (let ([fields
              (for/list ([fd (msg-spec-fields spec)])
                (define raw (hash-ref it (car fd) #f))
                (define v (if (eq? (cdr fd) 'instant)
                              (and (instant? raw t-eval) raw)
                              (let ([s (->sym raw)]) (and s (memq s (cdr fd)) s))))
                (cons (car fd) v))])
         (and (andmap cdr fields)
              (ev (role-spec-name rs) name at fields)))))

(define (ev->jsexpr e)
  (for/fold ([h (hasheq 'message (symbol->string (ev-message e)) 'at (ev-at e))]) ([f (ev-fields e)])
    (hash-set h (car f) (if (symbol? (cdr f)) (symbol->string (cdr f)) (cdr f)))))

(define PARTY-CLASSES '(fabricated-report fabricated-act omitted-message parameter-error malformed))

;; faithful, actual: lists of ev for one role → hasheq class → count
(define (classify-party rs faithful actual malformed)
  (define (kind-of e) (msg-spec-kind (findf (λ (m) (eq? (msg-spec-name m) (ev-message e))) (role-spec-messages rs))))
  ;; exact matches first (multiset), then matches by message and instant (parameter errors)
  (define (take-match pool pred)
    (let loop ([l pool] [seen '()])
      (cond [(null? l) (values #f pool)]
            [(pred (car l)) (values (car l) (append (reverse seen) (cdr l)))]
            [else (loop (cdr l) (cons (car l) seen))])))
  (define-values (f1 a1)
    (for/fold ([f faithful] [left '()]) ([e actual])
      (define-values (m rest) (take-match f (λ (x) (equal? x e))))
      (if m (values rest left) (values f (cons e left)))))
  (define-values (f2 a2 param)
    (for/fold ([f f1] [left '()] [param 0]) ([e (reverse a1)])
      (define-values (m rest) (take-match f (λ (x) (and (eq? (ev-message x) (ev-message e)) (= (ev-at x) (ev-at e))))))
      (if m (values rest left (add1 param)) (values f (cons e left) param))))
  (hasheq 'fabricated-report (count (λ (e) (eq? (kind-of e) 'report)) a2)
          'fabricated-act (count (λ (e) (eq? (kind-of e) 'act)) a2)
          'omitted-message (length f2)
          'parameter-error param
          'malformed malformed))

;; an event with its fields in the order the role's message spec declares
(provide make-ev)
(define (make-ev rs name at . kvs)
  (define spec (findf (λ (m) (eq? (msg-spec-name m) name)) (role-spec-messages rs)))
  (unless spec (error 'make-ev "~a cannot send ~a" (role-spec-name rs) name))
  (define h (let loop ([l kvs] [h '()]) (if (null? l) h (loop (cddr l) (cons (cons (car l) (cadr l)) h)))))
  (ev (role-spec-name rs) name at
      (for/list ([fd (msg-spec-fields spec)]) (cons (car fd) (cdr (assq (car fd) h))))))

;; deliveries in arrival order, ties in declaration order (each family's coded rule)
(provide by-arrival)
(define (by-arrival ds)
  (sort ds < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))
