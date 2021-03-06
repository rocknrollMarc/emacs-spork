; Run testdrb against the current file or an arbitrary filename via ansi-term
; Relies on spork being already up and running, but will start a new
; ansi-term buffer for you automatically if there is not one already
; (configured by the spork-test-buffer variable)

; TODO: Guess which test to run for a given model/controller/view
;       Run all Unit/Functional/Integration tests
;       Run all tests, via some kind of directory traversing up and back down

(defvar spork-test-buffer "spork-tests"
  "The name of the buffer tests will run in." )
(defvar es-small-stack-trace t
  "Hide .rvm (framework lines) from stack traces if t.
If this is false, you get the entire stack trace, which
include a bunch of garbage lines and really clutter up
the tests. Useless (but shouldn't hurt) if you're not
using RVM.")
(defvar es-colorize t
  "Whether to use grep to colorize the output. testdrb removes
  ansi color codes when it detects its output going to something
  besides a tty (e.g., grep) so we have to re-color afterwards.")
(defvar es-use-emacs-buffer nil
  "Send tests to an ansi-term buffer.")
(defvar es-use-compile nil
  "Send tests to a tmux pane. I've found that output
displays more reliably in a 'real' terminal than it does
in an emacs buffer.")
(defvar es-use-tmux-pane t
  "Send tests to a tmux pane. I've found that output
displays more reliably in a 'real' terminal than it does
in an emacs buffer.")
(defvar es-last-command nil
  "Store the most recent command run so we can redo it." )
(defvar es-tmux-target "1.0"
  "The target session, window, and pane for tmux to send the command to.
Needs to be of a format accepted by tmux send-panes -t <value>

You can find the right argument from tmux by using the list-panes function:

$ tmux list-panes -as

session_name:0.0: [118x65] [history 1/2000, 830 bytes] %11
session_name:0.1: [118x65] [history 266/2000, 109035 bytes] %15 (active)
session_name:1.0: [163x59] [history 5254/100000, 2171915 bytes] %14 (active)
session_name:2.0: [171x52] [history 1943/2000, 937870 bytes] %10 (active)
session_name:3.0: [257x58] [history 1976/2000, 686800 bytes] %9 (active)

I have one tmux session running, called session_name, with 4 windows. Windows
1-3 have only one pane in each, while Window 0 has two panes. To use the
second pane in window 0, I would do

(setq es-tmux-target \"session_name:0.1\")

See `man tmux` for more information.")

;; es-singularize and es-pluralize thanks to:
;; https://github.com/jimm/elisp/blob/master/emacs.el
(defun es-singularize (str)
  "Singularize STR, which is assumed to be a single word. This is
a simple algorithm that may grow over time if needed."
  (interactive "s")
  (let ((len (length str)))
    (cond ((equal "ies" (substring str (- len 3))) (concat (substring str 0 (- len 3)) "y"))
          ((equal "i" (substring str (- len 1))) (concat (substring str 0 (- len 1)) "us"))
          ((equal "s" (substring str (- len 1))) (substring str 0 (- len 1)))
          (t str))))
(defun es-pluralize (str)
  "Pluralize STR, which is assumed to be a single word. This is a
simple algorithm that may grow over time if needed."
  (interactive "s")
  (let ((len (length str)))
    (cond ((equal "y" (substring str (- len 1))) (concat (substring str 0 (- len 1)) "ies"))
          ((equal "us" (substring str (- len 2))) (concat (substring str 0 (- len 2)) "i"))
          (t (concat str "s")))))

; This sw-* stuff is from
;   http://curiousprogrammer.wordpress.com/2009/03/19/emacs-terminal-emulator/
; It takes care of getting ansi-term up and running, and returning to the same
; buffer for subsequent tests.

; sw-basic-shell is modified to open the buffer in another window, so that your
; tests pop up alongside the code.
(defun sw-shell-get-process (buffer-name)
  (let ((buffer (get-buffer (concat "*" buffer-name "*"))))
    (and (buffer-live-p buffer) (get-buffer-process buffer))))

(defun sw-get-process-if-live (buffer-name)
  (let ((proc (sw-shell-get-process buffer-name)))
    (and (processp proc)
         (equal (process-status proc) 'run)
         proc)))

(defun sw-kill-buffer-if-no-process (buffer-name)
  (let* ((buffer (get-buffer (concat "*" buffer-name "*")))
         (proc (sw-get-process-if-live buffer-name)))
    (when (and (not proc) (buffer-live-p buffer)) (kill-buffer buffer))))

(defalias 'sw-shell-exists-p 'sw-get-process-if-live)

(defun sw-basic-shell (buffer-name)
  (sw-kill-buffer-if-no-process buffer-name)
  ;; If there is a process running, leave it, otherwise
  ;; create the new buffer
  (if (sw-shell-exists-p buffer-name)
      (message "Buffer already exists")
    (ansi-term "bash" buffer-name)))

(defun sw-shell/commands (buffer-name &rest commands)
  (sw-basic-shell buffer-name)
  (let ((proc (sw-shell-get-process buffer-name)))
    (dolist (cmd commands)
      (term-simple-send proc "clear")
      (term-simple-send proc cmd))))

(defun es-send-command-somewhere (cmd)
  "Send a command to a terminal. Can either send to
an emacs buffer or to a tmux pane. Stores the command
run for redo functionality."
  (cond (es-use-compile
         (es-send-via-compile cmd))
        (es-use-emacs-buffer
         (sw-shell/commands spork-test-buffer cmd))
        (es-use-tmux-pane
         (es-send-via-tmux cmd))
        (t (message "Set a target for tests to run in.")))
  (setq es-last-command cmd))

(defun es-send-via-compile (cmd)
  "Compile the current command"
  (compile cmd))

(defun es-small-stack-trace-suffix ()
  (cond (es-small-stack-trace " | grep -v .rvm")
        (t "")))

(defun es-colorize-suffix ()
  (cond (es-colorize " | GREP_COLORS='mt=01;32' egrep --color=always 'PASS|' | GREP_COLORS='mt=01;31' egrep --color=always 'ERROR|FAIL|'")
        (t "")))

(defun es-command-suffix ()
  (concat (es-small-stack-trace-suffix) (es-colorize-suffix)))

(defun es-build-command (file-name)
  (concat "testdrb " file-name (es-command-suffix)))

(defun es-test-file (file-name)
  (interactive "FFile:")
  (let ((cmd (es-build-command file-name)))
    (es-send-command-somewhere cmd)))

(defun es-send-via-tmux (command)
  (message (concat "running: " command))
  (call-process "tmux" nil "*scratch*" nil "send-keys" "-t" es-tmux-target command "C-m"))

(defun es-run-ruby-on-file (filename)
  (es-send-via-tmux (concat "ruby " filename)))

(defun es-send-to-tmux (cmd)
  (interactive "MCommand: ")
  (es-send-via-tmux (concat cmd))
  (setq es-last-command cmd))

(defun es-run-ruby-on-current-file ()
  (interactive)
  (es-run-ruby-on-file buffer-file-name))

; (es-send-via-tmux "echo emacs rocks")
(defun es-test-files (filenames)
  (es-test-file (mapconcat 'identity filenames " ")))

(defun es-run-current-file ()
  (interactive)
  (es-test-file buffer-file-name))

(defun es-redo-last-test ()
  (interactive)
  (es-send-command-somewhere es-last-command))

(defun es-run-unit-tests ()
  (interactive)
  (let ((default-directory (es-project-directory)))
    (es-test-files (file-expand-wildcards "*test/unit/*rb"))))
;; (es-run-unit-tests)

(defun es-run-functional-tests ()
  (interactive)
  (let ((default-directory (es-project-directory)))
    (es-test-files (file-expand-wildcards "*test/functional/*rb"))))
;; (es-run-functional-tests)

(defun es-run-data-file-tests ()
  (interactive)
  (let ((default-directory (es-project-directory)))
    (es-test-files (file-expand-wildcards "*test/data_file_parsers/*rb"))))
;; (es-run-data-file-tests)

(defun es-project-directory ()
  "search up from the current directory, looking for a project folder. project
folder being a directory with a folder called test in it."
  (locate-dominating-file default-directory "test"))

(defun es-run-tests-for-current-file ()
  "Run the tests that correspond to the current file.
 Support:
   - Models: app/models/model_name.rb
     Unit,functional,parsers
   - Views: app/views/pluralized_name/thing.erb
   - Controller app/contollers/pluralized_name.rb
   - Test  test/"
  (interactive)
  (cond ((string-match ".*test/\\([^/]*\\)" buffer-file-name)
         (message (concat "Running " buffer-file-name))
         (es-test-file buffer-file-name))
        (t (let ((model (es-model-for-file buffer-file-name)))
          (let ((tests (es-tests-for-model model)))
            (es-test-files tests)
            (message (concat "Running tests for " model
                             ": " (mapconcat 'identity tests ", "))))))))

(defun es-run-unit-test-for-current-file ()
  "Run the unit tests that corresponds to the current file.
 Support:
   - Models: app/models/model_name.rb
     Unit,functional,parsers
   - Views: app/views/pluralized_name/thing.erb
   - Controller app/contollers/pluralized_name.rb"
  (interactive)
  (let ((model (es-model-for-file buffer-file-name)))
    (let ((tests (es-unit-test-for-model model)))
      (es-test-files tests)
      (message (concat "Running unit test for " model
                       ": " (mapconcat 'identity tests ", "))))))

(defun es-run-functional-test-for-current-file ()
  "Run the functional test that corresponds to the current file.
 Support:
   - Models: app/models/model_name.rb
     Unit,functional,parsers
   - Views: app/views/pluralized_name/thing.erb
   - Controller app/contollers/pluralized_name.rb"
  (interactive)
  (let ((model (es-model-for-file buffer-file-name)))
    (let ((tests (es-functional-test-for-model model)))
      (es-test-files tests)
      (message (concat "Running functional test for " model
                       ": " (mapconcat 'identity tests ", "))))))

(defun es-unit-test-for-model (model)
  (let ((default-directory (es-project-directory)))
    (append
     (file-expand-wildcards (concat "test/*/"
                                    (es-singularize model) "_test.rb")))))

(defun es-functional-test-for-model (model)
  (let ((default-directory (es-project-directory)))
    (append
     (file-expand-wildcards (concat "test/functional/"
                                    model "_controller_test.rb"))
     (file-expand-wildcards (concat "test/functional/"
                                    (es-pluralize model)
                                    "_controller_test.rb")))))

(defun es-tests-for-model (model)
  "Return both the unit and functional tests associated with this model"
  (append (es-unit-test-for-model model)
    (es-functional-test-for-model model))
  )
;; (es-functional-test-for-model "sample_list")
;; (es-unit-test-for-model "sample_list")
;; (es-tests-for-model "sample_list")

(defun es-model-for-file (filename)
  "Returns an underscored model name from a path name using rails' conventions"
  (cond ((string-match ".*views/\\([^/]*\\)" filename)
         (es-singularize (match-string 1 filename)))
        ((string-match ".*models.*/\\(.*\\).rb" filename)
         (match-string 1 filename))
        ((string-match ".*controllers/\\(.*\\)_controller.rb" filename)
         (es-singularize (match-string 1 filename)))))
;; (es-model-for-file "app/models/foo.rb")
;; (es-model-for-file "app/views/foos/index.html.erb")
;; (es-model-for-file "app/controllers/foos_controller.rb")

(provide 'emacs-spork)
