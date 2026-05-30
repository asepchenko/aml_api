-- =============================================================================
-- Deploy di HeidiSQL (WAJIB ikuti langkah ini, jangan pakai Run selection kosong)
-- 1. Buka tab Query, pilih database `lke`
-- 2. Di toolbar query, set "Delimiter" / "Query delimiter" = //
--    (bukan ; — kalau pakai ; hasilnya "0 queries" / SP tidak ke-update)
-- 3. Select ALL (Ctrl+A) lalu Execute (F9)
-- 4. Verifikasi:
--    SHOW CREATE PROCEDURE sp_driver_dashboard_json;
--    CALL sp_driver_dashboard_json('1');
-- =============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_dashboard_json//

CREATE PROCEDURE `sp_driver_dashboard_json`(
    IN `p_user_id` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
BEGIN
    DECLARE v_pickup_request INT DEFAULT 0;
    DECLARE v_delivery_active INT DEFAULT 0;
    DECLARE v_pickup_retur_active INT DEFAULT 0;

    /* Pickup request — selaras recentPickups */
    SELECT COUNT(*)
    INTO v_pickup_request
    FROM pickup_requests p
    WHERE p.last_status IN ('pending', 'accept', 'done')
      AND p.request_date >= CURDATE() - INTERVAL 30 DAY
      AND (p.driver_id = p_user_id OR p.driver_id IS NULL);

    /* Delivery DPL (dooring) — selaras recentDeliverys */
    SELECT COUNT(*)
    INTO v_delivery_active
    FROM delivery_packing_lists d
    WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
      AND d.packing_list_date >= CURDATE() - INTERVAL 30 DAY
      AND IFNULL(d.last_status, 'Open') NOT IN ('Closed', 'Delivered', 'Received');

    /* Pickup retur — selaras recentPickupReturs */
    SELECT COUNT(*)
    INTO v_pickup_retur_active
    FROM pickup_returs pr
    WHERE pr.driver_id = CAST(p_user_id AS UNSIGNED)
      AND pr.retur_date >= CURDATE() - INTERVAL 30 DAY
      AND IFNULL(pr.last_status, 'draft') IN ('assigned', 'on_trip', 'draft');

    SELECT JSON_OBJECT(
        '_schemaVersion', 3,
        'stats', JSON_ARRAY(
            JSON_OBJECT('label', 'Pickup Request', 'value', CAST(v_pickup_request AS CHAR)),
            JSON_OBJECT('label', 'Delivery DPL', 'value', CAST(v_delivery_active AS CHAR)),
            JSON_OBJECT('label', 'Pickup Retur', 'value', CAST(v_pickup_retur_active AS CHAR))
        ),
        'recentPickups', IFNULL((
            SELECT JSON_ARRAYAGG(pickup_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', CAST(p.id AS CHAR),
                    'code', p.request_number,
                    'customer_name', c.customer_name,
                    'pickup_address', p.address,
                    'schedule_time', p.request_time,
                    'status', p.last_status
                ) AS pickup_data
                FROM pickup_requests p
                LEFT JOIN customers c ON p.customer_id = c.id
                WHERE p.last_status IN ('pending', 'accept', 'done')
                  AND p.request_date >= CURDATE() - INTERVAL 30 DAY
                  AND (p.driver_id = p_user_id OR p.driver_id IS NULL)
                ORDER BY p.request_date DESC
                LIMIT 10
            ) x
        ), JSON_ARRAY()),
        'recentDeliverys', IFNULL((
            SELECT JSON_ARRAYAGG(delivery_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', CAST(d.id AS CHAR),
                    'code', d.packing_list_number,
                    'packing_list_date', DATE_FORMAT(d.packing_list_date, '%Y-%m-%d'),
                    'origin', IFNULL(d.origin, '-'),
                    'police_number', IFNULL(d.police_number, '-'),
                    'total_order', IFNULL(d.total_order, 0),
                    'total_kg', IFNULL(d.total_kg, 0),
                    'truck_type', IFNULL(tt.type_name, '-'),
                    'status', IFNULL(d.last_status, 'Open')
                ) AS delivery_data
                FROM delivery_packing_lists d
                LEFT JOIN trucks tr ON d.truck_id = tr.id
                LEFT JOIN truck_types tt ON tr.truck_type_id = tt.id
                WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
                  AND d.packing_list_date >= CURDATE() - INTERVAL 30 DAY
                  AND IFNULL(d.last_status, 'Open') NOT IN ('Closed', 'Delivered', 'Received')
                ORDER BY d.packing_list_date DESC, d.packing_list_number DESC
                LIMIT 10
            ) y
        ), JSON_ARRAY()),
        'recentPickupReturs', IFNULL((
            SELECT JSON_ARRAYAGG(retur_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', CAST(pr.id AS CHAR),
                    'code', pr.retur_number,
                    'retur_date', DATE_FORMAT(pr.retur_date, '%Y-%m-%d'),
                    'no_pol', IFNULL(pr.no_pol, '-'),
                    'total_order', IFNULL(pr.total_order, 0),
                    'total_kg', IFNULL(pr.total_kg, 0),
                    'notes', IFNULL(pr.notes, '-'),
                    'status', IFNULL(pr.last_status, 'draft')
                ) AS retur_data
                FROM pickup_returs pr
                WHERE pr.driver_id = CAST(p_user_id AS UNSIGNED)
                  AND pr.retur_date >= CURDATE() - INTERVAL 30 DAY
                  AND IFNULL(pr.last_status, 'draft') IN ('assigned', 'on_trip', 'draft')
                ORDER BY pr.retur_date DESC, pr.retur_number DESC
                LIMIT 10
            ) z
        ), JSON_ARRAY())
    ) AS json_result;
END//

DELIMITER ;
