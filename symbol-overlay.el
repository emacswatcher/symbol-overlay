;;; symbol-overlay.el --- Highlighting symbols with keymap-enabled overlays

;; Copyright (C) 2017 wolray

;; Author: wolray <wolray@foxmail.com>
;; Version: 2.1
;; URL: https://github.com/wolray/symbol-overlay/
;; Keywords: faces, matching
;; Package-Requires: ((emacs "24.3"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Highlighting symbols with overlays while providing a keymap for various
;; operations about highlighted symbols.  It was originally inspired by the
;; package `highlight-symbol'.  The fundamental difference is that in
;; `symbol-overlay' every symbol is highlighted by the Emacs built-in function
;; `overlay-put' rather than the `font-lock' mechanism used in
;; `highlight-symbol'.

;; Advantages

;; In `symbol-overlay', `overlay-put' is much faster than the traditional
;; highlighting method `font-lock' especially in a large buffer, or even a
;; less-than-100-lines small buffer of major-mode with complicated keywords
;; syntax,like haskell-mode.  Besides, all the overlays of each symbol are
;; sequentially stored in an alist `symbol-overlay-keywords-alist', from which
;; the number of occurrences can be immediately obtained.  While in
;; `highlight-symbol', counting the number occurrences would call the function
;; `how-many' twice, causing extra costs.

;; When highlighting symbols with overlays, **an auto-activated overlay-inside
;; keymap** will enable you to call various useful commands with **a single
;; keystroke**.

;; Toggle overlays of all occurrences of symbol at point: `symbol-overlay-put'
;; Remove all highlighted symbols in the buffer: `symbol-overlay-remove-all'
;; Jump between locations of symbol at point: `symbol-overlay-jump-next' &
;; `symbol-overlay-jump-prev'
;; Jump to the definition of symbol at point: `symbol-overlay-jump-to-definition'
;; Switch to the closest symbol highlighted nearby:
;; `symbol-overlay-switch-forward' & `symbol-overlay-switch-backward'
;; Query replace symbol at point: `symbol-overlay-query-replace'
;; Rename symbol at point on all its occurrences: `symbol-overlay-rename'

;; Usage

;; To use `symbol-overlay' in your Emacs, you need only to bind three keys:
;; (require 'symbol-overlay)
;; (global-set-key (kbd "M-i") 'symbol-overlay-put)
;; (global-set-key (kbd "M-u") 'symbol-overlay-switch-backward)
;; (global-set-key (kbd "M-o") 'symbol-overlay-switch-forward)

;; Default key-bindings are defined in `symbol-overlay-map'.
;; You can re-bind the commands to any keys you prefer by simply writing
;; (define-key symbol-overlay-map (kbd "your-prefer-key") 'any-command)

;;; Code:

(require 'thingatpt)
(require 'cl-lib)
(require 'seq)

(defvar symbol-overlay-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "i") 'symbol-overlay-put)
    (define-key map (kbd "u") 'symbol-overlay-jump-prev)
    (define-key map (kbd "o") 'symbol-overlay-jump-next)
    (define-key map (kbd "k") 'symbol-overlay-remove-all)
    (define-key map (kbd "e") 'symbol-overlay-echo-mark)
    (define-key map (kbd "d") 'symbol-overlay-jump-to-definition)
    (define-key map (kbd "q") 'symbol-overlay-query-replace)
    (define-key map (kbd "n") 'symbol-overlay-rename)
    map)
  "Keymap automatically activated inside overlays.
You can re-bind the commands to any keys you prefer.")

(defvar symbol-overlay-keywords-alist)
(make-variable-buffer-local 'symbol-overlay-keywords-alist)

(defvar symbol-overlay-colors '("dodger blue"
				"hot pink"
				"orange"
				"orchid"
				"red"
				"salmon"
				"spring green"
				"turquoise")
  "Colors used for overlays' background.
You can add more colors whatever you like.")

(defvar symbol-overlay-mark nil
  "A mark used for jumping back to the point saved befored.")
(make-variable-buffer-local 'symbol-overlay-mark)

(defun symbol-overlay-get-symbol (&optional str noerror)
  "Get the symbol at point, if none, return nil.
If STR is non-nil, `regexp-quote' STR rather than the symbol.
If NOERROR is non-nil, just return nil when symbol is not found."
  (let ((symbol (or str (thing-at-point 'symbol))))
    (if symbol (concat "\\_<" (regexp-quote symbol) "\\_>")
      (unless noerror (user-error "No symbol at point")))))

(defun symbol-overlay-assoc (symbol &optional noerror)
  "Get SYMBOL's associated list in `symbol-overlay-keywords-alist'.
If NOERROR is non-nil, just return nil when keyword is not found."
  (let ((keyword (assoc symbol symbol-overlay-keywords-alist)))
    (if keyword keyword
      (unless noerror (user-error "Symbol is not highlighted")))))

(defun symbol-overlay-remove (keyword)
  "Delete the KEYWORD list and all its overlays."
  (let ((index (cadr keyword)))
    (mapc 'delete-overlay (cddr keyword))
    (setq symbol-overlay-keywords-alist
	  (delq keyword symbol-overlay-keywords-alist))
    index))

(defun symbol-overlay-put-overlay (symbol &optional keyword)
  "Put overlay to all occurrences of SYMBOL in the buffer.
The background color is randomly picked from `symbol-overlay-colors'.
If KEYWORD is non-nil, remove it first then use its color on new overlays."
  (let* ((case-fold-search nil)
	 (limit (length symbol-overlay-colors))
	 (index (if keyword (symbol-overlay-remove keyword) (random limit)))
	 (indexes (mapcar 'cadr symbol-overlay-keywords-alist))
	 color face overlay p)
    (if (< (length symbol-overlay-keywords-alist) limit)
	(while (cl-find index indexes) (setq index (random limit)))
      (let ((the-oldest (car (last symbol-overlay-keywords-alist))))
	(setq index (symbol-overlay-remove the-oldest))))
    (setq keyword `(,symbol ,index)
	  color (elt symbol-overlay-colors index)
	  face `((foreground-color . "black")
		 (background-color . ,color)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward symbol nil t)
	(or p (setq p t))
	(setq overlay (make-overlay (match-beginning 0) (match-end 0))
	      keyword (append keyword `(,overlay)))
	(overlay-put overlay 'face face)
	(overlay-put overlay 'keymap symbol-overlay-map)))
    (when p
      (push keyword symbol-overlay-keywords-alist)
      (and (looking-at-p "\\_>") (backward-char)))
    color))

(defun symbol-overlay-count (symbol &optional color-msg)
  "Show the number of occurrences of SYMBOL.
If COLOR-MSG is non-nil, add the color used by current overlay in brackets."
  (let ((keyword (symbol-overlay-assoc symbol t))
	(overlay (car (overlays-at (point)))))
    (when keyword
      (message (concat (substring symbol 3 -3) ": %d/%d"
		       (and (stringp color-msg) (concat " (" color-msg ")")))
	       (- (cl-position overlay keyword) 1)
	       (- (length keyword) 2))
      keyword)))

(defun symbol-overlay-refresh-maybe (symbol)
  "Refresh SYMBOL if its overlays are not in the correct places."
  (when symbol
    (let* ((bounds (bounds-of-thing-at-point 'symbol))
	   (overlay-list (overlays-at (car bounds)))
	   (keyword (symbol-overlay-assoc symbol t))
	   find any refresh)
      (if overlay-list
	  (dolist (overlay overlay-list)
	    (unless (and keyword (setq find (cl-find overlay keyword)))
	      (setq any
		    (cl-find-if 'identity
				(mapcar
				 #'(lambda (kw) (and (cl-find overlay kw) kw))
				 symbol-overlay-keywords-alist)))
	      (and any (symbol-overlay-put-overlay (car any) any)))
	    (and keyword
		 (not (and find
			   (= (car bounds) (overlay-start overlay))
			   (= (cdr bounds) (overlay-end overlay))))
		 (setq refresh t)))
	(and keyword (setq refresh t)))
      (and refresh (symbol-overlay-put-overlay symbol keyword)))))

;;;###autoload
(defun symbol-overlay-put ()
  "Toggle overlays of all occurrences of symbol at point."
  (interactive)
  (unless (minibufferp)
    (let ((symbol (symbol-overlay-get-symbol))
	  keyword)
      (unless (symbol-overlay-refresh-maybe symbol)
	(setq keyword (symbol-overlay-assoc symbol t))
	(if keyword (symbol-overlay-remove keyword)
	  (symbol-overlay-count symbol (symbol-overlay-put-overlay symbol)))))))

;;;###autoload
(defun symbol-overlay-remove-all ()
  "Remove all highlighted symbols in the buffer."
  (interactive)
  (unless (minibufferp)
    (mapc 'symbol-overlay-remove symbol-overlay-keywords-alist)))

;;;###autoload
(defun symbol-overlay-echo-mark ()
  "Jump back to the mark `symbol-overlay-mark'."
  (interactive)
  (symbol-overlay-refresh-maybe (symbol-overlay-get-symbol))
  (and symbol-overlay-mark (goto-char symbol-overlay-mark)))

(defun symbol-overlay-jump-call (jump-function dir)
  "A general jumping process during which JUMP-FUNCTION is called to jump.
DIR must be 1 or -1."
  (unless (minibufferp)
    (let ((symbol (symbol-overlay-get-symbol))
	  keyword overlay last restart this length)
      (symbol-overlay-refresh-maybe symbol)
      (setq keyword (symbol-overlay-assoc symbol)
	    overlay (car (overlays-at (point)))
	    last (- (cl-position overlay keyword) 1)
	    symbol-overlay-mark (point)
	    restart (funcall jump-function symbol dir))
      (symbol-overlay-refresh-maybe symbol)
      (setq keyword (symbol-overlay-assoc symbol)
	    overlay (car (overlays-at (point)))
	    this (- (cl-position overlay keyword) 1)
	    length (- (length keyword) 2))
      (when restart
	(or (and (= restart 1) (= last length))
	    (and (= restart -1) (= last 1))
	    (and (= restart 0) (= (- this last) dir))
	    (symbol-overlay-put-overlay symbol keyword)))
      (symbol-overlay-count symbol))))

(defun symbol-overlay-basic-jump (symbol dir)
  "Jump to SYMBOL's next location in the direction DIR.  DIR must be 1 or -1."
  (let* ((case-fold-search nil)
	 (bounds (bounds-of-thing-at-point 'symbol))
	 (offset (- (point) (if (> dir 0) (cdr bounds) (car bounds))))
	 restart target)
    (goto-char (- (point) offset))
    (setq target (re-search-forward symbol nil t dir))
    (unless target
      (goto-char (if (> dir 0) (point-min) (point-max)))
      (setq target (re-search-forward symbol nil nil dir)
	    restart dir))
    (goto-char (+ target offset))
    (or restart 0)))

;;;###autoload
(defun symbol-overlay-jump-next ()
  "Jump to the next location of symbol at point."
  (interactive)
  (symbol-overlay-jump-call 'symbol-overlay-basic-jump 1))

;;;###autoload
(defun symbol-overlay-jump-prev ()
  "Jump to the previous location of symbol at point."
  (interactive)
  (symbol-overlay-jump-call 'symbol-overlay-basic-jump -1))

(defvar symbol-overlay-definition-function
  '(lambda (symbol) (concat "(?def[a-z-]* " symbol))
  "It must be an one-argument lambda function that returns a regexp.")
(make-variable-buffer-local 'symbol-overlay-definition-function)

;;;###autoload
(defun symbol-overlay-jump-to-definition ()
  "Jump to the definition of symbol at point.
The definition syntax should be defined in a lambda function stored in
`symbol-overlay-definition-function' that will return the definition's regexp
with the input symbol."
  (interactive)
  (symbol-overlay-jump-call
   '(lambda (symbol dir)
      (let ((p t) (pt (point)))
	(symbol-overlay-basic-jump symbol dir)
	(while (and p (not (save-excursion
			     (beginning-of-line)
			     (skip-chars-forward " \t")
			     (looking-at-p
			      (funcall symbol-overlay-definition-function
				       symbol)))))
	  (symbol-overlay-basic-jump symbol dir)
	  (and (= pt (point)) (setq p nil)))))
   1))

(defun symbol-overlay-switch-symbol (dir)
  "Switch to the closest symbol highlighted nearby, in the direction DIR.
DIR must be 1 or -1."
  (unless (minibufferp)
    (let ((symbol (symbol-overlay-get-symbol nil t))
	  (pt (point))
	  keyword others positions)
      (symbol-overlay-refresh-maybe symbol)
      (setq keyword (symbol-overlay-assoc symbol t)
	    others (remq keyword symbol-overlay-keywords-alist)
	    positions
	    (apply 'append
		   (mapcar
		    #'(lambda (list)
			(seq-filter '(lambda (x) (> (* dir (- x pt)) 0))
				    (mapcar 'overlay-start list)))
		    (mapcar 'cddr others))))
      (unless positions
	(user-error (concat "No more "
			    (if (> dir 0) "forward" "backward")
			    " symbols")))
      (setq symbol-overlay-mark (point))
      (goto-char (funcall (if (> dir 0) 'seq-min 'seq-max) positions))
      (setq symbol (symbol-overlay-get-symbol nil t))
      (symbol-overlay-refresh-maybe symbol)
      (unless (symbol-overlay-count symbol)
	(symbol-overlay-switch-symbol dir)))))

;;;###autoload
(defun symbol-overlay-switch-forward ()
  "Switch forward to another symbol."
  (interactive)
  (symbol-overlay-switch-symbol 1))

;;;###autoload
(defun symbol-overlay-switch-backward ()
  "Switch backward to another symbol."
  (interactive)
  (symbol-overlay-switch-symbol -1))

(defun symbol-overlay-replace-call (replace-function &optional count)
  "Replace symbol using REPLACE-FUNCTION.
If COUNT is non-nil, count at the end."
  (unless (minibufferp)
    (let* ((symbol (symbol-overlay-get-symbol))
	   (new (substring symbol 3 -3))
	   keyword conflict)
      (symbol-overlay-refresh-maybe symbol)
      (setq keyword (symbol-overlay-assoc symbol))
      (beginning-of-thing 'symbol)
      (setq symbol-overlay-mark (point)
	    new (funcall replace-function symbol new)
	    conflict (symbol-overlay-assoc new t))
      (and conflict (symbol-overlay-remove conflict))
      (symbol-overlay-put-overlay new keyword)
      (and count (symbol-overlay-count new)))))

;;;###autoload
(defun symbol-overlay-query-replace ()
  "Query replace symbol at point."
  (interactive)
  (symbol-overlay-replace-call
   '(lambda (symbol new)
      (let (defaults)
	(setq new (read-string "Replacement: " new)
	      defaults (cons symbol new))
	(query-replace-regexp symbol new)
	(setq query-replace-defaults
	      (if (< emacs-major-version 25) `,defaults `(,defaults)))
	(symbol-overlay-get-symbol new)))))

;;;###autoload
(defun symbol-overlay-rename ()
  "Rename symbol at point on all its occurrences."
  (interactive)
  (symbol-overlay-replace-call
   '(lambda (symbol new)
      (setq new (read-string (format "Rename (%s): " new) new))
      (save-excursion
	(goto-char (point-min))
	(while (re-search-forward symbol nil t)
	  (replace-match new)))
      (symbol-overlay-get-symbol new))
   t))

(provide 'symbol-overlay)

;;; symbol-overlay.el ends here
