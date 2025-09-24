;; Forest Biodiversity Registry
;; Species population tracking and ecosystem health monitoring through acoustic and camera trap networks

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-SPECIES-NOT-FOUND (err u201))
(define-constant ERR-INVALID-POPULATION (err u202))
(define-constant ERR-INVALID-STATUS (err u203))
(define-constant ERR-MONITORING-SITE-NOT-FOUND (err u204))
(define-constant ERR-INVALID-COORDINATES (err u205))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Conservation status constants
(define-constant STATUS-LEAST-CONCERN u1)
(define-constant STATUS-NEAR-THREATENED u2)
(define-constant STATUS-VULNERABLE u3)
(define-constant STATUS-ENDANGERED u4)
(define-constant STATUS-CRITICALLY-ENDANGERED u5)
(define-constant STATUS-EXTINCT-IN-WILD u6)
(define-constant STATUS-EXTINCT u7)

;; Monitoring method constants
(define-constant METHOD-CAMERA-TRAP u1)
(define-constant METHOD-ACOUSTIC u2)
(define-constant METHOD-VISUAL-SURVEY u3)
(define-constant METHOD-TRACKING u4)
(define-constant METHOD-SATELLITE u5)

;; Data maps
(define-map species-registry
    (string-ascii 100)
    {
        scientific-name: (string-ascii 100),
        common-name: (string-ascii 100),
        conservation-status: uint,
        population-estimate: uint,
        last-updated: uint,
        habitat-type: (string-ascii 50),
        monitoring-sites: uint,
        researcher: principal
    }
)

(define-map monitoring-sites
    uint
    {
        site-name: (string-ascii 100),
        location-lat: int,
        location-lng: int,
        site-type: (string-ascii 30),
        monitoring-methods: uint,
        species-count: uint,
        established-date: uint,
        manager: principal,
        is-active: bool
    }
)

(define-map population-records
    { species-id: (string-ascii 100), site-id: uint, timestamp: uint }
    {
        population-count: uint,
        monitoring-method: uint,
        confidence-level: uint,
        observer: principal,
        notes: (string-ascii 500)
    }
)

(define-map ecosystem-health
    uint
    {
        site-id: uint,
        biodiversity-index: uint,
        species-richness: uint,
        habitat-quality: uint,
        threat-level: uint,
        assessment-date: uint,
        assessor: principal
    }
)

(define-map authorized-researchers
    principal
    {
        is-authorized: bool,
        specialization: (string-ascii 50),
        institution: (string-ascii 100)
    }
)

;; Data variables
(define-data-var species-counter uint u0)
(define-data-var site-counter uint u0)
(define-data-var total-species-tracked uint u0)
(define-data-var endangered-species-count uint u0)

;; Authorization functions
(define-private (is-authorized-researcher (researcher principal))
    (or
        (is-eq researcher CONTRACT-OWNER)
        (default-to false
            (get is-authorized (map-get? authorized-researchers researcher))
        )
    )
)

;; Public functions

;; Register a new species in the registry
(define-public (register-species (species-id (string-ascii 100))
                                 (scientific-name (string-ascii 100))
                                 (common-name (string-ascii 100))
                                 (conservation-status uint)
                                 (habitat-type (string-ascii 50)))
    (begin
        (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= conservation-status STATUS-LEAST-CONCERN) 
                       (<= conservation-status STATUS-EXTINCT)) ERR-INVALID-STATUS)
        
        (map-set species-registry
            species-id
            {
                scientific-name: scientific-name,
                common-name: common-name,
                conservation-status: conservation-status,
                population-estimate: u0,
                last-updated: stacks-block-height,
                habitat-type: habitat-type,
                monitoring-sites: u0,
                researcher: tx-sender
            }
        )
        
        (var-set species-counter (+ (var-get species-counter) u1))
        (var-set total-species-tracked (+ (var-get total-species-tracked) u1))
        
        ;; Update endangered count if applicable
        (if (>= conservation-status STATUS-VULNERABLE)
            (var-set endangered-species-count (+ (var-get endangered-species-count) u1))
            true
        )
        
        (ok species-id)
    )
)

;; Establish a new monitoring site
(define-public (establish-monitoring-site (site-name (string-ascii 100))
                                          (lat int)
                                          (lng int)
                                          (site-type (string-ascii 30))
                                          (monitoring-methods uint))
    (let
        (
            (site-id (+ (var-get site-counter) u1))
        )
        (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR-INVALID-COORDINATES)
        (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR-INVALID-COORDINATES)
        
        (map-set monitoring-sites
            site-id
            {
                site-name: site-name,
                location-lat: lat,
                location-lng: lng,
                site-type: site-type,
                monitoring-methods: monitoring-methods,
                species-count: u0,
                established-date: stacks-block-height,
                manager: tx-sender,
                is-active: true
            }
        )
        
        (var-set site-counter site-id)
        (ok site-id)
    )
)

;; Record population observation
(define-public (record-population (species-id (string-ascii 100))
                                  (site-id uint)
                                  (population-count uint)
                                  (monitoring-method uint)
                                  (confidence-level uint)
                                  (notes (string-ascii 500)))
    (begin
        (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? species-registry species-id)) ERR-SPECIES-NOT-FOUND)
        (asserts! (is-some (map-get? monitoring-sites site-id)) ERR-MONITORING-SITE-NOT-FOUND)
        (asserts! (and (>= monitoring-method METHOD-CAMERA-TRAP) 
                       (<= monitoring-method METHOD-SATELLITE)) ERR-INVALID-STATUS)
        (asserts! (and (>= confidence-level u1) (<= confidence-level u100)) ERR-INVALID-POPULATION)
        
        (map-set population-records
            { species-id: species-id, site-id: site-id, timestamp: stacks-block-height }
            {
                population-count: population-count,
                monitoring-method: monitoring-method,
                confidence-level: confidence-level,
                observer: tx-sender,
                notes: notes
            }
        )
        
        ;; Update species population estimate
        (match (map-get? species-registry species-id)
            species-data
            (map-set species-registry
                species-id
                (merge species-data 
                    { 
                        population-estimate: (+ (get population-estimate species-data) population-count),
                        last-updated: stacks-block-height
                    }
                )
            )
            false
        )
        
        ;; Update site species count
        (match (map-get? monitoring-sites site-id)
            site-data
            (map-set monitoring-sites
                site-id
                (merge site-data 
                    { species-count: (+ (get species-count site-data) u1) }
                )
            )
            false
        )
        
        (ok true)
    )
)

;; Update species conservation status
(define-public (update-conservation-status (species-id (string-ascii 100)) 
                                           (new-status uint))
    (begin
        (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? species-registry species-id)) ERR-SPECIES-NOT-FOUND)
        (asserts! (and (>= new-status STATUS-LEAST-CONCERN) 
                       (<= new-status STATUS-EXTINCT)) ERR-INVALID-STATUS)
        
        (match (map-get? species-registry species-id)
            species-data
            (let
                (
                    (old-status (get conservation-status species-data))
                )
                (map-set species-registry
                    species-id
                    (merge species-data 
                        { 
                            conservation-status: new-status,
                            last-updated: stacks-block-height
                        }
                    )
                )
                
                ;; Update endangered count
                (if (and (< old-status STATUS-VULNERABLE) (>= new-status STATUS-VULNERABLE))
                    (var-set endangered-species-count (+ (var-get endangered-species-count) u1))
                    (if (and (>= old-status STATUS-VULNERABLE) (< new-status STATUS-VULNERABLE))
                        (var-set endangered-species-count 
                            (if (> (var-get endangered-species-count) u0)
                                (- (var-get endangered-species-count) u1)
                                u0
                            )
                        )
                        true
                    )
                )
                
                (ok true)
            )
            ERR-SPECIES-NOT-FOUND
        )
    )
)

;; Assess ecosystem health
(define-public (assess-ecosystem-health (site-id uint)
                                        (biodiversity-index uint)
                                        (species-richness uint)
                                        (habitat-quality uint)
                                        (threat-level uint))
    (begin
        (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? monitoring-sites site-id)) ERR-MONITORING-SITE-NOT-FOUND)
        (asserts! (and (<= biodiversity-index u100) (<= habitat-quality u100)) ERR-INVALID-STATUS)
        
        (map-set ecosystem-health
            site-id
            {
                site-id: site-id,
                biodiversity-index: biodiversity-index,
                species-richness: species-richness,
                habitat-quality: habitat-quality,
                threat-level: threat-level,
                assessment-date: stacks-block-height,
                assessor: tx-sender
            }
        )
        
        (ok true)
    )
)

;; Authorize researcher
(define-public (authorize-researcher (researcher principal) 
                                     (specialization (string-ascii 50))
                                     (institution (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-researchers
            researcher
            {
                is-authorized: true,
                specialization: specialization,
                institution: institution
            }
        )
        (ok true)
    )
)

;; Deactivate monitoring site
(define-public (deactivate-site (site-id uint))
    (begin
        (asserts! (is-authorized-researcher tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? monitoring-sites site-id)) ERR-MONITORING-SITE-NOT-FOUND)
        
        (match (map-get? monitoring-sites site-id)
            site-data
            (begin
                (map-set monitoring-sites
                    site-id
                    (merge site-data { is-active: false })
                )
                (ok true)
            )
            ERR-MONITORING-SITE-NOT-FOUND
        )
    )
)

;; Read-only functions

;; Get species information
(define-read-only (get-species (species-id (string-ascii 100)))
    (map-get? species-registry species-id)
)

;; Get monitoring site information
(define-read-only (get-monitoring-site (site-id uint))
    (map-get? monitoring-sites site-id)
)

;; Get population record
(define-read-only (get-population-record (species-id (string-ascii 100)) (site-id uint) (timestamp uint))
    (map-get? population-records { species-id: species-id, site-id: site-id, timestamp: timestamp })
)

;; Get ecosystem health assessment
(define-read-only (get-ecosystem-health (site-id uint))
    (map-get? ecosystem-health site-id)
)

;; Get total species count
(define-read-only (get-total-species)
    (var-get total-species-tracked)
)

;; Get endangered species count
(define-read-only (get-endangered-count)
    (var-get endangered-species-count)
)

;; Get total monitoring sites
(define-read-only (get-total-sites)
    (var-get site-counter)
)

;; Check researcher authorization
(define-read-only (get-researcher-info (researcher principal))
    (map-get? authorized-researchers researcher)
)

;; Calculate conservation urgency score
(define-read-only (calculate-urgency-score (species-id (string-ascii 100)))
    (match (map-get? species-registry species-id)
        species-data
        (let
            (
                (status-weight (get conservation-status species-data))
                (population-factor (if (< (get population-estimate species-data) u100) u10 u1))
            )
            (* status-weight population-factor)
        )
        u0
    )
)

;; title: forest-biodiversity-registry
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

