--Additional Analysis on the Critical Care Database

--Q.1 Compare total male and female patients in each department

--Query:

SELECT 
    admitdept,
    Round((100*SUM(CASE WHEN sex='Male' THEN 1 ELSE 0 END)/COUNT(*)),2) AS   Male_patients_percentage,
    ROUND((100*SUM(CASE WHEN sex='Female' THEN 1 ELSE 0 END )/COUNT(*)),2) AS Female_patients_percentage
FROM 
    baseline
GROUP BY 
    admitdept;

--Q.2  Find the list of patients who were discharged after receiving more than 10 different drugs during their stay.

--Query:

SELECT 
   patient_id,
   COUNT(DISTINCT drugname)AS drug_count
FROM 
   drugs d
GROUP BY
   patient_id
HAVING COUNT
   (drugname)>10;

--Q.3. Compute the most common age of the patients.

--Query:

-- Used MODE Function to compute the most frequent value of a set of values

SELECT 
    MODE() WITHIN GROUP (ORDER BY age) AS most_common_age
FROM 
    baseline;

--Q.4. Write a query to simulate a delay of 3 seconds before retrieving the names of all patients admitted to the ICU.

--Query:

SELECT pg_sleep(3); -- Introduces a 3-second delay
SELECT patient_id, admitdept
FROM baseline
WHERE admitdept = 'ICU';

--Q.5. Divide all patients into quartiles based on their age, and display the quartile they belong to along with their patient ID and age.

--Query:

SELECT 
    patient_id, 
    age, 
    NTILE(4) OVER (ORDER BY age) AS age_tertile
FROM 
    baseline
ORDER BY 
    age;

--Q.6. For each department, create an array of patient IDs of all patients admitted to that department.

--Query:

SELECT 
    admitdept,
    ARRAY_AGG(patient_id) AS patient_ids
FROM 
    baseline
GROUP BY 
    admitdept
ORDER BY 
    admitdept;

--Q.7. Find patients where the labvalue is outside the defined reference range. 

--Query:

–This Query uses two different types of range separators (-- and ～) to handle different formats of reference values. 

SELECT *
FROM lab
WHERE 
    reference LIKE '%--%' 
    AND split_part(reference, '--', 1) ~ '^[0-9.]+$'  -- Ensure reference range is numeric
    AND split_part(reference, '--', 2) ~ '^[0-9.]+$'  -- Ensure reference range is numeric
    AND labvalue ~ '^[0-9.]+$'  -- Ensure labvalue is numeric
    AND (labvalue::numeric < split_part(reference, '--', 1)::numeric 
         OR labvalue::numeric > split_part(reference, '--', 2)::numeric)
UNION ALL
SELECT *
FROM lab
WHERE 
    reference LIKE '%～%' 
    AND split_part(reference, '～', 1) ~ '^[0-9.]+$'  -- Ensure reference range is numeric
    AND split_part(reference, '～', 2) ~ '^[0-9.]+$'  -- Ensure reference range is numeric
    AND labvalue ~ '^[0-9.]+$'  -- Ensure labvalue is numeric
    AND (labvalue::numeric < split_part(reference, '～', 1)::numeric 
         OR labvalue::numeric > split_part(reference, '～', 2)::numeric)
ORDER BY labvalue DESC;

--Q.8. Find patients whose sf36_generalhealth was "Excellent" but spent more than the average time in the ICU. List their departments details.

--Query:

WITH avg_icu_time AS (
    -- Calculate the average ICU stay duration in hours
    SELECT 
        AVG(EXTRACT(EPOCH FROM (b.ICU_discharge_time - t.starttime)) / 3600) AS avg_icu_hours
    FROM 
        baseline b
    JOIN 
        transfer t ON b.inp_no = t.inp_no
    WHERE 
        t.startreason = 'Admission' 
        AND t.transferdept = 'ICU' 
        AND b.ICU_discharge_time IS NOT NULL
        AND t.starttime IS NOT NULL
),
patient_icu_time AS (
    -- Calculate the ICU time for each patient
    SELECT 
        b.patient_id,
        b.admitdept,
        t.transferdept,
        EXTRACT(EPOCH FROM (b.ICU_discharge_time - t.starttime)) / 3600 AS icu_hours,
        o.sf36_generalhealth
    FROM 
        baseline b
    JOIN 
        transfer t ON b.inp_no = t.inp_no
    JOIN 
        outcome o ON b.patient_id = o.patient_id
    WHERE 
        t.startreason = 'Admission' 
        AND t.transferdept = 'ICU'
        AND b.ICU_discharge_time IS NOT NULL
        AND t.starttime IS NOT NULL
),
filtered_patients AS (
    -- Filter patients whose ICU time exceeds the average and have "1_Excellent" sf36_generalhealth
    SELECT 
        p.patient_id,
        p.admitdept,
        p.transferdept,
        p.icu_hours,
		a.avg_icu_hours,
		p.sf36_generalhealth
    FROM 
        patient_icu_time p,
        avg_icu_time a
    WHERE 
        p.icu_hours > a.avg_icu_hours
        AND p.sf36_generalhealth = '1_Excellent'
)
-- Select the desired information
SELECT 
    patient_id,
    admitdept,
    transferdept,
	avg_icu_hours,
    icu_hours as icu_hours_by_patient,
	sf36_generalhealth
FROM 
    filtered_patients
ORDER BY 
    icu_hours DESC;

--Q.9. Calculate the number of drugs administered to patients in different age groups (e.g., 0-20, 21-40, 41-60, 61+)

--Query:

WITH age_groups AS (
    -- Categorize patients into age groups
    SELECT 
        b.patient_id,
        CASE 
            WHEN b.age BETWEEN 0 AND 20 THEN '0-20'
            WHEN b.age BETWEEN 21 AND 40 THEN '21-40'
            WHEN b.age BETWEEN 41 AND 60 THEN '41-60'
            ELSE '61+'
        END AS age_group
    FROM 
        baseline b
),
drug_counts AS (
    -- Count the number of drugs administered to each patient
    SELECT  
        d.patient_id,
        COUNT(d.drugname) AS drug_count
    FROM 
        drugs d
    GROUP BY 
        d.patient_id
)
-- Combine age groups with drug counts and aggregate by age group
SELECT 
    ag.age_group,
    SUM(dc.drug_count) AS total_drugs
FROM 
    age_groups ag
JOIN 
    drug_counts dc ON ag.patient_id = dc.patient_id
GROUP BY 
    ag.age_group
ORDER BY 
    ag.age_group;

--Q.10. Display the list of patients who got admitted in any department and got discharged without a transfer to any department.

--Query:

WITH initial_admissions AS (
    -- Get the initial admission for each patient
    SELECT 
        t.patient_id,
        t.transferdept,
        t.starttime,
        t.startreason
    FROM 
        transfer t
    JOIN 
        baseline b ON t.patient_id = b.patient_id
    WHERE 
        t.startreason = 'Admission'  -- Only consider the initial admission
),
pre_discharge_patients AS (
    -- Get patients who were discharged with "Patient pre discharge" as the start reason
    SELECT 
        t.patient_id,
        t.starttime AS discharge_time
    FROM 
        transfer t
    WHERE 
        t.startreason = 'Patient pre discharge'
),
no_subsequent_transfers AS (
    -- Ensure no subsequent transfers occurred for these patients
    SELECT 
        t.patient_id
    FROM 
        transfer t
    JOIN 
        pre_discharge_patients p ON t.patient_id = p.patient_id
    WHERE 
        t.starttime > p.discharge_time  -- Only consider transfers after discharge
    GROUP BY 
        t.patient_id
    HAVING 
        COUNT(*) = 0  -- Ensure no other transfers occurred after the discharge
)
SELECT 
    b.patient_id,
    b.admitdept,
    p.discharge_time
FROM 
    baseline b
JOIN 
    pre_discharge_patients p ON b.patient_id = p.patient_id
WHERE 
    b.patient_id NOT IN (SELECT patient_id FROM no_subsequent_transfers)  -- Ensure no subsequent transfers
ORDER BY 
    b.patient_id;

--Q.11. Calculate the survival rate (percentage of "Alive" patients) for each admitdept

--Query:

WITH dept_survival AS (
    -- Get the total count of patients and the count of alive patients for each admitdept
    SELECT 
        b.admitdept,
        COUNT(*) AS total_patients,
        COUNT(CASE WHEN o.follow_vital = 'Alive' THEN 1 END) AS alive_patients
    FROM 
        baseline b
    LEFT JOIN 
        outcome o ON b.patient_id = o.patient_id
    GROUP BY 
        b.admitdept
)
SELECT 
    admitdept,
    total_patients,
    alive_patients,
    ROUND((alive_patients::NUMERIC / total_patients) * 100, 2) AS survival_rate_percentage
FROM 
    dept_survival
ORDER BY 
    admitdept;

--Q.12. For each patient, compute an aggregated score combining the following metrics:
Average blood sugar
Maximum heart rate
Minimum blood oxygen saturation
Rank patients based on this aggregated score.

--Query:

WITH patient_metrics AS (
    -- Compute the average blood sugar, maximum heart rate, and minimum blood oxygen saturation for each patient
    SELECT 
        b.patient_id,
        AVG(nc.blood_sugar) AS avg_blood_sugar,
        MAX(nc.heart_rate) AS max_heart_rate,
        MIN(nc.blood_oxygen_saturation) AS min_oxygen_saturation
    FROM 
        nursingchart nc
    JOIN 
        baseline b ON nc.inp_no = b.inp_no
    GROUP BY 
        b.patient_id
),
aggregated_scores AS (
    -- Combine these metrics into a single aggregated score
    SELECT 
        patient_id,
        round((avg_blood_sugar + max_heart_rate + min_oxygen_saturation)::NUMERIC,2) AS aggregated_score  
    FROM 
        patient_metrics
)
SELECT 
    ascore.patient_id,
    ascore.aggregated_score,
    RANK() OVER (ORDER BY ascore.aggregated_score DESC) AS rank
FROM 
    aggregated_scores ascore
WHERE 
	aggregated_score is not null
ORDER BY 
    rank;

--Q.13. Identify patients with more than three disease codes in the ICU and their average hospital stay duration.

--QUERY:

WITH patient_diseases AS (
    -- Count the number of disease codes (icd_code) for each patient
    SELECT 
        i.patient_id,
        COUNT(i.icd_code) AS disease_count
    FROM 
        icd i
    GROUP BY 
        i.patient_id
    HAVING 
        COUNT(i.icd_code) > 3  -- Only include patients with more than 3 disease codes
),
hospital_stay AS (
    -- Calculate the average hospital stay duration for these patients
    SELECT 
        b.patient_id,
        ROUND(AVG(EXTRACT(EPOCH FROM (b.icu_discharge_time - t.starttime)) / 86400),2) AS avg_hospital_stay_days  -- Duration in days
    FROM 
        transfer t
    JOIN 
        baseline b ON t.patient_id = b.patient_id
    JOIN 
        patient_diseases pd ON b.patient_id = pd.patient_id
    WHERE 
        t.startreason = 'Admission'  -- Only consider admissions in ICU
		AND b.admitdept = 'ICU'
    GROUP BY 
        b.patient_id
)
SELECT 
    pd.patient_id,
    pd.disease_count,
    hs.avg_hospital_stay_days
FROM 
    patient_diseases pd
JOIN 
    hospital_stay hs ON pd.patient_id = hs.patient_id
ORDER BY 
    pd.disease_count;

--Q.14. Show the Patients count for the most frequently occurring Disease for each discharge status.

--Query:

WITH icd_counts AS (
    SELECT 
        status_discharge,
        icd_desc,
        COUNT(*) AS count
    FROM icd
    GROUP BY status_discharge, icd_desc
)
SELECT 
    status_discharge,
    icd_desc,
    count as Patients_count
FROM icd_counts
WHERE (status_discharge, count) IN (
    SELECT 
        status_discharge,
        MAX(count)
    FROM icd_counts
    GROUP BY status_discharge
)
ORDER BY count DESC;

--Q.15. How many patients reported being "limited a lot" in vigorous or moderate activities?

--Query:

SELECT 
    COUNT(DISTINCT CASE WHEN sf36_activitylimit_vigorousactivity = '1_limited a lot' THEN patient_id END) AS limited_vigorous,
    COUNT(DISTINCT CASE WHEN sf36_activitylimit_moderateactivity = '1_limited a lot' THEN patient_id END) AS limited_moderate
FROM outcome;

--Q.16. Is there a correlation between sf36_oneyearcomparehealthcondition and the discharge_dept?
--Query:
– Used REGEXP_REPLACE () to remove non digit characters from the string.
SELECT CORR(
               CAST(REGEXP_REPLACE(sf36_oneyearcomparehealthcondition, '\D', '', 'g') AS INTEGER),
               CASE
                   WHEN discharge_dept = 'ICU' THEN 1
                   WHEN discharge_dept = 'Surgery' THEN 2
                   WHEN discharge_dept = 'Medical Specialties' THEN 3
                   ELSE 0
               END
           ) AS correlation
FROM outcome;

--Q.17. Show the number of admissions, discharges and followups by each season.

--Query:

-- Take Number of admissions from transfer table, number of discharges from baseline table and number of followups from the outcome table.

SELECT all_seasons.season,
       COALESCE(admissions.num_admissions, 0) AS num_admissions,
       COALESCE(discharges.num_discharges, 0) AS num_discharges,
       COALESCE(followups.num_followups, 0) AS num_followups
FROM (
    SELECT CASE
                WHEN EXTRACT(MONTH FROM starttime) IN (12, 1, 2) THEN 'Winter'
                WHEN EXTRACT(MONTH FROM starttime) IN (3, 4, 5) THEN 'Spring'
                WHEN EXTRACT(MONTH FROM starttime) IN (6, 7, 8) THEN 'Summer'
                WHEN EXTRACT(MONTH FROM starttime) IN (9, 10, 11) THEN 'Fall'
            END AS season
    FROM transfer
    WHERE startreason = 'Admission'
    GROUP BY season
    UNION
    SELECT CASE
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (12, 1, 2) THEN 'Winter'
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (3, 4, 5) THEN 'Spring'
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (6, 7, 8) THEN 'Summer'
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (9, 10, 11) THEN 'Fall'
            END AS season
    FROM baseline
    WHERE icu_discharge_time IS NOT NULL
    GROUP BY season
    UNION
    SELECT CASE
                WHEN EXTRACT(MONTH FROM follow_date) IN (12, 1, 2) THEN 'Winter'
                WHEN EXTRACT(MONTH FROM follow_date) IN (3, 4, 5) THEN 'Spring'
                WHEN EXTRACT(MONTH FROM follow_date) IN (6, 7, 8) THEN 'Summer'
                WHEN EXTRACT(MONTH FROM follow_date) IN (9, 10, 11) THEN 'Fall'
            END AS season
    FROM outcome
    WHERE follow_date IS NOT NULL
    GROUP BY season
) AS all_seasons
LEFT JOIN (
    SELECT CASE
                WHEN EXTRACT(MONTH FROM starttime) IN (12, 1, 2) THEN 'Winter'
                WHEN EXTRACT(MONTH FROM starttime) IN (3, 4, 5) THEN 'Spring'
                WHEN EXTRACT(MONTH FROM starttime) IN (6, 7, 8) THEN 'Summer'
                WHEN EXTRACT(MONTH FROM starttime) IN (9, 10, 11) THEN 'Fall'
            END AS season,
            COUNT(*) AS num_admissions
    FROM transfer
    WHERE startreason = 'Admission'
    GROUP BY season
) AS admissions ON all_seasons.season = admissions.season
LEFT JOIN (
    SELECT CASE
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (12, 1, 2) THEN 'Winter'
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (3, 4, 5) THEN 'Spring'
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (6, 7, 8) THEN 'Summer'
                WHEN EXTRACT(MONTH FROM icu_discharge_time) IN (9, 10, 11) THEN 'Fall'
            END AS season,
            COUNT(*) AS num_discharges
    FROM baseline
    WHERE icu_discharge_time IS NOT NULL
    GROUP BY season
) AS discharges ON all_seasons.season = discharges.season
LEFT JOIN (
    SELECT CASE
                WHEN EXTRACT(MONTH FROM follow_date) IN (12, 1, 2) THEN 'Winter'
                WHEN EXTRACT(MONTH FROM follow_date) IN (3, 4, 5) THEN 'Spring'
                WHEN EXTRACT(MONTH FROM follow_date) IN (6, 7, 8) THEN 'Summer'
                WHEN EXTRACT(MONTH FROM follow_date) IN (9, 10, 11) THEN 'Fall'
            END AS season,
            COUNT(*) AS num_followups
    FROM outcome
    WHERE follow_date IS NOT NULL
    GROUP BY season
) AS followups ON all_seasons.season = followups.season
ORDER BY all_seasons.season;

--Q.18. How do patients from the ICU, Medical Specialties, and Surgery departments compare in terms of their self-reported health conditions one year after discharge, based on one year compare health condition. Pivot the values to show individually as columns and show the count of patients.

--Query:

CREATE EXTENSION IF NOT EXISTS tablefunc;

-- Used crosstab function and unnest(Array) to display and pivot the row values as column names

SELECT * 
FROM crosstab(
    $$ 
    SELECT discharge_dept,
           sf36_oneyearcomparehealthcondition,
           COUNT(*)
    FROM outcome
    WHERE discharge_dept IN ('ICU', 'Medical Specialties', 'Surgery')
    GROUP BY discharge_dept, sf36_oneyearcomparehealthcondition
    ORDER BY discharge_dept, sf36_oneyearcomparehealthcondition;
    $$,
    $$ SELECT unnest(ARRAY['1_Much better now than one year ago', 
                           '2_Somewhat better now than one year ago', 
                           '3_About the same', 
                           '④比1年前差一些',  
                           '5_Much worse now than one year ago']) 
    $$) 
AS pivoted_data(discharge_dept TEXT, 
                "Much better" INT, 
                "Somewhat better" INT, 
                "About the same" INT, 
                "Somewhat worse" INT, 
                "Much worse" INT);


--Q.19. Extract and rank patients based on total fluids intake from multiple columns (using UNION ALL and aggregation):

--Query:

WITH Fluids AS (
    SELECT inp_no, charttime, milk AS FluidVolume, 'Milk' AS FluidType FROM nursingchart
    UNION ALL
    SELECT inp_no, charttime, fruit_juice AS FluidVolume, 'Fruit Juice' AS FluidType FROM nursingchart
    UNION ALL
    SELECT inp_no, charttime, soup AS FluidVolume, 'Soup' AS FluidType  FROM nursingchart
)
SELECT inp_no, SUM(FluidVolume) AS TotalFluids, RANK() OVER (ORDER BY SUM(FluidVolume) DESC) AS Rank
FROM Fluids
WHERE FluidVolume IS NOT NULL
GROUP BY inp_no;

--Q.20. Identify patients with duplicate transfer records (i.e., multiple entries with the same StartTime, StopTime, and TransferDept).

--Query:

SELECT t1.*
FROM transfer t1
JOIN transfer t2
ON t1.patient_id = t2.patient_id
AND t1.starttime = t2.starttime
AND t1.stoptime = t2.stoptime
AND t1.transferdept = t2.transferdept
AND t1.inp_no <> t2.inp_no;

--Q.21. Identify patients with inconsistent pupil size (using ABS function)

--Query:

SELECT DISTINCT b.patient_id, charttime, left_pupil_size, right_pupil_size,
       ABS(CAST(left_pupil_size AS DECIMAL) - CAST(right_pupil_size AS DECIMAL)) AS SizeDifference
FROM nursingchart nc
JOIN baseline b
ON nc.inp_no=b.inp_no
WHERE ABS(CAST(left_pupil_size AS DECIMAL) - CAST(right_pupil_size AS DECIMAL)) > 1 -- More than 1 mm difference
AND (left_pupil_size IS NOT NULL AND right_pupil_size IS NOT NULL)

--Q.22.Find the list of patients who have both a recorded transfer to the "ICU" and a prescription for a drug named "Xingnaojing Injection"

--Query:

SELECT patient_id
FROM Transfer
WHERE transferdept = 'ICU'
INTERSECT
SELECT patient_id
FROM Drugs
WHERE drugname = 'Xingnaojing Injection';

--Q.23.List all patients who have recorded nursing data but are not included in the lab test results.

--Query:

WITH records_nursing_lab AS (
    SELECT inp_no
    FROM NursingChart
    EXCEPT
    SELECT inp_no
    FROM Lab
)
SELECT  patient_id
FROM records_nursing_lab rnl
JOIN baseline b
ON rnl.inp_no=b.inp_no




