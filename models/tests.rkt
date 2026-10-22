#lang racket/base
;; The models' own tests, over all eight families: well-formedness, totality,
;; oracle isolation (with a planted leak the check must catch), determinism and
;; common random numbers, a brute-force check of the judge, the adequacy
;; properties each family is built to exhibit, and P1–P3.
;;   raco test tests.rkt

(require rackunit racket/list racket/set racket/file redex/reduction-semantics
         "core/grammar.rkt" "core/family.rkt" "core/arm.rkt" "core/judge.rkt"
         "families.rkt" "propositions.rkt" "bench.rkt"
         (only-in "families/handoff/terms.rkt" HANDOFF)
         (only-in "families/reservation/terms.rkt" RESERVATION)
         (only-in "families/agreement/terms.rkt" AGREEMENT)
         (only-in "families/delegation/terms.rkt" DELEGATION)
         (only-in "families/deadline/terms.rkt" DEADLINE-SERVICE)
         (only-in "families/external/terms.rkt" EXTERNAL)
         (only-in "families/composition/terms.rkt" COMPOSITION)
         (only-in "families/replacement/terms.rkt" REPLACEMENT))

(define F family-by-name)
(define A arm-of)
(define (rows f a p) (for/list ([w (support f p)]) (classify-run f a p w)))
(define (false-count fname aname p)
  (define f (F fname))
  (for*/sum ([r (rows f (A fname aname) p)] [d (hash-ref r 'deps)]) (if (eq? (hash-ref d 'class) 'false) 1 0)))
(define (metric fname aname p m) (hash-ref (exact-metrics (F fname) (A fname aname) p) m))
(define (claims-of fname aname w)
  (define f (F fname)) (define a (A fname aname))
  (map (λ (c) (list (cadr c) (caddr c))) ((arm-judge a) (deliveries-of f a w))))

;; ------------------------------------------------------------------ registry

(test-case "DMBench's eight families are registered, each with the five arms of the hub"
  (check-equal? family-names '(handoff reservation agreement delegation deadline external composition replacement))
  (for ([n family-names]) (check-equal? (map arm-name (arms-of n)) ARM-NAMES)))

;; ------------------------------------------------------------------ well-formedness

(test-case "every world, every arm's deliveries and every claim are terms of the family's language"
  (for* ([fa FAMILIES] [p (profile-names (car fa))] [w (support (car fa) p)])
    (define f (car fa))
    (check-true ((family-world-term? f) w) (format "~a ~s" (family-name f) w))
    (for ([a (cdr fa)])
      (check-true ((family-ds-term? f) (deliveries-of f a w)))
      (check-true (claims-term? ((arm-judge a) (deliveries-of f a w)))))))

(test-case "every profile's probabilities sum to 1 and every support world has positive probability"
  (for* ([fa FAMILIES] [p (profile-names (car fa))])
    (define f (car fa))
    (check-equal? (for/sum ([w (support f p)]) (probability f p w)) 1 (format "~a ~a" (family-name f) p))
    (for ([w (support f p)]) (check-true (positive? (probability f p w))))))

(test-case "the canonical map is idempotent"
  (for* ([fa FAMILIES] [p (profile-names (car fa))] [w (support (car fa) p)])
    (check-equal? ((family-canonical (car fa)) w) w)))

;; ------------------------------------------------------------------ totality

(define LANGS
  (list (cons 'handoff (λ () (generate-term HANDOFF w 4)))
        (cons 'reservation (λ () (generate-term RESERVATION w 4)))
        (cons 'agreement (λ () (generate-term AGREEMENT w 4)))
        (cons 'delegation (λ () (generate-term DELEGATION w 4)))
        (cons 'deadline (λ () (generate-term DEADLINE-SERVICE w 4)))
        (cons 'external (λ () (generate-term EXTERNAL w 4)))
        (cons 'composition (λ () (generate-term COMPOSITION w 4)))
        (cons 'replacement (λ () (generate-term REPLACEMENT w 4)))))

(define (gen-world gen) (gen))

(test-case "execution, delivery and every arm are total on worlds generated from each family's grammar"
  (for ([fa FAMILIES])
    (define f (car fa))
    (define L (cdr (assq (family-name f) LANGS)))
    (for ([i 300])
      (define w ((family-canonical f) (gen-world L)))
      (for ([a (cdr fa)])
        (define ex ((family-execute f) (arm-protocol a) (arm-interface a) w))
        (for ([d (family-deps f)])
          (check-not-false (memq (hash-ref (hash-ref ex 'truth) (dependency-name d)) '(Fulfilled Violated))))
        (define ds ((family-deliveries f) (arm-protocol a) (arm-interface a) w))
        (check-true ((family-ds-term? f) ds) (format "~a/~a on ~s" (family-name f) (arm-name a) w))
        (check-true (claims-term? ((arm-judge a) ds)) (format "~a/~a on ~s" (family-name f) (arm-name a) w))))))

;; ------------------------------------------------------------------ oracle isolation

(define here (let-values ([(dir _n _d) (split-path (path->complete-path (syntax-source #'here)))]) dir))

;; the transitive closure of a module's relative-path imports
(define (import-closure file)
  (define seen (mutable-set))
  (let loop ([p (simplify-path (path->complete-path file))])
    (unless (set-member? seen p)
      (set-add! seen p)
      (define-values (dir _n _d) (split-path p))
      (define stx (with-input-from-file p
                    (λ () (parameterize ([read-accept-reader #t] [read-accept-lang #t]) (read-syntax p)))))
      (define reqs
        (let walk ([d (syntax->datum stx)])
          (cond [(and (pair? d) (eq? (car d) 'require))
                 (let strings ([x (cdr d)])
                   (cond [(string? x) (list x)] [(pair? x) (append (strings (car x)) (strings (cdr x)))] [else '()]))]
                [(pair? d) (append (walk (car d)) (walk (cdr d)))]
                [else '()])))
      (for ([r reqs]) (loop (simplify-path (build-path dir r))))))
  seen)

(define (isolation-violations arms-file)
  (define-values (dir _n _d) (split-path (simplify-path (path->complete-path arms-file))))
  (define allowed
    (set (simplify-path (path->complete-path arms-file))
         (simplify-path (build-path dir "terms.rkt"))
         (simplify-path (build-path here "core/arm.rkt"))
         (simplify-path (build-path here "core/observe.rkt"))
         (simplify-path (build-path here "core/grammar.rkt"))))
  (for/list ([p (import-closure arms-file)] #:unless (set-member? allowed p)) p))

(test-case "no arm module reaches anything but the core arm/observe/grammar modules and its own terms"
  (for ([n family-names])
    (check-equal? (isolation-violations (build-path here "families" (symbol->string n) "arms.rkt")) '()
                  (format "~a" n))))

(test-case "the isolation check catches a planted leak"
  (define dir (make-temporary-file "dmat-leak-~a" 'directory (build-path here "families")))
  (dynamic-wind
   void
   (λ ()
     (with-output-to-file (build-path dir "terms.rkt")
       (λ () (displayln "#lang racket/base\n(require \"../handoff/terms.rkt\")")))
     (with-output-to-file (build-path dir "arms.rkt")
       (λ () (displayln "#lang racket/base\n(require \"../../core/arm.rkt\" (only-in \"../handoff/world.rkt\" handoff) \"terms.rkt\")")))
     (define v (isolation-violations (build-path dir "arms.rkt")))
     (check-true (for/or ([p v]) (regexp-match? #rx"handoff/world\\.rkt$" (path->string p))))
     (check-true (for/or ([p v]) (regexp-match? #rx"core/family\\.rkt$" (path->string p))))
     (check-true (for/or ([p v]) (regexp-match? #rx"handoff/terms\\.rkt$" (path->string p)))))
   (λ () (delete-directory/files dir))))

;; ------------------------------------------------------------------ determinism and common random numbers

(test-case "a seed reproduces its world, seeds vary the world, draws stay in the support"
  (for* ([fa FAMILIES] [p (profile-names (car fa))])
    (define f (car fa))
    (check-equal? (draw f 7 p) (draw f 7 p))
    (for ([s 40]) (check-not-false (member (draw f s p) (support f p)))))
  (check-true (>= (length (remove-duplicates (for/list ([s 60]) (draw (F 'handoff) s 'adversarial)))) 15)))

(test-case "every arm of a family runs on the same world for a given (profile, seed)"
  (define rs (sampled-rows 4))
  (for* ([fa FAMILIES] [p (profile-names (car fa))] [s (in-range 1 5)])
    (define ws (for/list ([r rs] #:when (and (eq? (hash-ref r 'family) (family-name (car fa)))
                                             (eq? (hash-ref r 'profile) p) (equal? (hash-ref r 'seed) s)))
                 (hash-ref r 'world)))
    (check-equal? (length ws) 5)
    (check-equal? (length (remove-duplicates ws)) 1)))

(define (output-of thunk)
  (define o (open-output-string)) (parameterize ([current-output-port o]) (thunk)) (get-output-string o))
(test-case "the sampled benchmark prints the same bytes twice"
  (define (run) (output-of (λ () (write (sampled-summary (sampled-rows 6))))))
  (check-equal? (run) (run)))

;; ------------------------------------------------------------------ the judge

(test-case "judge classifications agree with a brute-force recomputation"
  (for* ([fa FAMILIES] [p (profile-names (car fa))] [a (cdr fa)])
    (define f (car fa))
    (define sup (support f p))
    (for ([r (rows f a p)])
      (define w (hash-ref r 'world))
      (define ds (hash-ref r 'deliveries))
      (define truth (hash-ref ((family-execute f) (arm-protocol a) (arm-interface a) w) 'truth))
      (for ([d (hash-ref r 'deps)])
        (define dep (hash-ref d 'dep))
        (define same (filter (λ (w2) (equal? ((family-deliveries f) (arm-protocol a) (arm-interface a) w2) ds)) sup))
        (define det (= 1 (length (remove-duplicates
                                  (map (λ (w2) (hash-ref (hash-ref ((family-execute f) (arm-protocol a) (arm-interface a) w2) 'truth) dep))
                                       same)))))
        (check-equal? (hash-ref d 'determined) det)
        (check-equal? (hash-ref d 'truth) (hash-ref truth dep))
        (case (hash-ref d 'class)
          [(false) (check-not-equal? (hash-ref d 'claim) (hash-ref truth dep))]
          [(supported) (check-equal? (hash-ref d 'claim) (hash-ref truth dep)) (check-true det)
                       (check-true (pair? (hash-ref d 'cites)))
                       (for ([i (hash-ref d 'cites)]) (check-true (< i (length ds))))]
          [(lucky) (check-equal? (hash-ref d 'claim) (hash-ref truth dep))]
          [(abstained-ok) (check-false det)]
          [(abstained-miss) (check-true det)])))))

;; ------------------------------------------------------------------ adequacy properties, all families

(test-case "HYBRID makes no false definitive claim in any family under any profile"
  (for* ([n family-names] [p (profile-names (F n))])
    (check-equal? (false-count n 'hybrid p) 0 (format "~a ~a" n p))))

(test-case "Ablation: without its evidentiary component the hybrid is unsafe in every family"
  (for ([n family-names])
    (check-true (for/or ([p (profile-names (F n))]) (> (false-count n 'hybrid-noe p) 0)) (format "~a" n))))

(test-case "Every single-paradigm arm is unsafe somewhere in DMBench"
  (for ([a '(chor fsm comm)])
    (check-true (for*/or ([n family-names] [p (profile-names (F n))]) (> (false-count n a p) 0)) (format "~a" a))))

;; ------------------------------------------------------------------ family-specific properties

(test-case "handoff — A2: FSM safe under reliable delivery, unsafe once stale reads or record lag are admitted"
  (check-equal? (false-count 'handoff 'fsm 'reliable) 0)
  (check-true (> (false-count 'handoff 'fsm 'stale-read) 0))
  (check-true (> (false-count 'handoff 'fsm 'record-lag) 0)))

(test-case "handoff — false completion: V's own report is not evidence of care initiation"
  (for ([n '(chor fsm comm hybrid-noe)]) (check-true (> (metric 'handoff n 'evidence-contradiction 'FCR) 0) (format "~a" n)))
  (check-equal? (metric 'handoff 'hybrid 'evidence-contradiction 'FCR) 0))

(test-case "reservation — operational adequacy: truth depends on the arm's regrant protocol"
  (define f (F 'reservation))
  (define (differs? aname dep)
    (for/or ([w (support f 'adversarial)])
      (not (equal? (truth-of f (A 'reservation aname) w dep) (truth-of f (A 'reservation 'hybrid) w dep)))))
  (check-true (differs? 'chor 'temporal))   ; regrant only on release: H2 waits past D2 when H1 never releases
  (check-true (differs? 'fsm 'sharing))     ; unfenced expiry regrant: H1 still uses the resource after H2's grant
  (check-false (differs? 'comm 'sharing))
  (check-true (> (metric 'reservation 'fsm 'reliable 'SFR) 0))       ; unfenced expiry regrant, judged by state
  (check-equal? (metric 'reservation 'comm 'adversarial 'SFR) 0))

(test-case "agreement — CHOR's binding without a fit check is unsafe even under reliable delivery"
  (check-true (> (false-count 'agreement 'chor 'reliable) 0))
  (check-equal? (false-count 'agreement 'fsm 'concurrent-revoke) 0)
  (check-true (> (false-count 'agreement 'fsm 'stale-read) 0)))

(test-case "delegation — releasing the delegator leaves responsibility unassigned (AGR), retaining does not"
  (check-true (> (metric 'delegation 'chor 'reliable 'AGR) 0))
  (for ([n '(fsm comm hybrid)]) (check-equal? (metric 'delegation n 'adversarial 'AGR) 0)))

(test-case "deadline — arrival-time judgment fails under transit delay; the provider's clock fails under skew"
  (check-true (> (false-count 'deadline 'chor 'transit) 0))
  (check-true (> (false-count 'deadline 'comm 'transit) 0))
  (check-equal? (false-count 'deadline 'fsm 'transit) 0)
  (check-true (> (false-count 'deadline 'fsm 'clock-skew) 0))
  (check-equal? (claims-of 'deadline 'fsm '(world late short behind delivered fresh))
                '((temporal Fulfilled) (completion Fulfilled))))              ; V's clock 3 behind: 9 ≤ 10

(test-case "external — a session or commitment over V alone cannot speak for X's part"
  (check-true (> (false-count 'external 'chor 'external-failure) 0))
  (check-true (> (false-count 'external 'comm 'reliable) 0))                  ; one conjunctive commitment for both parts
  (for* ([p (profile-names (F 'external))] [r (rows (F 'external) (A 'external 'fsm) p)])
    (check-equal? (hash-ref (cadr (hash-ref r 'deps)) 'claim) 'Indeterminate)))

(test-case "composition — under the coarse model H's temporal dependency on S is never determined"
  (for* ([n '(chor fsm comm)] [p (profile-names (F 'composition))] [r (rows (F 'composition) (A 'composition n) p)])
    (check-false (hash-ref (car (hash-ref r 'deps)) 'determined))))

(test-case "replacement — a ghost START from the withdrawn party passes for the debtor's start unless an attestation is required"
  ;; when V2 declines, V is the debtor again; V's stale queued START is then a START from the debtor
  (check-true (> (false-count 'replacement 'comm 'ghost) 0))
  (check-true (> (false-count 'replacement 'hybrid-noe 'ghost) 0))
  (check-equal? (false-count 'replacement 'hybrid 'ghost) 0)
  (check-equal? (false-count 'replacement 'chor 'ghost) 0)          ; outside the session's current branch
  (check-true (> (metric 'replacement 'chor 'reliable 'AGR) 0)))

;; ------------------------------------------------------------------ propositions

(test-case "P1: every witness is a pair of worlds with identical deliveries and different truth"
  (for* ([fa FAMILIES] [p (profile-names (car fa))] [a (cdr fa)])
    (define f (car fa))
    (for ([x (p1-witnesses f a p)])
      (define-values (dep ds wf wv) (apply values x))
      (check-equal? (deliveries-of f a wf) ds)
      (check-equal? (deliveries-of f a wv) ds)
      (check-equal? (truth-of f a wf dep) 'Fulfilled)
      (check-equal? (truth-of f a wv dep) 'Violated)))
  (check-true (pair? (p1-witnesses (F 'handoff) (A 'handoff 'chor) 'stale-read)))
  (for ([n family-names]) (check-equal? (p1-witnesses (F n) (A n 'hybrid) 'reliable) '() (format "~a" n))))

(test-case "P2: H's dependency on S is decidable only when S's stage is distinguishable, and S's self-report does not make it so"
  (define (mass p m dep) (cdr (assq dep (caddr (assq m (p2-report p))))))
  (check-equal? (mass 'reliable 'coarse 'temporal) 0)
  (check-equal? (mass 'reliable 'staged 'temporal) 1)
  (check-true (< (mass 'self-report 'staged 'temporal) 1))
  (check-equal? (mass 'self-report 'staged+attest 'temporal) 1)
  (for ([p (profile-names (F 'composition))])
    (check-true (<= (mass p 'coarse 'temporal) (mass p 'staged 'temporal) (mass p 'staged+attest 'temporal)))))

(test-case "P3: the ablation loses safety in every family; where conduct and observation are unchanged it loses no observation"
  (for ([n family-names])
    (define h (A n 'hybrid)) (define noe (A n 'hybrid-noe))
    (define reps (for/list ([p (profile-names (F n))]) (p3-report (F n) h noe p)))
    (check-true (ormap (λ (r) (pair? (hash-ref r 'safety-lost))) reps) (format "~a" n))
    (when (and (equal? (arm-protocol h) (arm-protocol noe)) (equal? (arm-interface h) (arm-interface noe)))
      (for ([r reps]) (check-equal? (hash-ref r 'observation-lost) '() (format "~a" n))))))

;; ------------------------------------------------------------------ commitment arms (phase 3)

(define (cupid-rows n an p) (let ([f (F n)]) (rows f (A n an) p)))
(define (cupid-false n an p)
  (for*/sum ([r (cupid-rows n an p)] [d (hash-ref r 'deps)]) (if (eq? (hash-ref d 'class) 'false) 1 0)))

(test-case "commitment arms: cupid and cupid-e in every family, with the hybrid's protocol and interface"
  (for ([n family-names])
    (check-equal? (map arm-name (cupid-arms-of n)) CUPID-NAMES)
    (for ([a (cupid-arms-of n)])
      (check-equal? (arm-protocol a) (arm-protocol (A n 'hybrid)) (format "~a ~a" n (arm-name a)))
      (check-equal? (arm-interface a) (arm-interface (A n 'hybrid)) (format "~a ~a" n (arm-name a))))))

(test-case "commitment arms: claims are terms on every support world and on generated worlds"
  (for ([fa FAMILIES])
    (define f (car fa)) (define n (family-name f))
    (define L (cdr (assq n LANGS)))
    (define worlds (append (for*/list ([p (profile-names f)] [w (support f p)]) w)
                           (for/list ([i 300]) ((family-canonical f) (gen-world L)))))
    (for* ([w worlds] [a (cupid-arms-of n)])
      (define ds ((family-deliveries f) (arm-protocol a) (arm-interface a) w))
      (check-true (claims-term? ((arm-judge a) ds)) (format "~a/~a on ~s" n (arm-name a) w)))))

(test-case "commitment arms import only the core arm/observe/grammar/cupid modules and their family's terms"
  (for ([n family-names])
    (define f (build-path here "families" (symbol->string n) "cupid.rkt"))
    (define allowed
      (set (simplify-path f)
           (simplify-path (build-path here "families" (symbol->string n) "terms.rkt"))
           (simplify-path (build-path here "core/arm.rkt"))
           (simplify-path (build-path here "core/observe.rkt"))
           (simplify-path (build-path here "core/grammar.rkt"))
           (simplify-path (build-path here "core/cupid.rkt"))))
    (check-equal? (for/list ([p (import-closure f)] #:unless (set-member? allowed p)) p) '() (format "~a" n))))

(test-case "commitment arms: judge classifications agree with a brute-force recomputation"
  (for* ([n family-names] [p (profile-names (F n))] [an CUPID-NAMES])
    (define f (F n)) (define a (A n an)) (define sup (support f p))
    (for ([r (rows f a p)])
      (define ds (hash-ref r 'deliveries))
      (define truth (hash-ref ((family-execute f) (arm-protocol a) (arm-interface a) (hash-ref r 'world)) 'truth))
      (for ([d (hash-ref r 'deps)])
        (define dep (hash-ref d 'dep))
        (define same (filter (λ (w2) (equal? ((family-deliveries f) (arm-protocol a) (arm-interface a) w2) ds)) sup))
        (define det (= 1 (length (remove-duplicates
                                  (map (λ (w2) (hash-ref (hash-ref ((family-execute f) (arm-protocol a) (arm-interface a) w2) 'truth) dep))
                                       same)))))
        (check-equal? (hash-ref d 'determined) det)
        (check-equal? (hash-ref d 'truth) (hash-ref truth dep))
        (when (eq? (hash-ref d 'class) 'supported)
          (check-true (pair? (hash-ref d 'cites)))
          (for ([i (hash-ref d 'cites)]) (check-true (< i (length ds)))))))))

(test-case "cupid-e makes no false claim in any family under any profile; cupid is unsafe in every family"
  (for ([n family-names])
    (for ([p (profile-names (F n))]) (check-equal? (cupid-false n 'cupid-e p) 0 (format "~a ~a" n p)))
    (check-true (for/or ([p (profile-names (F n))]) (> (cupid-false n 'cupid p) 0)) (format "~a" n))))

(test-case "the evidential layer loses no observation: cupid and cupid-e see the same deliveries, so P3 attributes the loss to judgment"
  (for ([n family-names])
    (define c (A n 'cupid)) (define e (A n 'cupid-e))
    (define reps (for/list ([p (profile-names (F n))]) (p3-report (F n) e c p)))
    (check-true (ormap (λ (r) (pair? (hash-ref r 'safety-lost))) reps) (format "~a" n))
    (for ([r reps]) (check-equal? (hash-ref r 'observation-lost) '() (format "~a" n)))))

;; cupid-e against the hub's hybrid (commitments.txt): the only runs where one
;; decides and the other abstains are the two documented causes
(test-case "cupid-e and the hybrid differ only on the documented runs"
  (define found
    (for*/list ([n family-names] [p (profile-names (F n))] [w (support (F n) p)]
                [dh (hash-ref (classify-run (F n) (A n 'hybrid) p w) 'deps)]
                [de (in-value (findf (λ (d) (eq? (hash-ref d 'dep) (hash-ref dh 'dep)))
                                     (hash-ref (classify-run (F n) (A n 'cupid-e) p w) 'deps)))]
                #:unless (eq? (hash-ref dh 'class) (hash-ref de 'class)))
      (list n (hash-ref dh 'dep) (hash-ref dh 'class) (hash-ref de 'class) w)))
  (check-equal? (sort (remove-duplicates (map (λ (x) (take x 4)) found)) string<? #:key (λ (x) (format "~a" x)))
                '((deadline completion supported abstained-miss)
                  (replacement temporal abstained-miss supported))))

;; ------------------------------------------------------------------ independent authorship

(require (only-in "diff.rkt" independent-arms independent-cupid-arms disagreements))

(test-case "independent arms import only the core arm/observe/grammar modules and their family's terms"
  (for ([n family-names])
    (define f (build-path here "independent" (format "~a-arms.rkt" n)))
    (define allowed
      (set (simplify-path f)
           (simplify-path (build-path here "families" (symbol->string n) "terms.rkt"))
           (simplify-path (build-path here "core/arm.rkt"))
           (simplify-path (build-path here "core/observe.rkt"))
           (simplify-path (build-path here "core/grammar.rkt"))))
    (check-equal? (for/list ([p (import-closure f)] #:unless (set-member? allowed p)) p) '() (format "~a" n))))

(test-case "independent arms: same protocol and interface as the spec; the independent HYBRID is safe everywhere and its ablation is not"
  (for ([n family-names])
    (define inds (independent-arms n))
    (check-equal? (map arm-name inds) ARM-NAMES)
    (for ([a inds])
      (check-equal? (arm-protocol a) (arm-protocol (A n (arm-name a))))
      (check-equal? (arm-interface a) (arm-interface (A n (arm-name a)))))
    (define (ind-false aname p)
      (define f (F n)) (define a (findf (λ (x) (eq? (arm-name x) aname)) inds))
      (for*/sum ([r (rows f a p)] [d (hash-ref r 'deps)]) (if (eq? (hash-ref d 'class) 'false) 1 0)))
    (for ([p (profile-names (F n))]) (check-equal? (ind-false 'hybrid p) 0 (format "~a ~a" n p)))
    (check-true (for/or ([p (profile-names (F n))]) (> (ind-false 'hybrid-noe p) 0)) (format "~a" n))))

;; The adjudicated residue (specs/adjudication.md): every remaining disagreement
;; is one of the documented admissible alternative readings.
(define RESIDUE
  '((agreement chor 9) (delegation chor 2) (delegation fsm 6) (deadline chor 1)
    (external chor 3) (external comm 3) (external hybrid-noe 1) (composition fsm 3) (composition comm 5)))

(test-case "the remaining disagreements are exactly the adjudicated residue"
  (for* ([n family-names] [an ARM-NAMES])
    (define ind (findf (λ (x) (eq? (arm-name x) an)) (independent-arms n)))
    (define expected (cond [(findf (λ (r) (and (eq? (car r) n) (eq? (cadr r) an))) RESIDUE) => caddr] [else 0]))
    (check-equal? (length (disagreements n (A n an) ind)) expected (format "~a ~a" n an))))

;; Commitment arms (specs/commitments/adjudication.md): the independent cupid-e
;; agrees with the reference everywhere; the only residue is the replacement
;; ghost rule amended in the reference after the check.
(test-case "independent commitment arms: same protocol and interface; agreement up to the adjudicated residue"
  (for ([n family-names])
    (define f (build-path here "independent" (format "~a-cupid.rkt" n)))
    (define allowed
      (set (simplify-path f)
           (simplify-path (build-path here "families" (symbol->string n) "terms.rkt"))
           (simplify-path (build-path here "core/arm.rkt")) (simplify-path (build-path here "core/observe.rkt"))
           (simplify-path (build-path here "core/grammar.rkt")) (simplify-path (build-path here "core/cupid.rkt"))))
    (check-equal? (for/list ([p (import-closure f)] #:unless (set-member? allowed p)) p) '() (format "~a" n))
    (define inds (independent-cupid-arms n))
    (check-equal? (map arm-name inds) CUPID-NAMES)
    (for ([a inds])
      (check-equal? (arm-protocol a) (arm-protocol (A n (arm-name a))))
      (check-equal? (arm-interface a) (arm-interface (A n (arm-name a))))
      (define expected (if (and (eq? n 'replacement) (eq? (arm-name a) 'cupid)) 9 0))
      (check-equal? (length (disagreements n (A n (arm-name a)) a)) expected (format "~a ~a" n (arm-name a))))))

;; ------------------------------------------------------------------ enactment (specs/enactment.md)

(require (only-in "enact.rkt" ENACTMENTS check-all classify holm binom-two-sided party-prompt observer-prompt parse-claims faithful-events)
         (only-in "core/enact.rkt" enactment-family enactment-roles enactment-assemble enactment-truth
                  role-spec-name role-spec-messages msg-spec-name msg-spec-kind msg-spec-fields
                  parse-events classify-party ev->jsexpr make-ev))

(test-case "enactment: faithful events reproduce the coded deliveries and truth in every world of every family"
  (check-equal? (check-all) 0))

(test-case "enactment: scoring a faithful run classifies cupid-e exactly as the judge does"
  (for* ([en ENACTMENTS] [n (in-value (enactment-family en))] [p '(reliable adversarial)] [w (support (F n) p)])
    (define-values (ds notes) ((enactment-assemble en) w (faithful-events en w)))
    (define rows (classify n w ds ((enactment-truth en) w ds) ((arm-judge (A n 'cupid-e)) ds) p))
    (define ref (hash-ref (classify-run (F n) (A n 'cupid-e) p w) 'deps))
    (check-equal? (map (λ (d) (hash-ref d 'class)) rows) (map (λ (d) (hash-ref d 'class)) ref) (format "~a ~a ~s" n p w))))

(test-case "enactment: party events are parsed, validated and classified against the faithful events"
  (for* ([en ENACTMENTS] [n (in-value (enactment-family en))] [w (support (F n) 'adversarial)] [rs (enactment-roles en)])
    (define faithful (hash-ref (faithful-events en w) (role-spec-name rs)))
    (define js (hasheq 'events (map ev->jsexpr faithful)))
    (define-values (evs bad) (parse-events rs js 100))
    (check-equal? evs faithful)
    (check-equal? (classify-party rs faithful evs bad) (hasheq 'fabricated-report 0 'fabricated-act 0 'omitted-message 0 'parameter-error 0 'malformed 0))
    (when (pair? faithful)
      (check-equal? (hash-ref (classify-party rs faithful (cdr faithful) 0) 'omitted-message) 1)))
  (define rs (car (enactment-roles (findf (λ (e) (eq? (enactment-family e) 'replacement)) ENACTMENTS))))
  (define-values (evs bad) (parse-events rs (hasheq 'events (list (hasheq 'message "Start" 'at 9) (hasheq 'message "Fly" 'at 1) (hasheq 'message "Start" 'at -1))) 13))
  (check-equal? bad 2)
  (check-equal? (hash-ref (classify-party rs '() evs 0) 'fabricated-report) 1)
  (define A-rs (caddr (enactment-roles (findf (λ (e) (eq? (enactment-family e) 'replacement)) ENACTMENTS))))
  (check-equal? (hash-ref (classify-party A-rs (list (make-ev A-rs 'Attest 6 'performer 'V)) (list (make-ev A-rs 'Attest 6 'performer 'V2)) 0) 'parameter-error) 1)
  (define-values (none bad2) (parse-events rs #f 13))
  (check-equal? bad2 1))

(test-case "enactment: commitment arms and the hub hybrid are total on deliveries with any one message removed"
  (for* ([en ENACTMENTS] [n (in-value (enactment-family en))] [p '(reliable adversarial)] [w (support (F n) p)])
    (define ds (deliveries-of (F n) (A n 'hybrid) w))
    (for ([i (length ds)])
      (define ds* (append (take ds i) (drop ds (add1 i))))
      (for ([an '(cupid cupid-e)])
        (check-true (claims-term? ((arm-judge (A n an)) ds*)) (format "~a ~a ~s" n an ds*))))))

(test-case "enactment: prompts are built for every role and condition; observer output parsing is defensive"
  (for ([en ENACTMENTS])
    (define n (enactment-family en))
    (define w (car (support (F n) 'adversarial)))
    (for ([rs (enactment-roles en)])
      (define-values (sys user) (party-prompt en w rs))
      (check-true (and (string? sys) (string? user) (> (string-length user) 200))))
    (define ds (deliveries-of (F n) (A n 'hybrid) w))
    (for ([c '(role commitments evidential)])
      (define-values (sys user) (observer-prompt en ds c))
      (check-true (string? user)))
    (define-values (cls bad) (parse-claims n "no json here"))
    (check-true bad)
    (check-true (andmap (λ (c) (eq? (caddr c) 'Indeterminate)) cls))))

(test-case "enactment report statistics: exact sign test and Holm adjustment"
  (check-= (binom-two-sided 8 1) 0.0390625 1e-12)
  (check-= (binom-two-sided 0 0) 1 0)
  (check-equal? (holm (list 0.01 0.04 0.03)) (list 0.03 0.06 0.06)))

;; ------------------------------------------------------------------ the composite family (phase 3, step 3.7)

(require (only-in "families.rkt" COMPOSITE composite-arms composite-arm PURCHASE-ARM-NAMES)
         (only-in "families/purchase/terms.rkt" PURCHASE CALL-LIMIT)
         (only-in "families/purchase/world.rkt" run-transcript)
         (only-in "families/purchase/external.rkt" json->call call->json reply->json json->claims)
         (only-in "families/purchase/external-cache.rkt" arm-cache EXTERNAL-ARMS))

(define PF (car (car COMPOSITE)))
(define (purchase-ref-arms) (filter (λ (a) (not (eq? (hash-ref (arm-protocol a) 'mechanism) 'external))) (composite-arms)))
(define (stored? name) (positive? (hash-count (hash-ref (arm-cache name) 'runs))))
(define (purchase-arms-present)
  (filter (λ (a) (or (not (eq? (hash-ref (arm-protocol a) 'mechanism) 'external)) (stored? (arm-name a)))) (composite-arms)))

(test-case "purchase: the family's arms are registered apart from the eight families"
  (check-equal? (map arm-name (composite-arms)) PURCHASE-ARM-NAMES)
  (check-false (memq 'purchase family-names)))

(test-case "purchase: every arm present ends within the call limit in every world, with well-formed deliveries and claims"
  (for* ([p (profile-names PF)] [w (support PF p)] [a (purchase-arms-present)])
    (define ds (deliveries-of PF a w))
    (check-true (<= (length ds) CALL-LIMIT))
    (check-true ((family-ds-term? PF) ds) (format "~a ~s" (arm-name a) w))
    (check-true (claims-term? ((arm-judge a) ds)) (format "~a ~s" (arm-name a) w))))

(test-case "purchase: the reference mechanisms see no world and the judges see no providers"
  (define fam (build-path here "families" "purchase"))
  (define (closure f) (for/list ([p (import-closure (build-path fam f))]) p))
  (define (allowed . fs) (list->set (map (λ (f) (simplify-path f)) fs)))
  (define core (list (build-path here "core/arm.rkt") (build-path here "core/observe.rkt")
                     (build-path here "core/grammar.rkt") (build-path here "core/cupid.rkt")))
  (define base (append core (list (build-path fam "terms.rkt") (build-path fam "external-cache.rkt"))))
  (for ([f '("mechanisms.rkt" "arms.rkt" "cupid.rkt" "external-cache.rkt")])
    (define ok (apply allowed (build-path fam f) base))
    (check-equal? (filter (λ (p) (not (set-member? ok p))) (closure f)) '() f)))

(test-case "purchase: judge classifications agree with a brute-force recomputation"
  (for* ([p '(stockout unknown-outcome stale-release carrier)] [a (purchase-arms-present)])
    (define sup (support PF p))
    (for ([w sup])
      (define r (classify-run PF a p w))
      (define ds (hash-ref r 'deliveries))
      (for ([d (hash-ref r 'deps)])
        (define dep (hash-ref d 'dep))
        (define same (filter (λ (w2) (equal? (deliveries-of PF a w2) ds)) sup))
        (define det (= 1 (length (remove-duplicates (map (λ (w2) (truth-of PF a w2 dep)) same)))))
        (check-equal? (hash-ref d 'determined) det)
        (check-equal? (hash-ref d 'truth) (truth-of PF a w dep))))))

(test-case "purchase: hybrid and cupid-e make no false claim under any profile; their ablations are unsafe"
  (define (false-in a p) (for*/sum ([w (support PF p)] [d (hash-ref (classify-run PF a p w) 'deps)]) (if (eq? (hash-ref d 'class) 'false) 1 0)))
  (for ([p (profile-names PF)])
    (check-equal? (false-in (composite-arm 'hybrid) p) 0 (format "hybrid ~a" p))
    (check-equal? (false-in (composite-arm 'cupid-e) p) 0 (format "cupid-e ~a" p)))
  (for ([n '(hybrid-noe cupid)])
    (check-true (for/or ([p (profile-names PF)]) (> (false-in (composite-arm n) p) 0)) (format "~a" n))))

(test-case "purchase: a stale record read as current leaves two holds on the principal's funds (the ablation), not the hybrid"
  (define w '(world lost within replied timeout stale replied on-time honest recorded))
  (check-equal? (truth-of PF (composite-arm 'hybrid-noe) w 'funds) 'Violated)
  (check-equal? (truth-of PF (composite-arm 'hybrid) w 'funds) 'Fulfilled))

(test-case "purchase: the external-arm protocol's JSON forms"
  (check-equal? (json->call (hasheq 'op "authorize" 'args (hasheq 'seller "B" 'amount 170 'key "k"))) '(authorize B 170 "k"))
  (check-equal? (json->call (hasheq 'op "authorize" 'args (hasheq 'seller "C" 'amount 170 'key "k"))) '(invalid))
  (check-equal? (json->call (hasheq 'op "authorize" 'args (hasheq 'seller "A" 'amount 1.5 'key "k"))) '(invalid))
  (check-equal? (json->call (hasheq 'op "fly" 'args (hasheq))) '(invalid))
  (for ([c '((reserve A) (alternatives) (void B "v") (payment-record) (order-state A) (reconcile))])
    (check-equal? (json->call (call->json c)) c))
  (check-equal? (hash-ref (reply->json 3 '(failed STATE-UNCERTAIN no-reply)) 'failure) "STATE_UNCERTAIN")
  (check-equal? (hash-ref (reply->json 3 '(ok IN-TRANSIT)) 'value) "IN_TRANSIT")
  (check-equal? (json->claims (list (hasheq 'dependency "funds" 'judgment "Fulfilled" 'cites '(2))) 3) #f)
  (check-equal? (json->claims (for/list ([d '("funds" "fit" "flow" "temporal")]) (hasheq 'dependency d 'judgment "Violated" 'cites '(3))) 3)
                (for/list ([d '(funds fit flow temporal)]) (list 'claim d 'Violated '(2))))
  (check-false (json->claims (for/list ([d '("funds" "fit" "flow" "temporal")]) (hasheq 'dependency d 'judgment "Violated" 'cites '(4))) 3)))

(test-case "purchase: every stored external run replays against the world exactly"
  (for* ([name EXTERNAL-ARMS] #:when (stored? name) [(ws run) (hash-ref (arm-cache name) 'runs)])
    (define w (read (open-input-string ws)))
    (define-values (tr truth) (run-transcript (hasheq 'mechanism 'external 'arm name) (hasheq 'watermark #t) w))
    (check-equal? (map car tr) (hash-ref run 'calls))
    (check-equal? (map cadr tr) (hash-ref run 'replies))))
