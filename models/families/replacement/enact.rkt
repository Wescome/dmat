#lang racket/base
;; Family 8 — dynamic participant replacement. Enactment adapter
;; (specs/enactment.md): party agents V (provider), V2 (replacement) and A
;; (attester naming the performer); observer H. Protocol: the hybrid's
;; retention. System fault on V's stream: a stale START from V's outbound
;; queue after its withdrawal (the ghost). The registry is the role
;; registry's system of record (holder, whether care started).

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide replacement-enactment)

(define PROTOCOL (hasheq 'on-withdraw 'retain))
(define IFACE (hasheq 'attest? #t 'view 'full))

(define V (role-spec 'V "the provider V"
                     (list (msg-spec 'Accept 'act '() "accept H's referral (the instant you accepted)")
                           (msg-spec 'Withdraw 'act '() "notify H that you withdraw from the role (the instant you withdrew)")
                           (msg-spec 'Start 'report '() "notify H that you initiated care (the instant care was initiated)"))))
(define V2 (role-spec 'V2 "the replacement provider V2"
                      (list (msg-spec 'Start 'report '() "notify H that you initiated care (the instant care was initiated)"))))
(define A (role-spec 'A "the attester A, an independent party that witnesses care initiation and its performer"
                     (list (msg-spec 'Attest 'report '((performer V V2)) "attest to H that care was initiated (the instant, and who performed it)"))))

(define (brief w role)
  (define r (run PROTOCOL w))
  (define wd (hash-ref r 'wd)) (define v2 (hash-ref r 'v2))
  (define st (hash-ref r 'start-at)) (define perf (hash-ref r 'performer))
  (case role
    [(V) (append
          (list (format "You accepted H's referral at instant ~a." T-ACCEPT))
          (cond [(not wd) (list (if st (format "You initiated care at instant ~a." st) "You did not initiate care."))]
                [v2 (list (format "You withdrew from the role at instant ~a." T-WITHDRAW)
                          (format "The replacement V2 accepted the role at instant ~a; from then you are no longer responsible." T-V2))]
                [else (list (format "You withdrew from the role at instant ~a." T-WITHDRAW)
                            (format "The replacement V2 declined the role at instant ~a, so you retained it and resumed." T-V2)
                            (if st (format "You initiated care at instant ~a." st) "You did not initiate care."))]))]
    [(V2) (cond [(not wd) (list "You were not offered any role.")]
                [v2 (list (format "You were offered V's role and accepted it at instant ~a." T-V2)
                          (if st (format "You initiated care at instant ~a." st) "You did not initiate care."))]
                [else (list (format "You were offered V's role and declined it at instant ~a." T-V2))])]
    [(A) (if st (list (format "You witnessed ~a initiating care at instant ~a." (if (eq? perf 'V2) "V2" "V") st))
             (list "You did not witness any initiation of care."))]))

(define (faithful w role)
  (define r (run PROTOCOL w))
  (define st (hash-ref r 'start-at)) (define who (if (eq? (hash-ref r 'performer) 'V2) 'V2 'V))
  (case role
    [(V) (append (list (make-ev V 'Accept T-ACCEPT))
                 (if (hash-ref r 'wd) (list (make-ev V 'Withdraw T-WITHDRAW)) '())
                 (if (and st (eq? who 'V)) (list (make-ev V 'Start st)) '()))]
    [(V2) (if (and st (eq? who 'V2)) (list (make-ev V2 'Start st)) '())]
    [(A) (if st (list (make-ev A 'Attest st 'performer who)) '())]))

(define (assemble w events)
  (define r (run PROTOCOL w))
  (define st (hash-ref r 'start-at))
  (define v-evs (evs-of events 'V))
  (define acc (for/list ([e (msg-of v-evs 'Accept)]) (list 'msg 'ACCEPT (+ 1 (ev-at e)) (ev-at e))))
  (define wdr (for/list ([e (msg-of v-evs 'Withdraw)]) (list 'msg 'WITHDRAW (+ 1 (ev-at e)) (ev-at e))))
  (define starts (sort (append (msg-of v-evs 'Start) (msg-of (evs-of events 'V2) 'Start)) < #:key ev-at))
  (define notice (for/list ([e starts] #:when (or (not st) (eq? (ref w 'notice) 'delivered)))
                   (list 'msg 'START (+ (ev-at e) NOTICE-DELAY) (ev-at e) (ev-role e))))
  (define ghost (if (ref w 'ghost) (list (list 'msg 'START (+ T-V-START NOTICE-DELAY) T-V-START 'V)) '()))
  (define att (for/list ([e (msg-of (evs-of events 'A) 'Attest)] #:when (or (not st) (eq? (ref w 'attest) 'delivered)))
                (list 'msg 'ATTEST (+ (ev-at e) ATTEST-DELAY) (ev-at e) (ev-field e 'performer))))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
            (define-values (holder started) (registry r as-of))
            (list 'read-ok T-READ (list 'full holder started as-of))]))
  (values (by-arrival (append acc wdr notice ghost att (list rd)))
          (if (ref w 'ghost) (list "ghost: V's outbound queue emits a stale START") '())))

(define (truth w ds) (hash-ref ((family-execute replacement) PROTOCOL IFACE w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (case (cadr d)
               [(START) (format "[~a] arrived at ~a: START from ~a, care initiated at ~a" i (caddr d) (list-ref d 4) (cadddr d))]
               [(ATTEST) (format "[~a] arrived at ~a: ATTEST from the attester A, care initiated at ~a by ~a" i (caddr d) (cadddr d) (list-ref d 4))]
               [else (format "[~a] arrived at ~a: ~a from V, at ~a" i (caddr d) (cadr d) (cadddr d))])]
      [(read-failed) (format "[~a] at ~a: the read-back of the role registry failed" i (cadr d))]
      [(read-ok) (define v (caddr d))
                 (format "[~a] at ~a: read-back of the role registry as of instant ~a — role holder ~a; care started: ~a"
                         i (cadr d) (list-ref v 3) (list-ref v 1) (if (list-ref v 2) "yes" "no"))])))

(define texts
  (hasheq
   'scenario (format (string-append
                      "You are a hospital H. Provider V accepts your referral at ~a and may withdraw at ~a; a replacement V2 is then offered the role and accepts or declines at ~a. V retains the role until V2 accepts, and resumes it if V2 declines. "
                      "The responsible party initiates care: V at ~a if V never withdrew, V2 at ~a if V2 took over, V at ~a if it resumed. The performer sends a START notice naming itself; an independent attester A attests care initiation and names the performer. "
                      "A withdrawn V may emit a stale START from its outbound queue. At ~a you read back the role registry.")
                     T-ACCEPT T-WITHDRAW T-V2 T-V-START T-V2-START T-RESUME T-READ)
   'deps (list (cons 'continuity "some party was responsible at every instant from acceptance")
               (cons 'temporal (format "the responsible party initiated care by instant ~a" DEADLINE)))
   'commitments (format "C = C(role, H, true, care initiated by ~a): the debtor is the role, held by V and, after an assignment, by V2. temporal holds iff C is discharged by the party responsible at the instant of initiation (V2 from ~a; V without a withdrawal, before ~a, or from ~a when resuming). If V holds the role after its withdrawal, it resumes at ~a, after the deadline: Violated. continuity holds unless the registry shows the role vacant (the role is retained or assigned, never released)."
                        DEADLINE T-V2 T-V2 T-RESUME T-RESUME)
   'evidence "ACCEPT and WITHDRAW are V's acts. A START notice is the role holder's report of its own performance: not evidence of initiation, though a report of initiation after the deadline is an admission. ATTEST is a third party's report and is evidence. The registry is complete only through its as-of instant; its 'care started' flag has no instant. It shows that care was not initiated by the deadline only if complete through the deadline and not itself showing care started."
   'render render))

(define replacement-enactment
  (enactment 'replacement (list V V2 A) 'H T-EVAL brief faithful assemble truth texts))
