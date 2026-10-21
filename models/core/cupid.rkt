#lang racket/base
;; Commitment evaluation over an information base, in the style of Cupid
;; (commitments as queries over the events an agent's information records),
;; with an optional evidential layer.
;;
;; An arm builds an information base from its deliveries alone:
;;   facts     : what the observer's information says happened — an event kind,
;;               the party the information comes from, whether the event is an
;;               act (constitutive: an acceptance, an acknowledgement, a grant)
;;               or a performance (a report that something was done), its
;;               instant as asserted, attributes, and the delivery it came from;
;;   coverages : records the observer read, each from a party, complete through
;;               an instant, for a set of event kinds.
;;
;; An achievement commitment C(debtor, creditor, antecedent by t_a, consequent
;; by t_c) takes its lifecycle state from the status of its antecedent and
;; consequent:
;;   discharged  consequent held by its deadline
;;   violated    antecedent held and consequent not held by its deadline
;;               (late discharge does not cure)
;;   expired     antecedent did not hold by its deadline, consequent not held
;;   unknown     the information base does not settle the state
;;
;; Event status is one of held | late | absent | unknown. Without the evidential
;; layer the information base is read under the closed-world assumption, as
;; commitment queries over a database are: what is not recorded did not happen.
;; With it (rules E1–E3):
;;   E1  a performance fact whose source is the commitment's debtor is not
;;       evidence that the performance happened; it can still establish that
;;       the debtor admits a late performance, where the family declares the
;;       debtor's time stamps reliable (#:debtor-clock? #t, the default; a
;;       debtor whose clock may be skewed admits nothing by its stamps);
;;   E2  absence is established only by a coverage that includes the event
;;       kind, is complete through the deadline, and does not itself report
;;       the event;
;;   E3  otherwise the status is unknown.
;; Acts are constitutive: a party's own act is evidence of itself.

(require racket/list)
(provide (struct-out fact) (struct-out coverage) (struct-out commitment)
         event-status commitment-state status-cites)

(struct fact (event source kind time attrs index) #:transparent)
(struct coverage (party through events index) #:transparent)
;; antecedent / consequent: (fact → boolean) predicates, or 'true for an
;; antecedent that holds from the start (an order already placed)
(struct commitment (name debtor creditor antecedent a-deadline consequent c-deadline) #:transparent)

;; → (values status cites)
(define (event-status facts coverages pred deadline
                      #:evidential? ev #:debtor debtor #:kinds kinds #:debtor-clock? [clock #t])
  (define matching (filter pred facts))
  (define admitted-late
    (filter (λ (f) (> (fact-time f) deadline)) matching))
  (define usable
    (if ev
        (filter (λ (f) (not (and (eq? (fact-kind f) 'performance) (eq? (fact-source f) debtor)))) matching)
        matching))
  (define on-time (filter (λ (f) (<= (fact-time f) deadline)) usable))
  (define late (filter (λ (f) (> (fact-time f) deadline)) usable))
  (define (idx fs) (map fact-index fs))
  (cond
    [(pair? on-time) (values 'held (idx on-time))]
    [(pair? late) (values 'late (idx late))]
    [(and ev clock (pair? admitted-late)) (values 'late (idx admitted-late))]
    [(not ev) (values 'absent (map coverage-index coverages))]
    [else
     ;; a record that itself reports the event (from a source E1 discounts)
     ;; cannot be read as showing its absence
     (define reported (map fact-index matching))
     (define cov (filter (λ (c) (and (>= (coverage-through c) deadline)
                                     (pair? (filter (λ (k) (memq k kinds)) (coverage-events c)))
                                     (not (memv (coverage-index c) reported))))
                         coverages))
     (if (pair? cov) (values 'absent (map coverage-index cov)) (values 'unknown '()))]))

;; kinds: the event kinds the antecedent and consequent refer to (for coverage)
;; → (values state cites)
(define (commitment-state c facts coverages #:evidential? ev #:a-kinds a-kinds #:c-kinds c-kinds
                          #:debtor-clock? [clock #t])
  (define-values (as acites)
    (if (eq? (commitment-antecedent c) 'true)
        (values 'held '())
        (event-status facts coverages (commitment-antecedent c) (commitment-a-deadline c)
                      #:evidential? ev #:debtor (commitment-creditor c) #:kinds a-kinds)))
  (define-values (cs ccites)
    (event-status facts coverages (commitment-consequent c) (commitment-c-deadline c)
                  #:evidential? ev #:debtor (commitment-debtor c) #:kinds c-kinds #:debtor-clock? clock))
  (define cites (remove-duplicates (append acites ccites)))
  (values
   (cond [(eq? cs 'held) 'discharged]
         [(and (eq? as 'held) (memq cs '(late absent))) 'violated]
         [(and (memq as '(late absent)) (memq cs '(late absent))) 'expired]
         [else 'unknown])
   (filter values cites)))

(define (status-cites . lists) (sort (remove-duplicates (filter values (apply append lists))) <))

;; A dependency judgment from a commitment state. An expired commitment's
;; meaning for the dependency is family-specific and supplied by the caller.
(provide state->judgment)
(define (state->judgment st #:expired [exp 'Indeterminate])
  (case st
    [(discharged) 'Fulfilled]
    [(violated) 'Violated]
    [(expired) exp]
    [else 'Indeterminate]))

;; A claim entry for `claims`: abstentions cite nothing.
(provide dep-claim)
(define (dep-claim dep j cites) (list dep j (if (eq? j 'Indeterminate) '() cites)))
