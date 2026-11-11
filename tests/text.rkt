#lang racket/base
;; usage: racket tests/text.rkt [<results>]
;;
;; Checks every language module in text/ against report.rkt's `text-keys`:
;; exactly those keys, each a procedure taking the listed number of
;; arguments.  Then renders a report of <results> (default: the fixture's
;; expected results) in each language, so that every text used by the
;; fixture is actually called.  Prints one line per language; exits 1 on
;; any problem.  Run by tests/run.sh.
(require racket/list racket/runtime-path racket/file racket/path racket/port)

(define-runtime-path root "..")
(define text-keys (dynamic-require (build-path root "report.rkt") 'text-keys))
(define report (dynamic-require (build-path root "report.rkt") 'report))
(define read-results (dynamic-require (build-path root "results.rkt") 'read-results))

(define results-path
  (let ([args (current-command-line-arguments)])
    (if (> (vector-length args) 0)
        (vector-ref args 0)
        (build-path root "tests" "expected.results"))))

(define failed #f)
(define (problem fmt . args)
  (set! failed #t)
  (apply eprintf (string-append "FAIL: " fmt "\n") args))

(define langs
  (sort (for/list ([p (directory-list (build-path root "text") #:build? #t)]
                   #:when (regexp-match? #rx"[.]rkt$" (path->string p)))
          p)
        string<? #:key path->string))
(when (null? langs) (problem "no language modules in text/"))

(define-values (_vir fns) (read-results results-path))

(for ([p langs])
  (define name (path->string (path-replace-extension (file-name-from-path p) #"")))
  (define texts (dynamic-require p 'texts))
  (define want (map car text-keys))
  (define have (hash-keys texts))
  (for ([k want] #:unless (hash-has-key? texts k)) (problem "~a: missing key ~a" name k))
  (for ([k have] #:unless (memq k want)) (problem "~a: unknown key ~a" name k))
  (for ([kv text-keys] #:when (hash-has-key? texts (car kv)))
    (define f (hash-ref texts (car kv)))
    (unless (and (procedure? f) (procedure-arity-includes? f (cdr kv)))
      (problem "~a: ~a must be a procedure of ~a argument(s)" name (car kv) (cdr kv))))
  (define out (make-temporary-file "ensures-coverage-~a.md"))
  (with-handlers ([exn:fail? (lambda (e) (problem "~a: report failed: ~a" name (exn-message e)))])
    (parameterize ([current-output-port (open-output-nowhere)])
      (report fns "all" (length fns) out texts))
    (printf "text ~a: ~a keys, report of ~a functions rendered (~a bytes)\n"
            name (length want) (length fns) (file-size out)))
  (delete-file out))

(when failed (exit 1))
