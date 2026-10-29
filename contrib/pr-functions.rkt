#lang racket/base
;; usage: racket contrib/pr-functions.rkt <head.results> <base.results> <worktree> <merge-base> <out.results>
;;
;; Writes the results of only the functions a PR's changes involve, each
;; `fn` form followed by a comment naming why it is there; `racket main.rkt
;; report <out.results> <out.md> all` expands it.  The choice of functions is
;; the reviewer's, made outside the tool (design.md, 结论20):
;;   changed   the function's whole item (attributes, spec, signature, body)
;;             in the PR head overlaps a hunk of `git diff MERGE-BASE...HEAD`
;;   new       the function is in the head results but not in the base
;;             results, compared by module and report name; e.g. existing
;;             code the PR moved into `verus! {}`
(require racket/list racket/string racket/system racket/port
         "../results.rkt")

(define args (current-command-line-arguments))
(define-values (head-path base-path worktree base out)
  (apply values (vector->list args)))

;; file -> list of (first . last), the new-side lines of each hunk; a pure
;; deletion after line n is (n+1 . n), overlapping items that contain both
(define changes
  (let ([diff (parameterize ([current-directory worktree])
                (with-output-to-string
                  (lambda () (system* (find-executable-path "git") "diff" "-U0" "--no-color"
                                      (string-append base "...HEAD") "--" "*.rs"))))]
        [h (make-hash)])
    (for/fold ([file #f]) ([line (string-split diff "\n")])
      (cond
        [(regexp-match #rx"^[+][+][+] b/(.*)$" line) => cadr]
        [(string-prefix? line "+++ ") #f]
        [(and file (regexp-match #px"^@@ [^+]*[+]([0-9]+)(?:,([0-9]+))? @@" line))
         => (lambda (m)
              (define start (string->number (cadr m)))
              (define n (if (caddr m) (string->number (caddr m)) 1))
              (hash-update! h file (lambda (l) (cons (if (= n 0) (cons (add1 start) start)
                                                         (cons start (+ start n -1)))
                                                     l))
                            '())
              file)]
        [else file]))
    h))

(define (changed? r)
  (and (fn-file r) (fn-start r)
       (for/or ([c (hash-ref changes (fn-file r) '())])
         (and (<= (fn-start r) (cdr c)) (>= (fn-end r) (car c))))))

(define (key r) (cons (fn-module r) (fn-name r)))
(define-values (vir head) (read-results head-path))
(define-values (_b base-fns) (read-results base-path))
(define old (for/hash ([r base-fns]) (values (key r) #t)))
(define (new? r) (not (hash-ref old (key r) #f)))

(define picked
  (for/list ([r head] #:when (or (changed? r) (new? r)))
    (list r (changed? r) (new? r))))

(with-output-to-file out #:exists 'replace
  (lambda ()
    (printf ";; ensures-coverage results, design.md 结论22: only the functions involved in\n")
    (printf ";; the changes since ~a (pr-functions.rkt); the comment after each is why\n" base)
    (write `(vir ,@vir)) (newline)
    (for ([p picked])
      (write (car p))
      (printf " ; ~a\n" (string-join (filter values (list (and (cadr p) "changed") (and (caddr p) "new"))) "+")))))

(printf "~a functions: ~a changed, ~a new only\n" (length picked)
        (count cadr picked) (count (lambda (p) (and (caddr p) (not (cadr p)))) picked))
