
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; MODULE      : text-speech.scm
;; DESCRIPTION : control textual editing via speech
;; COPYRIGHT   : (C) 2022  Joris van der Hoeven
;;
;; This software falls under the GNU general public license version 3 or later.
;; It comes WITHOUT ANY WARRANTY WHATSOEVER. For details, see the file LICENSE
;; in the root directory or <http://www.gnu.org/licenses/gpl-3.0.html>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(texmacs-module (text text-speech)
  (:use (text text-kbd)
        (math math-speech)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Stripping punctuation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (strip-punctuation s)
  (if (and (>= (string-length s) 2)
           (nin? (string-take s 1) (list "." "," ":" ";" "!" "?"))
           (in? (string-take-right s 1) (list "." "," ":" ";" "!" "?")))
      (strip-punctuation (string-drop-right s 1))
      s))

(define (speech-has*? lan type s)
  (speech-has? lan type (strip-punctuation s)))

(define (speech-accepts*? lan type s)
  (speech-accepts? lan type (strip-punctuation s)))

(define (speech-start-accepts*? lan type s)
  (set! s (strip-punctuation s))
  (when (letterized? s)
    (set! s (car (letterized-list s))))
  (speech-border-accepts? lan type s))

(define (speech-end-accepts*? lan type s)
  (set! s (strip-punctuation s))
  (when (letterized? s)
    (set! s (cAr (letterized-list s))))
  (speech-border-accepts? lan type s))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Text with inline mathematical formulas
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (accept-middle? lan l r) #t)

(define (accept-start? lan l r)
  (cond ((< (length r) 1) #f)
        ((and (list-1? l) (letterized? (car l)))
         (accept-start? lan (letterized-list (car l)) r))
        ((and (null? (cdr r))
              (> (string-length (car r)) 1)
              (nin? (string-append "<" (car r) ">") greek-letters)) #f)
        ((and (or (null? l) (null? (cdr l))) (nnull? (cdr r))) #f)
        ((speech-has? lan 'dangerous (car l))
         (and (>= (length l) 2) (>= (length r) 2)
              (let* ((l1 (speech-rewrite lan 'math (car l)))
                     (r1 (car r))
                     (l2 (speech-rewrite lan 'math (cadr l)))
                     (r2 (cadr r)))
                (cond ((in? r1 lowercase-letters)
                       (cond ((!= l1 r1) #f)
                             ((!= l2 r2) #f)
                             ((string-number? (cadr l)) #t)
                             ((speech-has? lan 'number (cadr l)) #t)
                             ((speech-has? lan 'infix (cadr l)) #t)
                             ((speech-has? lan 'postfix (cadr l)) #t)
                             ((speech-has? lan 'prefix-infix (cadr l)) #t)
                             ((speech-has? lan 'separator (cadr l)) #t)
                             (else #f)))
                      (else #f)))))
        (else #t)))

(define (accept-end? lan l r)
  (cond ((< (length r) 1) #f)
        ((and (list-1? l) (letterized? (car l)))
         (accept-end? lan (letterized-list (car l)) r))
        ((in? (cAr l) punctuation-symbols) #f)
        ((in? (string-take-right (cAr l) 1) punctuation-symbols)
         (with h (string-drop-right (cAr l) 1)
           (accept-end? lan (rcons (cDr l) h) (cDr r))))
        ((speech-has? lan 'dangerous (cAr l))
         (and (>= (length l) 2) (>= (length r) 2)
              (let* ((l1 (speech-rewrite lan 'math (cAr l)))
                     (r1 (cAr r))
                     (l2 (speech-rewrite lan 'math (cADr l)))
                     (r2 (cADr r)))
                (cond ((in? r1 lowercase-letters)
                       (cond ((!= l1 r1) #f)
                             ((!= l2 r2) #f)
                             ((speech-has? lan 'infix (cADr l)) #t)
                             ((speech-has? lan 'prefix (cADr l)) #t)
                             ((speech-has? lan 'prefix-infix (cADr l)) #t)
                             ((speech-has? lan 'separator (cADr l)) #t)
                             (else #f)))
                      (else #f)))))
        (else #t)))

(define (text-math-speech* lan pre l post)
  (let* ((s1 (string-recompose pre " "))
         (s2 (string-recompose l " "))
         (s3 (string-recompose post " ")))
    ;;(display* "  Found " s1 " / " s2 " / " s3 "\n")
    (kbd-insert s1)
    (speech-inline 'math)
    (kbd-speech s2)
    (with t (tree-innermost 'math)
      (when t
        (tree-go-to t 0 :end)
        (with prev (before-cursor)
          (if (in? prev punctuation-symbols)
              (begin
                (cut-before-cursor)
                (tree-go-to t :end)
                (insert prev))
              (tree-go-to t :end))))
      (when (!= s3 "")
        (kbd-speech s3)))))

(define (text-math-speech-bis lan pre l punc post)
  (let* ((s (string-recompose l " "))
         (w (speech-rewrite lan 'math s))
         (r (string-decompose w " ")))
    ;;(display* "Try " (string-recompose pre " ")
    ;;          " / " s " / " punc (string-recompose post " ") "\n")
    (cond ((or (null? l) (null? r))
           (text-speech* lan pre post))
          ((speech-has? lan 'math-mode (car l))
           (set! l (cdr l))
           (when (speech-has? lan 'text-mode (cAr l)) (set! l (cDr l)))
           (text-math-speech* lan pre l post))
          ((not (accept-middle? lan l r))
           (text-speech* lan (append pre l) post))
          ((not (accept-start? lan l r))
           (text-math-speech lan (append pre (list (car l))) (cdr l) post))
          ((and (null? (cdr l)) (not (accept-end? lan l r)))
           (text-speech* lan (append pre l) post))
          ((and (null? (cdr l)) (not (speech-recognizes? lan 'math s)))
           (text-speech* lan (append pre l) post))
          ((not (accept-end? lan l r))
           (text-math-speech lan pre (cDr l) (cons (cAr l) post)))
          ((not (speech-recognizes? lan 'math s))
           (text-math-speech lan pre (cDr l) (cons (cAr l) post)))
          ((== punc "") (text-math-speech* lan pre l post))
          (else (text-math-speech* lan pre l (cons punc post))))))

(define (text-math-speech lan pre l post)
  (if (or (null? l) (== (strip-punctuation (cAr l)) (cAr l)))
      (text-math-speech-bis lan pre l "" post)
      (let* ((s (cAr l))
             (s* (strip-punctuation s))
             (punc (string-drop s (string-length s*))))
        (text-math-speech-bis lan pre (rcons (cDr l) s*) punc post))))

(define (longest-math-prefix* lan l)
  (cond ((null? l) l)
        ((letterized? (car l))
         (cons (car l) (longest-math-prefix* lan (cdr l))))
        ((speech-has*? lan 'skip (car l)) (list))
        ((not (speech-accepts*? lan 'math (car l))) (list))
        (else (cons (car l) (longest-math-prefix* lan (cdr l))))))

(define (trim-longest-math-prefix lan l)
  (cond ((null? l) l)
        ((speech-has*? lan 'skip-end (locase-all (cAr l)))
         (trim-longest-math-prefix lan (cDr l)))
        ((speech-end-accepts*? lan 'math (cAr l)) l)
        (else (trim-longest-math-prefix lan (cDr l)))))

(define (speech-until-text lan l)
  (cond ((null? l) l)
        ((speech-has*? lan 'text-mode (car l)) (list (car l)))
        (else (cons (car l) (speech-until-text lan (cdr l))))))

(define (longest-math-prefix lan l)
  (cond ((null? l) l)
        ((speech-has*? lan 'math-mode (car l)) (speech-until-text lan l))
        ((not (speech-start-accepts*? lan 'math (car l))) (list))
        ((speech-has*? lan 'skip-start (locase-all (car l))) (list))
        (else (trim-longest-math-prefix lan (longest-math-prefix* lan l)))))

(define (text-speech* lan h t)
  (if (null? t)
      (when (nnull? h)
        (kbd-insert (string-recompose h " ")))
      (with l (longest-math-prefix lan t)
        (if (null? l)
            (text-speech* lan (rcons h (car t)) (cdr t))
            (with r (sublist t (length l) (length t))
              ;;(display* "Try mathematics " (string-recompose l " ") "\n")
              ;;(debug-message "keyboard-warning"
              ;;               (string-append "Mathematics "
              ;;                              (string-recompose h " ") " / "
              ;;                              (string-recompose l " ") " / "
              ;;                              (string-recompose r " ") "\n"))
              (text-math-speech lan h l r))))))

(define (text-speech s*)
  (let* ((lan (speech-language))
         (s (speech-rewrite lan 'text-hack s*))
         (l (string-decompose s " ")))
    ;;(display* (upcase-first (symbol->string lan))
    ;;          " text speach " (cork->utf8 s) "\n")
    (when (nnull? l)
      (text-speech* lan (list) l))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Customized speech driver routines for text mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (clean-text-speech l)
  (cond ((or (null? l) (null? (cdr l))) l)
        ((and (string-locase? (car l)) (string-upcase? (cadr l)))
         (cons* (car l) " " (clean-text-speech (cdr l))))
        ((and (string-number? (car l)) (string-alpha? (cadr l)))
         (cons* (car l) " " (clean-text-speech (cdr l))))
        ((and (string-alpha? (car l)) (string-number? (cadr l)))
         (cons* (car l) " " (clean-text-speech (cdr l))))
        ((and (== (car l) "+") (string-alpha? (cadr l)))
         (cons* (car l) " " (clean-text-speech (cdr l))))
        ((and (string-alpha? (car l)) (== (cadr l) "+"))
         (cons* (car l) " " (clean-text-speech (cdr l))))
        ((null? (cddr l))
         (cond ((== (car l) " ")
                (cons (car l) (clean-text-speech (cdr l))))
               ((in? (cadr l) (list "+" "-"))
                (cons* (car l) " " (clean-text-speech (cdr l))))
               (else (cons (car l) (clean-text-speech (cdr l))))))
        ((and (== (car l) " ") (== (cadr l) "-") (string-alpha? (caddr l)))
         (cons* " " "-" " " (clean-text-speech (cddr l))))
        ((and (string-alpha? (car l)) (== (cadr l) "-") (== (caddr l) " "))
         (cons* (car l) " " "-" (clean-text-speech (cddr l))))
        (else (cons (car l) (clean-text-speech (cdr l))))))

(define (requires-lowercase? t)
  (and (tree? t)
       (tree-empty? t)
       (tree-ref t :up)
       (tree-in? (tree-ref t :up) '(abbr em name samp strong verbatim))))

(tm-define (kbd-speech S)
  (:mode in-std-text?)
  (:require (not (inside? 'math)))
  ;;(display* "Raw  speech " (cork->utf8 S) "\n")
  (set! S (list->tmstring (clean-text-speech (tmstring->list S))))
  (set! S (string-replace S "a.m." "AM"))
  (set! S (string-replace S "p.m." "PM"))
  ;;(display* "Text speech " (cork->utf8 S) "\n")
  (let* ((prev1 (before-cursor))
         (prev2 (before-before-cursor))
         (prev  (if (== prev1 " ") prev2 prev1))
         (spc?  (!= prev1 " ")))
    (cond ((== S "") (noop))
          ((speech-command S) (noop))
          ((speech-make S) (noop))
          ((in? prev (list "." "!" "?"))
           (when spc? (kbd-space))
           (text-speech S))
          ((in? prev (list "," ":" ";"))
           (when spc? (kbd-space))
           (text-speech (locase-first S)))
          (prev
           (when (and spc? (nin? (string-take S 1)
                                 (list "." "," ":" ";" "!" "?")))
             (kbd-space))
           (text-speech (locase-first S)))
          ((requires-lowercase? (cursor-tree))
           (text-speech (locase-first S)))
          (else (text-speech S)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Further textual speech commands
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(tm-define (speech-inline . args)
  (with prev (before-cursor)
    (when (and prev (!= prev " "))
      (kbd-space))
    (apply make args)))

(tm-define (speech-proof)
  (with-innermost t enunciation-context?
    (tree-go-to t :end))
  (make 'proof))
