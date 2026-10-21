#lang racket/base
;; Enactment pipeline (specs/enactment.md), the Racket side. The model calls
;; are made by harness/run.py; Racket draws worlds, briefs agents, assembles
;; deliveries, writes the observer prompts and scores. Truth never leaves
;; Racket.
;;
;;   racket enact.rkt plan FAMILIES PROFILES SEEDS > plan.jsonl
;;       FAMILIES: comma-separated or `all`; PROFILES: comma-separated, `all`, or
;;       `reliable,adversarial`; SEEDS: number of seeds per (family, profile)
;;   racket enact.rkt assemble parties.jsonl > observe.jsonl
;;   racket enact.rkt score observe.jsonl claims.jsonl results.jsonl > enactment.txt
;;   racket enact.rkt check            every world: faithful events reproduce the coded run

(require racket/list racket/string racket/port racket/math racket/format json racket/runtime-path
         "core/family.rkt" "core/arm.rkt" "core/judge.rkt" "core/enact.rkt" "families.rkt"
         (only-in "families/handoff/enact.rkt" handoff-enactment)
         (only-in "families/reservation/enact.rkt" reservation-enactment)
         (only-in "families/agreement/enact.rkt" agreement-enactment)
         (only-in "families/delegation/enact.rkt" delegation-enactment)
         (only-in "families/deadline/enact.rkt" deadline-enactment)
         (only-in "families/external/enact.rkt" external-enactment)
         (only-in "families/composition/enact.rkt" composition-enactment)
         (only-in "families/replacement/enact.rkt" replacement-enactment))
(provide ENACTMENTS enactment-of faithful-events assemble-run check-all classify holm binom-two-sided
         party-prompt observer-prompt parse-claims extract-json CONDITIONS)

(define-runtime-path BSPL "specs/bspl")

(define ENACTMENTS
  (list handoff-enactment reservation-enactment agreement-enactment delegation-enactment
        deadline-enactment external-enactment composition-enactment replacement-enactment))
(define (enactment-of n) (or (findf (λ (e) (eq? (enactment-family e) n)) ENACTMENTS) (error 'enact "no family ~a" n)))
(define CONDITIONS '(role commitments evidential))

(define (hybrid n) (arm-of n 'hybrid))
(define (coded-deliveries n w) (let ([a (hybrid n)]) ((family-deliveries (family-by-name n)) (arm-protocol a) (arm-interface a) w)))

(define (faithful-events en w)
  (for/hasheq ([r (enactment-roles en)]) (values (role-spec-name r) ((enactment-faithful en) w (role-spec-name r)))))

;; ------------------------------------------------------------------ prompts

(define (bspl-text n) (call-with-input-file (build-path BSPL (format "~a.bspl" n)) port->string))

(define (msg-line m)
  (format "- ~a (~a): ~a~a" (msg-spec-name m) (if (eq? (msg-spec-kind m) 'act) "an act" "a report")
          (msg-spec-doc m)
          (if (null? (msg-spec-fields m)) ""
              (format "; fields: ~a"
                      (string-join (for/list ([fd (msg-spec-fields m)])
                                     (if (eq? (cdr fd) 'instant) (format "~a (an instant)" (car fd))
                                         (format "~a (one of ~a)" (car fd) (string-join (map symbol->string (cdr fd)) ", "))))
                                   "; ")))))

(define (party-prompt en w rs)
  (define n (enactment-family en))
  (values
   (format "You are ~a in a multi-party protocol. You act only through the protocol's messages. Instants are integers on a shared timeline. Reply with a single JSON object and nothing else."
           (role-spec-title rs))
   (string-append
    (format "The protocol, in BSPL (Blindingly Simple Protocol Language):\n\n~a\n" (bspl-text n))
    (format "\nYour role: ~a.\n\nWhat happened, as you know it:\n~a\n" (role-spec-title rs)
            (string-join (map (λ (s) (string-append "- " s)) ((enactment-brief en) w (role-spec-name rs))) "\n"))
    (format "\nThe messages your role can send:\n~a\n" (string-join (map msg-line (role-spec-messages rs)) "\n"))
    "\nSend the protocol messages your role sends, given what happened. Reply with JSON of the form "
    "{\"events\": [{\"message\": NAME, \"at\": INSTANT, ...fields}]}, one entry per message you send, "
    "where `at` is the instant described for that message. If you send no message, reply {\"events\": []}.")))

(define (observer-prompt en ds condition)
  (define tx (enactment-texts en))
  (values
   "You are a participant in a multi-party protocol, judging whether the dependencies you rely on held. Reply with a single JSON object and nothing else."
   (string-append
    (hash-ref tx 'scenario) "\n\nDependencies to judge:\n"
    (string-join (for/list ([d (hash-ref tx 'deps)]) (format "- ~a: ~a" (car d) (cdr d))) "\n")
    (if (memq condition '(commitments evidential))
        (string-append "\n\nCommitments:\n" (hash-ref tx 'commitments)) "")
    (if (eq? condition 'evidential)
        (string-append "\n\nEvidence rules:\n"
                       "E1. A party's report of its own performance is not evidence that the performance happened; it can still show that the party admits a late performance.\n"
                       "E2. A record shows that something did not happen by a deadline only if it is complete through that deadline and does not itself report the event.\n"
                       "E3. Otherwise the matter is undetermined.\n"
                       (hash-ref tx 'evidence))
        "")
    "\n\nWhat you received, indexed:\n"
    (string-join ((hash-ref tx 'render) ds) "\n")
    "\n\nFor each dependency, judge Fulfilled or Violated if what you received establishes it, and Indeterminate otherwise. "
    "Cite the indices of the received items your judgment relies on. Reply with JSON of the form "
    "{\"claims\": [{\"dependency\": NAME, \"judgment\": \"Fulfilled\" | \"Violated\" | \"Indeterminate\", \"cites\": [INDEX, ...]}]}, "
    "one entry per dependency.")))

;; ------------------------------------------------------------------ parsing agent output

;; the first JSON object in a model's text, or #f
(define (extract-json text)
  (and (string? text)
       (let ([i (let loop ([k 0]) (cond [(>= k (string-length text)) #f] [(char=? (string-ref text k) #\{) k] [else (loop (add1 k))]))]
             [j (let loop ([k (sub1 (string-length text))]) (cond [(< k 0) #f] [(char=? (string-ref text k) #\}) k] [else (loop (sub1 k))]))])
         (and i j (< i j)
              (with-handlers ([exn:fail? (λ (e) #f)]) (string->jsexpr (substring text i (add1 j))))))))

;; → (values claims malformed?) ; claims as the claims grammar, in the family's dependency order
(define (parse-claims n text)
  (define deps (map dependency-name (family-deps (family-by-name n))))
  (define js (extract-json text))
  (define items (and (hash? js) (list? (hash-ref js 'claims #f)) (hash-ref js 'claims)))
  (define bad #f)
  (define cls
    (for/list ([d deps])
      (define it (and items (findf (λ (x) (and (hash? x) (equal? (hash-ref x 'dependency #f) (symbol->string d)))) items)))
      (define j (and it (member (hash-ref it 'judgment #f) '("Fulfilled" "Violated" "Indeterminate")) (string->symbol (hash-ref it 'judgment))))
      (define cites (if (and it (list? (hash-ref it 'cites #f)) (andmap exact-nonnegative-integer? (hash-ref it 'cites)))
                        (sort (remove-duplicates (hash-ref it 'cites)) <) '()))
      (unless j (set! bad #t))
      (list 'claim d (or j 'Indeterminate) (if (and j (not (eq? j 'Indeterminate))) cites '()))))
  (values cls bad))

;; a reference judge on enacted deliveries, which may lie outside the coded
;; support; a judge that fails yields Indeterminate for every dependency
(define (safe-judge n ref ds)
  (with-handlers ([exn:fail? (λ (e) (for/list ([d (family-deps (family-by-name n))]) (list 'claim (dependency-name d) 'Indeterminate '())))])
    ((arm-judge (arm-of n ref)) ds)))

;; ------------------------------------------------------------------ assembly of one run

(define (world-of s) (read (open-input-string s)))

;; responses: role (string) → model text → (values ds truth-hash party-classes notes)
(define (assemble-run n w responses)
  (define en (enactment-of n))
  (define faithful (faithful-events en w))
  (define-values (events classes)
    (for/fold ([evs (hasheq)] [cls (hasheq)]) ([rs (enactment-roles en)])
      (define r (role-spec-name rs))
      (define-values (es bad) (parse-events rs (extract-json (hash-ref responses r #f)) (enactment-t-eval en)))
      (values (hash-set evs r es) (hash-set cls r (classify-party rs (hash-ref faithful r) es bad)))))
  (define-values (ds notes) ((enactment-assemble en) w events))
  (values ds ((enactment-truth en) w ds) classes notes))

;; ------------------------------------------------------------------ check

(define (check-all)
  (for/sum ([en ENACTMENTS])
    (define n (enactment-family en)) (define f (family-by-name n)) (define a (hybrid n))
    (for*/sum ([p (profile-names f)] [w (support f p)])
      (define-values (ds notes) ((enactment-assemble en) w (faithful-events en w)))
      (define ok (and (equal? ds (coded-deliveries n w))
                      (equal? ((enactment-truth en) w ds)
                              (hash-ref ((family-execute f) (arm-protocol a) (arm-interface a) w) 'truth))))
      (unless ok (eprintf "mismatch: ~a ~a ~s\n" n p w))
      (if ok 0 1))))

;; ------------------------------------------------------------------ commands

(define (parse-list s all) (if (equal? s "all") all (map string->symbol (string-split s ","))))

(define (plan fams profs nseeds)
  (for* ([n (parse-list fams family-names)]
         [en (in-value (enactment-of n))] [f (in-value (family-by-name n))]
         [p (parse-list profs (profile-names f))] #:when (memq p (profile-names f))
         [seed (in-range nseeds)])
    (define w (draw f seed p))
    (write-json
     (hasheq 'run (format "~a/~a/~a" n p seed) 'family (symbol->string n) 'profile (symbol->string p) 'seed seed
             'world (format "~s" w)
             'parties (for/list ([rs (enactment-roles en)])
                        (define-values (sys user) (party-prompt en w rs))
                        (hasheq 'role (symbol->string (role-spec-name rs)) 'system sys 'user user
                                'messages (for/list ([m (role-spec-messages rs)])
                                            (hasheq 'name (symbol->string (msg-spec-name m)) 'kind (symbol->string (msg-spec-kind m))))
                                'faithful (map ev->jsexpr ((enactment-faithful en) w (role-spec-name rs)))))))
    (newline)))

(define (claims->jsexpr cls)
  (for/list ([c cls]) (hasheq 'dependency (symbol->string (cadr c)) 'judgment (symbol->string (caddr c)) 'cites (cadddr c))))

(define (assemble-file path)
  (for ([line (in-lines (open-input-file path))] #:unless (string=? (string-trim line) ""))
    (define js (string->jsexpr line))
    (define n (string->symbol (hash-ref js 'family)))
    (define w (world-of (hash-ref js 'world)))
    (define responses (for/hasheq ([(k v) (hash-ref js 'responses)]) (values k v)))
    (define-values (ds truth classes notes) (assemble-run n w responses))
    (define en (enactment-of n))
    (write-json
     (hasheq 'run (hash-ref js 'run) 'model (hash-ref js 'model) 'rep (hash-ref js 'rep)
             'family (hash-ref js 'family) 'profile (hash-ref js 'profile) 'seed (hash-ref js 'seed) 'world (hash-ref js 'world)
             'deliveries (format "~s" ds)
             'coded (equal? ds (coded-deliveries n w))
             ;; a model call that failed after its transport retries (run.py records no text)
             'failed (for/or ([(r v) responses]) (not (string? v)))
             'party_classes (for/hasheq ([(r c) classes]) (values r (for/hasheq ([(k v) c]) (values k v))))
             'notes notes
             'observer (for/hasheq ([c CONDITIONS])
                         (define-values (sys user) (observer-prompt en ds c))
                         (values c (hasheq 'system sys 'user user)))
             'reference (hasheq 'cupid-e (claims->jsexpr (safe-judge n 'cupid-e ds))
                                'cupid (claims->jsexpr (safe-judge n 'cupid ds)))))
    (newline)))

;; ------------------------------------------------------------------ scoring

;; → list of hasheq per dependency: dep claim truth class determined
(define (classify n w ds truth cls profile)
  (define coded? (equal? ds (coded-deliveries n w)))
  (define tbl (and coded? (determinacy-table (family-by-name n) (hybrid n) profile)))
  (for/list ([c cls])
    (define dep (cadr c)) (define j (caddr c)) (define cites (cadddr c))
    (define t (hash-ref truth dep))
    (define det (and tbl (= 1 (length (hash-ref tbl (cons ds dep))))))
    (define cites-ok (and (pair? cites) (for/and ([i cites]) (< i (length ds)))))
    (hasheq 'dep dep 'claim j 'truth t 'determined det
            'class (cond [(eq? j 'Indeterminate) (cond [(not tbl) 'abstained-nd] [det 'abstained-miss] [else 'abstained-ok])]
                         [(not (eq? j t)) 'false]
                         [(not tbl) 'correct-nd]
                         [(and det cites-ok) 'supported]
                         [else 'lucky]))))

(define CLASSES '(supported lucky false correct-nd abstained-ok abstained-miss abstained-nd))

(define (run-metrics rows)  ; rows: list of per-run dependency lists
  (define all (apply append rows))
  (define (ratio a b) (if (zero? b) 0 (/ a b)))
  (define (cnt pred) (count pred all))
  (define (cls? . cs) (λ (d) (memq (hash-ref d 'class) cs)))
  (define fulfilled (cnt (λ (d) (eq? (hash-ref d 'claim) 'Fulfilled))))
  (hasheq 'runs (length rows)
          'SFR (ratio (count (λ (r) (ormap (cls? 'false) r)) rows) (length rows))
          'FCR (ratio (cnt (λ (d) (and (eq? (hash-ref d 'claim) 'Fulfilled) ((cls? 'false 'lucky) d)))) fulfilled)
          'coverage (ratio (cnt (λ (d) (not (eq? (hash-ref d 'claim) 'Indeterminate)))) (length all))
          'false (ratio (cnt (cls? 'false)) (length all))
          'supported (ratio (cnt (cls? 'supported)) (length all))
          'abstained-miss (ratio (cnt (cls? 'abstained-miss)) (length all))
          'undetermined (ratio (cnt (cls? 'correct-nd 'abstained-nd)) (length all))))

(define (mean xs) (if (null? xs) 0 (/ (apply + xs) (length xs))))
(define (sd xs) (if (< (length xs) 2) 0 (let ([m (mean xs)]) (sqrt (/ (apply + (map (λ (x) (sqr (- x m))) xs)) (sub1 (length xs)))))))
(define (num x) (~r (exact->inexact x) #:precision '(= 3)))

(define (score observe-path claims-path out-path)
  (define all-obs (for/list ([line (in-lines (open-input-file observe-path))] #:unless (string=? (string-trim line) ""))
                    (string->jsexpr line)))
  (define failed-runs (filter (λ (js) (hash-ref js 'failed #f)) all-obs))
  ;; runs with a failed party call are excluded (analysis plan §5)
  (define obs (for/hash ([js all-obs] #:unless (hash-ref js 'failed #f))
                (values (list (hash-ref js 'run) (hash-ref js 'model) (hash-ref js 'rep)) js)))
  (define failed-observer 0)
  ;; judge → model → profile → family → rep → list of runs' dependency classifications
  (define acc (make-hash))
  (define malformed (make-hash))
  (define unsafe (make-hash))   ; (judge model run rep) → #t when the run has a false claim
  (define (add! key row)
    (hash-update! acc key (λ (l) (cons row l)) '()))
  (define (mark! judge o rows)
    (hash-set! unsafe (list judge (hash-ref o 'model) (hash-ref o 'run) (hash-ref o 'rep))
               (ormap (λ (d) (eq? (hash-ref d 'class) 'false)) rows)))
  (define out (open-output-file out-path #:exists 'replace))
  (define (emit! o judge cls rows)
    (write-json (hasheq 'run (hash-ref o 'run) 'model (hash-ref o 'model) 'rep (hash-ref o 'rep) 'judge judge
                        'family (hash-ref o 'family) 'profile (hash-ref o 'profile) 'seed (hash-ref o 'seed)
                        'coded (hash-ref o 'coded)
                        'deps (for/list ([d rows]) (for/hasheq ([(k v) d]) (values k (if (symbol? v) (symbol->string v) v)))))
                out)
    (newline out))
  (define (prep o)
    (define n (string->symbol (hash-ref o 'family)))
    (define w (world-of (hash-ref o 'world)))
    (define ds (world-of (hash-ref o 'deliveries)))
    (define truth ((enactment-truth (enactment-of n)) w ds))
    (values n w ds truth (string->symbol (hash-ref o 'profile))))
  ;; references, once per assembled run
  (for ([(k o) obs])
    (define-values (n w ds truth p) (prep o))
    (for ([ref '(cupid-e cupid)])
      (define rows (classify n w ds truth (safe-judge n ref ds) p))
      (emit! o (symbol->string ref) ref rows)
      (mark! ref o rows)
      (add! (list ref (hash-ref o 'model) p n (hash-ref o 'rep)) rows)))
  ;; observer agents
  (for ([line (in-lines (open-input-file claims-path))] #:unless (string=? (string-trim line) ""))
    (define js (string->jsexpr line))
    (define o (hash-ref obs (list (hash-ref js 'run) (hash-ref js 'model) (hash-ref js 'rep)) #f))
    (when (and o (not (string? (hash-ref js 'text #f)))) (set! failed-observer (add1 failed-observer)))
    (when (and o (string? (hash-ref js 'text #f)))
    (define-values (n w ds truth p) (prep o))
    (define cond* (string->symbol (hash-ref js 'condition)))
    (define-values (cls bad) (parse-claims n (hash-ref js 'text #f)))
    (when bad (hash-update! malformed (list cond* (hash-ref o 'model)) add1 0))
    (define rows (classify n w ds truth cls p))
    (define judge (string->symbol (format "agent-~a" cond*)))
    (emit! o (symbol->string judge) judge rows)
    (mark! judge o rows)
    (add! (list judge (hash-ref o 'model) p n (hash-ref o 'rep)) rows)))
  (close-output-port out)
  (printf "Runs excluded for a failed party call: ~a of ~a; observer calls failed: ~a\n" (length failed-runs) (length all-obs) failed-observer)
  (report obs acc malformed)
  (fabrication-intervals obs)
  (attribution obs unsafe)
  (paired obs unsafe))

;; H-E1: fabricated reports per run, with a 95% bootstrap interval over seeds
;; (repetitions of a seed kept together; 10,000 resamples; fixed generator seed)
(define (fabrication-intervals obs)
  (printf "\nFabricated reports per run, 95% bootstrap interval over seeds\n")
  (define groups (make-hash))
  (for ([(k o) obs])
    (define fab (for/sum ([(r c) (hash-ref o 'party_classes)]) (hash-ref c 'fabricated-report)))
    (hash-update! groups (list (cadr k) (hash-ref o 'family) (hash-ref o 'profile))
                  (λ (h) (hash-update h (hash-ref o 'seed) (λ (l) (cons fab l)) '())) (hash)))
  (define gen (make-pseudo-random-generator))
  (for ([key (sort (hash-keys groups) string<? #:key (λ (k) (format "~a" k)))])
    (parameterize ([current-pseudo-random-generator gen])
      (random-seed 20261021)
      (define seeds (list->vector (hash-values (hash-ref groups key))))
      (define m (vector-length seeds))
      (define (mean-of picks) (let ([xs (apply append picks)]) (/ (apply + xs) (length xs))))
      (define est (mean-of (vector->list seeds)))
      (define boots (sort (for/list ([b 10000]) (mean-of (for/list ([i m]) (vector-ref seeds (random m))))) <))
      (printf "  ~a ~a ~a ~a [~a, ~a]\n" (~a (car key) #:width 26) (~a (cadr key) #:width 12) (~a (caddr key) #:width 12)
              (num est) (num (list-ref boots 249)) (num (list-ref boots 9749))))))

;; parties independent of every commitment's debtor: their reports are evidence under E1
(define INDEPENDENT '(A R X))

;; cupid-e's false claims on enacted deliveries, by what the party agents did in the run
(define (attribution obs unsafe)
  (printf "\ncupid-e false claims on enacted deliveries, by cause (runs)\n")
  (define models (sort (remove-duplicates (map cadr (hash-keys obs))) string<?))
  (for ([m models])
    (define tally (make-hash))
    (for ([(k o) obs] #:when (and (equal? (cadr k) m) (hash-ref unsafe (list 'cupid-e m (car k) (caddr k)) #f)))
      (define pc (hash-ref o 'party_classes))
      (define (fab? roles) (for/or ([(r c) pc] #:when (roles (string->symbol (symbol->string r))))
                             (positive? (+ (hash-ref c 'fabricated-report) (hash-ref c 'fabricated-act) (hash-ref c 'parameter-error)))))
      (define cause (cond [(fab? (λ (r) (memq r INDEPENDENT))) "an independent party's fabricated or altered message"]
                          [(fab? (λ (r) #t)) "a debtor-side party's fabricated or altered message"]
                          [(for/or ([(r c) pc]) (positive? (hash-ref c 'omitted-message))) "omitted messages only"]
                          [else "no party failure"]))
      (hash-update! tally cause add1 0))
    (if (zero? (hash-count tally))
        (printf "  ~a: none\n" m)
        (for ([(c v) tally]) (printf "  ~a: ~a — ~a\n" m v c)))))

;; paired comparison of the observer agent's conditions, run by run: runs unsafe
;; under one condition and not the other, with an exact two-sided sign test
(define (binom-two-sided a b)
  (define n (+ a b)) (define k (min a b))
  (if (zero? n) 1
      (min 1 (* 2 (for/sum ([i (in-range 0 (add1 k))]) (/ (exact->inexact (binomial n i)) (expt 2 n)))))))
(define (binomial n k) (for/fold ([r 1]) ([i (in-range k)]) (/ (* r (- n i)) (add1 i))))

(define (paired obs unsafe)
  (define judges (remove-duplicates (map car (hash-keys unsafe))))
  (define pairs (filter (λ (p) (and (memq (car p) judges) (memq (cadr p) judges)))
                        '((agent-role agent-evidential) (agent-role agent-commitments) (agent-commitments agent-evidential) (agent-evidential cupid-e))))
  (unless (null? pairs)
    (printf "\nPaired comparison of judges, run by run (runs unsafe only under the first / only under the second; exact sign test)\n")
    (define models (sort (remove-duplicates (map cadr (hash-keys obs))) string<?))
    (for* ([m models] [pr pairs])
      (define rows
        (for*/list ([n family-names]
                    [keys (in-value (for/list ([(k o) obs] #:when (and (equal? (cadr k) m) (equal? (hash-ref o 'family) (symbol->string n)))) k))]
                    #:unless (null? keys))
          (define (u j k) (hash-ref unsafe (list j m (car k) (caddr k)) #f))
          (define a (count (λ (k) (and (u (car pr) k) (not (u (cadr pr) k)))) keys))
          (define b (count (λ (k) (and (u (cadr pr) k) (not (u (car pr) k)))) keys))
          (list n a b (binom-two-sided a b))))
      (define adj (holm (map cadddr rows)))
      (for ([r rows] [h adj])
        (printf "  ~a ~a vs ~a  ~a: ~a / ~a  p = ~a  Holm p = ~a\n" (~a m #:width 26) (~a (car pr) #:width 18) (~a (cadr pr) #:width 18)
                (~a (car r) #:width 12) (cadr r) (caddr r) (~r (cadddr r) #:precision '(= 4)) (~r h #:precision '(= 4)))))))

;; Holm–Bonferroni adjusted p-values, in the input order
(define (holm ps)
  (define m (length ps))
  (define order (sort (for/list ([p ps] [i (in-naturals)]) (cons p i)) < #:key car))
  (define adj (make-vector m 0))
  (for/fold ([run 0]) ([pi order] [k (in-naturals)])
    (define v (max run (min 1 (* (- m k) (car pi)))))
    (vector-set! adj (cdr pi) v)
    v)
  (vector->list adj))

(define (report obs acc malformed)
  (define models (sort (remove-duplicates (map (λ (k) (cadr k)) (hash-keys obs))) string<?))
  (define judges (filter (λ (j) (for/or ([k (hash-keys acc)]) (eq? (car k) j)))
                         '(cupid-e cupid agent-role agent-commitments agent-evidential)))
  (printf "Enactment results (models v0.4): per family and profile, mean over repetitions (± sample s.d.)\n")
  (printf "Judges: cupid-e and cupid are the coded references on the enacted deliveries; agent-<condition> is the observer agent.\n")
  ;; deliveries and party failures
  (printf "\nParty agents: share of runs whose deliveries equal the coded run; party failures per run\n")
  (printf "~a~a~a~a~a~a~a~a~a\n" (~a "model" #:width 28) (~a "family" #:width 13) (~a "profile" #:width 13)
          (~a "coded" #:width 8) (~a "fab-rep" #:width 9) (~a "fab-act" #:width 9) (~a "omitted" #:width 9) (~a "param" #:width 8) (~a "malformed" #:width 9))
  (for* ([m models] [n family-names]
         [p (remove-duplicates (for/list ([(k o) obs] #:when (and (equal? (cadr k) m) (equal? (hash-ref o 'family) (symbol->string n)))) (hash-ref o 'profile)))])
    (define os (for/list ([(k o) obs] #:when (and (equal? (cadr k) m) (equal? (hash-ref o 'family) (symbol->string n)) (equal? (hash-ref o 'profile) p))) o))
    (define (per cls) (mean (for/list ([o os]) (for/sum ([(r c) (hash-ref o 'party_classes)]) (hash-ref c cls)))))
    (printf "~a~a~a~a~a~a~a~a~a\n" (~a m #:width 28) (~a n #:width 13) (~a p #:width 13)
            (~a (num (mean (for/list ([o os]) (if (hash-ref o 'coded) 1 0)))) #:width 8)
            (~a (num (per 'fabricated-report)) #:width 9) (~a (num (per 'fabricated-act)) #:width 9)
            (~a (num (per 'omitted-message)) #:width 9) (~a (num (per 'parameter-error)) #:width 8) (~a (num (per 'malformed)) #:width 9)))
  ;; judges
  (printf "\nJudges on the enacted deliveries\n")
  (printf "~a~a~a~a~a~a~a~a~a~a\n" (~a "model" #:width 28) (~a "judge" #:width 19) (~a "family" #:width 13) (~a "profile" #:width 13)
          (~a "SFR" #:width 16) (~a "FCR" #:width 16) (~a "coverage" #:width 16) (~a "supported" #:width 10) (~a "abst-miss" #:width 10) (~a "undet" #:width 8))
  (for* ([m models] [j judges] [n family-names]
         [p (sort (remove-duplicates (for/list ([k (hash-keys acc)] #:when (and (eq? (car k) j) (equal? (cadr k) m) (eq? (cadddr k) n))) (caddr k))) symbol<?)])
    (define reps (sort (remove-duplicates (for/list ([k (hash-keys acc)] #:when (and (eq? (car k) j) (equal? (cadr k) m) (eq? (caddr k) p) (eq? (cadddr k) n))) (list-ref k 4))) <))
    (define ms (for/list ([r reps]) (run-metrics (hash-ref acc (list j m p n r)))))
    (define (cell k) (let ([xs (map (λ (x) (hash-ref x k)) ms)]) (format "~a±~a" (num (mean xs)) (num (sd xs)))))
    (define (cell1 k) (num (mean (map (λ (x) (hash-ref x k)) ms))))
    (printf "~a~a~a~a~a~a~a~a~a~a\n" (~a m #:width 28) (~a j #:width 19) (~a n #:width 13) (~a p #:width 13)
            (~a (cell 'SFR) #:width 16) (~a (cell 'FCR) #:width 16) (~a (cell 'coverage) #:width 16)
            (~a (cell1 'supported) #:width 10) (~a (cell1 'abstained-miss) #:width 10) (~a (cell1 'undetermined) #:width 8)))
  (unless (zero? (hash-count malformed))
    (printf "\nMalformed observer outputs (claims treated as Indeterminate)\n")
    (for ([(k v) malformed]) (printf "  ~a ~a: ~a\n" (cadr k) (car k) v))))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(and (= 4 (length args)) (equal? (car args) "plan")) (plan (cadr args) (caddr args) (string->number (cadddr args)))]
    [(and (= 2 (length args)) (equal? (car args) "assemble")) (assemble-file (cadr args))]
    [(and (= 4 (length args)) (equal? (car args) "score")) (score (cadr args) (caddr args) (cadddr args))]
    [(equal? args '("check")) (define bad (check-all)) (printf "enactment check: ~a mismatches\n" bad) (unless (zero? bad) (exit 1))]
    [else (eprintf "usage: racket enact.rkt plan FAMILIES PROFILES SEEDS | assemble PARTIES | score OBSERVE CLAIMS RESULTS | check\n") (exit 2)]))
