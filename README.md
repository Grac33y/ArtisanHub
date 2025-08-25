# ArtisanHub - Decentralized NFT Marketplace

A community-driven NFT marketplace built on Stacks blockchain that empowers artists and collectors through transparent royalties and curated galleries.

## Features

- **Creator Registration**: Artists can register and manage their collections across multiple categories
- **Curated Galleries**: Community curators create themed galleries with custom floor prices and royalty rates
- **Transparent Royalties**: Automatic royalty distribution to creators with configurable rates
- **Category System**: Organized art categories for better discovery and curation
- **Marketplace Fees**: Sustainable platform economics with configurable fee structure

## Smart Contract Functions

### Creator Functions
- `register-creator`: Register as an artist with preferred collection categories
- `update-collections`: Modify collection preferences
- `mint-in-gallery`: Mint NFTs in matching galleries
- `claim-earnings`: Withdraw accumulated royalties

### Gallery Functions
- `create-art-gallery`: Create curated galleries with custom parameters
- `pause-gallery`/`resume-gallery`: Control gallery activity
- `add-gallery-funds`: Increase gallery liquidity

### Admin Functions
- `add-category`: Add new art categories
- `set-marketplace-fee`: Configure platform fees

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Add art categories using admin functions
3. Artists register with their preferred categories
4. Curators create galleries for specific themes
5. Artists mint NFTs in matching galleries

## License

MIT License
\`\`\`

```clarity file="project-2-prediction-market/contracts/prediction-market.clar"
;; OracleVision - A decentralized prediction market for real-world events
;; Users create and participate in prediction markets with automated resolution

;; Data storage
(define-map predictor-profiles principal {
  active: bool,
  interests: (list 10 uint),
  winnings: uint,
  last-claim: uint,
  prediction-count: uint
})

(define-map prediction-markets uint {
  creator: principal,
  total-stake: uint,
  payout-ratio: uint,
  active: bool,
  event-type: uint,
  total-predictors: uint,
  created-at: uint
})

(define-map prediction-records {predictor: principal, market-id: uint} {
  timestamp: uint,
  resolved: bool
})

(define-map event-types uint (string-ascii 64))

;; Constants
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMS (err u101))
(define-constant ERR_PREDICTOR_NOT_FOUND (err u102))
(define-constant ERR_MARKET_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_ALREADY_REGISTERED (err u105))
(define-constant ERR_ALREADY_PREDICTED (err u106))
(define-constant ERR_INVALID_PRINCIPAL (err u107))
(define-constant ERR_INVALID_VALUE (err u108))
(define-constant ERR_EVENT_TYPE_NOT_FOUND (err u109))

(define-constant ZERO_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MIN_PAYOUT_RATIO u1)
(define-constant MAX_PAYOUT_RATIO u1000)
(define-constant MIN_MARKET_STAKE u1000)
(define-constant MAX_EVENT_TYPE_ID u1000)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-market-id uint u1)
(define-data-var oracle-fee-percent uint u5) ;; 5% fee
(define-data-var oracle-balance uint u0)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR_INVALID_PRINCIPAL)
    (ok (var-set contract-owner new-owner))))

(define-public (set-oracle-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (&lt;= new-fee u20) ERR_INVALID_PARAMS) ;; Max 20% fee
    (ok (var-set oracle-fee-percent new-fee))))

(define-public (add-event-type (event-id uint) (event-name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> (len event-name) u0) ERR_INVALID_PARAMS)
    (asserts! (&lt; event-id MAX_EVENT_TYPE_ID) ERR_INVALID_PARAMS)
    (asserts! (is-none (map-get? event-types event-id)) ERR_ALREADY_REGISTERED)
    (ok (map-set event-types event-id event-name))))

;; Predictor functions
(define-public (register-predictor (interests (list 10 uint)))
  (begin
    (asserts! (is-none (map-get? predictor-profiles tx-sender)) ERR_ALREADY_REGISTERED)
    (asserts! (validate-interests interests) ERR_INVALID_PARAMS)
    (ok (map-set predictor-profiles tx-sender {
      active: true,
      interests: interests,
      winnings: u0,
      last-claim: u0,
      prediction-count: u0
    }))))

(define-public (update-interests (interests (list 10 uint)))
  (let ((predictor-profile (unwrap! (map-get? predictor-profiles tx-sender) ERR_PREDICTOR_NOT_FOUND)))
    (asserts! (validate-interests interests) ERR_INVALID_PARAMS)
    (ok (map-set predictor-profiles tx-sender (merge predictor-profile {interests: interests})))))

(define-public (pause-predictions)
  (let ((predictor-profile (unwrap! (map-get? predictor-profiles tx-sender) ERR_PREDICTOR_NOT_FOUND)))
    (ok (map-set predictor-profiles tx-sender (merge predictor-profile {active: false})))))

(define-public (resume-predictions)
  (let ((predictor-profile (unwrap! (map-get? predictor-profiles tx-sender) ERR_PREDICTOR_NOT_FOUND)))
    (ok (map-set predictor-profiles tx-sender (merge predictor-profile {active: true})))))

;; Market creator functions
(define-public (create-prediction-market (total-stake uint) (payout-ratio uint) (event-type uint) (stx-amount uint))
  (begin
    (asserts! (>= total-stake MIN_MARKET_STAKE) ERR_INVALID_PARAMS)
    (asserts! (and (>= payout-ratio MIN_PAYOUT_RATIO) (&lt;= payout-ratio MAX_PAYOUT_RATIO)) ERR_INVALID_PARAMS)
    (asserts! (is-some (map-get? event-types event-type)) ERR_EVENT_TYPE_NOT_FOUND)
    (asserts! (>= stx-amount total-stake) ERR_INSUFFICIENT_FUNDS)
    
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    (let ((market-id (var-get next-market-id)))
      (map-set prediction-markets market-id {
        creator: tx-sender,
        total-stake: total-stake,
        payout-ratio: payout-ratio,
        active: true,
        event-type: event-type,
        total-predictors: u0,
        created-at: u0
      })
      
      (var-set next-market-id (+ market-id u1))
      (ok market-id))))

(define-public (pause-market (market-id uint))
  (let ((market (unwrap! (map-get? prediction-markets market-id) ERR_MARKET_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator market)) ERR_NOT_AUTHORIZED)
    (ok (map-set prediction-markets market-id (merge market {active: false})))))

(define-public (resume-market (market-id uint))
  (let ((market (unwrap! (map-get? prediction-markets market-id) ERR_MARKET_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator market)) ERR_NOT_AUTHORIZED)
    (ok (map-set prediction-markets market-id (merge market {active: true})))))

(define-public (add-market-liquidity (market-id uint) (additional-liquidity uint))
  (let ((market (unwrap! (map-get? prediction-markets market-id) ERR_MARKET_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator market)) ERR_NOT_AUTHORIZED)
    (asserts! (> additional-liquidity u0) ERR_INVALID_PARAMS)
    
    (try! (stx-transfer? additional-liquidity tx-sender (as-contract tx-sender)))
    
    (ok (map-set prediction-markets market-id 
      (merge market {total-stake: (+ (get total-stake market) additional-liquidity)})))))

;; Helper function to check if an event type matches predictor interests
(define-private (check-interest-match (event-type uint) (interests (list 10 uint)))
  (or
    (and (> (len interests) u0) (is-eq event-type (unwrap-panic (element-at interests u0))))
    (and (> (len interests) u1) (is-eq event-type (unwrap-panic (element-at interests u1))))
    (and (> (len interests) u2) (is-eq event-type (unwrap-panic (element-at interests u2))))
    (and (> (len interests) u3) (is-eq event-type (unwrap-panic (element-at interests u3))))
    (and (> (len interests) u4) (is-eq event-type (unwrap-panic (element-at interests u4))))
    (and (> (len interests) u5) (is-eq event-type (unwrap-panic (element-at interests u5))))
    (and (> (len interests) u6) (is-eq event-type (unwrap-panic (element-at interests u6))))
    (and (> (len interests) u7) (is-eq event-type (unwrap-panic (element-at interests u7))))
    (and (> (len interests) u8) (is-eq event-type (unwrap-panic (element-at interests u8))))
    (and (> (len interests) u9) (is-eq event-type (unwrap-panic (element-at interests u9))))
  ))

;; Prediction and payouts
(define-public (make-prediction (market-id uint))
  (let (
    (predictor-profile (unwrap! (map-get? predictor-profiles tx-sender) ERR_PREDICTOR_NOT_FOUND))
    (market (unwrap! (map-get? prediction-markets market-id) ERR_MARKET_NOT_FOUND))
    (prediction-key {predictor: tx-sender, market-id: market-id})
  )
    (asserts! (get active predictor-profile) ERR_PREDICTOR_NOT_FOUND)
    (asserts! (get active market) ERR_MARKET_NOT_FOUND)
    (asserts! (is-none (map-get? prediction-records prediction-key)) ERR_ALREADY_PREDICTED)
    (asserts! (>= (get total-stake market) (get payout-ratio market)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (check-interest-match (get event-type market) (get interests predictor-profile)) ERR_INVALID_PARAMS)
    
    (let (
      (payout-ratio (get payout-ratio market))
      (oracle-fee (/ (* payout-ratio (var-get oracle-fee-percent)) u100))
      (predictor-payout (- payout-ratio oracle-fee))
    )
      (map-set prediction-records prediction-key {timestamp: u0, resolved: true})
      
      (map-set prediction-markets market-id (merge market {
        total-stake: (- (get total-stake market) payout-ratio),
        total-predictors: (+ (get total-predictors market) u1)
      }))
      
      (map-set predictor-profiles tx-sender (merge predictor-profile {
        winnings: (+ (get winnings predictor-profile) predictor-payout),
        prediction-count: (+ (get prediction-count predictor-profile) u1)
      }))
      
      (var-set oracle-balance (+ (var-get oracle-balance) oracle-fee))
      
      (ok predictor-payout))))

(define-public (claim-winnings)
  (let ((predictor-profile (unwrap! (map-get? predictor-profiles tx-sender) ERR_PREDICTOR_NOT_FOUND)))
    (let ((winnings (get winnings predictor-profile)))
      (asserts! (> winnings u0) ERR_INSUFFICIENT_FUNDS)
      
      (try! (as-contract (stx-transfer? winnings tx-sender tx-sender)))
      
      (map-set predictor-profiles tx-sender (merge predictor-profile {
        winnings: u0,
        last-claim: u0
      }))
      
      (ok winnings))))

(define-public (withdraw-oracle-fees)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (let ((amount (var-get oracle-balance)))
      (asserts! (> amount u0) ERR_INSUFFICIENT_FUNDS)
      
      (try! (as-contract (stx-transfer? amount tx-sender (var-get contract-owner))))
      
      (var-set oracle-balance u0)
      
      (ok amount))))

;; Helper functions
(define-private (is-valid-interest (interest uint))
  (is-some (map-get? event-types interest)))

(define-private (count-valid-interests (interests (list 10 uint)))
  (+ 
    (if (and (> (len interests) u0) (is-valid-interest (unwrap-panic (element-at interests u0)))) u1 u0)
    (if (and (> (len interests) u1) (is-valid-interest (unwrap-panic (element-at interests u1)))) u1 u0)
    (if (and (> (len interests) u2) (is-valid-interest (unwrap-panic (element-at interests u2)))) u1 u0)
    (if (and (> (len interests) u3) (is-valid-interest (unwrap-panic (element-at interests u3)))) u1 u0)
    (if (and (> (len interests) u4) (is-valid-interest (unwrap-panic (element-at interests u4)))) u1 u0)
    (if (and (> (len interests) u5) (is-valid-interest (unwrap-panic (element-at interests u5)))) u1 u0)
    (if (and (> (len interests) u6) (is-valid-interest (unwrap-panic (element-at interests u6)))) u1 u0)
    (if (and (> (len interests) u7) (is-valid-interest (unwrap-panic (element-at interests u7)))) u1 u0)
    (if (and (> (len interests) u8) (is-valid-interest (unwrap-panic (element-at interests u8)))) u1 u0)
    (if (and (> (len interests) u9) (is-valid-interest (unwrap-panic (element-at interests u9)))) u1 u0)
  ))

(define-private (validate-interests (interests (list 10 uint)))
  (let ((interests-len (len interests)))
    (and 
      (> interests-len u0)
      (&lt;= interests-len u10)
      (is-eq interests-len (count-valid-interests interests)))))

;; Read-only functions
(define-read-only (get-predictor-profile (predictor principal))
  (map-get? predictor-profiles predictor))

(define-read-only (get-market (market-id uint))
  (map-get? prediction-markets market-id))

(define-read-only (get-event-type (event-id uint))
  (map-get? event-types event-id))

(define-read-only (get-oracle-fee)
  (var-get oracle-fee-percent))

(define-read-only (get-oracle-balance)
  (var-get oracle-balance))

(define-read-only (get-prediction-record (predictor principal) (market-id uint))
  (map-get? prediction-records {predictor: predictor, market-id: market-id}))
