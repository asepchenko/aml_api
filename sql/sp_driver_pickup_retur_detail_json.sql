-- Detail Pickup Retur + STT untuk driver
-- CALL sp_driver_pickup_retur_detail_json('1', 'RET-xxx' atau id);

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_pickup_retur_detail_json//

CREATE PROCEDURE `sp_driver_pickup_retur_detail_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_retur_key` VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver detail pickup retur'
proc: BEGIN
    DECLARE v_found INT DEFAULT 0;
    DECLARE v_key VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SET v_key = TRIM(p_retur_key);

    SELECT COUNT(*)
    INTO v_found
    FROM pickup_returs pr
    WHERE pr.driver_id = CAST(p_user_id AS UNSIGNED)
      AND (
          CAST(pr.id AS CHAR) COLLATE utf8mb4_unicode_ci = v_key
          OR pr.retur_number COLLATE utf8mb4_unicode_ci = v_key
      );

    IF v_found = 0 THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Pickup retur tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    SELECT JSON_OBJECT(
        'pickup_retur', (
            SELECT JSON_OBJECT(
                'id', CAST(pr.id AS CHAR),
                'code', pr.retur_number,
                'retur_date', DATE_FORMAT(pr.retur_date, '%Y-%m-%d'),
                'branch_name', IFNULL(br.branch_name, '-'),
                'no_pol', IFNULL(pr.no_pol, '-'),
                'total_order', IFNULL(pr.total_order, 0),
                'total_kg', IFNULL(pr.total_kg, 0),
                'notes', IFNULL(pr.notes, '-'),
                'status', IFNULL(pr.last_status, 'draft'),
                'next_action', CASE IFNULL(pr.last_status, 'draft') COLLATE utf8mb4_unicode_ci
                    WHEN 'assigned' COLLATE utf8mb4_unicode_ci THEN 'start_trip'
                    WHEN 'on_trip' COLLATE utf8mb4_unicode_ci THEN 'arrived'
                    ELSE NULL
                END,
                'allowed_actions', CASE IFNULL(pr.last_status, 'draft') COLLATE utf8mb4_unicode_ci
                    WHEN 'assigned' COLLATE utf8mb4_unicode_ci THEN JSON_ARRAY('start_trip')
                    WHEN 'on_trip' COLLATE utf8mb4_unicode_ci THEN JSON_ARRAY('arrived')
                    ELSE JSON_ARRAY()
                END
            )
            FROM pickup_returs pr
            LEFT JOIN branchs br ON pr.branch_id = br.id
            WHERE pr.driver_id = CAST(p_user_id AS UNSIGNED)
              AND (
                  CAST(pr.id AS CHAR) COLLATE utf8mb4_unicode_ci = v_key
                  OR pr.retur_number COLLATE utf8mb4_unicode_ci = v_key
              )
            LIMIT 1
        ),
        'items', IFNULL((
            SELECT JSON_ARRAYAGG(item_json)
            FROM (
                SELECT JSON_OBJECT(
                    'order_number', prd.order_number,
                    'awb_no', IFNULL(o.awb_no, '-'),
                    'customer_name', IFNULL(c.customer_name, '-'),
                    'total_colly', IFNULL(prd.total_colly, 0),
                    'total_kg', IFNULL(prd.total_kg, 0),
                    'goods_description', IFNULL(prd.goods_description, '-')
                ) AS item_json
                FROM pickup_retur_details prd
                INNER JOIN pickup_returs prh
                    ON prh.retur_number COLLATE utf8mb4_unicode_ci = prd.retur_number COLLATE utf8mb4_unicode_ci
                LEFT JOIN orders o
                    ON o.order_number COLLATE utf8mb4_unicode_ci = prd.order_number COLLATE utf8mb4_unicode_ci
                LEFT JOIN customers c ON c.id = o.customer_id
                WHERE prh.driver_id = CAST(p_user_id AS UNSIGNED)
                  AND (
                      CAST(prh.id AS CHAR) COLLATE utf8mb4_unicode_ci = v_key
                      OR prh.retur_number COLLATE utf8mb4_unicode_ci = v_key
                  )
                ORDER BY prd.id ASC
            ) x
        ), JSON_ARRAY())
    ) AS json;

END//

DELIMITER ;
