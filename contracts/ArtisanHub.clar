;; ArtisanHub - A decentralized NFT marketplace with creator royalties and community curation
;; Artists mint and sell NFTs while collectors discover and trade unique digital assets

;; Data storage
(define-map creator-profiles principal {
  verified: bool,
  collections: (list 10 uint),
  earnings: uint,
  last-payout: uint,
  artwork-count: uint
})

(define-map art-galleries uint {
  curator: principal,
  floor-price: uint,
  royalty-rate: uint,
  active: bool,
  category-type: uint,
  total-collectors: uint,
  created-at: uint
})

(define-map collection-records {creator: principal, gallery-id: uint} {
  timestamp: uint,
  featured: bool
})

(define-map art-categories uint (string-ascii 64))

;; Constants
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMS (err u101))
(define-constant ERR_CREATOR_NOT_FOUND (err u102))
(define-constant ERR_GALLERY_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_ALREADY_REGISTERED (err u105))
(define-constant ERR_ALREADY_FEATURED (err u106))
(define-constant ERR_INVALID_PRINCIPAL (err u107))
(define-constant ERR_INVALID_VALUE (err u108))
(define-constant ERR_CATEGORY_NOT_FOUND (err u109))

(define-constant ZERO_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MIN_ROYALTY_RATE u1)
(define-constant MAX_ROYALTY_RATE u1000)
(define-constant MIN_FLOOR_PRICE u1000)
(define-constant MAX_CATEGORY_ID u1000)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-gallery-id uint u1)
(define-data-var marketplace-fee-percent uint u5) ;; 5% fee
(define-data-var marketplace-balance uint u0)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR_INVALID_PRINCIPAL)
    (ok (var-set contract-owner new-owner))))

(define-public (set-marketplace-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-fee u20) ERR_INVALID_PARAMS) ;; Max 20% fee
    (ok (var-set marketplace-fee-percent new-fee))))

(define-public (add-category (category-id uint) (category-name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> (len category-name) u0) ERR_INVALID_PARAMS)
    (asserts! (< category-id MAX_CATEGORY_ID) ERR_INVALID_PARAMS)
    (asserts! (is-none (map-get? art-categories category-id)) ERR_ALREADY_REGISTERED)
    (ok (map-set art-categories category-id category-name))))

;; Creator functions
(define-public (register-creator (collections (list 10 uint)))
  (begin
    (asserts! (is-none (map-get? creator-profiles tx-sender)) ERR_ALREADY_REGISTERED)
    (asserts! (validate-collections collections) ERR_INVALID_PARAMS)
    (ok (map-set creator-profiles tx-sender {
      verified: true,
      collections: collections,
      earnings: u0,
      last-payout: u0,
      artwork-count: u0
    }))))

(define-public (update-collections (collections (list 10 uint)))
  (let ((creator-profile (unwrap! (map-get? creator-profiles tx-sender) ERR_CREATOR_NOT_FOUND)))
    (asserts! (validate-collections collections) ERR_INVALID_PARAMS)
    (ok (map-set creator-profiles tx-sender (merge creator-profile {collections: collections})))))

(define-public (pause-sales)
  (let ((creator-profile (unwrap! (map-get? creator-profiles tx-sender) ERR_CREATOR_NOT_FOUND)))
    (ok (map-set creator-profiles tx-sender (merge creator-profile {verified: false})))))

(define-public (resume-sales)
  (let ((creator-profile (unwrap! (map-get? creator-profiles tx-sender) ERR_CREATOR_NOT_FOUND)))
    (ok (map-set creator-profiles tx-sender (merge creator-profile {verified: true})))))

;; Gallery curator functions
(define-public (create-art-gallery (floor-price uint) (royalty-rate uint) (category-type uint) (stx-amount uint))
  (begin
    (asserts! (>= floor-price MIN_FLOOR_PRICE) ERR_INVALID_PARAMS)
    (asserts! (and (>= royalty-rate MIN_ROYALTY_RATE) (<= royalty-rate MAX_ROYALTY_RATE)) ERR_INVALID_PARAMS)
    (asserts! (is-some (map-get? art-categories category-type)) ERR_CATEGORY_NOT_FOUND)
    (asserts! (>= stx-amount floor-price) ERR_INSUFFICIENT_FUNDS)
    
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    (let ((gallery-id (var-get next-gallery-id)))
      (map-set art-galleries gallery-id {
        curator: tx-sender,
        floor-price: floor-price,
        royalty-rate: royalty-rate,
        active: true,
        category-type: category-type,
        total-collectors: u0,
        created-at: u0
      })
      
      (var-set next-gallery-id (+ gallery-id u1))
      (ok gallery-id))))

(define-public (pause-gallery (gallery-id uint))
  (let ((gallery (unwrap! (map-get? art-galleries gallery-id) ERR_GALLERY_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get curator gallery)) ERR_NOT_AUTHORIZED)
    (ok (map-set art-galleries gallery-id (merge gallery {active: false})))))

(define-public (resume-gallery (gallery-id uint))
  (let ((gallery (unwrap! (map-get? art-galleries gallery-id) ERR_GALLERY_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get curator gallery)) ERR_NOT_AUTHORIZED)
    (ok (map-set art-galleries gallery-id (merge gallery {active: true})))))

(define-public (add-gallery-funds (gallery-id uint) (additional-funds uint))
  (let ((gallery (unwrap! (map-get? art-galleries gallery-id) ERR_GALLERY_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get curator gallery)) ERR_NOT_AUTHORIZED)
    (asserts! (> additional-funds u0) ERR_INVALID_PARAMS)
    
    (try! (stx-transfer? additional-funds tx-sender (as-contract tx-sender)))
    
    (ok (map-set art-galleries gallery-id 
      (merge gallery {floor-price: (+ (get floor-price gallery) additional-funds)})))))

;; Helper function to check if a category matches creator preferences
(define-private (check-category-match (category-type uint) (collections (list 10 uint)))
  (or
    (and (> (len collections) u0) (is-eq category-type (unwrap-panic (element-at collections u0))))
    (and (> (len collections) u1) (is-eq category-type (unwrap-panic (element-at collections u1))))
    (and (> (len collections) u2) (is-eq category-type (unwrap-panic (element-at collections u2))))
    (and (> (len collections) u3) (is-eq category-type (unwrap-panic (element-at collections u3))))
    (and (> (len collections) u4) (is-eq category-type (unwrap-panic (element-at collections u4))))
    (and (> (len collections) u5) (is-eq category-type (unwrap-panic (element-at collections u5))))
    (and (> (len collections) u6) (is-eq category-type (unwrap-panic (element-at collections u6))))
    (and (> (len collections) u7) (is-eq category-type (unwrap-panic (element-at collections u7))))
    (and (> (len collections) u8) (is-eq category-type (unwrap-panic (element-at collections u8))))
    (and (> (len collections) u9) (is-eq category-type (unwrap-panic (element-at collections u9))))
  ))

;; NFT minting and sales
(define-public (mint-in-gallery (gallery-id uint))
  (let (
    (creator-profile (unwrap! (map-get? creator-profiles tx-sender) ERR_CREATOR_NOT_FOUND))
    (gallery (unwrap! (map-get? art-galleries gallery-id) ERR_GALLERY_NOT_FOUND))
    (collection-key {creator: tx-sender, gallery-id: gallery-id})
  )
    (asserts! (get verified creator-profile) ERR_CREATOR_NOT_FOUND)
    (asserts! (get active gallery) ERR_GALLERY_NOT_FOUND)
    (asserts! (is-none (map-get? collection-records collection-key)) ERR_ALREADY_FEATURED)
    (asserts! (>= (get floor-price gallery) (get royalty-rate gallery)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (check-category-match (get category-type gallery) (get collections creator-profile)) ERR_INVALID_PARAMS)
    
    (let (
      (royalty-rate (get royalty-rate gallery))
      (marketplace-fee (/ (* royalty-rate (var-get marketplace-fee-percent)) u100))
      (creator-earnings (- royalty-rate marketplace-fee))
    )
      (map-set collection-records collection-key {timestamp: u0, featured: true})
      
      (map-set art-galleries gallery-id (merge gallery {
        floor-price: (- (get floor-price gallery) royalty-rate),
        total-collectors: (+ (get total-collectors gallery) u1)
      }))
      
      (map-set creator-profiles tx-sender (merge creator-profile {
        earnings: (+ (get earnings creator-profile) creator-earnings),
        artwork-count: (+ (get artwork-count creator-profile) u1)
      }))
      
      (var-set marketplace-balance (+ (var-get marketplace-balance) marketplace-fee))
      
      (ok creator-earnings))))

(define-public (claim-earnings)
  (let ((creator-profile (unwrap! (map-get? creator-profiles tx-sender) ERR_CREATOR_NOT_FOUND)))
    (let ((earnings (get earnings creator-profile)))
      (asserts! (> earnings u0) ERR_INSUFFICIENT_FUNDS)
      
      (try! (as-contract (stx-transfer? earnings tx-sender tx-sender)))
      
      (map-set creator-profiles tx-sender (merge creator-profile {
        earnings: u0,
        last-payout: u0
      }))
      
      (ok earnings))))

(define-public (withdraw-marketplace-fees)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (let ((amount (var-get marketplace-balance)))
      (asserts! (> amount u0) ERR_INSUFFICIENT_FUNDS)
      
      (try! (as-contract (stx-transfer? amount tx-sender (var-get contract-owner))))
      
      (var-set marketplace-balance u0)
      
      (ok amount))))

;; Helper functions
(define-private (is-valid-collection (collection uint))
  (is-some (map-get? art-categories collection)))

(define-private (count-valid-collections (collections (list 10 uint)))
  (+ 
    (if (and (> (len collections) u0) (is-valid-collection (unwrap-panic (element-at collections u0)))) u1 u0)
    (if (and (> (len collections) u1) (is-valid-collection (unwrap-panic (element-at collections u1)))) u1 u0)
    (if (and (> (len collections) u2) (is-valid-collection (unwrap-panic (element-at collections u2)))) u1 u0)
    (if (and (> (len collections) u3) (is-valid-collection (unwrap-panic (element-at collections u3)))) u1 u0)
    (if (and (> (len collections) u4) (is-valid-collection (unwrap-panic (element-at collections u4)))) u1 u0)
    (if (and (> (len collections) u5) (is-valid-collection (unwrap-panic (element-at collections u5)))) u1 u0)
    (if (and (> (len collections) u6) (is-valid-collection (unwrap-panic (element-at collections u6)))) u1 u0)
    (if (and (> (len collections) u7) (is-valid-collection (unwrap-panic (element-at collections u7)))) u1 u0)
    (if (and (> (len collections) u8) (is-valid-collection (unwrap-panic (element-at collections u8)))) u1 u0)
    (if (and (> (len collections) u9) (is-valid-collection (unwrap-panic (element-at collections u9)))) u1 u0)
  ))

(define-private (validate-collections (collections (list 10 uint)))
  (let ((collections-len (len collections)))
    (and 
      (> collections-len u0)
      (<= collections-len u10)
      (is-eq collections-len (count-valid-collections collections)))))

;; Read-only functions
(define-read-only (get-creator-profile (creator principal))
  (map-get? creator-profiles creator))

(define-read-only (get-gallery (gallery-id uint))
  (map-get? art-galleries gallery-id))

(define-read-only (get-category (category-id uint))
  (map-get? art-categories category-id))

(define-read-only (get-marketplace-fee)
  (var-get marketplace-fee-percent))

(define-read-only (get-marketplace-balance)
  (var-get marketplace-balance))

(define-read-only (get-collection-record (creator principal) (gallery-id uint))
  (map-get? collection-records {creator: creator, gallery-id: gallery-id}))
