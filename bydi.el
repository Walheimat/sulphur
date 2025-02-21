;;; bydi.el --- Mocking macros -*- lexical-binding: t; -*-

;; Author: Krister Schuchardt <krister.schuchardt@gmail.com>
;; Homepage: https://github.com/Walheimat/bydi
;; Version: 0.8.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: extensions

;;; Commentary:
;;
;; `bydi' is a framework to stump, mock and spy on functions during
;; the execution of `ert' tests.
;;
;; You can selectively mock (almost) any function and command by
;; providing your own mock implementation or simply defining what
;; should be returned.
;;
;; You can also spy on functions to just record invocations without
;; providing a return value or replacement implementation.
;;
;; You can also watch variables.
;;
;; Finally, you can verify invocations and assignments in various
;; ways using macros similar to `should'.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'compat nil t)

;;;; Variables

(defvar bydi--history nil
  "A hash table mapping symbols to invocations/settings.

For functions, each value is a list of the arguments it was called with.
For variables, it's the values it was set to.

The verification functions use this table to inspect invocation and
assignment results.")

(defvar bydi--suspects nil
  "Hash table of selective mocking of spies.")

(defvar bydi--volatile nil
  "Hash map of functions that should return t or nil when called.

Can be toggled using `bydi-toggle-volatile' or
`bydi-toggle-sometimes'.")

(defvar bydi--ignore nil
  "List of functions that will return nil when called.

Can be toggled using `bydi-toggle-volatile' or
`bydi-toggle-sometimes'.")

(defvar bydi--vars nil
  "List of variables created for mocks using `:var'.")

(defvar bydi--targets nil
  "List of functions spied upon during `bydi--mock'.

Each function will be advised to record the arguments it was
called with.")

(defvar bydi--wards nil
  "List of variables watched during `bydi--mock'.

Each variable will be watched to record the values assigned to
it.")

;;;; Macros

(cl-defmacro bydi--mock (instructions
                         &rest form
                         &key history volatile
                         &allow-other-keys)
  "Evaluate FORM while instructed symbols behave predictably.

INSTRUCTIONS is a list of definitions that ensure that desired symbols
are temporarily rebound and remain under observation. Each definition is
a plist describing the desired action. All symbols instructed this way
can be used in assertions.

The most common use for this is mocking function invocations. They may
also be spied upon. You may also watch variables.

Within FORM you may now make assertions of the type `bydi-was-*' to
inspect the behavior.

The following instructions are possible:

Plist (:mock FUN :with REPLACE) which means that when FUN is called,
REPLACE is called instead. The same effect can be done by using a cons
cell (FUN . REPLACE) which is discouraged. For functions that shouldn't
be mocked you can use (:risky-mock FUN) to suppress the warning.

Plist (:mock FUN :return VAL) which means that when FUN is called, VAL
is returned.

Plist (:mock FUN :var VAR) which means that when FUN is called, the
value of VAR is returned. The variable VAR will be created. Its initial
value can be set using (:initial INITIAL-VAL).

Plist (:always FUN) which means that FUN will always return t.

Plist (:ignore FUN) which means that FUN will return nil.

Plist (:sometimes FUN) which means that FUN will return t until it is
toggled.

Plist (:othertimes FUN) which means that FUN will return nil until it is
toggled.

Plist (:spy FUN) which means that invocations of FUN can be inspected
the same way a mock could without replacing the implementation.

Plist (:fail FUN :with SIGNAL) which means that invocations of FUN will
throw. This can be further refined by using (:args ARGS) that will
ensure the signaling function is called with ARGS.

Plist (:watch VAR) which means that settings of VAR can be inspected.

You can pass HISTORY to share histories when stacking `bydi--mock'
invocations.

You can also pass VOLATILE to allow toggling volatile functions when
stacking `bydi--mock' forms."
  (declare (indent defun))

  (let ((instructions (if (listp instructions) instructions (list instructions))))

    `(cl-letf* ((bydi--history ,(if history history '(bydi--make-table)))
                (bydi--suspects (bydi--make-table))

                (bydi--targets ',(bydi--collect instructions :spy))
                (bydi--wards ',(bydi--collect instructions :watch))

                (bydi--volatile ,(if volatile volatile '(bydi--make-table)))
                (bydi--vars ',(bydi--collect instructions :var))

                ,@(bydi-mock--create instructions))

       (unwind-protect

           (progn

             (bydi--into-volatile
              ',(bydi--collect instructions :sometimes)
              ',(bydi--collect instructions :othertimes))

             (bydi--setup)
             ,@(bydi--safe-body form))

         (bydi--teardown)))))

(defun bydi--setup ()
  "Set up spies and watchers."
  (bydi-spy--create)
  (bydi-watch--create))

(defun bydi--teardown ()
  "Tear down spies and watchers."
  (bydi-spy--clear)
  (bydi-watch--clear)
  (bydi-mock--clear-vars))

;;;; Calling macros

(cl-defmacro bydi-was-called (fun &key clear)
  "Check if mocked FUN was called.

If CLEAR is t, clear the history of calls of that function."
  `(let ((actual (gethash ',fun bydi--history 'not-called)))
     ,@(delq
        nil
        `((should (bydi-verify--was-called ',fun 'called actual))
          ,(when clear `(bydi-clear-mocks-for ',fun))))))

(defmacro bydi-was-not-called (fun)
  "Check if mocked FUN was not called."
  `(let ((actual (gethash ',fun bydi--history 'not-called)))
     (should (bydi-verify--was-not-called ',fun 'not-called actual))))

(cl-defmacro bydi-was-called-with (fun expected &key clear)
  "Check if FUN was called with EXPECTED.

If CLEAR is t, clear the history of calls of that function."
  (declare (indent defun))

  `(let ((expected (bydi-verify--safe-exp ,expected))
         (actual (or (car-safe (gethash ',fun bydi--history))
                     'not-called)))
     ,@(delq
        nil
        `((should (bydi-verify--was-called-with ',fun expected actual))
          ,(when clear `(bydi-clear-mocks-for ',fun))))))

(defmacro bydi-was-called-nth-with (fun expected index)
  "Check if FUN was called with EXPECTED on the INDEXth call."
  `(let ((expected (bydi-verify--safe-exp ,expected))
         (actual (or (nth ,index (reverse (gethash ',fun bydi--history)))
                     'not-called)))
     (should (bydi-verify--was-called-with ',fun expected actual))))

(defmacro bydi-was-called-last-with (fun expected)
  "Check if FUN was called with EXPECTED on the last call."
  `(let ((expected (bydi-verify--safe-exp ,expected))
         (actual (or (car-safe (last (reverse (gethash ',fun bydi--history))))
                     'not-called)))
     (should (bydi-verify--was-called-with ',fun expected actual))))

(defmacro bydi-was-called-n-times (fun expected)
  "Check if mocked FUN was called EXPECTED times."
  `(let ((actual (length (gethash ',fun bydi--history))))
     (should (bydi-verify--was-called-n-times ',fun ,expected actual))))

;;;; Setting macros

(cl-defmacro bydi-was-set-to (var to &key clear)
  "Check that VAR was set to TO.

If CLEAR is t, clear the history of assignments to that variable."
  `(let ((actual (car-safe (gethash ',var bydi--history))))
     ,@(delq
        nil
        `((should (bydi-verify--was-set-to ',var ,to actual))
          ,(when clear `(bydi-clear-mocks-for ',var))))))

(defmacro bydi-was-set-to-nth (var to index)
  "Check that VAR was set to TO during INDEXth setting."
  `(let ((actual (nth ,index (reverse (gethash ',var bydi--history)))))
     (should (bydi-verify--was-set-to ',var ,to actual))))

(defmacro bydi-was-set-to-last (var to)
  "Check that VAR was set to TO during last setting."
  `(let ((actual (car-safe (last (reverse (gethash ',var bydi--history))))))
     (should (bydi-verify--was-set-to ',var ,to actual))))

(defmacro bydi-was-set-n-times (var expected)
  "Verify that VAR was set EXPECTED times."
  `(let ((actual (length (gethash ',var bydi--history))))

     (should (bydi-verify--was-set-n-times ',var ,expected actual))))

(cl-defmacro bydi-was-set (var &key clear)
  "Check if VAR was set.

If CLEAR is t, clear the history of assignments to that variable."
  `(let ((actual (gethash ',var bydi--history 'not-set)))
     ,@(delq
        nil
        `((should (bydi-verify--was-set ',var 'set actual))
          ,(when clear `(bydi-clear-mocks-for ',var))))))

(defmacro bydi-was-not-set (var)
  "Check that VAR was not set."
  `(let ((actual (gethash ',var bydi--history 'not-set)))

     (should-not (bydi-verify--was-set ',var 'not-set actual))))

;;;; Other macros

(defmacro bydi-match-expansion (form &rest value)
  "Match expansion of FORM against VALUE."
  `(should (bydi-verify--matches ',form ,@value)))

(cl-defmacro bydi-should-every (forms &key check expected)
  "CHECK if all FORMS have EXPECTED value using CHECK."
  (declare (indent defun))
  (let ((check (or check 'eq)))

    `(progn ,@(mapcar (lambda (it) `(should (,check ,it ,expected))) forms))))

;;;; Convenience functions

(defun bydi-return-first (a &rest _r)
  "Return first argument passed A."
  a)
(defalias 'bydi-rf 'bydi-return-first)

(defun bydi-return-all (&rest r)
  "Return all arguments R."
  r)
(defalias 'bydi-ra 'bydi-return-all)

(defun bydi-return-testing (&rest _r)
  "Return symbol `testing'."
  'testing)
(defalias 'bydi-rt 'bydi-return-testing)

;;;; Handlers

(defun bydi--record (sym artifact)
  "Record ARTIFACT for SYM.

The artifact is also returned."
  (let* ((existing (gethash sym bydi--history))
         (history (if existing (push artifact existing) (list artifact))))

    (puthash sym history bydi--history)

    artifact))

(defun bydi--warn (message &rest args)
  "Emit a warning.

The MESSAGE will be formatted with ARGS."
  (display-warning
   'bydi
   (apply #'format message args)
   :warning))

;;;; Helpers

(defun bydi--make-table ()
  "Make a table."
  (make-hash-table :test 'equal))

(defun bydi--into-volatile (always ignore)
  "Collect a list of volatile functions into TARGET.

IGNORE are the functions to ignore, ALWAYS are the functions to always."
  (let ((cur-always (gethash 'always bydi--volatile))
        (cur-ignore (gethash 'ignore bydi--volatile)))

    (puthash 'always (append cur-always always) bydi--volatile)
    (puthash 'ignore (append cur-ignore ignore) bydi--volatile)))

(defvar bydi--keywords '(:history :volatile)
  "List of keywords for `bydi--mock'.")

(defun bydi--safe-body (body)
  "Collect everything from BODY that's not a key argument."
  (cl-loop for (key val)
           on body by 'cddr
           unless (memq key bydi--keywords)
           collect key
           and if val collect val))

(defun bydi--collect (instructions prop)
  "Collect PROP entries from INSTRUCTIONS."
  (cl-loop for i in instructions
           when (and (bydi-mock--valid-plistp i)
                     (plist-member i prop))
           collect (plist-get i prop)))

(defun bydi-mock--valid-plistp (plist)
  "Check if PLIST list a valid one."
  (and (plistp plist)
       (or (and (or (memq :mock plist) (memq :risky-mock plist))
                (or (memq :return plist)
                    (memq :with plist)
                    (memq :var plist)))
           (memq :fail plist)
           (memq :spy plist)
           (memq :watch plist)
           (memq :always plist)
           (memq :ignore plist)
           (memq :sometimes plist)
           (memq :othertimes plist))))

;;;; Verification

(defvar bydi-verify--elision '\...
  "Symbol indicating an elision during argument verification.

Allows verifying only those arguments passed to a mocked function
that are of interest.")

(defun bydi-verify--was-called (_fun _expected actual)
  "Verify that ACTUAL represents a function call."
  (not (equal 'not-called actual)))

(defun bydi-verify--was-not-called (_fun _expected actual)
  "Verify that ACTUAL represents missing function call."
  (equal 'not-called actual))

(defun bydi-verify--was-called-with (_fun expected actual)
  "Verify that EXPECTED represents ACTUAL arguments.

If the EXPECTED value start with `bydi-verify--elision', the check only
extends to verifying that expected argument is in expected
arguments in the order given."
  (let ((safe-exp (bydi-verify--safe-exp expected)))

    (cond
     ((memq bydi-verify--elision safe-exp)
      (let ((args safe-exp)
            (matches t)
            (last-match -1))

        (while (and matches args)
          (let* ((it (car args))
                 (this-match (seq-position actual it)))

            (unless (eq it bydi-verify--elision)
              (if (and this-match
                       (> this-match last-match))
                  (setq last-match this-match)
                (setq matches nil)))
            (setq args (cdr args))))
        matches))
     ((and (sequencep actual)
           (eq (length safe-exp) (length actual)))
      (equal safe-exp actual))
     ((null expected)
      (null actual))
     (t nil))))

(defun bydi-verify--was-called-n-times (_fun expected actual)
  "Verify that EXPECTED number matches ACTUAL."
  (eq expected actual))

(defun bydi-verify--was-set-to (_var exp-to to)
  "Verify that expected and actual settings match.

Matches EXP-FROM against FROM and EXP-TO against TO."
  (equal exp-to to))

(defun bydi-verify--was-set (_var _expected actual)
  "Verify that variable was set.

This is done by checking that ACTUAL is not the symbol `not-set'."
  (not (equal actual 'not-set)))

(defun bydi-verify--was-set-n-times (_var expected actual)
  "Verify that EXPECTED matches ACTUAL settings."
  (eq expected actual))

(defun bydi-verify--matches (form value)
  "Make sure FORM matches VALUE."
  (eval
   `(pcase (macroexpand-1 ',form)
      (',value t))))

(defun bydi-verify--safe-exp (sexp)
  "Get SEXP as a quoted list."
  (cond
   ((null sexp)
    (list nil))
   ((listp sexp)
    sexp)
   (t (list sexp))))

(defun bydi-verify--unwrap-single-item (a b)
  "If A and B are both single-item lists, unwrap them."
  (or (and (listp a)
           (listp b)
           (= 1 (length a) (length b))
           (list (nth 0 a) (nth 0 b)))
      (list a b)))

;;;; Mocking

(defvar bydi-mock--risky '(fboundp advice-add advice-remove file-exists-p)
  "List of risky functions.

These are functions that, when mocked, do or may prevent test
execution.")

(defun bydi-mock--create (instructions)
  "Get mocks for INSTRUCTIONS."
  (cl-loop for instruction in instructions
           for bindings = (cl-destructuring-bind (bind type composite) (bydi-mock--template instruction)
                            (when bind
                              (bydi-mock--caution-about-risky-mocks bind instruction)
                              (bydi-mock--mock-implementation bind type composite)))
           if bindings
           nconc bindings))

(defun bydi-mock--template (mock)
  "Get function and binding for MOCK."
  (cond
   ((bydi-mock--valid-plistp mock)
    (cond
     ;; Returning constant value or variable.
     ((plist-member mock :return)
      (unless (plist-get mock :return)
        (bydi--warn "Returning `nil' may lead to unexpected results"))
      `(,(or (plist-get mock :mock) (plist-get mock :risky-mock))
        replace
        ,(plist-get mock :return)))

     ;; Signaling.
     ((plist-member mock :fail)
      `(,(plist-get mock :fail)
        replace
        ,(let ((type (or (plist-get mock :with) 'signal)))

           `(apply #',type
                   ,(or (plist-get mock :args)
                        (pcase type
                          ('user-error
                           ''("User error"))
                          ('signal
                           ''(error "Lisp error"))))))))

     ;; Replacing implementation.
     ((plist-member mock :with)
      `(,(or (plist-get mock :mock) (plist-get mock :risky-mock))
        replace
        (apply #',(plist-get mock :with) r)))

     ;; Creating a variable.
     ((plist-member mock :var)
      `(,(or (plist-get mock :mock) (plist-get mock :risky-mock))
        var
        (,(plist-get mock :var) ,(plist-get mock :initial))))

     ;; Ignore spying and watching.
     ((or (plist-member mock :spy) (plist-member mock :watch))
      '(nil default nil))

     ;; Short-hands.
     ((plist-member mock :ignore)
      `(,(plist-get mock :ignore) replace (apply #'ignore r)))
     ((plist-member mock :always)
      `(,(plist-get mock :always) replace (apply #'always r)))

     ;; Volatile.
     ((or (plist-member mock :sometimes) (plist-member mock :othertimes))
      (let ((fun (or (plist-get mock :sometimes) (plist-get mock :othertimes))))
        `(,fun replace (funcall #'bydi-mock--volatile ',fun))))))

   ((consp mock)
    `(,(car mock) replace (apply ,(cdr mock) r)))

   (t `(,mock default nil))))

(defun bydi-mock--mock-implementation (fun type &optional composite)
  "Return the mock implementation of FUN.

TYPE determines the composition of the mock function. COMPOSITE
is used to build it."
  (pcase type
    ('replace
     `(((symbol-function ',fun)
        (lambda (&rest r)
          (interactive)
          (apply 'bydi--record (list ',fun r))
          ,composite))))
    ('var
     (let* ((name (car-safe composite))
            (val (cadr composite))
            (var (intern (symbol-name name))))

       `((,var ,val)
         ((symbol-function ',fun)
          (lambda (&rest r)
            (interactive)
            (apply 'bydi--record (list ',fun r))
            ,var)))))
    ('default
     `(((symbol-function ',fun)
        (lambda (&rest r)
          (interactive)
          (apply 'bydi--record (list ',fun r))))))))

(defun bydi-mock--volatile (fun)
  "Return volatile value for FUN."
  (and (memq fun (bydi--always)) t))

(defun bydi-mock--caution-about-risky-mocks (fun instruction)
  "Caution if FUN is a risky mock but not tagged as such.

This is done by inspecing if INSTRUCTION is using `:risky-mock' for
risky mocks."
  (when (and (memq fun bydi-mock--risky)
             (not (memq :risky-mock instruction)))

    (bydi--warn "Mocking `%s' may lead to issues" fun)))

(defun bydi-mock--clear-vars ()
  "Unintern interned variables."
  (mapc (lambda (it) (unintern it nil)) bydi--vars))

;;;; Spying

(defvar bydi-spy--advice-name 'bydi-spy
  "Name used for the advising of spied upon functions.

Allows removing anonymous advice.")

(defun bydi-spy--create ()
  "Record invocations of FUN in history."
  (mapc (lambda (it)
          (advice-add
           it :around
           (lambda (fun &rest args)

             (apply 'bydi--record (list it args))

             (or (apply 'bydi-spy--capture-when (append (list it) args))
                 (apply fun args)))
           (list (cons 'name bydi-spy--advice-name))))
        bydi--targets))

(defun bydi-spy--clear ()
  "Clear all spies."
  (mapc (lambda (it) (advice-remove it bydi-spy--advice-name)) bydi--targets))

(defun bydi-spy--capture-when (fun &rest args)
  "Maybe return recorded value for FUN.

If ARGS match the the IN field of the recorded value, the value
of OUT will be returned. If it was recorded with ONCE being t,
the recording is removed before returning the OUT value."
  (and-let* ((condition (gethash fun bydi--suspects))
             ((equal args (plist-get condition :called-with))))

    (when-let (rem (plist-get condition :once))
      (remhash fun bydi--suspects))

    (plist-get condition :then-return)))

(cl-defmacro bydi-spy--define-when (fun &key called-with then-return once)
  "Return THEN-RETURN when FUN is called with CALLED-WITH.

If ONCE is to, only do this once."
  `(progn
     (unless (memq ',fun bydi--targets)
       (bydi--warn "No spy for `%s' was recorded" ',fun))
     (puthash
      ',fun
      (list :called-with ,called-with :then-return ,then-return :once ,once)
      bydi--suspects)))

;;;; Watching

(defun bydi-watch--watch-variable (symbol newval operation _where)
  "Record that SYMBOL was updated with NEWVAL.

Only records when OPERATION is a let or set binding."
  (when (memq operation '(let set))
    (bydi--record symbol newval)))

(defun bydi-watch--create ()
  "Record settings of symbols."
  (mapc (lambda (it)
          (add-variable-watcher it #'bydi-watch--watch-variable))
        bydi--wards))

(defun bydi-watch--clear ()
  "Clear watchers."
  (mapc
   (lambda (it) (remove-variable-watcher it #'bydi-watch--watch-variable))
   bydi--wards))

;;;; Explaining
;;
;; These functions deal with explaining why a `bydi' assertion failed.

(defun bydi-explain--wrong-call (fun expected actual)
  "Explain that FUN was called with ACTUAL not EXPECTED."
  (cond
   ((equal expected 'not-called)
    `(was-called ',fun :args ,actual))

   ((eq expected 'called)
    `(never-called ',fun))

   ((eq actual 'not-called)
    `(never-called ',fun))

   (t
    `(wrong-arguments
      ',fun
      :reason ,(cl-destructuring-bind (a b)
                   (bydi-verify--unwrap-single-item expected actual)
                 (ert--explain-equal-rec a b))))))

(defun bydi-explain--wrong-setting (var expected actual)
  "Explain that VAR was set to ACTUAL, not EXPECTED."
  (cond
   ((eq expected 'not-set)
    `(was-set ',var :to ,actual))

   ((eq expected 'set)
    `(never-set ',var))

   (t
    `(wrong-setting
      ',var
      :reason ,(ert--explain-equal-rec expected actual)))))

(defun bydi-explain--explain-mismatch (actual expected)
  "Explain that ACTUAL didn't match EXPECTED."
  (let ((actual (macroexpand-1 actual)))

    `(no-match
      :reason ,(ert--explain-equal-rec expected actual)
      :wanted ,expected
      :got ,actual)))

(put 'bydi-verify--was-called 'ert-explainer 'bydi-explain--wrong-call)
(put 'bydi-verify--was-not-called 'ert-explainer 'bydi-explain--wrong-call)
(put 'bydi-verify--was-called-with 'ert-explainer 'bydi-explain--wrong-call)
(put 'bydi-verify--was-called-n-times 'ert-explainer 'bydi-explain--wrong-call)

(put 'bydi-verify--was-set 'ert-explainer 'bydi-explain--wrong-setting)
(put 'bydi-verify--was-not-set 'ert-explainer 'bydi-explain--wrong-setting)
(put 'bydi-verify--was-set-to 'ert-explainer 'bydi-explain--wrong-setting)
(put 'bydi-verify--was-set-n-times 'ert-explainer 'bydi-explain--wrong-setting)

(put 'bydi-verify--matches 'ert-explainer 'bydi-explain--explain-mismatch)

;;;; API

(defun bydi-clear-mocks ()
  "Clear all mocks.

This will clear the entire history (which is shared by functions
and variables)."
  (clrhash bydi--history))

(defun bydi-clear-mocks-for (symbol)
  "Clear mocks for SYMBOL.

SYMBOL can be the name of a function or a variable."
  (remhash symbol bydi--history))

(defun bydi-toggle-sometimes (&optional no-clear)
  "Toggle all volatile functions.

Unless NO-CLEAR is t, this also calls `bydi-clear-mocks-for' for
all functions."
  (dolist (it (append (bydi--always) (bydi--ignore)))

    (bydi-toggle-volatile it no-clear)))

(defun bydi--always ()
  "Get volatile functions that return t."
  (gethash 'always bydi--volatile))

(defun bydi--ignore ()
  "Get volatile functions that return nil."
  (gethash 'ignore bydi--volatile))

(defun bydi-toggle-volatile (fun &optional no-clear)
  "Toggle volatile FUN.

If this function previously returned t, it will now return nil
and vice versa.

Unless NO-CLEAR is t, this also calls `bydi-clear-mocks' for this
function."
  (cond
   ((memq fun (bydi--always))

    (puthash 'always (delq fun (bydi--always)) bydi--volatile)
    (puthash 'ignore (append (bydi--ignore) (list fun)) bydi--volatile))

   ((memq fun (bydi--ignore))

    (puthash 'always (append (bydi--always) (list fun)) bydi--volatile)
    (puthash 'ignore (delq fun (bydi--ignore)) bydi--volatile)))

  (unless no-clear
    (bydi-clear-mocks-for fun)))

;;;###autoload
(defalias 'bydi 'bydi--mock)

;;;###autoload
(defalias 'bydi-with-mock 'bydi--mock)

(defalias 'bydi-when 'bydi-spy--define-when)

(provide 'bydi)

;;; bydi.el ends here
