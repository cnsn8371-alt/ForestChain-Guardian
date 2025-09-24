;; Deforestation Detection System
;; Satellite imagery and ground sensors detecting illegal logging and forest clearing activities

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALERT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-COORDINATES (err u102))
(define-constant ERR-INVALID-THREAT-LEVEL (err u103))
(define-constant ERR-SENSOR-NOT-FOUND (err u104))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Alert status constants
(define-constant ALERT-ACTIVE u1)
(define-constant ALERT-INVESTIGATING u2)
(define-constant ALERT-RESOLVED u3)
(define-constant ALERT-FALSE-POSITIVE u4)

;; Threat level constants
(define-constant THREAT-LOW u1)
(define-constant THREAT-MEDIUM u2)
(define-constant THREAT-HIGH u3)
(define-constant THREAT-CRITICAL u4)

;; Data maps
(define-map deforestation-alerts
    uint
    {
        location-lat: int,
        location-lng: int,
        threat-level: uint,
        detected-at: uint,
        sensor-id: (string-ascii 50),
        area-affected: uint,
        status: uint,
        reporter: principal,
        verified: bool
    }
)

(define-map sensor-registry
    (string-ascii 50)
    {
        location-lat: int,
        location-lng: int,
        sensor-type: (string-ascii 20),
        is-active: bool,
        last-reading: uint,
        owner: principal
    }
)

(define-map authorized-operators
    principal
    {
        is-authorized: bool,
        role: (string-ascii 20)
    }
)

;; Data variables
(define-data-var alert-counter uint u0)
(define-data-var total-area-at-risk uint u0)
(define-data-var emergency-threshold uint u1000)

;; Authorization functions
(define-private (is-authorized (operator principal))
    (or
        (is-eq operator CONTRACT-OWNER)
        (default-to false
            (get is-authorized (map-get? authorized-operators operator))
        )
    )
)

;; Public functions

;; Register a new sensor in the network
(define-public (register-sensor (sensor-id (string-ascii 50))
                                (lat int)
                                (lng int)
                                (sensor-type (string-ascii 20)))
    (begin
        (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR-INVALID-COORDINATES)
        (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR-INVALID-COORDINATES)
        (map-set sensor-registry
            sensor-id
            {
                location-lat: lat,
                location-lng: lng,
                sensor-type: sensor-type,
                is-active: true,
                last-reading: stacks-block-height,
                owner: tx-sender
            }
        )
        (ok sensor-id)
    )
)

;; Submit a deforestation alert
(define-public (submit-alert (lat int)
                             (lng int)
                             (threat-level uint)
                             (sensor-id (string-ascii 50))
                             (area-affected uint))
    (let
        (
            (alert-id (+ (var-get alert-counter) u1))
        )
        (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR-INVALID-COORDINATES)
        (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR-INVALID-COORDINATES)
        (asserts! (and (>= threat-level THREAT-LOW) (<= threat-level THREAT-CRITICAL)) ERR-INVALID-THREAT-LEVEL)
        (asserts! (is-some (map-get? sensor-registry sensor-id)) ERR-SENSOR-NOT-FOUND)
        
        (map-set deforestation-alerts
            alert-id
            {
                location-lat: lat,
                location-lng: lng,
                threat-level: threat-level,
                detected-at: stacks-block-height,
                sensor-id: sensor-id,
                area-affected: area-affected,
                status: ALERT-ACTIVE,
                reporter: tx-sender,
                verified: false
            }
        )
        
        (var-set alert-counter alert-id)
        (var-set total-area-at-risk (+ (var-get total-area-at-risk) area-affected))
        
        ;; Update sensor last reading
        (match (map-get? sensor-registry sensor-id)
            sensor-data
            (map-set sensor-registry
                sensor-id
                (merge sensor-data { last-reading: stacks-block-height })
            )
            false
        )
        
        (ok alert-id)
    )
)

;; Update alert status
(define-public (update-alert-status (alert-id uint) (new-status uint))
    (begin
        (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? deforestation-alerts alert-id)) ERR-ALERT-NOT-FOUND)
        
        (match (map-get? deforestation-alerts alert-id)
            alert-data
            (begin
                (map-set deforestation-alerts
                    alert-id
                    (merge alert-data { status: new-status })
                )
                ;; If resolved, reduce area at risk
                (if (is-eq new-status ALERT-RESOLVED)
                    (var-set total-area-at-risk 
                        (if (>= (var-get total-area-at-risk) (get area-affected alert-data))
                            (- (var-get total-area-at-risk) (get area-affected alert-data))
                            u0
                        )
                    )
                    true
                )
                (ok true)
            )
            ERR-ALERT-NOT-FOUND
        )
    )
)

;; Verify an alert
(define-public (verify-alert (alert-id uint))
    (begin
        (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? deforestation-alerts alert-id)) ERR-ALERT-NOT-FOUND)
        
        (match (map-get? deforestation-alerts alert-id)
            alert-data
            (begin
                (map-set deforestation-alerts
                    alert-id
                    (merge alert-data { verified: true })
                )
                (ok true)
            )
            ERR-ALERT-NOT-FOUND
        )
    )
)

;; Authorize an operator
(define-public (authorize-operator (operator principal) (role (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-operators
            operator
            {
                is-authorized: true,
                role: role
            }
        )
        (ok true)
    )
)

;; Deactivate sensor
(define-public (deactivate-sensor (sensor-id (string-ascii 50)))
    (begin
        (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? sensor-registry sensor-id)) ERR-SENSOR-NOT-FOUND)
        
        (match (map-get? sensor-registry sensor-id)
            sensor-data
            (begin
                (map-set sensor-registry
                    sensor-id
                    (merge sensor-data { is-active: false })
                )
                (ok true)
            )
            ERR-SENSOR-NOT-FOUND
        )
    )
)

;; Read-only functions

;; Get alert details
(define-read-only (get-alert (alert-id uint))
    (map-get? deforestation-alerts alert-id)
)

;; Get sensor details
(define-read-only (get-sensor (sensor-id (string-ascii 50)))
    (map-get? sensor-registry sensor-id)
)

;; Get total alerts count
(define-read-only (get-total-alerts)
    (var-get alert-counter)
)

;; Get total area at risk
(define-read-only (get-total-area-at-risk)
    (var-get total-area-at-risk)
)

;; Check if emergency threshold is exceeded
(define-read-only (is-emergency-state)
    (>= (var-get total-area-at-risk) (var-get emergency-threshold))
)

;; Get operator authorization status
(define-read-only (get-operator-status (operator principal))
    (map-get? authorized-operators operator)
)

;; Count active alerts in area
(define-read-only (count-alerts-in-radius (center-lat int) (center-lng int) (radius uint))
    ;; Simplified implementation - in production would use proper distance calculation
    (var-get alert-counter)
)

;; title: deforestation-detection-system
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

