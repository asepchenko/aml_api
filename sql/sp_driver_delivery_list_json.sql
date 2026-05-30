-- =============================================================================
-- Daftar Delivery Packing List (dooring) untuk driver — paginated JSON
-- Hindari MySQL 1267: semua banding string pakai CONVERT utf8mb4_unicode_ci
--
-- Deploy: delimiter // → Execute ALL
-- CALL sp_driver_delivery_list_json('1', NULL, 1, 20);
-- =============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_delivery_list_json//

CREATE PROCEDURE `sp_driver_delivery_list_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_status` VARCHAR(30),
    IN `p_page` INT,
    IN `p_limit` INT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver list DPL — delivery_packing_lists'
proc: BEGIN
    DECLARE v_offset INT;
    DECLARE v_total INT;
    DECLARE v_total_pages INT;
    DECLARE v_status VARCHAR(30);

    SET p_page  = IFNULL(NULLIF(p_page, 0), 1);
    SET p_limit = IFNULL(NULLIF(p_limit, 0), 20);
    SET v_offset = (p_page - 1) * p_limit;
    SET v_status = NULLIF(TRIM(p_status), '');

    SELECT COUNT(*)
    INTO v_total
    FROM delivery_packing_lists d
    WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
      AND d.packing_list_date >= CURDATE() - INTERVAL 30 DAY
      AND (
          v_status IS NULL
          OR CONVERT(d.last_status USING utf8mb4) COLLATE utf8mb4_unicode_ci
             = CONVERT(v_status USING utf8mb4) COLLATE utf8mb4_unicode_ci
      )
      AND (
          v_status IS NOT NULL
          OR CONVERT(IFNULL(d.last_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci NOT IN (
              CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci,
              CONVERT('Received' USING utf8mb4) COLLATE utf8mb4_unicode_ci
          )
      );

    SET v_total_pages = IF(v_total = 0, 0, CEIL(v_total / p_limit));

    SELECT JSON_OBJECT(
        'deliveries', IFNULL((
            SELECT JSON_ARRAYAGG(delivery_json)
            FROM (
                SELECT JSON_OBJECT(
                    'id', CAST(d.id AS CHAR),
                    'code', d.packing_list_number,
                    'date', DATE_FORMAT(d.packing_list_date, '%d %b %Y'),
                    'packing_list_date', DATE_FORMAT(d.packing_list_date, '%Y-%m-%d'),
                    'origin', IFNULL(d.origin, '-'),
                    'police_number', IFNULL(d.police_number, '-'),
                    'total_order', IFNULL(d.total_order, 0),
                    'total_kg', IFNULL(d.total_kg, 0),
                    'pending_items', IFNULL((
                        SELECT COUNT(*)
                        FROM delivery_packing_list_details x
                        WHERE CONVERT(x.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                            = CONVERT(d.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                          AND CONVERT(IFNULL(x.item_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
                            <> CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci
                    ), 0),
                    'truck_type', IFNULL(tt.type_name, '-'),
                    'status', IFNULL(d.last_status, 'Open'),
                    'status_hpp', IFNULL(d.status_hpp, '-'),
                    'on_process_at', IFNULL(DATE_FORMAT(d.on_process_at, '%d %b %Y, %H:%i'), '-'),
                    'delivered_at', IFNULL(DATE_FORMAT(d.delivered_at, '%d %b %Y, %H:%i'), '-'),
                    'eta', '-'
                ) AS delivery_json
                FROM delivery_packing_lists d
                LEFT JOIN trucks tr ON d.truck_id = tr.id
                LEFT JOIN truck_types tt ON tr.truck_type_id = tt.id
                WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
                  AND d.packing_list_date >= CURDATE() - INTERVAL 30 DAY
                  AND (
                      v_status IS NULL
                      OR CONVERT(d.last_status USING utf8mb4) COLLATE utf8mb4_unicode_ci
                         = CONVERT(v_status USING utf8mb4) COLLATE utf8mb4_unicode_ci
                  )
                  AND (
                      v_status IS NOT NULL
                      OR CONVERT(IFNULL(d.last_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci NOT IN (
                          CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci,
                          CONVERT('Received' USING utf8mb4) COLLATE utf8mb4_unicode_ci
                      )
                  )
                ORDER BY
                    CASE CONVERT(IFNULL(d.last_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
                        WHEN CONVERT('Open' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN 1
                        WHEN CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN 2
                        ELSE 3
                    END,
                    d.packing_list_date DESC,
                    d.packing_list_number DESC
                LIMIT v_offset, p_limit
            ) data
        ), JSON_ARRAY()),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json;

END//

DELIMITER ;
