-- basic table with necessary columns to generate view

WITH commercial_last_enrollment AS (
    SELECT 
    enterprise_person_identifier, 
    MAX(EFFECTIVE_END_DATE), 
    MAX(birth_date)
    FROM main_table
    WHERE current_derived_plan IN ('Commercial Group', 'Commercial Individual')
    GROUP BY enterprise_person_identifier
),
commercial_create_two_columns AS (
    SELECT 
    1 AS disenroll_from_commercial,
    -- not sure if this is the best way to convert the 8dig date string
    DATEADD(year, 64.75, CONVERT(DATETIME, CAST('birth_date' AS VARCHAR(8)))) AS date_when_customer_age_become_eligible
    FROM commercial_last_disenrollment
)
main_table_with_commercial_columns AS (
    SELECT *
    FROM temp_enroll
    LEFT JOIN
    commercial_create_two_columns
    ON enterprise_person_identifier, EFFECTIVE_END_DATE
)
convert_prep_table AS (
    SELECT enterprise_person_identifier,
    -- are these the right start/end dates to use?
    member_eligibility_start_date,
    member_eligibility_end_date,
    current_derived_plan
    WHERE current_derived_plan in ('Commercial Group', 'Commercial Individual', 'MA Individual')
    ORDER BY enterprise_person_identifier, member_eligibility_start_date
)
convert_prior_commercial_end_date AS (
    SELECT enterprise_person_identifier, current_derived_plan,
    -- is this the right way to get most recent commercial end date? how do we know it's the max?
    CASE WHEN
    LAG(current_derived_plan, 1) OVER 
        (PARTITION BY enterprise_person_identifier 
            ORDER BY member_eligibility_start_date, member_eligibility_end_date) in ('Commercial Group', 'Commercial Individual')
    -- right end date to use?
    THEN member_eligibility_end_date
    ELSE NULL
    END AS prior_commercial_end_date,
    CASE WHEN
    LEAD(current_derived_plan, 1) OVER 
        (PARTITION BY enterprise_person_identifier
            ORDER BY member_eligibility_start_date, member_eligibility_end_date) in ('Individual MA')
    THEN member_eligibility_start_date
    ELSE NULL
    END AS ma_enrollment_start_date
    FROM convert_prep_table
)
table_with_convert_columns AS (
    -- should it just be selecting the EPI or other columns?
    SELECT enterprise_person_identifier,
    CASE WHEN DATEDIFF(day, ma_enrollment_start_date, prior_commercial_end_date) BETWEEN 0 AND 365
    AND current_derived_plan = 'Individual MA'
    THEN 1 
    ELSE 0 
    END AS converted_within_12_months
    FROM convert_prior_commercial_end_date
);

-- eligible population view

CREATE VIEW eligible_column_view AS (
    WITH temp_table AS (
        SELECT 
        prior_commercial_end_date,
        YEAR(prior_commercial_end_date) as end_year, 
        MONTH(prior_commercial_end_date) as end_month,
        disenroll_from_commercial,
        EFFECTIVE_END_DATE,
        date_when_customer_age_become_eligible
        FROM convert_table_w_columns)
    SELECT end_year, 
    end_month,
    CASE WHEN disenroll_from_commercial = 1 AND
    DATEDIFF(day, prior_commercial_end_date, EFFECTIVE_END_DATE) BETWEEN 0 AND 365 AND
    date_when_customer_age_become_eligible < prior_commercial_end_date
    THEN sum(disenroll_from_commercial)
    ELSE 0
    END AS eligible_count
    FROM eligible_column_view
);

-- convert population view

CREATE VIEW convert_column_view AS (
    WITH temp_table AS (
        SELECT 
        ma_enrollment_start_date,
        YEAR(ma_enrollment_start_date) as end_year, 
        MONTH(ma_enrollment_start_date) as end_month,
        current_derived_plan,
        date_when_customer_age_become_eligible,
        disenroll_from_commercial
        FROM convert_table_w_columns)
    SELECT end_year, 
    end_month,
    CASE WHEN current_derived_plan like 'MA Individual' AND
    DATEDIFF(day, prior_commercial_end_date, EFFECTIVE_END_DATE) BETWEEN 0 AND 365 AND
    date_when_customer_age_become_eligible <= ma_enrollment_start_date
    THEN sum(disenroll_from_commercial)
    ELSE 0
    END AS convert_count
    FROM convert_column_view
)
;


-- view after talking to Ryan 02091320

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
    ORDER BY YEAR ASC, MONTH ASC
)
;

-- Final View
WITH prep_for_flag_creation AS (
    SELECT enterprise_person_identifier,
    SUBSTRING('EFFECTIVE_END_DATE', 1, 4) AS year,
    SUBSTRING('EFFECTIVE_END_DATE', 5, 6) AS month,
    DATEADD(year, 64.75, CONVERT(DATETIME, CAST('birth_date' AS VARCHAR(8)))) AS date_when_customer_age_become_eligible,
    commercial_group_indicator,
    commercial_individual_indicator,
    -- is this the right date to choose for conversion?
    ma_enrollment_start_date
    -- ensure this is the relevant table name
    FROM temp_enroll_0209
)
SELECT *,
-- commercial_age_eligible could be redundant with eligible_for_conversion
CASE WHEN date_when_customer_age_become_eligible <= month_end_date 
AND (commercial_group_indicator = 1 OR commercial_individual_indicator = 1)
THEN 1
ELSE 0
END AS commercial_age_eligible,
CASE WHEN date_when_customer_age_become_eligible <= month_end_date 
AND (commercial_group_indicator = 1 OR commercial_individual_indicator = 1)
AND (ma_enrollment_start_date is NULL or ma_enrollment_start_date >= month_end_date)
THEN 1
ELSE 0
END AS eligible_for_conversion,
CASE WHEN ma_enrollment_start_date BETWEEN month_start_date AND month_end_date
THEN 1 
ELSE 0
END AS converted_flag
FROM month_year_table 
LEFT JOIN 
flag_creation
USING 
(year, month)
