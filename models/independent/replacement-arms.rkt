#lang racket/base
;; Family `replacement` — dynamic participant replacement (Flow with
;; responsibility continuity, Temporal). Independent arms.
;;
;; H (the observer) placed an order that V accepted at T-ACCEPT. V may withdraw
;; at T-WITHDRAW; a replacement V2 is offered the role and accepts or declines
;; at T-V2. The responsible party initiates care. A withdrawn V may emit a
;; ghost START (asserted T-V-START) from its outbound queue. H receives no
;; message about V2's decision: it learns of V2 only from V2's own START, an
;; ATTEST naming V2, or the role registry read-back at T-READ.
;;
;; Dependencies, in order: continuity, temporal.

(require racket/list
         "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/replacement/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Shared helpers over deliveries (pure; no world access).

(define (who-of d) (car (msg-payload d)))
(define (from? who) (λ (d) (eq? (who-of d) who)))

(define (accept-ix ds) (msg-indices ds 'ACCEPT))
(define (withdraw-ix ds) (msg-indices ds 'WITHDRAW))
(define (withdrew? ds) (pair? (withdraw-ix ds)))

;; read-back view accessors; both view kinds carry holder and started first
(define (view-holder v) (cadr v))
(define (view-started v) (caddr v))
;; the completeness watermark: only the `full` view carries one
(define (view-as-of v) (and (eq? (car v) 'full) (cadddr v)))

(define (read-cite ds) (let ([i (read-index ds)]) (if i (list i) '())))

;; ---------------------------------------------------------------------------
;; CHOR — protocol: on-withdraw release; interface: no ATTEST, registry view.
;;
;; The global type: V -> H : ACCEPT; then either V -> H : START (V performs),
;; or V -> H : WITHDRAW, after which V leaves the session and the role is
;; re-offered (V2's accept/decline is between V2 and the coordinator, outside
;; H's projection); if V2 joins, V2 -> H : START. H's local type therefore
;; awaits START from V on the no-withdraw branch and START from V2 on the
;; withdraw branch, with a timed branch at DEADLINE.
;;
;; continuity: the role is the session role. With no WITHDRAW in H's session
;;   the role stayed with V from ACCEPT on: Fulfilled (cites ACCEPT). A
;;   WITHDRAW is V leaving the session under `release`; the global type has
;;   nobody in the role until V2's acceptance at T-V2 at the earliest, so the
;;   role was unheld from T-WITHDRAW: Violated (cites WITHDRAW).
;; temporal: a message is the event it names. If the START H's projection
;;   awaits (from V on the no-withdraw branch, from V2 on the withdraw branch)
;;   arrived by DEADLINE, care was initiated in time: Fulfilled. Otherwise the
;;   timed branch fired: Violated. A START from V after V's WITHDRAW is not a
;;   message of H's projection on that branch and is not taken as the event.
;;   The session decides every case, so the registry read-back is not needed.
(define (chor-judge ds)
  (define acc (accept-ix ds))
  (define wd (withdraw-ix ds))
  (define performer (if (pair? wd) 'V2 'V))
  (define starts (msg-indices ds 'START #:arrived-by DEADLINE #:where (from? performer)))
  (claims
   (if (pair? wd)
       (list 'continuity 'Violated wd)
       (list 'continuity 'Fulfilled acc))
   (if (pair? starts)
       (list 'temporal 'Fulfilled starts)
       (list 'temporal 'Violated (append acc wd)))))

;; ---------------------------------------------------------------------------
;; FSM — protocol: on-withdraw retain; interface: no ATTEST, registry view.
;;
;; The role registry is a state machine: holder V from acceptance; on V's
;; withdrawal under `retain` it stays V (state awaiting-replacement); at T-V2
;; it moves to V2 if V2 accepts, else stays V and V's machine takes its
;; resume transition at T-RESUME. Each holder's machine moves to `started`
;; when it initiates care. H reads the registry's state at T-READ; the
;; record is the machine's current state.
;;
;; continuity: the record names a holder (V or V2): the machine is in a held
;;   state, and the retain machine has no unheld state: Fulfilled. A record
;;   naming `none` is an unheld state: Violated. No record: Indeterminate.
;; temporal: the read is at T-READ, after DEADLINE, so the record's state is
;;   the state the machine reached by then.
;;   - not started: the machine passed DEADLINE without starting: Violated.
;;   - started, holder V, and H's machine saw V's WITHDRAW: the holder is
;;     still V after T-V2, so V2 declined and V's start is the resume
;;     transition at T-RESUME, after DEADLINE: Violated.
;;   - started otherwise (V without withdrawal, starting at T-V-START; V2,
;;     starting at T-V2-START): Fulfilled.
;;   No record: Indeterminate (the paradigm judges from the recorded state).
(define (fsm-judge ds)
  (define v (read-view ds))
  (define rc (read-cite ds))
  (cond
    [(not v)
     (claims (list 'continuity 'Indeterminate '())
             (list 'temporal 'Indeterminate '()))]
    [else
     (define holder (view-holder v))
     (define started (view-started v))
     (define wd (withdraw-ix ds))
     (claims
      (if (eq? holder 'none)
          (list 'continuity 'Violated rc)
          (list 'continuity 'Fulfilled rc))
      (cond
        [(not started) (list 'temporal 'Violated rc)]
        [(and (eq? holder 'V) (pair? wd)) (list 'temporal 'Violated (append rc wd))]
        [else (list 'temporal 'Fulfilled rc)]))]))

;; ---------------------------------------------------------------------------
;; COMM — protocol: on-withdraw retain; interface: no ATTEST, registry view.
;;
;; ACCEPT creates and detaches C(V, H, accepted, care-initiated by DEADLINE).
;; Under `retain`, V's WITHDRAW is not a release: V stays debtor until the
;; commitment is assigned to V2 (V2's acceptance at T-V2). The read-back is
;; the counterpart's ledger: its holder is the commitment's current debtor.
;; A START from V2 is V2 acting as debtor, so it shows the assignment.
;;
;; continuity: the commitment was never released or cancelled; it was
;;   retained by V and at most assigned to V2: some debtor at every instant:
;;   Fulfilled (cites ACCEPT, and WITHDRAW when present).
;; temporal: the creditor's view at DEADLINE. A START that arrived by
;;   DEADLINE from the party that was debtor at the instant it asserts
;;   discharges the commitment: Fulfilled. The debtor is V, except from T-V2
;;   on when H has seen the assignment (ledger holder V2, or a START from
;;   V2). A commitment H cannot see discharged by DEADLINE is Violated.
(define (comm-judge ds)
  (define acc (accept-ix ds))
  (define wd (withdraw-ix ds))
  (define v (read-view ds))
  (define v2-starts (msg-indices ds 'START #:where (from? 'V2)))
  (define assigned?
    (or (and v (eq? (view-holder v) 'V2)) (pair? v2-starts)))
  (define (debtor-at s) (if (and assigned? (>= s T-V2)) 'V2 'V))
  (define discharges
    (msg-indices ds 'START #:arrived-by DEADLINE #:asserted-by DEADLINE
                 #:where (λ (d) (eq? (who-of d) (debtor-at (msg-asserted d))))))
  (claims
   (list 'continuity 'Fulfilled (append acc wd))
   (if (pair? discharges)
       (list 'temporal 'Fulfilled discharges)
       (list 'temporal 'Violated acc))))

;; ---------------------------------------------------------------------------
;; HYBRID — protocol: on-withdraw retain; interface: ATTEST, full view.
;;
;; COMM's commitment C(V, H, accepted, care-initiated by DEADLINE), retained by
;; V on withdrawal and assigned to V2 only on V2's explicit acceptance at
;; T-V2; the registry as an FSM record with completeness watermark `as-of`;
;; and the evidentiary rules. ATTEST is an independent party's attestation;
;; START messages and the registry's `started` flag are the performer side's
;; own reports (E1).
;;
;; continuity: responsibility is retained or assigned explicitly, never
;;   dropped: from ACCEPT on, V or its assignee held the role at every
;;   instant: Fulfilled (cites ACCEPT, and WITHDRAW when present).
;; temporal:
;;   - E1: an ATTEST, asserted by DEADLINE, of care by the party responsible
;;     at that instant (V2 from T-V2; V without withdrawal, before T-V2, or
;;     when an authoritative record shows V still holder after T-V2, or in
;;     V's resume at T-RESUME): Fulfilled.
;;   - An ATTEST of the responsible party's initiation after DEADLINE: a party
;;     initiates once, so it did not initiate by DEADLINE: Violated.
;;   - E2: a record complete through DEADLINE (as-of >= DEADLINE) that does
;;     not show care started establishes the negative: Violated.
;;   - E2: a record complete through T-V2 showing V as holder after V's
;;     WITHDRAW establishes that V2 declined; under `retain` V's only
;;     initiation is then the resume at T-RESUME, after DEADLINE: Violated.
;;   - E3: otherwise (START reports alone, a `started` flag alone, a stale
;;     or failed read-back): Indeterminate.
(define (hybrid-judge ds) (hybrid-core ds #t))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE — protocol: on-withdraw retain; interface: ATTEST, full view.
;;
;; The same commitment and record mechanism with E1–E3 removed: a performer's
;; START report counts as evidence of the care it reports, the registry's
;; `started` flag counts as the performer having started, and every
;; successful read-back is authoritative whatever its as-of.
;;
;; continuity: as HYBRID — retained or assigned, never dropped: Fulfilled.
;; temporal:
;;   - an ATTEST or START, asserted by DEADLINE, of care by the party
;;     responsible at that instant (V2 from T-V2; V without withdrawal,
;;     before T-V2, or when the record shows V still holder): Fulfilled.
;;   - an ATTEST or START of the responsible party's initiation after
;;     DEADLINE: Violated.
;;   - a record not showing care started: Violated. A record showing V as
;;     holder after V's WITHDRAW: V2 declined, V resumes at T-RESUME: Violated.
;;   - a record showing care started by V2, or by V without a withdrawal:
;;     those parties start at T-V2-START / T-V-START: Fulfilled.
;;   - otherwise the creditor's commitment rule: a commitment not seen
;;     discharged by DEADLINE is Violated.
(define (hybrid-noe-judge ds) (hybrid-core ds #f))

;; evidence? #t applies E1–E3; #f is the ablation
(define (hybrid-core ds evidence?)
  (define acc (accept-ix ds))
  (define wd (withdraw-ix ds))
  (define withdrawn? (pair? wd))
  (define v (read-view ds))
  (define rc (read-cite ds))
  (define as-of (and v (view-as-of v)))
  ;; E2: the record is authoritative for an event recorded by instant `by`
  (define (authoritative-by? by)
    (and v (or (not evidence?) (and as-of (>= as-of by)))))
  ;; holder after T-V2, when the record is authoritative for V2's decision
  (define holder-after-v2
    (and (authoritative-by? T-V2) (view-holder v)))
  (define (responsible? who s)
    (case who
      [(V2) (>= s T-V2)]
      ;; after a withdrawal V acts as responsible party only if it kept the
      ;; role (record shows it) or in the resume transition at T-RESUME,
      ;; which `retain` gives V only when it kept the role
      [(V) (or (not withdrawn?) (< s T-V2) (eq? holder-after-v2 'V) (>= s T-RESUME))]
      [else #f]))
  ;; E1: under the evidentiary discipline only ATTEST counts as performance
  (define kinds (if evidence? '(ATTEST) '(ATTEST START)))
  (define (perf-ix pred)
    (sort (append* (for/list ([k kinds])
                     (msg-indices ds k #:where (λ (d) (and (responsible? (who-of d) (msg-asserted d))
                                                           (pred (msg-asserted d)))))))
          <))
  (define in-time (perf-ix (λ (s) (<= s DEADLINE))))
  (define late (perf-ix (λ (s) (> s DEADLINE))))
  (define temporal
    (cond
      [(pair? in-time) (list 'temporal 'Fulfilled in-time)]
      [(pair? late) (list 'temporal 'Violated late)]
      [(and (authoritative-by? DEADLINE) (not (view-started v)))
       (list 'temporal 'Violated rc)]
      [(and withdrawn? (eq? holder-after-v2 'V))
       (list 'temporal 'Violated (append rc wd))]
      [(and (not evidence?) v (view-started v)
            (or (eq? (view-holder v) 'V2)
                (and (eq? (view-holder v) 'V) (not withdrawn?))))
       (list 'temporal 'Fulfilled rc)]
      [(not evidence?) (list 'temporal 'Violated acc)]
      [else (list 'temporal 'Indeterminate '())]))
  (claims
   (list 'continuity 'Fulfilled (append acc wd))
   temporal))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm 'replacement 'chor
        (hasheq 'on-withdraw 'release)
        (hasheq 'attest? #f 'view 'registry)
        chor-judge)
   (arm 'replacement 'fsm
        (hasheq 'on-withdraw 'retain)
        (hasheq 'attest? #f 'view 'registry)
        fsm-judge)
   (arm 'replacement 'comm
        (hasheq 'on-withdraw 'retain)
        (hasheq 'attest? #f 'view 'registry)
        comm-judge)
   (arm 'replacement 'hybrid
        (hasheq 'on-withdraw 'retain)
        (hasheq 'attest? #t 'view 'full)
        hybrid-judge)
   (arm 'replacement 'hybrid-noe
        (hasheq 'on-withdraw 'retain)
        (hasheq 'attest? #t 'view 'full)
        hybrid-noe-judge)))
