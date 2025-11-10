;; Conditional Time-locked Payments
;; Allows users to lock funds that can only be released when both:
;; 1. A specific block height has been reached
;; 2. External conditions (such as oracle data) have been met

;; <CHANGE> Renamed counter variable for clarity
(define-data-var next-payment-id uint u0)

;; Constants for validation
(define-constant maximum-block-lock u52560) ;; ~1 year at 10 min blocks
(define-constant minimum-locked-amount u1)
(define-constant maximum-locked-amount u1000000000000) ;; 1 million STX

;; <CHANGE> Renamed map keys from tx-id to payment-id and addresses to more descriptive names
(define-map payment-transactions
  { payment-id: uint }
  {
    sender-address: principal,
    recipient-address: principal,
    locked-amount: uint,
    release-height: uint,
    condition-key: (string-ascii 128),
    required-value: uint,
    is-fulfilled: bool,
    is-canceled: bool
  }
)

;; <CHANGE> Renamed data-feed-values map and fields for clarity
(define-map oracle-feed-registry
  { oracle-feed-key: (string-ascii 128) }
  { oracle-value: uint, updated-at: uint }
)

;; <CHANGE> Renamed oracle-providers map and fields
(define-map authorized-oracle-registry
  { oracle-address: principal }
  { is-authorized: bool }
)

;; <CHANGE> Renamed deployer-address constant to contract-owner
(define-constant contract-owner tx-sender)

;; Validation functions
(define-private (validate-amount (locked-amount uint))
  (and (>= locked-amount minimum-locked-amount) (<= locked-amount maximum-locked-amount))
)

(define-private (validate-lock-duration (block-count uint))
  (and (>= block-count u1) (<= block-count maximum-block-lock))
)

(define-private (validate-feed-key (oracle-feed-key (string-ascii 128)))
  (> (len oracle-feed-key) u0)
)

(define-private (validate-payment-id (payment-id uint))
  (< payment-id (var-get next-payment-id))
)

;; Create a new conditional payment
(define-public (create-payment (recipient-address principal) (locked-amount uint) (lock-duration uint) 
                              (condition-key (string-ascii 128)) (required-value uint))
  (let
    ((payment-id (var-get next-payment-id))
     (release-height (+ block-height lock-duration)))
    
    ;; Validate all parameters
    (asserts! (validate-amount locked-amount) (err u1)) ;; Invalid amount
    (asserts! (validate-lock-duration lock-duration) (err u2)) ;; Invalid lock period
    (asserts! (validate-feed-key condition-key) (err u3)) ;; Invalid oracle key
    (asserts! (not (is-eq recipient-address tx-sender)) (err u4)) ;; Cannot send to self
    (asserts! (is-standard recipient-address) (err u5)) ;; Invalid recipient principal
    
    ;; Transfer STX from sender to contract
    (try! (stx-transfer? locked-amount tx-sender (as-contract tx-sender)))
    
    ;; Create the payment entry with validated data
    (map-set payment-transactions
      { payment-id: payment-id }
      {
        sender-address: tx-sender,
        recipient-address: recipient-address,
        locked-amount: locked-amount,
        release-height: release-height,
        condition-key: condition-key,
        required-value: required-value,
        is-fulfilled: false,
        is-canceled: false
      }
    )
    
    ;; Increment payment ID counter
    (var-set next-payment-id (+ payment-id u1))
    
    (ok payment-id)
  )
)

;; Set an oracle value (only callable by authorized oracles)
(define-public (set-oracle-value (oracle-feed-key (string-ascii 128)) (oracle-value uint))
  (begin
    ;; Validate oracle key
    (asserts! (validate-feed-key oracle-feed-key) (err u6)) ;; Invalid oracle key
    
    ;; Check that the caller is an authorized oracle
    (asserts! (check-oracle-auth tx-sender) (err u7)) ;; Not authorized as oracle
    
    ;; Update the oracle value with validated data
    (map-set oracle-feed-registry
      { oracle-feed-key: oracle-feed-key }
      { oracle-value: oracle-value, updated-at: block-height }
    )
    
    (ok true)
  )
)

;; Private function to check if sender is an authorized oracle
(define-private (check-oracle-auth (oracle-address principal))
  (default-to false (get is-authorized (map-get? authorized-oracle-registry { oracle-address: oracle-address })))
)

;; Add an authorized oracle (contract owner only)
(define-public (add-authorized-oracle (oracle-address principal))
  (begin
    ;; Validate provider principal
    (asserts! (is-standard oracle-address) (err u8)) ;; Invalid provider principal
    (asserts! (not (is-eq oracle-address (as-contract tx-sender))) (err u9)) ;; Cannot authorize contract itself
    
    ;; Only contract owner can add oracles
    (asserts! (is-eq tx-sender (get-owner-address)) (err u10)) ;; Not authorized
    
    ;; Add the authorized oracle with validated data
    (map-set authorized-oracle-registry
      { oracle-address: oracle-address }
      { is-authorized: true }
    )
    
    (ok true)
  )
)

;; Private function to get contract owner
(define-private (get-owner-address)
  contract-owner
)

;; Claim a payment if conditions are met
(define-public (claim-payment (payment-id uint))
  (let
    ((payment-info (map-get? payment-transactions { payment-id: payment-id })))
    
    ;; Validate payment exists
    (asserts! (is-some payment-info) (err u11)) ;; Payment not found
    
    (let
      ((payment-data (unwrap-panic payment-info))
       (feed-data (unwrap! (map-get? oracle-feed-registry { oracle-feed-key: (get condition-key payment-data) }) (err u12)))) ;; Oracle data not found
      
      ;; Validate conditions
      (asserts! (is-eq tx-sender (get recipient-address payment-data)) (err u13)) ;; Only recipient can claim
      (asserts! (not (get is-fulfilled payment-data)) (err u14)) ;; Payment already fulfilled
      (asserts! (not (get is-canceled payment-data)) (err u15)) ;; Payment was canceled
      (asserts! (>= block-height (get release-height payment-data)) (err u16)) ;; Payment still time-locked
      (asserts! (>= (get oracle-value feed-data) (get required-value payment-data)) (err u17)) ;; Threshold condition not met
      
      ;; Mark payment as fulfilled with validated payment-id
      (map-set payment-transactions
        { payment-id: payment-id }
        (merge payment-data { is-fulfilled: true })
      )
      
      ;; Transfer STX to recipient
      (try! (as-contract (stx-transfer? (get locked-amount payment-data) tx-sender (get recipient-address payment-data))))
      
      (ok true)
    )
  )
)

;; Cancel a payment (sender only, before fulfillment)
(define-public (cancel-payment (payment-id uint))
  (let
    ((payment-info (map-get? payment-transactions { payment-id: payment-id })))
    
    ;; Validate payment exists
    (asserts! (is-some payment-info) (err u18)) ;; Payment not found
    
    (let
      ((payment-data (unwrap-panic payment-info)))
      
      ;; Validate conditions
      (asserts! (is-eq tx-sender (get sender-address payment-data)) (err u19)) ;; Only sender can cancel
      (asserts! (not (get is-fulfilled payment-data)) (err u20)) ;; Payment already fulfilled
      (asserts! (not (get is-canceled payment-data)) (err u21)) ;; Payment already canceled
      
      ;; Mark payment as canceled with validated payment-id
      (map-set payment-transactions
        { payment-id: payment-id }
        (merge payment-data { is-canceled: true })
      )
      
      ;; Return STX to sender
      (try! (as-contract (stx-transfer? (get locked-amount payment-data) tx-sender (get sender-address payment-data))))
      
      (ok true)
    )
  )
)

;; Check payment status
(define-read-only (get-payment-status (payment-id uint))
  (let ((payment-data (map-get? payment-transactions { payment-id: payment-id })))
    (if (is-none payment-data)
        (err u22) ;; Payment not found
        (ok (unwrap-panic payment-data))
    )
  )
)

;; Check if payment is claimable
(define-read-only (is-payment-claimable (payment-id uint))
  (let
    ((payment-info (map-get? payment-transactions { payment-id: payment-id })))
    
    (if (is-none payment-info)
        (err u23) ;; Payment not found
        (let
          ((payment-data (unwrap-panic payment-info))
           (feed-data (map-get? oracle-feed-registry { oracle-feed-key: (get condition-key payment-data) })))
          
          (if (and
                (not (get is-fulfilled payment-data))
                (not (get is-canceled payment-data))
                (>= block-height (get release-height payment-data))
                (is-some feed-data)
                (>= (get oracle-value (unwrap-panic feed-data)) (get required-value payment-data))
              )
              (ok true)
              (ok false)
          )
        )
    )
  )
)

;; Get oracle value
(define-read-only (get-oracle-value (oracle-feed-key (string-ascii 128)))
  (map-get? oracle-feed-registry { oracle-feed-key: oracle-feed-key })
)

;; Check if a principal is an authorized oracle
(define-read-only (check-oracle-authorization (oracle-address principal))
  (default-to false (get is-authorized (map-get? authorized-oracle-registry { oracle-address: oracle-address })))
)

;; Get current payment ID nonce
(define-read-only (get-payment-nonce)
  (var-get next-payment-id)
)