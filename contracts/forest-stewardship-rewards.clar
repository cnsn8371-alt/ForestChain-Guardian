;; Forest Stewardship Rewards
;; Token incentives for tree planting, wildlife monitoring, fire prevention, and indigenous land rights support

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INSUFFICIENT-BALANCE (err u401))
(define-constant ERR-INVALID-AMOUNT (err u402))
(define-constant ERR-REWARD-NOT-FOUND (err u403))
(define-constant ERR-ALREADY-CLAIMED (err u404))
(define-constant ERR-CLAIM-EXPIRED (err u405))
(define-constant ERR-INVALID-ACTIVITY (err u406))
(define-constant ERR-STAKING-NOT-FOUND (err u407))
(define-constant ERR-UNSTAKING-TOO-EARLY (err u408))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Token constants
(define-constant TOKEN-NAME "ForestGuardian")
(define-constant TOKEN-SYMBOL "FRST")
(define-constant TOKEN-DECIMALS u6)
(define-constant TOKEN-MAX-SUPPLY u1000000000000) ;; 1M tokens with 6 decimals

;; Activity type constants
(define-constant ACTIVITY-TREE-PLANTING u1)
(define-constant ACTIVITY-WILDLIFE-MONITORING u2)
(define-constant ACTIVITY-FIRE-PREVENTION u3)
(define-constant ACTIVITY-INDIGENOUS-SUPPORT u4)
(define-constant ACTIVITY-DEFORESTATION-REPORTING u5)
(define-constant ACTIVITY-RESEARCH-CONTRIBUTION u6)

;; Reward multipliers (basis points, 10000 = 100%)
(define-constant MULTIPLIER-TREE-PLANTING u100)    ;; 1% per tree
(define-constant MULTIPLIER-WILDLIFE-MONITORING u500) ;; 5% per report
(define-constant MULTIPLIER-FIRE-PREVENTION u1000)    ;; 10% per alert
(define-constant MULTIPLIER-INDIGENOUS-SUPPORT u2000) ;; 20% per project
(define-constant MULTIPLIER-DEFORESTATION-REPORTING u1500) ;; 15% per report
(define-constant MULTIPLIER-RESEARCH-CONTRIBUTION u800)    ;; 8% per contribution

;; Fungible token implementation (SIP-010 compatible)

;; Token data maps
(define-map token-balances principal uint)
(define-map token-supplies uint uint)

;; Stewardship activity tracking
(define-map stewardship-activities
    uint
    {
        participant: principal,
        activity-type: uint,
        quantity: uint,
        location-lat: int,
        location-lng: int,
        reported-at: uint,
        verified: bool,
        verifier: (optional principal),
        description: (string-ascii 500),
        reward-amount: uint,
        claimed: bool
    }
)

(define-map reward-claims
    { participant: principal, activity-id: uint }
    {
        claimed-at: uint,
        amount: uint,
        tx-hash: (optional (buff 32))
    }
)

(define-map staking-positions
    { staker: principal, stake-id: uint }
    {
        amount-staked: uint,
        staking-start: uint,
        staking-period: uint,
        reward-rate: uint,
        last-claim: uint,
        is-active: bool
    }
)

(define-map authorized-verifiers
    principal
    {
        is-authorized: bool,
        verification-types: uint,
        reputation-score: uint
    }
)

(define-map governance-proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 1000),
        proposal-type: uint,
        votes-for: uint,
        votes-against: uint,
        voting-ends: uint,
        executed: bool,
        minimum-votes: uint
    }
)

;; Data variables
(define-data-var total-supply uint u0)
(define-data-var activity-counter uint u0)
(define-data-var stake-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var base-reward-amount uint u1000000) ;; 1 token base reward
(define-data-var staking-reward-rate uint u500)     ;; 5% annual reward
(define-data-var total-staked uint u0)
(define-data-var governance-threshold uint u100000000) ;; 100 tokens to propose

;; SIP-010 Standard Functions

(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
    (begin
        (asserts! (or (is-eq tx-sender from) (is-eq contract-caller from)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (get-balance from) amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; Update balances
        (map-set token-balances from (- (get-balance from) amount))
        (map-set token-balances to (+ (get-balance to) amount))
        
        ;; Print transfer event
        (print {action: "transfer", sender: from, recipient: to, amount: amount, memo: memo})
        (ok true)
    )
)

(define-read-only (get-name)
    (ok TOKEN-NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN-SYMBOL)
)

(define-read-only (get-decimals)
    (ok TOKEN-DECIMALS)
)

(define-read-only (get-balance (account principal))
    (default-to u0 (map-get? token-balances account))
)

(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

(define-read-only (get-token-uri)
    (ok (some u"https://forestchain-guardian.org/token-metadata.json"))
)

;; Private functions

(define-private (mint-tokens (recipient principal) (amount uint))
    (let
        (
            (new-supply (+ (var-get total-supply) amount))
        )
        (asserts! (<= new-supply TOKEN-MAX-SUPPLY) ERR-INVALID-AMOUNT)
        (map-set token-balances recipient (+ (get-balance recipient) amount))
        (var-set total-supply new-supply)
        (print {action: "mint", recipient: recipient, amount: amount})
        (ok true)
    )
)

(define-private (calculate-reward (activity-type uint) (quantity uint))
    (let
        (
            (base-reward (var-get base-reward-amount))
            (multiplier (if (is-eq activity-type ACTIVITY-TREE-PLANTING)
                MULTIPLIER-TREE-PLANTING
                (if (is-eq activity-type ACTIVITY-WILDLIFE-MONITORING)
                    MULTIPLIER-WILDLIFE-MONITORING
                    (if (is-eq activity-type ACTIVITY-FIRE-PREVENTION)
                        MULTIPLIER-FIRE-PREVENTION
                        (if (is-eq activity-type ACTIVITY-INDIGENOUS-SUPPORT)
                            MULTIPLIER-INDIGENOUS-SUPPORT
                            (if (is-eq activity-type ACTIVITY-DEFORESTATION-REPORTING)
                                MULTIPLIER-DEFORESTATION-REPORTING
                                (if (is-eq activity-type ACTIVITY-RESEARCH-CONTRIBUTION)
                                    MULTIPLIER-RESEARCH-CONTRIBUTION
                                    u100 ;; Default 1%
                                )
                            )
                        )
                    )
                )
            ))
        )
        (/ (* base-reward quantity multiplier) u10000)
    )
)

;; Public functions

;; Report stewardship activity
(define-public (report-activity (activity-type uint)
                                (quantity uint)
                                (lat int)
                                (lng int)
                                (description (string-ascii 500)))
    (let
        (
            (activity-id (+ (var-get activity-counter) u1))
            (reward-amount (calculate-reward activity-type quantity))
        )
        (asserts! (and (>= activity-type ACTIVITY-TREE-PLANTING) 
                       (<= activity-type ACTIVITY-RESEARCH-CONTRIBUTION)) ERR-INVALID-ACTIVITY)
        (asserts! (> quantity u0) ERR-INVALID-AMOUNT)
        (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR-INVALID-AMOUNT)
        (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR-INVALID-AMOUNT)
        
        (map-set stewardship-activities
            activity-id
            {
                participant: tx-sender,
                activity-type: activity-type,
                quantity: quantity,
                location-lat: lat,
                location-lng: lng,
                reported-at: stacks-block-height,
                verified: false,
                verifier: none,
                description: description,
                reward-amount: reward-amount,
                claimed: false
            }
        )
        
        (var-set activity-counter activity-id)
        (ok activity-id)
    )
)

;; Verify stewardship activity
(define-public (verify-activity (activity-id uint))
    (begin
        (asserts! (is-some (map-get? stewardship-activities activity-id)) ERR-REWARD-NOT-FOUND)
        (asserts! (default-to false (get is-authorized (map-get? authorized-verifiers tx-sender))) 
                  ERR-NOT-AUTHORIZED)
        
        (match (map-get? stewardship-activities activity-id)
            activity-data
            (begin
                (map-set stewardship-activities
                    activity-id
                    (merge activity-data { verified: true, verifier: (some tx-sender) })
                )
                (ok true)
            )
            ERR-REWARD-NOT-FOUND
        )
    )
)

;; Claim reward for verified activity
(define-public (claim-reward (activity-id uint))
    (begin
        (asserts! (is-some (map-get? stewardship-activities activity-id)) ERR-REWARD-NOT-FOUND)
        
        (match (map-get? stewardship-activities activity-id)
            activity-data
            (begin
                (asserts! (is-eq tx-sender (get participant activity-data)) ERR-NOT-AUTHORIZED)
                (asserts! (get verified activity-data) ERR-NOT-AUTHORIZED)
                (asserts! (not (get claimed activity-data)) ERR-ALREADY-CLAIMED)
                
                ;; Mint reward tokens
                (try! (mint-tokens tx-sender (get reward-amount activity-data)))
                
                ;; Mark as claimed
                (map-set stewardship-activities
                    activity-id
                    (merge activity-data { claimed: true })
                )
                
                ;; Record claim
                (map-set reward-claims
                    { participant: tx-sender, activity-id: activity-id }
                    {
                claimed-at: stacks-block-height,
                        amount: (get reward-amount activity-data),
                        tx-hash: none
                    }
                )
                
                (ok (get reward-amount activity-data))
            )
            ERR-REWARD-NOT-FOUND
        )
    )
)

;; Stake tokens for governance and rewards
(define-public (stake-tokens (amount uint) (staking-period uint))
    (let
        (
            (stake-id (+ (var-get stake-counter) u1))
        )
        (asserts! (>= (get-balance tx-sender) amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= staking-period u4320) ERR-INVALID-AMOUNT) ;; Minimum 30 days
        
        ;; Transfer tokens to contract (effectively burning from circulation)
        (try! (transfer amount tx-sender (as-contract tx-sender) none))
        
        (map-set staking-positions
            { staker: tx-sender, stake-id: stake-id }
            {
                amount-staked: amount,
                staking-start: stacks-block-height,
                staking-period: staking-period,
                reward-rate: (var-get staking-reward-rate),
                last-claim: stacks-block-height,
                is-active: true
            }
        )
        
        (var-set stake-counter stake-id)
        (var-set total-staked (+ (var-get total-staked) amount))
        (ok stake-id)
    )
)

;; Claim staking rewards
(define-public (claim-staking-rewards (stake-id uint))
    (begin
        (asserts! (is-some (map-get? staking-positions { staker: tx-sender, stake-id: stake-id })) 
                  ERR-STAKING-NOT-FOUND)
        
        (match (map-get? staking-positions { staker: tx-sender, stake-id: stake-id })
            stake-data
            (let
                (
                    (blocks-elapsed (- stacks-block-height (get last-claim stake-data)))
                    (reward-amount (/ (* (get amount-staked stake-data) 
                                         (get reward-rate stake-data) 
                                         blocks-elapsed) 
                                     u525600)) ;; Approximate blocks per year
                )
                (asserts! (get is-active stake-data) ERR-STAKING-NOT-FOUND)
                (asserts! (> blocks-elapsed u144) ERR-INVALID-AMOUNT) ;; Min 1 day between claims
                
                ;; Mint reward tokens
                (try! (mint-tokens tx-sender reward-amount))
                
                ;; Update last claim
                (map-set staking-positions
                    { staker: tx-sender, stake-id: stake-id }
                    (merge stake-data { last-claim: stacks-block-height })
                )
                
                (ok reward-amount)
            )
            ERR-STAKING-NOT-FOUND
        )
    )
)

;; Unstake tokens
(define-public (unstake-tokens (stake-id uint))
    (begin
        (asserts! (is-some (map-get? staking-positions { staker: tx-sender, stake-id: stake-id })) 
                  ERR-STAKING-NOT-FOUND)
        
        (match (map-get? staking-positions { staker: tx-sender, stake-id: stake-id })
            stake-data
            (begin
                (asserts! (get is-active stake-data) ERR-STAKING-NOT-FOUND)
                (asserts! (>= stacks-block-height (+ (get staking-start stake-data) (get staking-period stake-data)))
                          ERR-UNSTAKING-TOO-EARLY)
                
                ;; Return staked tokens
                (try! (as-contract (transfer (get amount-staked stake-data) 
                                             (as-contract tx-sender) 
                                             tx-sender 
                                             none)))
                
                ;; Deactivate stake
                (map-set staking-positions
                    { staker: tx-sender, stake-id: stake-id }
                    (merge stake-data { is-active: false })
                )
                
                (var-set total-staked (- (var-get total-staked) (get amount-staked stake-data)))
                (ok (get amount-staked stake-data))
            )
            ERR-STAKING-NOT-FOUND
        )
    )
)

;; Authorize verifier
(define-public (authorize-verifier (verifier principal) 
                                   (verification-types uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-verifiers
            verifier
            {
                is-authorized: true,
                verification-types: verification-types,
                reputation-score: u100
            }
        )
        (ok true)
    )
)

;; Initial token distribution (only owner)
(define-public (initial-mint (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (try! (mint-tokens recipient amount))
        (ok amount)
    )
)

;; Read-only functions

;; Get activity details
(define-read-only (get-activity (activity-id uint))
    (map-get? stewardship-activities activity-id)
)

;; Get staking position
(define-read-only (get-staking-position (staker principal) (stake-id uint))
    (map-get? staking-positions { staker: staker, stake-id: stake-id })
)

;; Get reward claim
(define-read-only (get-reward-claim (participant principal) (activity-id uint))
    (map-get? reward-claims { participant: participant, activity-id: activity-id })
)

;; Get total activities reported
(define-read-only (get-total-activities)
    (var-get activity-counter)
)

;; Get total staked amount
(define-read-only (get-total-staked)
    (var-get total-staked)
)

;; Check if user is authorized verifier
(define-read-only (is-authorized-verifier (verifier principal))
    (default-to false (get is-authorized (map-get? authorized-verifiers verifier)))
)

;; Calculate pending staking rewards
(define-read-only (calculate-pending-rewards (staker principal) (stake-id uint))
    (match (map-get? staking-positions { staker: staker, stake-id: stake-id })
        stake-data
        (if (get is-active stake-data)
            (let
                (
                    (blocks-elapsed (- stacks-block-height (get last-claim stake-data)))
                    (reward-amount (/ (* (get amount-staked stake-data) 
                                         (get reward-rate stake-data) 
                                         blocks-elapsed) 
                                     u525600))
                )
                reward-amount
            )
            u0
        )
        u0
    )
)

;; title: forest-stewardship-rewards
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

