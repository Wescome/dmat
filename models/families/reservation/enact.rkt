#lang racket/base
;; Family 2 — resource reservation. Enactment adapter (specs/enactment.md):
;; party agents V (the allocator, which keeps the allocation log) and R (the
;; resource, which keeps the access log); observer: the auditor U, who reads
;; both logs once. Protocol: the hybrid's expiry with fencing tokens.
;;
;; The logs hold the entries the agents write; the read-back shows those with
;; instant ≤ as-of (the world's read fault), in time order.

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide reservation-enactment)

(define PROTOCOL (hasheq 'regrant 'expiry-fenced))
(define IFACE (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT)))

(define V (role-spec 'V "the allocator V, which grants the exclusive resource and keeps the allocation log"
                     (list (msg-spec 'Grant 'report '((holder h1 h2)) "log entry: you granted the resource to holder (the instant of the grant)")
                           (msg-spec 'ReleaseReceived 'act '() "log entry: you received h1's release (the instant you received it)")
                           (msg-spec 'Expire 'act '() "log entry: you expired h1's lease (the instant of expiry)"))))
(define R (role-spec 'R "the resource R, which checks fencing tokens and keeps the access log"
                     (list (msg-spec 'Use 'report '((holder h1 h2) (from . instant) (to . instant))
                                     "access-log entry: holder used the resource from instant `from` to instant `to` (the entry's instant is `to`)")
                           (msg-spec 'Reject 'act '((holder h1 h2)) "access-log entry: you rejected holder's use of a superseded token (the instant of rejection)"))))

(define (trace w) (let-values ([(events g2 over) (run PROTOCOL w)]) events))

(define (brief w role)
  (define es (trace w))
  (define (find k [who #f]) (findf (λ (e) (and (eq? (car e) k) (or (not who) (eq? (cadr e) who)))) es))
  (case role
    [(V) (append
          (list (format "You granted the resource to h1 at instant ~a, with a lease until instant ~a (fencing token 1). h2 requested the resource at instant ~a."
                        T-GRANT1 LEASE-END T-REQ2))
          (cond [(find 'RELEASE) => (λ (e) (list (format "You received h1's release at instant ~a." (cadr e))))]
                [else (list "You received no release from h1.")])
          (cond [(find 'EXPIRE) => (λ (e) (list (format "At instant ~a, with no release received, you expired h1's lease." (cadr e))))]
                [else '()])
          (cond [(find 'GRANT 'h2) => (λ (e) (list (format "You granted the resource to h2 at instant ~a (fencing token 2)." (caddr e))))]
                [else (list "You did not grant the resource to h2.")]))]
    [(R) (append
          (for/list ([e es] #:when (eq? (car e) 'USE))
            (format "~a used the resource from instant ~a to instant ~a." (cadr e) (caddr e) (cadddr e)))
          (for/list ([e es] #:when (eq? (car e) 'REJECT))
            (format "At instant ~a you rejected ~a's use of its superseded token." (caddr e) (cadr e))))]))

(define (faithful w role)
  (for/list ([e (trace w)]
             #:when (memq (car e) (if (eq? role 'V) '(GRANT RELEASE EXPIRE) '(USE REJECT))))
    (case (car e)
      [(GRANT) (make-ev V 'Grant (caddr e) 'holder (cadr e))]
      [(RELEASE) (make-ev V 'ReleaseReceived (cadr e))]
      [(EXPIRE) (make-ev V 'Expire (cadr e))]
      [(USE) (make-ev R 'Use (cadddr e) 'holder (cadr e) 'from (caddr e) 'to (cadddr e))]
      [(REJECT) (make-ev R 'Reject (caddr e) 'holder (cadr e))])))

;; the coded log's declaration order, for ties
(define (rank e)
  (case (car e) [(GRANT) (if (eq? (cadr e) 'h1) 0 3)] [(RELEASE) 1] [(EXPIRE) 2]
    [(USE) (if (eq? (cadr e) 'h1) 4 6)] [(REJECT) 5]))

(define (assemble w events)
  (define entries
    (append
     (for/list ([e (evs-of events 'V)])
       (case (ev-message e)
         [(Grant) (list 'GRANT (ev-field e 'holder) (ev-at e))]
         [(ReleaseReceived) (list 'RELEASE (ev-at e))]
         [(Expire) (list 'EXPIRE (ev-at e))]))
     (for/list ([e (evs-of events 'R)])
       (case (ev-message e)
         [(Use) (list 'USE (ev-field e 'holder) (ev-field e 'from) (ev-field e 'to))]
         [(Reject) (list 'REJECT (ev-field e 'holder) (ev-at e))]))))
  (define ds
    (case (ref w 'read)
      [(unavailable) (list (list 'read-failed T-READ))]
      [else
       (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
       (define visible (filter (λ (e) (<= (event-time e) as-of)) entries))
       (list (list 'read-ok T-READ (list* 'log as-of (sort (sort visible < #:key rank) < #:key event-time))))]))
  (values ds '()))

(define (truth w ds) (hash-ref ((family-execute reservation) PROTOCOL IFACE w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(read-failed) (format "[~a] at ~a: the read-back of the logs failed" i (cadr d))]
      [(read-ok)
       (define v (caddr d))
       (string-append
        (format "[~a] at ~a: read-back of V's allocation log and R's access log, complete as of instant ~a, entries in time order:" i (cadr d) (cadr v))
        (apply string-append
               (for/list ([e (cddr v)])
                 (case (car e)
                   [(GRANT) (format "\n      V granted the resource to ~a at ~a" (cadr e) (caddr e))]
                   [(RELEASE) (format "\n      V received h1's release at ~a" (cadr e))]
                   [(EXPIRE) (format "\n      V expired h1's lease at ~a" (cadr e))]
                   [(USE) (format "\n      R: ~a used the resource from ~a to ~a" (cadr e) (caddr e) (cadddr e))]
                   [(REJECT) (format "\n      R rejected ~a's superseded token at ~a" (cadr e) (caddr e))]))))])))

(define texts
  (hasheq
   'scenario (format (string-append
                      "An allocator V holds one exclusive resource. V grants it to holder h1 at instant ~a with a lease until instant ~a; holder h2 requests it at instant ~a. "
                      "V grants h2 at the earlier of h1's release and the lease end, expiring h1's lease if no release arrived; grants carry fencing tokens that the resource R checks, rejecting a superseded token. "
                      "You are an auditor U who reads V's allocation log and R's access log once, at instant ~a.")
                     T-GRANT1 LEASE-END T-REQ2 T-READ)
   'deps (list (cons 'sharing "at no instant do two holders effectively use the resource")
               (cons 'temporal (format "h2 is granted the resource by instant ~a" D2)))
   'commitments (format "C2 = C(V, h2, true, h2 granted by instant ~a): temporal holds iff C2 is discharged. h2 is granted if V's log shows a grant to h2, R's log shows a use by h2, or R's log shows a rejection of h1's superseded token. M: V's maintenance commitment to both holders that at no instant do two holders effectively use the resource: sharing holds iff M is never violated." D2)
   'evidence "V's GRANT entries are V's reports of its own performance and are not evidence of the grant. R is an independent party: its USE and REJECT entries are evidence. The read-back is complete only through its as-of instant: it shows the absence of an event by a deadline only if its as-of instant is at or after that deadline. The fencing tokens are checked by R itself, so if R's uses do not overlap, no two holders used the resource at once."
   'render render))

(define reservation-enactment
  (enactment 'reservation (list V R) 'U T-EVAL brief faithful assemble truth texts))
