;; Impermanent Loss Protection Insurance Protocol
;; Built for Stacks blockchain in Clarity

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-policy-expired (err u103))
(define-constant err-policy-active (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-already-exists (err u106))
(define-constant err-unauthorized (err u107))
(define-constant err-invalid-parameters (err u108))
(define-constant err-claim-too-early (err u109))
(define-constant err-claim-too-late (err u110))

;; Define data variables
(define-data-var next-policy-id uint u1)
(define-data-var protocol-fee uint u300) ;; 3% in basis points
(define-data-var min-coverage-period uint u144) ;; Minimum 1 day in blocks
(define-data-var max-coverage-period uint u52560) ;; Maximum 1 year in blocks
(define-data-var protocol-treasury uint u0)

;; Define data maps
(define-map policies
  { policy-id: uint }
  {
    holder: principal,
    lp-token-amount: uint,
    pool-pair: (string-ascii 64),
    premium-paid: uint,
    coverage-amount: uint,
    start-block: uint,
    end-block: uint,
    initial-price-ratio: uint, ;; Price ratio at policy start (scaled by 1e6)
    status: (string-ascii 20) ;; "active", "expired", "claimed"
  }
)

(define-map price-oracles
  { pool-pair: (string-ascii 64) }
  {
    price-ratio: uint, ;; Current price ratio (scaled by 1e6)
    last-updated: uint,
    oracle-address: principal
  }
)

(define-map user-policies
  { user: principal }
  { policy-ids: (list 100 uint) }
)

(define-map claims
  { policy-id: uint }
  {
    claim-amount: uint,
    claim-block: uint,
    status: (string-ascii 20) ;; "pending", "approved", "rejected", "paid"
  }
)

;; Read-only functions
(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-price-oracle (pool-pair (string-ascii 64)))
  (map-get? price-oracles { pool-pair: pool-pair })
)

(define-read-only (get-user-policies (user principal))
  (default-to { policy-ids: (list) } (map-get? user-policies { user: user }))
)

(define-read-only (get-claim (policy-id uint))
  (map-get? claims { policy-id: policy-id })
)

(define-read-only (get-protocol-treasury)
  (var-get protocol-treasury)
)

(define-read-only (calculate-premium (lp-amount uint) (coverage-period uint) (coverage-amount uint))
  (let ((base-rate u50) ;; 0.5% base rate in basis points
        (period-multiplier (/ coverage-period u1440)) ;; Per 10 days
        (coverage-ratio (/ (* coverage-amount u10000) lp-amount))) ;; Coverage ratio in basis points
    (/ (* (* lp-amount base-rate) (+ u1 period-multiplier) (+ u10000 coverage-ratio)) u100000000)
  )
)

(define-read-only (calculate-impermanent-loss (initial-ratio uint) (current-ratio uint))
  (let ((ratio-change (if (> current-ratio initial-ratio)
                        (- current-ratio initial-ratio)
                        (- initial-ratio current-ratio)))
        (percentage-change (/ (* ratio-change u10000) initial-ratio)))
    ;; Simplified IL calculation: IL = 2 * sqrt(ratio) / (1 + ratio) - 1
    ;; For simplicity, using linear approximation for small changes
    (if (< percentage-change u2000) ;; Less than 20% change
      (/ (* percentage-change percentage-change) u40000) ;; Quadratic approximation
      (/ (* percentage-change u3) u10)) ;; Linear for larger changes
  )
)

;; Administrative functions
(define-public (set-oracle (pool-pair (string-ascii 64)) (oracle-address principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set price-oracles
      { pool-pair: pool-pair }
      {
        price-ratio: u1000000, ;; Default 1:1 ratio
        last-updated: block-height,
        oracle-address: oracle-address
      }
    ))
  )
)

(define-public (update-price (pool-pair (string-ascii 64)) (new-price-ratio uint))
  (let ((oracle-data (unwrap! (map-get? price-oracles { pool-pair: pool-pair }) err-not-found)))
    (asserts! (is-eq tx-sender (get oracle-address oracle-data)) err-unauthorized)
    (asserts! (> new-price-ratio u0) err-invalid-parameters)
    (ok (map-set price-oracles
      { pool-pair: pool-pair }
      (merge oracle-data {
        price-ratio: new-price-ratio,
        last-updated: block-height
      })
    ))
  )
)

(define-public (set-protocol-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u1000) err-invalid-parameters) ;; Max 10%
    (ok (var-set protocol-fee new-fee))
  )
)

;; Core insurance functions
(define-public (purchase-policy 
  (lp-token-amount uint)
  (pool-pair (string-ascii 64))
  (coverage-amount uint)
  (coverage-period uint))
  (let ((policy-id (var-get next-policy-id))
        (premium (calculate-premium lp-token-amount coverage-period coverage-amount))
        (oracle-data (unwrap! (map-get? price-oracles { pool-pair: pool-pair }) err-not-found))
        (user-policy-data (get-user-policies tx-sender)))
    
    ;; Validation
    (asserts! (> lp-token-amount u0) err-invalid-amount)
    (asserts! (> coverage-amount u0) err-invalid-amount)
    (asserts! (>= coverage-period (var-get min-coverage-period)) err-invalid-parameters)
    (asserts! (<= coverage-period (var-get max-coverage-period)) err-invalid-parameters)
    (asserts! (<= coverage-amount (* lp-token-amount u2)) err-invalid-parameters) ;; Max 200% coverage
    
    ;; Transfer premium (assuming STX payment)
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    ;; Update protocol treasury
    (var-set protocol-treasury (+ (var-get protocol-treasury) premium))
    
    ;; Create policy
    (map-set policies
      { policy-id: policy-id }
      {
        holder: tx-sender,
        lp-token-amount: lp-token-amount,
        pool-pair: pool-pair,
        premium-paid: premium,
        coverage-amount: coverage-amount,
        start-block: block-height,
        end-block: (+ block-height coverage-period),
        initial-price-ratio: (get price-ratio oracle-data),
        status: "active"
      }
    )
    
    ;; Update user policies list
    (map-set user-policies
      { user: tx-sender }
      { policy-ids: (unwrap! (as-max-len? (append (get policy-ids user-policy-data) policy-id) u100) err-invalid-parameters) }
    )
    
    ;; Increment policy counter
    (var-set next-policy-id (+ policy-id u1))
    
    (ok policy-id)
  )
)

(define-public (file-claim (policy-id uint))
  (let ((policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
        (oracle-data (unwrap! (map-get? price-oracles { pool-pair: (get pool-pair policy) }) err-not-found)))
    
    ;; Validation
    (asserts! (is-eq tx-sender (get holder policy)) err-unauthorized)
    (asserts! (is-eq (get status policy) "active") err-policy-expired)
    (asserts! (> block-height (+ (get start-block policy) u144)) err-claim-too-early) ;; Wait 1 day
    (asserts! (<= block-height (get end-block policy)) err-claim-too-late)
    
    ;; Calculate impermanent loss
    (let ((il-percentage (calculate-impermanent-loss 
                           (get initial-price-ratio policy)
                           (get price-ratio oracle-data)))
          (calculated-loss (/ (* (get lp-token-amount policy) il-percentage) u10000))
          (claim-amount (if (< calculated-loss (get coverage-amount policy))
                          calculated-loss
                          (get coverage-amount policy))))
      
      ;; Only process if there's significant IL (>1%)
      (asserts! (> il-percentage u100) err-invalid-amount)
      
      ;; Create claim record
      (map-set claims
        { policy-id: policy-id }
        {
          claim-amount: claim-amount,
          claim-block: block-height,
          status: "approved"
        }
      )
      
      ;; Update policy status
      (map-set policies
        { policy-id: policy-id }
        (merge policy { status: "claimed" })
      )
      
      ;; Pay claim (from contract balance)
      (try! (as-contract (stx-transfer? claim-amount tx-sender (get holder policy))))
      
      ;; Update treasury
      (var-set protocol-treasury (- (var-get protocol-treasury) claim-amount))
      
      (ok claim-amount)
    )
  )
)

(define-public (expire-policy (policy-id uint))
  (let ((policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found)))
    (asserts! (is-eq (get status policy) "active") err-policy-expired)
    (asserts! (> block-height (get end-block policy)) err-policy-active)
    
    ;; Update policy status
    (map-set policies
      { policy-id: policy-id }
      (merge policy { status: "expired" })
    )
    
    (ok true)
  )
)

;; Emergency functions
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
    (ok true)
  )
)

(define-public (fund-contract)
  (let ((amount (stx-get-balance tx-sender)))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set protocol-treasury (+ (var-get protocol-treasury) amount))
    (ok amount)
  )
)

;; Initialize contract
(define-private (init-contract)
  (begin
    ;; Set initial oracles for common pairs
    (map-set price-oracles { pool-pair: "STX-USDC" } 
      { price-ratio: u1000000, last-updated: block-height, oracle-address: contract-owner })
    (map-set price-oracles { pool-pair: "STX-BTC" } 
      { price-ratio: u1000000, last-updated: block-height, oracle-address: contract-owner })
    true
  )
)

;; Initialize on deployment
(init-contract)