#lang racket/base
;; Family 1 — information handoff. Enactment adapter (specs/enactment.md):
;; party agents V (provider) and A (attester); observer H.
;;
;; System faults applied to V's stream: a crash after acceptance (nothing V
;; sends after accepting is transmitted); a premature start report by V's
;; system (V's reported start is instant T-START). V's record holds V's
;; acceptance (conduct) and V's reported start (V's reports, after system
;; faults), with the world's read and lag faults.

(require racket/list racket/string "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide handoff-enactment)

(define V (role-spec 'V "the home-care provider V"
                     (list (msg-spec 'Accept 'act '() "accept H's referral (the instant is when you accepted)")
                           (msg-spec 'Start 'report '() "notify H that care was initiated (the instant is when care was initiated)"))))
(define A (role-spec 'A "the attester A, an independent party that witnesses care initiation"
                     (list (msg-spec 'Attest 'report '() "attest to H that care was initiated (the instant is when it was initiated)"))))

(define (brief w role)
  (case role
    [(V) (append
          (if (accepted? w) (list (format "You accepted H's referral at instant ~a." (accept-at w)))
              (list "You did not accept H's referral."))
          (cond [(and (accepted? w) (ref w 'crash)) (list "After accepting, your system crashed: you initiated no care.")]
                [(started? w) (list (format "You initiated care at instant ~a." T-START))]
                [(accepted? w) (list "You did not initiate care.")]
                [else '()]))]
    [(A) (if (started? w)
             (list (format "You witnessed V initiating care at instant ~a." T-START))
             (list "You did not witness any initiation of care by V."))]))

(define (faithful w role)
  (case role
    [(V) (append (if (accepted? w) (list (make-ev V 'Accept (accept-at w))) '())
                 (if (started? w) (list (make-ev V 'Start T-START)) '()))]
    [(A) (if (started? w) (list (make-ev A 'Attest T-START)) '())]))

(define DELAY (hasheq 'fast FAST 'slow SLOW))

(define (assemble w events)
  (define notes '())
  (define (note! s) (set! notes (cons s notes)))
  (define v-evs (evs-of events 'V))
  ;; system faults on V's stream
  (define starts
    (cond [(and (accepted? w) (ref w 'crash))
           (unless (null? (msg-of v-evs 'Start)) (note! "crash: V's start reports not transmitted"))
           '()]
          [(and (accepted? w) (not (started? w)) (eq? (ref w 'report) 'premature))
           (note! "premature: V's system reports a start") (list T-START)]
          [else (map ev-at (msg-of v-evs 'Start))]))
  ;; ACCEPT: the reply's fate and transit delay; a message the world never
  ;; planned travels on a reliable channel with the nominal delay
  (define acc
    (for*/list ([e (msg-of v-evs 'Accept)]
                [planned (in-value (accepted? w))]
                [n (in-range (if planned (case (ref w 'reply) [(delivered) 1] [(duplicated) 2] [else 0]) 1))])
      (list 'msg 'ACCEPT (+ (ev-at e) (if planned (hash-ref DELAY (ref w 'reply-delay)) FAST)) (ev-at e))))
  (define notice
    (for/list ([s starts] #:when (or (not (reported-start? w)) (eq? (ref w 'notice) 'delivered)))
      (list 'msg 'START (+ s (- T-NOTICE T-START)) s)))
  (define attest
    (for/list ([e (msg-of (evs-of events 'A) 'Attest)]
               #:when (or (not (started? w)) (eq? (ref w 'attest) 'delivered)))
      (list 'msg 'ATTEST (+ (ev-at e) (- T-ATTEST T-START)) (ev-at e))))
  (define rd
    (if (eq? (ref w 'read) 'unavailable)
        (list 'read-failed T-READ)
        (list 'read-ok T-READ (record w (and (pair? starts) (apply min starts))))))
  (values (by-arrival (append acc notice attest (list rd))) (reverse notes)))

;; V's record (full view): acceptance from conduct, start from V's reports
(define (record w reported)
  (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
  (define lag? (eq? (ref w 'record) 'lag))
  (define oat (and (accepted? w) (<= (accept-at w) as-of) (accept-at w)))
  (define ost (and reported (not lag?) (<= reported as-of) reported))
  (define wm (if lag? (min as-of LAG-WATERMARK) as-of))
  (define S (cond [ost 'started] [oat 'accepted] [else 'referred]))
  (define c0 (cond [(not oat) 'none] [(<= oat ACCEPT-DEADLINE) 'discharged] [else 'late-discharged]))
  (define c1 (cond [ost 'discharged] [oat 'detached] [else 'none]))
  (list 'full S oat ost c0 c1 wm))

(define (truth w ds)
  (hash-ref ((family-execute handoff) (hasheq) (hasheq 'notice? #t 'attest? #t 'view 'full) w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (format "[~a] arrived at ~a: ~a from ~a, for instant ~a" i (caddr d) (cadr d)
                     (if (eq? (cadr d) 'ATTEST) "the attester A" "V") (cadddr d))]
      [(read-failed) (format "[~a] at ~a: the read-back of V's record failed" i (cadr d))]
      [(read-ok)
       (define v (caddr d))
       (format "[~a] at ~a: read-back of V's record — state ~a; acceptance recorded at ~a; start recorded at ~a; commitment C0 ~a; commitment C1 ~a; the record is complete through instant ~a"
               i (cadr d) (list-ref v 1) (or (list-ref v 2) "none") (or (list-ref v 3) "none")
               (list-ref v 4) (list-ref v 5) (list-ref v 6))])))

(define texts
  (hasheq
   'scenario (string-append
              "A hospital H refers a patient to a home-care provider V at instant 0. V may accept the referral and is then expected to initiate care. "
              "V's acceptance reply travels to H; V notifies H when care starts; an independent attester A confirms an initiation of care it witnessed. "
              "At instant " (number->string T-READ) " H reads back V's record. You are H.")
   'deps (list (cons 'flow (format "responsibility passed to V in time: V accepted the referral by instant ~a" ACCEPT-DEADLINE))
               (cons 'temporal (format "care was actually initiated by instant ~a" DEADLINE)))
   'commitments (format "C0 = C(V, H, true, V accepts by instant ~a): the flow dependency holds iff C0 is discharged. C1 = C(V, H, V accepted by instant ~a, care initiated by instant ~a): the temporal dependency holds iff C1 is discharged; if V never accepted, care was never initiated, so temporal is Violated."
                        ACCEPT-DEADLINE DEADLINE DEADLINE)
   'evidence "ACCEPT is V's own act and is evidence of itself. A START notice, and a start recorded in V's record, are V's reports of its own performance: they are not evidence that care was initiated, though a report of a start after the deadline is V's admission of lateness. ATTEST is a third party's report and is evidence. V's record is complete only through the instant it states; it can show that something did not happen by a deadline only if it is complete through that deadline and does not itself report the event."
   'render render))

(define handoff-enactment
  (enactment 'handoff (list V A) 'H T-EVAL brief faithful assemble truth texts))
