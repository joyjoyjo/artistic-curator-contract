;; Artistic Curator Smart Contract
;; This smart contract provides a comprehensive management system for unique digital collectibles.
;; It enables authorized user control, validation mechanisms, and comprehensive metadata management
;; while ensuring proper governance of collectible attributes including naming, dimensions, and classifications.


;; -----------------------------
;; Primary Storage Structures
;; -----------------------------
;; Tracks the cumulative count of registered items
(define-data-var item-counter uint u0)

;; Primary repository for collectible metadata
(define-map collectible-repository
  { item-identifier: uint }  ;; Unique identifier for each collectible
  {
    name: (string-ascii 64),            ;; Collectible official name
    originator: principal,              ;; Registered originator of the collectible
    dimensions: uint,                   ;; Collectible dimensional specifications
    registration-block: uint,           ;; Blockchain height at registration time
    narrative: (string-ascii 128),      ;; Extended information about the collectible
    classifications: (list 10 (string-ascii 32))  ;; Categorical classifications
  }
)


;; -----------------------------
;; Global Configuration Constants
;; -----------------------------
;; The system administrator (established during deployment)
(define-constant SYSTEM-ADMINISTRATOR tx-sender)

;; System Status Codes
(define-constant STATUS-ITEM-MISSING (err u301))              ;; Item requested does not exist in records
(define-constant STATUS-ITEM-ALREADY-EXISTS (err u302))       ;; Attempt to register an existing item
(define-constant STATUS-INVALID-NAMING (err u303))            ;; Item name doesn't meet format requirements
(define-constant STATUS-INVALID-DIMENSIONS (err u304))        ;; Item dimensions outside acceptable range
(define-constant STATUS-PERMISSION-DENIED (err u305))         ;; User lacks required permissions
(define-constant STATUS-INVALID-DESTINATION (err u306))       ;; Transfer destination is invalid
(define-constant STATUS-ADMIN-RESTRICTED (err u307))          ;; Operation limited to system administrator
(define-constant STATUS-ACCESS-VIOLATION (err u308))          ;; User does not have viewing permissions

;; Permission management for item viewing and interaction
(define-map permission-registry
  { item-identifier: uint, viewer: principal }  ;; Item and viewer pairing
  { permission-granted: bool }                  ;; Indicates whether viewing is permitted
)

;; -----------------------------
;; Utility Functions
;; -----------------------------

;; Validates text field lengths against minimum and maximum constraints
(define-private (validate-text-length (text-field (string-ascii 64)) (minimum-length uint) (maximum-length uint))
  (and 
    (>= (len text-field) minimum-length)
    (<= (len text-field) maximum-length)
  )
)

;; Manages the incrementation of the item counter
(define-private (increment-item-counter)
  (let ((current-value (var-get item-counter)))
    (var-set item-counter (+ current-value u1))
    (ok current-value)
  )
)

;; Determines if a collectible exists in the repository
(define-private (collectible-registered? (item-identifier uint))
  (is-some (map-get? collectible-repository { item-identifier: item-identifier }))
)

;; Verifies if user is the registered originator of a collectible
(define-private (is-originator? (item-identifier uint) (user principal))
  (match (map-get? collectible-repository { item-identifier: item-identifier })
    collectible-data (is-eq (get originator collectible-data) user)
    false
  )
)

;; Retrieves dimensional specifications of a collectible
(define-private (get-collectible-dimensions (item-identifier uint))
  (default-to u0 
    (get dimensions 
      (map-get? collectible-repository { item-identifier: item-identifier })
    )
  )
)

;; Validates a single classification tag format
(define-private (is-classification-valid? (classification (string-ascii 32)))
  (and 
    (> (len classification) u0)     ;; Must contain at least one character
    (< (len classification) u33)    ;; Must not exceed 32 characters
  )
)

;; Validates the entire set of classification tags
(define-private (are-classifications-valid? (classifications (list 10 (string-ascii 32))))
  (and
    (> (len classifications) u0)                 ;; At least one classification required
    (<= (len classifications) u10)               ;; Maximum 10 classifications allowed
    (is-eq (len (filter is-classification-valid? classifications)) (len classifications))  ;; All must meet format requirements
  )
)

;; -----------------------------
;; Public Interface Functions
;; -----------------------------

;; Transfer originator rights to another user
(define-public (transfer-originator-rights (item-identifier uint) (new-originator principal))
  (let
    (
      (collectible-data (unwrap! (map-get? collectible-repository { item-identifier: item-identifier }) STATUS-ITEM-MISSING))
    )
    (asserts! (collectible-registered? item-identifier) STATUS-ITEM-MISSING)
    (asserts! (is-eq (get originator collectible-data) tx-sender) STATUS-PERMISSION-DENIED)

    ;; Update repository with new originator information
    (map-set collectible-repository
      { item-identifier: item-identifier }
      (merge collectible-data { originator: new-originator })
    )
    (ok true)
  )
)

;; Update collectible metadata
(define-public (modify-collectible (item-identifier uint) (updated-name (string-ascii 64)) (updated-dimensions uint) (updated-narrative (string-ascii 128)) (updated-classifications (list 10 (string-ascii 32))))
  (let
    (
      (collectible-data (unwrap! (map-get? collectible-repository { item-identifier: item-identifier }) STATUS-ITEM-MISSING))
    )
    ;; Validation sequence
    (asserts! (collectible-registered? item-identifier) STATUS-ITEM-MISSING)
    (asserts! (is-eq (get originator collectible-data) tx-sender) STATUS-PERMISSION-DENIED)
    (asserts! (and (> (len updated-name) u0) (< (len updated-name) u65)) STATUS-INVALID-NAMING)
    (asserts! (and (> updated-dimensions u0) (< updated-dimensions u1000000000)) STATUS-INVALID-DIMENSIONS)
    (asserts! (and (> (len updated-narrative) u0) (< (len updated-narrative) u129)) STATUS-INVALID-NAMING)
    (asserts! (are-classifications-valid? updated-classifications) STATUS-INVALID-NAMING)

    ;; Update repository with modified metadata
    (map-set collectible-repository
      { item-identifier: item-identifier }
      (merge collectible-data { 
        name: updated-name, 
        dimensions: updated-dimensions, 
        narrative: updated-narrative, 
        classifications: updated-classifications 
      })
    )
    (ok true)
  )
)

;; Register a new collectible item
(define-public (register-collectible (name (string-ascii 64)) (dimensions uint) (narrative (string-ascii 128)) (classifications (list 10 (string-ascii 32))))
  (let
    (
      (new-identifier (+ (var-get item-counter) u1))  ;; Generate sequential identifier
    )
    ;; Input validation sequence
    (asserts! (and (> (len name) u0) (< (len name) u65)) STATUS-INVALID-NAMING)
    (asserts! (and (> dimensions u0) (< dimensions u1000000000)) STATUS-INVALID-DIMENSIONS)
    (asserts! (and (> (len narrative) u0) (< (len narrative) u129)) STATUS-INVALID-NAMING)
    (asserts! (are-classifications-valid? classifications) STATUS-INVALID-NAMING)

    ;; Create new repository entry
    (map-insert collectible-repository
      { item-identifier: new-identifier }
      {
        name: name,
        originator: tx-sender,
        dimensions: dimensions,
        registration-block: block-height,
        narrative: narrative,
        classifications: classifications
      }
    )

    ;; Establish initial access permissions
    (map-insert permission-registry
      { item-identifier: new-identifier, viewer: tx-sender }
      { permission-granted: true }
    )

    ;; Update system counter
    (var-set item-counter new-identifier)
    (ok new-identifier)  ;; Return newly assigned identifier
  )
)

;; Retrieve extended description of a collectible
(define-public (retrieve-collectible-narrative (item-identifier uint))
  (let
    (
      (collectible-data (unwrap! (map-get? collectible-repository { item-identifier: item-identifier }) STATUS-ITEM-MISSING))
    )
    (ok (get narrative collectible-data))
  )
)

;; Verify viewer permission status
(define-public (verify-viewer-permission (item-identifier uint) (viewer principal))
  (let
    (
      (permission-data (map-get? permission-registry { item-identifier: item-identifier, viewer: viewer }))
    )
    (ok (is-some permission-data))
  )
)

;; Count total classifications for a collectible
(define-public (count-classifications (item-identifier uint))
  (let
    (
      (collectible-data (unwrap! (map-get? collectible-repository { item-identifier: item-identifier }) STATUS-ITEM-MISSING))
    )
    (ok (len (get classifications collectible-data)))
  )
)

;; Check if a name meets system requirements
(define-public (validate-collectible-name (name (string-ascii 64)))
  (ok (and (> (len name) u0) (<= (len name) u64)))
)

;; Remove collectible from the repository
(define-public (remove-collectible (item-identifier uint))
  (let
    (
      (collectible-data (unwrap! (map-get? collectible-repository { item-identifier: item-identifier }) STATUS-ITEM-MISSING))
    )
    (asserts! (collectible-registered? item-identifier) STATUS-ITEM-MISSING)
    (asserts! (is-eq (get originator collectible-data) tx-sender) STATUS-PERMISSION-DENIED)

    ;; Delete collectible from repository
    (map-delete collectible-repository { item-identifier: item-identifier })
    (ok true)
  )
)

