#lang racket/base
;; English wording of the report.  The keys and their arguments are listed
;; in report.rkt (`text-keys`); arguments that are code arrive already
;; formatted, e.g. "`Frame`".
(provide texts)

(define (ghost g) (if g "ghost " ""))
(define (named name) (if name (string-append " " name) ""))
(define (plural n one many) (if (= n 1) one many))

(define texts
  (hash
   'title (lambda () "Outputs the postcondition does not mention")
   'scope
   (lambda (total sel n exec proof pub private)
     (format "Scope: of the ~a exec and proof functions checked, the selector ~a picks ~a (exec ~a, proof ~a; pub ~a, non-pub ~a). The design is in `design.md`."
             total sel n exec proof pub private))
   'summary-heading (lambda () "Summary")
   'summary-columns (lambda () '("Group" "Functions" "Outputs" "Findings"))
   'group-name (lambda (g) (if g "Functions with a postcondition" "Functions without a postcondition"))
   'tally-columns (lambda () '("Finding" "Unconstrained" "Type invariant only"))
   'kind-name
   (lambda (k)
     (case k
       [(return-unmentioned) "Return value not mentioned"]
       [(mut-param-unmentioned) "State of a `&mut` parameter after the call not mentioned"]))
   'trait-impls
   (lambda (impls own with-decl merged merged-reported)
     (define (n-impls n) (format "~a ~a" n (plural n "implementation" "implementations")))
     (string-append
      (format "Trait method implementations: ~a." impls)
      (if (> own 0)
          (format " ~a ~a postcondition clauses of their own and ~a listed one by one."
                  (n-impls own) (plural own "adds" "add") (plural own "is" "are"))
          "")
      (if (> with-decl 0)
          (format " ~a without clauses of their own ~a the results of their declaration, which is in this report, and ~a reported with it."
                  (n-impls with-decl) (plural with-decl "has" "have") (plural with-decl "is" "are"))
          "")
      (if (> merged 0)
          (format " ~a without clauses of their own ~a a declaration that is not in this report, and ~a merged by trait method; ~a of them ~a findings listed below."
                  (n-impls merged) (plural merged "has" "have") (plural merged "is" "are")
                  merged-reported (plural merged-reported "has" "have"))
          "")))
   'no-findings (lambda () "No findings.")
   'selected-heading (lambda () "Selected functions")
   'selected-columns (lambda () '("Function" "Location" "Findings"))
   'private (lambda () "non-pub")
   'merged-heading
   (lambda (decl n)
     (format "~a (~a ~a, all specified by this declaration, with the same results)"
             decl n (plural n "implementation" "implementations")))
   'merged-example (lambda () "Taking the first implementation as the example:")
   'finding-return
   (lambda (g name ty)
     (format "The ~areturn value~a has type ~a. The postcondition does not name the return value, and there is no `returns` clause."
             (ghost g) (named name) ty))
   'finding-return-component
   (lambda (i name ty)
     (format "Component ~a of the `#[verus_spec]` return tuple (the ~a return value~a, of type ~a) is not mentioned by the postcondition."
             i (if (= i 0) "exec" "ghost") (named name) ty))
   'finding-mut
   (lambda (g name ty raw)
     (format "The ~aparameter ~a has type ~a. No `final(...)` in the postcondition contains `~a`, so a caller can only assume it may have been changed arbitrarily."
             (ghost g) name ty raw))
   'finding-type-inv
   (lambda (inv)
     (format " Type invariant only: a caller knows only that it satisfies the type invariant ~a, not how it relates to the arguments or to the state before the call." inv))
   'finding-default-only
   (lambda () " Mentioned only in `default_ensures`: only implementations that keep the default body guarantee it, and a caller going through the trait generically does not get it.")
   'fn-external-body (lambda () "`external_body`: the body is not verified, and the specification is trusted")
   'fn-post-from-decl
   (lambda (decl own?)
     (format "postcondition from the trait declaration ~a~a" decl (if own? " and the clauses the implementation adds" "")))
   'fn-decl-missing
   (lambda (decl) (format "trait declaration ~a not found; checked against the implementation's own clauses only" decl))
   'fn-inferred (lambda () "name inferred from VIR")))
