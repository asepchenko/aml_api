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

DROP PROCEDURE IF EXISTS sp_driver_pickup_list_json//

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_driver_pickup_list_json`(
	IN `p_user_id` VARCHAR(50),
	IN `p_status` VARCHAR(20),
	IN `p_page` INT,
	IN `p_limit` INT,
	IN `p_user_id` VARCHAR(50),
	IN `p_status` VARCHAR(20),
	IN `p_page` INT,
	IN `p_limit` INT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
proc: BEGIN
    DECLARE v_offset INT;
    DECLARE v_total INT;
    DECLARE v_total_pages INT;
    DECLARE v_status VARCHAR(20);

    /* ================= SAFETY ================= */
    SET p_page  = IFNULL(NULLIF(p_page,0),1);
    SET p_limit = IFNULL(NULLIF(p_limit,0),20);
    SET v_offset = (p_page - 1) * p_limit;

    /* ================= NORMALIZE STATUS ================= */
    SET v_status = NULLIF(p_status,'');

    /* ================= COUNT TOTAL ================= */
    SELECT COUNT(*)
    INTO v_total
    FROM pickup_requests pr
    WHERE (pr.driver_id = p_user_id OR pr.driver_id IS NULL)
      AND (v_status IS NULL OR pr.last_status = v_status) 
	  AND pr.request_date >= CURDATE() - INTERVAL 30 DAY 
	  AND driver_id = p_user_id;

    SET v_total_pages = CEIL(v_total / p_limit);

    /* ================= MAIN JSON ================= */
    SELECT JSON_OBJECT(
        'pickups', IFNULL((
            SELECT JSON_ARRAYAGG(pickup_json)
            FROM (
                SELECT JSON_OBJECT(
                    'id', pr.id,
                    'code', pr.request_number,
                    'date', DATE_FORMAT(pr.request_date, '%d %b %Y, %H:%i'),
                    'customer_name', IFNULL(c.customer_name, '-'),
                    'pickup_address', IFNULL(pr.address, '-'),
                    'schedule_date', IFNULL(DATE_FORMAT(pr.request_date, '%d %b %Y'), '-'),
                    'schedule_time', IFNULL(pr.request_time, '-'),
                    'koli', IFNULL(pr.total_colly, 0),
                    'weight_kg', IFNULL(pr.total_volume, 0),
                    'description', IFNULL(pr.description, '-'),
                    'category', IFNULL(pr.category, '-'),
                    'pic_name', IFNULL(pr.pic_name, '-'),
                    'pic_phone', IFNULL(pr.pic_phone, '-'),
                    'pic_whatsapp', IFNULL(pr.pic_whatsapp, 0),
                    'status', pr.last_status,                    
                    'confirm_date', IFNULL(DATE_FORMAT(pr.realisasi_date, '%d %b %Y'), '-'),
                    'eta', '-'
                ) AS pickup_json
                FROM pickup_requests pr
				LEFT JOIN customers c on pr.customer_id = c.id
                WHERE (pr.driver_id = p_user_id OR pr.driver_id IS NULL)
                  AND (v_status IS NULL OR pr.last_status = v_status)
                ORDER BY
                    CASE pr.last_status
                        WHEN 'pending' THEN 1
                        WHEN 'accept' THEN 2
                        ELSE 3
                    END,
                    pr.realisasi_date DESC
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
