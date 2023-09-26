-- Make a table with Year, Month, and Start/End Date of Month to join onto for the final view
WITH month_year_table AS (
    WITH distinct_month_year as (
        SELECT DISTINCT SUBSTRING('EFFECTIVE_END_DATE', 1, 4) AS year,
        DISTINCT SUBSTRING('EFFECTIVE_END_DATE', 5, 6) AS month
        -- ensure this is the relevant table name
        FROM temp_enroll_0209
    )
    SELECT year,
    month,
    CONCAT(year, month, '01') as month_start_date,
    TO_CHAR(LAST_DAY(TO_DATE(CONCAT(year, month, '01'), 'YYYYMMDD')), 'YYYYMMDD') AS month_end_date
    FROM distinct_month_year
    ORDER BY year asc, month asc
)
;

-- Final View

-- Get relevant columns needed to determine eligiblity/conversion
WITH final_table AS (
    WITH prep_for_flag_creation AS (
        SELECT enterprise_person_identifier,
        SUBSTRING('EFFECTIVE_END_DATE', 1, 4) AS year,
        SUBSTRING('EFFECTIVE_END_DATE', 5, 6) AS month,
        -- need to validate a decimal in the year will work
        DATEADD(year, 64.75, CONVERT(DATETIME, CAST('birth_date' AS VARCHAR(8)))) AS date_when_customer_age_become_eligible,
        commercial_group_indicator,
        commercial_individual_indicator,
        -- is this the right date to choose for conversion?
        ma_enrollment_start_date
        -- ensure this is the relevant table name
        FROM temp_enroll_0209
    )
    -- create a long table with all rows with their relevant YYYYMM & flags
    SELECT *,
    -- commercial_age_eligible could be redundant with eligible_for_conversion
    CASE WHEN date_when_customer_age_become_eligible <= month_end_date 
    AND (commercial_group_indicator = 1 OR commercial_individual_indicator = 1)
    THEN 1
    ELSE 0
    END AS commercial_age_eligible,
    CASE WHEN date_when_customer_age_become_eligible <= month_end_date 
    AND (commercial_group_indicator = 1 OR commercial_individual_indicator = 1)
    -- making sure they haven't enrolled in MA yet for a specific row
    AND (ma_enrollment_start_date is NULL or ma_enrollment_start_date >= month_end_date)
    THEN 1
    ELSE 0
    END AS eligible_for_conversion,
    CASE WHEN ma_enrollment_start_date BETWEEN month_start_date AND month_end_date
    THEN 1 
    ELSE 0
    END AS converted
    FROM month_year_table 
    LEFT JOIN 
    flag_creation
    USING 
    (year, month)
)
-- Group results to get total counts per YYYYMM
SELECT 
year,
month,
SUM(commercial_age_eligible) as commercial_age_eligible_total,
SUM(eligibile_for_conversion) as eligibile_for_conversion_total,
SUM(converted) as converted_total
FROM final_table
GROUP BY year, month
ORDER BY year asc, month asc 
;
