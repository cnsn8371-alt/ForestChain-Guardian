;; Sustainable Logging Verification
;; Certification and tracking of legally harvested timber with replanting requirement enforcement

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PERMIT-NOT-FOUND (err u301))
(define-constant ERR-INVALID-VOLUME (err u302))
(define-constant ERR-PERMIT-EXPIRED (err u303))
(define-constant ERR-CERTIFICATION-NOT-FOUND (err u304))
(define-constant ERR-INVALID-COORDINATES (err u305))
(define-constant ERR-REPLANTING-OVERDUE (err u306))
(define-constant ERR-INSUFFICIENT-REPLANTING (err u307))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Permit status constants
(define-constant PERMIT-ACTIVE u1)
(define-constant PERMIT-SUSPENDED u2)
(define-constant PERMIT-REVOKED u3)
(define-constant PERMIT-COMPLETED u4)
(define-constant PERMIT-EXPIRED u5)

;; Certification types
(define-constant CERT-FSC u1)      ;; Forest Stewardship Council
(define-constant CERT-PEFC u2)     ;; Programme for Endorsement of Forest Certification
(define-constant CERT-SFI u3)      ;; Sustainable Forestry Initiative
(define-constant CERT-ATFS u4)     ;; American Tree Farm System
(define-constant CERT-CUSTOM u5)   ;; Custom certification

;; Data maps
(define-map logging-permits
    uint
    {
        operator: principal,
        forest-area-id: uint,
        location-lat: int,
        location-lng: int,
        authorized-volume: uint,
        harvested-volume: uint,
        permit-start: uint,
        permit-end: uint,
        status: uint,
        certification-required: uint,
        replanting-deadline: uint,
        trees-replanted: uint,
        minimum-replanting: uint
    }
)

(define-map forest-certifications
    uint
    {
        certificate-id: (string-ascii 100),
        certification-type: uint,
        forest-area-id: uint,
        issued-to: principal,
        issued-date: uint,
        expiry-date: uint,
        certifying-body: (string-ascii 100),
        is-valid: bool,
        sustainability-score: uint
    }
)

(define-map harvest-logs
    { permit-id: uint, batch-id: uint }
    {
        harvest-date: uint,
        volume-harvested: uint,
        tree-species: (string-ascii 50),
        quality-grade: uint,
        logger: principal,
        verified: bool,
        chain-of-custody: (string-ascii 200)
    }
)

(define-map replanting-records
    { permit-id: uint, planting-date: uint }
    {
        trees-planted: uint,
        species-planted: (string-ascii 50),
        survival-rate: uint,
        planting-location-lat: int,
        planting-location-lng: int,
        planter: principal,
        verified: bool
    }
)

(define-map authorized-certifiers
    principal
    {
        is-authorized: bool,
        certification-types: uint,
        organization: (string-ascii 100)
    }
)

(define-map authorized-inspectors
    principal
    {
        is-authorized: bool,
        inspector-id: (string-ascii 50),
        specialization: (string-ascii 50)
    }
)

;; Data variables
(define-data-var permit-counter uint u0)
(define-data-var certification-counter uint u0)
(define-data-var total-volume-harvested uint u0)
(define-data-var total-trees-replanted uint u0)
(define-data-var compliance-threshold uint u80)

;; Authorization functions
(define-private (is-authorized-certifier (certifier principal))
    (or
        (is-eq certifier CONTRACT-OWNER)
        (default-to false
            (get is-authorized (map-get? authorized-certifiers certifier))
        )
    )
)

(define-private (is-authorized-inspector (inspector principal))
    (or
        (is-eq inspector CONTRACT-OWNER)
        (default-to false
            (get is-authorized (map-get? authorized-inspectors inspector))
        )
    )
)

;; Public functions

;; Issue logging permit
(define-public (issue-logging-permit (operator principal)
                                     (forest-area-id uint)
                                     (lat int)
                                     (lng int)
                                     (authorized-volume uint)
                                     (permit-duration uint)
                                     (certification-required uint)
                                     (minimum-replanting uint))
    (let
        (
            (permit-id (+ (var-get permit-counter) u1))
            (permit-end (+ stacks-block-height permit-duration))
            (replanting-deadline (+ permit-end u4320)) ;; ~30 days after permit end
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR-INVALID-COORDINATES)
        (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR-INVALID-COORDINATES)
        (asserts! (> authorized-volume u0) ERR-INVALID-VOLUME)
        
        (map-set logging-permits
            permit-id
            {
                operator: operator,
                forest-area-id: forest-area-id,
                location-lat: lat,
                location-lng: lng,
                authorized-volume: authorized-volume,
                harvested-volume: u0,
                permit-start: stacks-block-height,
                permit-end: permit-end,
                status: PERMIT-ACTIVE,
                certification-required: certification-required,
                replanting-deadline: replanting-deadline,
                trees-replanted: u0,
                minimum-replanting: minimum-replanting
            }
        )
        
        (var-set permit-counter permit-id)
        (ok permit-id)
    )
)

;; Issue forest certification
(define-public (issue-certification (certificate-id (string-ascii 100))
                                    (certification-type uint)
                                    (forest-area-id uint)
                                    (issued-to principal)
                                    (validity-period uint)
                                    (certifying-body (string-ascii 100))
                                    (sustainability-score uint))
    (let
        (
            (cert-id (+ (var-get certification-counter) u1))
            (expiry-date (+ stacks-block-height validity-period))
        )
        (asserts! (is-authorized-certifier tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= certification-type CERT-FSC) 
                       (<= certification-type CERT-CUSTOM)) ERR-INVALID-VOLUME)
        (asserts! (and (>= sustainability-score u0) (<= sustainability-score u100)) ERR-INVALID-VOLUME)
        
        (map-set forest-certifications
            cert-id
            {
                certificate-id: certificate-id,
                certification-type: certification-type,
                forest-area-id: forest-area-id,
                issued-to: issued-to,
                issued-date: stacks-block-height,
                expiry-date: expiry-date,
                certifying-body: certifying-body,
                is-valid: true,
                sustainability-score: sustainability-score
            }
        )
        
        (var-set certification-counter cert-id)
        (ok cert-id)
    )
)

;; Log harvest activity
(define-public (log-harvest (permit-id uint)
                            (batch-id uint)
                            (volume-harvested uint)
                            (tree-species (string-ascii 50))
                            (quality-grade uint)
                            (chain-of-custody (string-ascii 200)))
    (begin
        (asserts! (is-some (map-get? logging-permits permit-id)) ERR-PERMIT-NOT-FOUND)
        
        (match (map-get? logging-permits permit-id)
            permit-data
            (begin
                (asserts! (is-eq tx-sender (get operator permit-data)) ERR-NOT-AUTHORIZED)
                (asserts! (is-eq (get status permit-data) PERMIT-ACTIVE) ERR-PERMIT-EXPIRED)
                (asserts! (<= stacks-block-height (get permit-end permit-data)) ERR-PERMIT-EXPIRED)
                (asserts! (<= (+ (get harvested-volume permit-data) volume-harvested) 
                             (get authorized-volume permit-data)) ERR-INVALID-VOLUME)
                
                ;; Record harvest log
                (map-set harvest-logs
                    { permit-id: permit-id, batch-id: batch-id }
                    {
                        harvest-date: stacks-block-height,
                        volume-harvested: volume-harvested,
                        tree-species: tree-species,
                        quality-grade: quality-grade,
                        logger: tx-sender,
                        verified: false,
                        chain-of-custody: chain-of-custody
                    }
                )
                
                ;; Update permit harvested volume
                (map-set logging-permits
                    permit-id
                    (merge permit-data 
                        { harvested-volume: (+ (get harvested-volume permit-data) volume-harvested) }
                    )
                )
                
                ;; Update global volume
                (var-set total-volume-harvested (+ (var-get total-volume-harvested) volume-harvested))
                
                (ok true)
            )
            ERR-PERMIT-NOT-FOUND
        )
    )
)

;; Record replanting activity
(define-public (record-replanting (permit-id uint)
                                  (trees-planted uint)
                                  (species-planted (string-ascii 50))
                                  (planting-lat int)
                                  (planting-lng int))
    (begin
        (asserts! (is-some (map-get? logging-permits permit-id)) ERR-PERMIT-NOT-FOUND)
        (asserts! (and (>= planting-lat -90000000) (<= planting-lat 90000000)) ERR-INVALID-COORDINATES)
        (asserts! (and (>= planting-lng -180000000) (<= planting-lng 180000000)) ERR-INVALID-COORDINATES)
        
        (match (map-get? logging-permits permit-id)
            permit-data
            (begin
                (asserts! (is-eq tx-sender (get operator permit-data)) ERR-NOT-AUTHORIZED)
                (asserts! (<= stacks-block-height (get replanting-deadline permit-data)) ERR-REPLANTING-OVERDUE)
                
                ;; Record replanting
                (map-set replanting-records
                    { permit-id: permit-id, planting-date: stacks-block-height }
                    {
                        trees-planted: trees-planted,
                        species-planted: species-planted,
                        survival-rate: u0,
                        planting-location-lat: planting-lat,
                        planting-location-lng: planting-lng,
                        planter: tx-sender,
                        verified: false
                    }
                )
                
                ;; Update permit replanting count
                (map-set logging-permits
                    permit-id
                    (merge permit-data 
                        { trees-replanted: (+ (get trees-replanted permit-data) trees-planted) }
                    )
                )
                
                ;; Update global replanting count
                (var-set total-trees-replanted (+ (var-get total-trees-replanted) trees-planted))
                
                (ok true)
            )
            ERR-PERMIT-NOT-FOUND
        )
    )
)

;; Verify harvest log
(define-public (verify-harvest (permit-id uint) (batch-id uint))
    (begin
        (asserts! (is-authorized-inspector tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? harvest-logs { permit-id: permit-id, batch-id: batch-id })) 
                  ERR-PERMIT-NOT-FOUND)
        
        (match (map-get? harvest-logs { permit-id: permit-id, batch-id: batch-id })
            log-data
            (begin
                (map-set harvest-logs
                    { permit-id: permit-id, batch-id: batch-id }
                    (merge log-data { verified: true })
                )
                (ok true)
            )
            ERR-PERMIT-NOT-FOUND
        )
    )
)

;; Verify replanting
(define-public (verify-replanting (permit-id uint) 
                                  (planting-date uint) 
                                  (survival-rate uint))
    (begin
        (asserts! (is-authorized-inspector tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? replanting-records { permit-id: permit-id, planting-date: planting-date })) 
                  ERR-PERMIT-NOT-FOUND)
        (asserts! (<= survival-rate u100) ERR-INVALID-VOLUME)
        
        (match (map-get? replanting-records { permit-id: permit-id, planting-date: planting-date })
            planting-data
            (begin
                (map-set replanting-records
                    { permit-id: permit-id, planting-date: planting-date }
                    (merge planting-data { verified: true, survival-rate: survival-rate })
                )
                (ok true)
            )
            ERR-PERMIT-NOT-FOUND
        )
    )
)

;; Complete permit (check compliance)
(define-public (complete-permit (permit-id uint))
    (begin
        (asserts! (is-some (map-get? logging-permits permit-id)) ERR-PERMIT-NOT-FOUND)
        
        (match (map-get? logging-permits permit-id)
            permit-data
            (begin
                (asserts! (or (is-eq tx-sender (get operator permit-data)) 
                             (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
                (asserts! (>= (get trees-replanted permit-data) 
                             (get minimum-replanting permit-data)) ERR-INSUFFICIENT-REPLANTING)
                
                (map-set logging-permits
                    permit-id
                    (merge permit-data { status: PERMIT-COMPLETED })
                )
                
                (ok true)
            )
            ERR-PERMIT-NOT-FOUND
        )
    )
)

;; Authorize certifier
(define-public (authorize-certifier (certifier principal) 
                                    (certification-types uint)
                                    (organization (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-certifiers
            certifier
            {
                is-authorized: true,
                certification-types: certification-types,
                organization: organization
            }
        )
        (ok true)
    )
)

;; Authorize inspector
(define-public (authorize-inspector (inspector principal) 
                                    (inspector-id (string-ascii 50))
                                    (specialization (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-inspectors
            inspector
            {
                is-authorized: true,
                inspector-id: inspector-id,
                specialization: specialization
            }
        )
        (ok true)
    )
)

;; Read-only functions

;; Get permit details
(define-read-only (get-permit (permit-id uint))
    (map-get? logging-permits permit-id)
)

;; Get certification details
(define-read-only (get-certification (cert-id uint))
    (map-get? forest-certifications cert-id)
)

;; Get harvest log
(define-read-only (get-harvest-log (permit-id uint) (batch-id uint))
    (map-get? harvest-logs { permit-id: permit-id, batch-id: batch-id })
)

;; Get replanting record
(define-read-only (get-replanting-record (permit-id uint) (planting-date uint))
    (map-get? replanting-records { permit-id: permit-id, planting-date: planting-date })
)

;; Get total volume harvested
(define-read-only (get-total-volume-harvested)
    (var-get total-volume-harvested)
)

;; Get total trees replanted
(define-read-only (get-total-trees-replanted)
    (var-get total-trees-replanted)
)

;; Check compliance rate
(define-read-only (calculate-compliance-rate (permit-id uint))
    (match (map-get? logging-permits permit-id)
        permit-data
        (let
            (
                (replanted (get trees-replanted permit-data))
                (required (get minimum-replanting permit-data))
            )
            (if (> required u0)
                (/ (* replanted u100) required)
                u100
            )
        )
        u0
    )
)

;; Check if permit is compliant
(define-read-only (is-permit-compliant (permit-id uint))
    (>= (calculate-compliance-rate permit-id) (var-get compliance-threshold))
)

;; title: sustainable-logging-verification
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

