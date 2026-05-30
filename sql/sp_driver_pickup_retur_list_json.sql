-- =============================================================================
-- Daftar Pickup Retur untuk driver — paginated JSON
-- Model: pickup_returs (Laravel API)
--
-- Deploy di HeidiSQL:
-- 1. Database `lke`
-- 2. Query delimiter = //
-- 3. Select ALL → Execute (F9)
-- =============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_pickup_retur_list_json//

CREATE PROCEDURE `sp_driver_pickup_retur_list_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_status` VARCHAR(20),
    IN `p_page` INT,
    IN `p_limit` INT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver list pickup retur — pickup_returs'
proc: BEGIN
    DECLARE v_offset INT;
    DECLARE v_total INT;
    DECLARE v_total_pages INT;
    DECLARE v_status VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SET p_page  = IFNULL(NULLIF(p_page, 0), 1);
    SET p_limit = IFNULL(NULLIF(p_limit, 0), 20);
    SET v_offset = (p_page - 1) * p_limit;
    SET v_status = NULLIF(TRIM(p_status), '');

    SELECT COUNT(*)
    INTO v_total
    FROM pickup_returs pr
    WHERE pr.driver_id = CAST(p_user_id AS UNSIGNED)
      AND pr.retur_date >= CURDATE() - INTERVAL 30 DAY
      AND (
          v_status IS NULL
          OR pr.last_status COLLATE utf8mb4_unicode_ci = v_status
      )
      AND (
          v_status IS NOT NULL
          OR IFNULL(pr.last_status, 'draft') COLLATE utf8mb4_unicode_ci IN (
              'draft' COLLATE utf8mb4_unicode_ci,
              'assigned' COLLATE utf8mb4_unicode_ci,
              'on_trip' COLLATE utf8mb4_unicode_ci
          )
      );

    SET v_total_pages = IF(v_total = 0, 0, CEIL(v_total / p_limit));

    SELECT JSON_OBJECT(
        'pickup_returs', IFNULL((
            SELECT JSON_ARRAYAGG(retur_json)
            FROM (
                SELECT JSON_OBJECT(
                    'id', CAST(pr.id AS CHAR),
                    'code', pr.retur_number,
                    'date', DATE_FORMAT(pr.retur_date, '%d %b %Y'),
                    'retur_date', DATE_FORMAT(pr.retur_date, '%Y-%m-%d'),
                    'branch_name', IFNULL(br.branch_name, '-'),
                    'no_pol', IFNULL(pr.no_pol, '-'),
                    'truck_type', IFNULL(tt.type_name, '-'),
                    'total_order', IFNULL(pr.total_order, 0),
                    'total_kg', IFNULL(pr.total_kg, 0),
                    'notes', IFNULL(pr.notes, '-'),
                    'sample_customer', IFNULL((
                        SELECT c.customer_name
                        FROM pickup_retur_details prd
                        INNER JOIN orders o
                            ON o.order_number COLLATE utf8mb4_unicode_ci = prd.order_number COLLATE utf8mb4_unicode_ci
                        LEFT JOIN customers c ON c.id = o.customer_id
                        WHERE prd.retur_number COLLATE utf8mb4_unicode_ci = pr.retur_number COLLATE utf8mb4_unicode_ci
                        ORDER BY prd.id ASC
                        LIMIT 1
                    ), '-'),
                    'status', IFNULL(pr.last_status, 'draft'),
                    'eta', '-'
                ) AS retur_json
                FROM pickup_returs pr
                LEFT JOIN branchs br ON pr.branch_id = br.id
                LEFT JOIN trucks tr ON pr.truck_id = tr.id
                LEFT JOIN truck_types tt ON tr.truck_type_id = tt.id
                WHERE pr.driver_id = CAST(p_user_id AS UNSIGNED)
                  AND pr.retur_date >= CURDATE() - INTERVAL 30 DAY
                  AND (
                      v_status IS NULL
                      OR pr.last_status COLLATE utf8mb4_unicode_ci = v_status
                  )
                  AND (
                      v_status IS NOT NULL
                      OR IFNULL(pr.last_status, 'draft') COLLATE utf8mb4_unicode_ci IN (
                          'draft' COLLATE utf8mb4_unicode_ci,
                          'assigned' COLLATE utf8mb4_unicode_ci,
                          'on_trip' COLLATE utf8mb4_unicode_ci
                      )
                  )
                ORDER BY
                    CASE IFNULL(pr.last_status, 'draft') COLLATE utf8mb4_unicode_ci
                        WHEN 'assigned' COLLATE utf8mb4_unicode_ci THEN 1
                        WHEN 'on_trip' COLLATE utf8mb4_unicode_ci THEN 2
                        WHEN 'draft' COLLATE utf8mb4_unicode_ci THEN 3
                        ELSE 4
                    END,
                    pr.retur_date DESC,
                    pr.retur_number DESC
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
