(in-package :pq)

;; Unit prefix database ------------------------------------------------------------

(defparameter *unit-prefix-table* (make-hash-table :test 'equal))
(export '*unit-prefix-table*)

(defun define-unit-prefix% (name power &key abbrev (base 10))
  "Defines a unit prefix such as kilo in kilometre. Apart from the name the power is required (3 for kilo) together with the base that defaults to 10. An abbreviation for the prefix is also allowed which will be used in combination with abbreviated units."
  ;; Check inputs
  (unless (symbolp name)
    (error "Unit prefix must be a symbol."))
  (unless (symbolp abbrev)
    (error "Unit prefix abbreviation must be a symbol."))
  (unless (and (integerp base) (plusp base))
    (error "Unit prefix base must be an integer greater than zero."))
  (unless (and (integerp power) (not (zerop power)))
    (error "Unit prefix power must be an integer different from zero."))
  (let ((name-str (symbol-name name)) (abbrev-str (if abbrev (symbol-name abbrev))))
    ;; Check for name conflicts. Names and abbreviations can be treated separately.
    (when (has-key name-str *unit-prefix-table*)
      (error "Unit prefix ~a is already defined." name-str))
    (when abbrev-str
      (loop for v being the hash-values of *unit-prefix-table* when (string= abbrev-str (third v)) do
           (error "Unit prefix ~a is already defined." abbrev-str)))
    ;; Add the prefixes to the hash table
    (setf (gethash name-str *unit-prefix-table*) (list base power abbrev-str))
    ;; FIXME: add prefixes to existing units
    ))

(defmacro define-unit-prefix (name power &key abbrev (base 10))
  `(define-unit-prefix% ',name ,power :abbrev ',abbrev :base ,base))
(export 'define-unit-prefix)

;; Unit prefix composition functions -----------------------------------------------

(defun prefix-and (&rest functions)
  (lambda (base power)
    (loop for f in functions always (funcall f base power))))

(defun prefix-or (&rest functions)
  (lambda (base power)
    (loop for f in functions thereis (funcall f base power))))

(defun prefix-range (base power-min power-max)
  (lambda (b p)
    (and (= b base) (or (not power-min) (>= p power-min)) (or (not power-max) (<= p power-max)))))

(defun prefix-list (base &rest powers)
  (lambda (b p)
    (and (= b base) (have p powers))))

(defun prefix-base (base &optional mod)
  (lambda (b p)
    (and (= b base) (or (not mod) (zerop (rem p mod))))))

;; FIXME: create a macro that defines a language for defining prefixes validation functions

;; Unit database -------------------------------------------------------------------

(defparameter *unit-translation-table* (make-hash-table :test 'equal))
(defparameter *unit-alias-table* (make-hash-table :test 'equal))
(defparameter *unit-abbreviation-table* (make-hash-table :test 'equal))
(export '(*unit-translation-table* *unit-alias-table* *unit-abbreviation-table*))

(defun clear-units ()
  (setf *unit-prefix-table* (make-hash-table :test 'equal))
  (setf *unit-translation-table* (make-hash-table :test 'equal))
  (setf *unit-alias-table* (make-hash-table :test 'equal))
  (setf *unit-abbreviation-table* (make-hash-table :test 'equal)))

(defun table-insert (name aliases abbrevs def)
  ;; Set main entry
  (setf (gethash (symbol-name name) *unit-translation-table*) def)
  ;; Set aliases
  (loop for alias in (mklist aliases) do
       (setf (gethash (symbol-name alias) *unit-alias-table*) (symbol-name name)))
  ;; Set abbreviations
  (loop for abbrev in (mklist abbrevs) do
       (setf (gethash (symbol-name abbrev) *unit-abbreviation-table*) (symbol-name name))))

(defun has-key (key hash-table)
  (second (multiple-value-list (gethash key hash-table))))

(defun unit-hash-key-check (key)
  (or (has-key (symbol-name key) *unit-translation-table*)
      (has-key (symbol-name key) *unit-alias-table*)
      (has-key (symbol-name key) *unit-abbreviation-table*)))

(defun table-check (name aliases abbrevs)
  (when (unit-hash-key-check name)
    (error "Unit ~a is already defined." name))
  (loop for alias in (mklist aliases)
     when (unit-hash-key-check alias)
     do (error "Unit ~a is already defined." alias))
  (loop for abbrev in (mklist abbrevs)
     when (unit-hash-key-check abbrev)
     do (error "Unit ~a is already defined." abbrev)))

(defun symbol-prefix (prefix symbols)
  (mapcar #'(lambda (x) (symb prefix x)) (mklist symbols)))

(defun define-unit% (name &key def aliases abbreviations prefix-test overwrite)
  "Defines a new unit with the identifier name. A list of aliases and a list of abbreviations are permitted which - when encountered - are internally converted to the primary identifier. The definition allows the unit to be defined in terms of other units, e.g :def (1.602 kilometre). Prefixes is must be a function of two parameters, the base and the power, with which it decides whether a prefix is allowed for the unit. It defaults to allowing all defined prefixes."
  ;; FIXME: the prefix test needs to be stored to allow new prefixes to be defined after defining the unit.
  ;; First pass to check for conflicts
  (unless overwrite
    ;; Check principal entry
    (table-check name aliases abbreviations)
    ;; Iterate over all prefixes
    (loop for prefix being the hash-keys of *unit-prefix-table* using (hash-value prefix-value)
       ;; Define the hash keys
       for name-key = (symb prefix name)
       for alias-keys = (symbol-prefix prefix aliases)
       for abbrev-keys = (symbol-prefix (third prefix-value) abbreviations)
       when (or (not prefix-test) (funcall prefix-test (first prefix-value) (second prefix-value))) do
         (table-check name-key alias-keys abbrev-keys)))
  ;; Second pass to insert the values
  (table-insert name aliases abbreviations def)
  (loop for prefix being the hash-keys of *unit-prefix-table* using (hash-value prefix-value)
     ;; Define the hash keys
     for name-key = (symb prefix name)
     for alias-keys = (symbol-prefix prefix aliases)
     for abbrev-keys = (symbol-prefix (third prefix-value) abbreviations)
     when (or (not prefix-test) (funcall prefix-test (first prefix-value) (second prefix-value))) do
       (table-insert name-key alias-keys abbrev-keys (if (zerop (second prefix-value)) def (list (expt (first prefix-value) (second prefix-value)) (list (make-uf (symbol-name name) 1)))))))

(defmacro define-unit (name &key def alias abbrev prefix-test overwrite)
  `(define-unit% ',name :def (list ,@(parseq 'unit-definition def)) :aliases ',alias :abbreviations ',abbrev :prefix-test ,prefix-test :overwrite ,overwrite))
(export 'define-unit)

(defun lookup-unit (unit)
  ;; Search the translation table directly
  (multiple-value-bind (result found) (gethash unit *unit-translation-table*)
    (if found
        (values unit result)
        ;; Not found, search the alias table instead
        (multiple-value-bind (result found) (gethash unit *unit-alias-table*)
          (if found
              (lookup-unit result)
              ;; Still not found, search the abbreviation table instead
              (multiple-value-bind (result found) (gethash unit *unit-abbreviation-table*)
                (if found
                    (lookup-unit result)
                    (error "Unknown unit ~a!" unit))))))))

(defmacro with-unit-lookup ((base-unit translation unit) &body body)
  `(multiple-value-bind (,base-unit ,translation) (lookup-unit ,unit)
     ,@body))

;; Unit interface ------------------------------------------------------------------

(defun make-unit (&rest unit-factors)
  (loop for uf in unit-factors collect
       (cond
         ((unit-factor-p uf) uf)
         ((and (listp uf) (l= uf 2) (stringp (first uf)) (integerp (second uf))) (make-uf (lookup-unit (first uf)) (second uf)))
         ((and (listp uf) (l= uf 2) (symbolp (first uf)) (integerp (second uf))) (make-uf (lookup-unit (symbol-name (first uf))) (second uf)))
         (t (error "Invalid unit factor specified.")))))
(export 'make-unit)

(defun unitp (object)
  (and (listp object) (every #'unit-factor-p object)))
(export 'unitp)

(defun has-unit-p (quantity)
  "Checks whether the given quantity has a unit."
  (consp (expand-unit (unit quantity))))

(defun unitlessp (quantity)
  "Checks whether the given quantity is unitless."
  (not (has-unit-p quantity)))

;; Unit expansion ------------------------------------------------------------------

(defun collect-factors (f &rest expanded-unit-factors)
  ;; Each of the expanded-unit-factors is a list (conv () () ())
  (destructuring-bind (conv units)
      (loop for factor in expanded-unit-factors
         collect (first factor) into conv-factors
         append (rest factor) into unit-factors
         finally (return (list conv-factors unit-factors)))
    `(,(apply #'* f conv) ,@units)))

(defun reduce-unit (unit)
  ;; Reduces the powers of duplicate unit factors in a given unit, e.g. km^2 / km -> km, but m / km -> m / km. No unit lookup is made.
  (if (l> unit 1)
      ;; Split the list of unit factors into those that have the same unit as the first one and those that do not
      (let* ((name (uf-unit (first unit)))
             (split (split #'(lambda (x) (equal x name)) unit :key #'uf-unit)))
        ;; Sum the powers of the first set
        (let ((sum (loop for item in (first split) summing (uf-power item))))
          ;; Append the resulting unit-factor
          (append (if (/= 0 sum) (list (make-uf name sum))) (reduce-unit (second split)))))
      ;; Only one unit factor. Keep everything as is.
      unit))

(defun expand-unit-factor (factor)
  ;; Converts a single unit factor into its expansion of base units, together with a conversion factor
  ;; Query the unit translation table
  (with-unit-lookup (base expansion (uf-unit factor))
    ;; When expansion is nil the unit is a base unit
    (if expansion
        ;; Not a base unit
        (destructuring-bind (conv unit-factors) expansion
          ;; Expand the unit collecting all conversion factors
          (apply #'collect-factors (expt conv (uf-power factor))
                 (loop for uf in unit-factors collect (expand-unit-factor (uf-pow uf (uf-power factor))))))
        ;; Base unit, no recursion
        (list 1 (make-uf base (uf-power factor))))))

(defun expand-unit (unit)
  ;; Expands the given unit into base units and reduces them
  (destructuring-bind (conv &rest unit-factors)
      (apply #'collect-factors 1 (loop for factor in unit collect (expand-unit-factor factor)))
    (values (reduce-unit unit-factors) conv)))

(defun dereference-unit (unit)
  ;; Takes a unit and looks up aliases and abbreviations of unit factors and replaces them with the base unit.
  (loop for uf in unit collect (make-uf (lookup-unit (uf-unit uf)) (uf-power uf))))

(defun units-equal (unit-a unit-b)
  ;; Reduces both units and compares the unit factors for equality (in unit and power)
  (let ((a (reduce-unit unit-a)) (b (reduce-unit unit-b)))
    (when (ll= a b)
      (loop for uf-a in a always
           (have uf-a b :test #'uf-equal)))))

(defgeneric convert-unit% (value unit-a &optional unit-b))
(defmethod convert-unit% ((value number) unit-a &optional unit-b)
  (multiple-value-bind (base-unit-a conv-a) (expand-unit unit-a)
    (multiple-value-bind (base-unit-b conv-b) (expand-unit unit-b)
      (unless (units-equal base-unit-a base-unit-b)
        (error "Cannot convert unit ~a into ~a (base units: ~a -> ~a)!" (print-unit unit-a) (print-unit unit-b) base-unit-a base-unit-b))
      (/ (* value conv-a) conv-b))))
(defmethod convert-unit% ((q quantity) unit-a &optional unit-b)
  (when unit-b
    (error (format nil "Overdefined unit conversion!")))
  (multiple-value-bind (base-unit-a conv-a) (expand-unit (unit q))
    (multiple-value-bind (base-unit-b conv-b) (expand-unit unit-a)
      (unless (units-equal base-unit-a base-unit-b)
        (error "Cannot convert unit ~a into ~a (base units: ~a -> ~a)!" (print-unit (unit q)) (print-unit unit-a) base-unit-a base-unit-b))
      (make-quantity% :value (/ (* (value q) conv-a) conv-b) :error (if (minusp (error-direct q)) (error-direct q) (/ (* (error-direct q) conv-a) conv-b)) :unit unit-a))))

(defun convert-unit (quantity unit)
  (unless (quantityp quantity)
    (error "Quantity must be of type quantity."))
  (convert-unit% quantity (if (unitp unit) unit (apply #'make-unit unit))))
(export 'convert-unit)

(defun power-unit (unit power)
  (loop for uf in unit collect (uf-pow uf power)))

(defun multiply-units (&rest units)
  (reduce-unit (apply #'append units)))

(defun divide-units (&rest units)
  (if (l> units 1)
      (reduce-unit (append (first units) (apply #'append (mapcar #'(lambda (x) (power-unit x -1)) (rest units)))))
      (power-unit (first units) -1)))

(defun root-unit (unit index)
  (loop for uf in unit
     when (zerop (rem (uf-power uf) index))
     collect (make-uf (uf-unit uf) (/ (uf-power uf) index))
     else
     do (error (format nil "Cannot extract the ~:r root of the unit ~a!" index unit))))

(defun sort-unit (unit)
  (stable-sort unit #'(lambda (a b) (and (not (minusp a)) (minusp b))) :key #'uf-power))

(defun print-unit (unit)
  ;; Prints the given unit in human readable form
  (if unit
      ;; List of unit factors is not empty
      (with-output-to-string (stream)
        ;; Loop over the unit factors
        (loop
           for uf in (sort-unit (copy-tree unit))
           for i upfrom 0
           ;; Insert a space unless it's before the first unit factor
           when (plusp i) do (format stream " ")
           do
             (cond
               ((and (minusp (uf-power uf)) (= (uf-power uf) -1)) (format stream "/ ~a" (uf-unit uf)))
               ((and (minusp (uf-power uf)) (< (uf-power uf) -1)) (format stream "/ ~a ^ ~a" (uf-unit uf) (- (uf-power uf))))
               ((= (uf-power uf) 1) (format stream "~a" (uf-unit uf)))
               (t (format stream "~a ^ ~a" (uf-unit uf) (uf-power uf))))))
      ;; List of unit factors is empty, therefore unit 1
      "1"))
