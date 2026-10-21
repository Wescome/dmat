#lang racket/base
;; The scenario family: environment (Ω), oracle truth, execution and delivery.
;;
;; A family declares
;;   deps        : the dependencies it judges, each with its DMAT kind
;;   slots       : ordered slot names of a world; a world is (world v ...)
;;   base        : slot → list of (value . weight)
;;   profiles    : list of (name . overrides), overrides a slot → weights hash
;;   canonical   : world → world, one representative per class of irrelevant variation
;;   execute     : protocol interface world → hasheq 'truth (dep → Fulfilled|Violated)
;;                                        'gap   unassigned-responsibility time
;;                                        'required  required-responsibility time
;;                                        'trace oracle events
;;   deliveries  : protocol interface world → deliveries
;;   world-term? : the family's Redex predicate for worlds
;;   ds-term?    : the family's Redex predicate for deliveries
;;
;; Only world modules construct families; arm modules never import them.

(require racket/list file/sha1)
(provide (struct-out family) (struct-out dependency)
         profile-names profile-weights support probability draw world-ref)

(struct dependency (name kind) #:transparent)
(struct family (name deps slots base profiles canonical execute deliveries world-term? ds-term?)
  #:transparent)

(define (profile-names f) (map car (family-profiles f)))

(define (profile-weights f pname)
  (define o (cond [(assq pname (family-profiles f)) => cdr]
                  [else (error 'profile "~a has no profile ~a" (family-name f) pname)]))
  (for/hasheq ([s (family-slots f)])
    (define ws (hash-ref o s (λ () (hash-ref (family-base f) s))))
    (values s (filter (λ (vw) (positive? (cdr vw))) ws))))

(define (world-ref f w slot)
  (list-ref w (+ 1 (index-of (family-slots f) slot))))

(define (cartesian lists)
  (if (null? lists) '(())
      (for*/list ([x (car lists)] [rest (cartesian (cdr lists))]) (cons x rest))))

(define support-cache (make-hash))
(define (support f pname)
  (hash-ref! support-cache (cons (family-name f) pname)
             (λ ()
               (define ws (profile-weights f pname))
               (define raw (cartesian (for/list ([s (family-slots f)]) (map car (hash-ref ws s)))))
               (define worlds (remove-duplicates (for/list ([vals raw]) ((family-canonical f) (cons 'world vals)))))
               (for ([w worlds]) (unless ((family-world-term? f) w) (error 'support "~a: not a world: ~s" (family-name f) w)))
               (sort worlds string<? #:key (λ (w) (format "~s" w))))))

(define prob-cache (make-hash))
(define (probability f pname w)
  (define tbl
    (hash-ref! prob-cache (cons (family-name f) pname)
               (λ ()
                 (define ws (profile-weights f pname))
                 (define dists
                   (for/list ([s (family-slots f)])
                     (define l (hash-ref ws s))
                     (define tot (apply + (map cdr l)))
                     (for/list ([vw l]) (cons (car vw) (/ (cdr vw) tot)))))
                 (define h (make-hash))
                 (for ([combo (cartesian dists)])
                   (define cw ((family-canonical f) (cons 'world (map car combo))))
                   (hash-update! h cw (λ (x) (+ x (apply * (map cdr combo)))) 0))
                 h)))
  (hash-ref tbl w 0))

;; Keyed draw: each slot's value is chosen by SHA-256 of (family, seed,
;; profile, slot), so the same seed gives every arm the same world and a draw
;; for one slot never shifts another.
(define (draw f seed pname)
  (define ws (profile-weights f pname))
  (define vals
    (for/list ([s (family-slots f)])
      (define l (hash-ref ws s))
      (define tot (apply + (map cdr l)))
      (define digest (sha256-bytes (string->bytes/utf-8 (format "dmat/3|~a|~a|~a|~a" (family-name f) seed pname s))))
      (define k (modulo (for/fold ([n 0]) ([i 8]) (+ (* n 256) (bytes-ref digest i))) tot))
      (let loop ([l l] [k k]) (if (< k (cdar l)) (caar l) (loop (cdr l) (- k (cdar l)))))))
  ((family-canonical f) (cons 'world vals)))
