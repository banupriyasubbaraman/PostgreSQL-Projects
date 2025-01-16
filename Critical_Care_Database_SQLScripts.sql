--Critical Care Database Analysis using Postgresql

/* Q1. Write a query to count the number of columns in the nursing chart table. */

--Query 1: Querying the information_schema.columns

SELECT COUNT(*) AS nursingchart_column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'nursingchart'
AND TABLE_SCHEMA = 'public';

--Alternative Method to get the number of columns
--Query 2: Using the pg_attribute System Catalog

SELECT COUNT(*) AS nursingchart_column_count
FROM pg_attribute
WHERE attrelid = 'nursingchart'::regclass
AND attnum > 0  -- Excludes system columns
AND NOT attisdropped; 

/* Q2. Using a recursive query, show a list of patients that were transferred to various departments after they were admitted, along with the departments and the time of transfer. Hint, use earliest start time as time of admission. */

--Query:

WITH RECURSIVE patient_info AS (
    -- Get the earliest start time as the admission time for each patient
    SELECT 
        patient_id,
        MIN(starttime) AS admission_time,
		transferdept as AdmittedDept
    FROM 
        transfer
    WHERE 
        startreason = 'Admission'
    GROUP BY 
        patient_id,transferdept
),
patient_transfers AS (
    -- Anchor member: Get initial transfers right after admission
    SELECT 
        t.patient_id,
        t.transferdept,
        t.starttime AS transfer_time,
        t.startreason
    FROM 
        transfer t
    JOIN 
        patient_info p
    ON 
        t.patient_id = p.patient_id
    WHERE 
        t.starttime > p.admission_time
        AND t.startreason = 'Transfer'

    UNION ALL

    -- Recursive member: Find subsequent transfers for each patient
    SELECT 
        t.patient_id,
        t.transferdept,
        t.starttime AS transfer_time,
        t.startreason
    FROM 
        transfer t
    JOIN 
        patient_transfers pt
    ON 
        t.patient_id = pt.patient_id 
        AND t.starttime > pt.transfer_time 
        AND t.startreason = 'Transfer'
)
SELECT DISTINCT -- Listing all the patients that were transferred to various departments
    pt.patient_id,
    pi.admission_time,
	pi.AdmittedDept,
	pt.startreason as Reason,
    pt.transfer_time,
    pt.transferdept
FROM 
    patient_transfers pt
JOIN 
    patient_info pi
ON 
    pt.patient_id = pi.patient_id
ORDER BY 
    pt.patient_id, pt.transfer_time;

/* Q3. List all patients who had a systolic blood pressure higher than the median value in the ICU. Use windows functions to achieve this.*/

--Query:

--This CTE calculates the median value in the ICU department
WITH median_calc AS (
    SELECT 
        percentile_cont(0.5) WITHIN GROUP (ORDER BY invasive_sbp) AS median_icu
    FROM 
        nursingchart n 
    JOIN 
        baseline b ON n.inp_no = b.inp_no
    WHERE 
        n.invasive_sbp IS NOT NULL -- Ensure no null values are included
        AND b.admitdept = 'ICU' -- Focus on ICU department
),-- This CTE ranks the SBP values and get all the required columns
Ranked_SBP AS (
    SELECT 
        b.admitdept,
        b.patient_id,
        n.invasive_sbp,
        mc.median_icu,
        n.charttime,
        DENSE_RANK() OVER (PARTITION BY n.inp_no ORDER BY n.invasive_sbp DESC,n.charttime desc) AS Rank_SBP -- only take Highest SBP Values and latest recorded time for each Patient to avoid multiple values per patient
    FROM 
        nursingchart n
    JOIN 
        baseline b ON b.inp_no = n.inp_no
    JOIN 
        median_calc mc ON 1=1 -- Broadcasting the median value across all rows
    WHERE 
        n.invasive_sbp > mc.median_icu -- Only include SBP values higher than the median
)
SELECT DISTINCT -- This Query lists only the highest SBP value per patient across all the departments to avoid multiple SBP values
    admitdept,
    patient_id,
    invasive_sbp as systolic_bp,
    median_icu,
    charttime
FROM 
    Ranked_SBP
WHERE 
    Rank_SBP = 1 -- Only include the highest systolic blood pressure per patient
ORDER BY 
    admitdept,patient_id;

/* Q4. Create a function to fetch the details of the last recorded drug for a patient. */

--Query:

CREATE OR REPLACE FUNCTION last_recorded_drugs(patient_id_input BIGINT)
RETURNS TABLE (
    patient_id BIGINT,   
    drugname TEXT,
    drug_time TIMESTAMP,
    formula TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH latest_drug_time AS (
        -- Fetch the latest drug time for the patient
        SELECT 
            MAX(d.drug_time) AS latest_time
        FROM 
            drugs d
        WHERE 
            d.patient_id = patient_id_input
    )
    -- Fetch all drugs given at the latest drug time
    SELECT 
        d.patient_id::BIGINT,  -- Cast to BIGINT to avoid conversion errors.
        d.drugname,
        d.drug_time,
        d.formula
    FROM 
        drugs d
    INNER JOIN 
        latest_drug_time ldt
        ON d.drug_time = ldt.latest_time
	WHERE 
        d.patient_id = patient_id_input
    ORDER BY 
        d.drug_time DESC
    LIMIT 10; -- Limiting the list to show up to 10 last recorded Drugs
END;
$$ LANGUAGE plpgsql;

--Function Call:

SELECT * FROM last_recorded_drugs(1895783)

--As part of Cleaning Up:

Drop Function last_recorded_drugs(patient_id_input BIGINT)

--Output Screenshot: The output shows multiple rows of last recorded drugs since they all have same recorded time.

/* Q5. List the 5 most recent transfers.*/

--Query: 

WITH RankedTransfers AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY stoptime DESC) AS row_num -- This Ranks the most recent transfers 
    FROM transfer
)
SELECT * 
FROM RankedTransfers
WHERE row_num <= 5 --Listing the 5 most recent transfers Patient wise
ORDER BY patient_id, row_num;

/* Q6. Use a window function to calculate the rolling average of heart rate for each patient. */

--Query:

SELECT 
    inp_no,
    charttime,
    heart_rate,
    ROUND(AVG(heart_rate::Integer) OVER (
        PARTITION BY inp_no 
        ORDER BY charttime 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ),2) AS rolling_avg_heart_rate
FROM 
    nursingchart
WHERE 
    heart_rate IS NOT NULL
ORDER BY 
    inp_no, charttime;

/* Q7. List patients who were transferred back into surgery after they were discharged.  */

--Query:

SELECT  *
FROM transfer
WHERE 
    startreason = 'Transfer' 
    AND stopreason = 'Patient pre discharge' 
    AND transferdept = 'Surgery'
ORDER BY patient_id;

/* Q8. Find the average age in each department by gender */

--Query: Used CEIL() to Round Up:

SELECT admitdept, sex, CEIL(AVG(age)) AS avg_age
FROM baseline
GROUP BY admitdept, sex;

/* Q9. Show all patients whose blood sugar is in the 99th percentile, and the time when it was recorded. */

--Query:

WITH percentile_calc AS (
    SELECT 
        inp_no,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY blood_sugar) AS bs_99_perc
    FROM 
        nursingchart
    GROUP BY
        inp_no
)
SELECT DISTINCT
    b.patient_id,
    n.inp_no,
    n.charttime AS recordedtime,
    n.blood_sugar,
	pc.bs_99_perc
FROM 
    nursingchart n
JOIN 
    percentile_calc pc ON n.inp_no = pc.inp_no
JOIN
    baseline b ON b.inp_no = n.inp_no
WHERE
    n.blood_sugar >= pc.bs_99_perc  -- Filtering blood sugar values in the 99th percentile
ORDER BY 
    b.patient_id, n.charttime;

/* Q10. Show the last 6 letters of disease names. */

--Query: Using REGEXP_SUBSTR Function

SELECT DISTINCT icd_desc as DiseaseName, REGEXP_SUBSTR(icd_desc, '.{6}$') AS last_six_letters
FROM icd
ORDER BY icd_desc;

/* Q11. Show the most commonly administered drug for each department, and the number of times it was administered. Use windows function to achieve this. */

--Query:

WITH Rank_Drugs AS (
    SELECT 
        patient_id,
        drugname,
        COUNT(drugname) AS common_drug,
        RANK() OVER (PARTITION BY patient_id ORDER BY COUNT(drugname) DESC) AS rank_drug
    FROM 
        drugs
    GROUP BY 
        patient_id, drugname
)
SELECT 
	b.admitdept,
	rd.drugname,
    MAX(rd.common_drug) AS times_given
FROM 
    baseline b
JOIN 
    Rank_Drugs rd ON b.patient_id = rd.patient_id
WHERE 
    rd.rank_drug = 1
GROUP BY 
    b.admitdept,rd.drugname
ORDER BY 
    times_given DESC
LIMIT 3;

--Output: – Showing only the most common administered drug for each department

/* Q12. Show the position of the letter y in disease name if it exists. */

--Query 1: Using STRPOS Function

SELECT DISTINCT icd_desc as Disease_name, STRPOS(icd_desc, 'y') AS y_position
FROM icd
WHERE STRPOS(icd_desc, 'y') > 0
ORDER BY y_position DESC;

--Alternative Method to get the letter y position

--Query 2: Using POSITION Function

SELECT DISTINCT icd_desc as Disease_name, POSITION('y' IN icd_desc) AS y_position
FROM icd 
WHERE POSITION('y' IN icd_desc) > 0
ORDER BY y_position DESC;

/* Q13. Using windows function rank and display the 3 oldest patients admitted into each department. */

--Query:

WITH Rank_Patients AS (
    SELECT 
        patient_id,
        admitdept,
        age,
		sex,
        DENSE_RANK() OVER (PARTITION BY admitdept ORDER BY age DESC) AS rank_num -- Used Dense_Rank() instead of Rank() to avoid skipping ranks
    FROM 
        baseline
)
SELECT 
    patient_id,
    admitdept,
    age,
	sex,
    rank_num
FROM 
    Rank_Patients
WHERE 
    rank_num <= 3
ORDER BY 
    admitdept, rank_num;

/* Q14. Show the number of patients that were discharged in 2020. */

--Query: Using Date_Part Function

SELECT 
    DATE_PART('year', icu_discharge_time) AS discharge_year,
    COUNT(patient_id) AS patient_count
FROM 
    baseline
WHERE DATE_PART('year', icu_discharge_time) = 2020
GROUP BY 
    DATE_PART('year', icu_discharge_time)
ORDER BY 
    discharge_year;

/* Q15. Show the total ICU stay in days for each patient who was transferred at least once.*/

--Query:

SELECT 
    patient_id,
    startreason,
    transferdept,
    SUM(EXTRACT(DAY FROM (stoptime - starttime))) AS total_ICU_stay_in_days
FROM 
    transfer
WHERE 
    transferdept = 'ICU' 
    AND startreason = 'Transfer'
GROUP BY 
    patient_id, startreason, transferdept
HAVING 
    SUM(EXTRACT(DAY FROM (stoptime - starttime))) != 0
ORDER BY 
    total_ICU_stay_in_days desc;

/* Q16. Find the average, minimum, and maximum systolic blood pressure for patients in each department. */

--Query:

SELECT DISTINCT 
    b.patient_id,
    b.admitdept,
    MIN(n.invasive_sbp) AS Min_SBP,
    MAX(n.invasive_sbp) AS Max_SBP,
    TRUNC(AVG(n.invasive_sbp::INTEGER),2) AS AVG_SBP -- Keeping only 2 decimal places
FROM 
    nursingchart n 
JOIN 
    baseline b
ON 
    b.inp_no = n.inp_no 
WHERE 
    n.invasive_sbp IS NOT NULL -- Not Showing Null Values in the result
GROUP BY 
    b.admitdept,b.patient_id
ORDER BY
	b.admitdept;


--Q.17 Write a stored procedure to calculate the total number of patients per department and return the results as a table.

--Query

---- DROP PROCEDURE IF EXISTS TotalPatientCntPerDept(); 
---- Drop the procedure if it already exists
CREATE OR REPLACE PROCEDURE TotalPatientCntPerDept()
LANGUAGE plpgsql
AS $$
BEGIN
   -- Create a temporary table to store the results
   CREATE TEMP TABLE IF NOT EXISTS PtCntPerDept (
       PatientCnt INT, 
       DeptName TEXT
   );
   -- Empty the table before running the query
   TRUNCATE PtCntPerDept;
   -- Insert the patient count per department
   INSERT INTO PtCntPerDept (PatientCnt, DeptName)
   SELECT 
       COUNT(patient_id), 
       admitdept
   FROM 
       baseline
   GROUP BY 
       admitdept;
END;
$$;
-- Call the procedure
CALL TotalPatientCntPerDept();
-- Retrieve the results from the temporary table
SELECT * FROM PtCntPerDept;

--As part of Cleaning up:

DROP Procedure TotalPatientCntPerDept()

--Q.18 Show the top 3 patients who went into surgery the most number of times

-- Query

SELECT 
    patient_id,
    COUNT(patient_id) AS surgery_ct
FROM 
    transfer
WHERE 
    startreason = 'Transfer'
	AND
    transferdept = 'Surgery'
GROUP BY 
    patient_id
ORDER BY 
    COUNT(patient_id) DESC
LIMIT 3; -- Returns top 3 patients who had max surgery



--Q.19 Show patients whose critical-care pain observation tool score is 0.

--Query

SELECT DISTINCT 
    b.patient_id, 
    n.cpot_pain_score -- cpot = critical-care pain observation tool
FROM 
    baseline b
JOIN 
    nursingchart n
    ON b.inp_no = n.inp_no
WHERE 
    n.cpot_pain_score = '0';



--Q.20 Use windows functions to find BP measurements for 3 consecutive days. 
--List all patients who experienced a drop in blood pressure measurements for 3 continuous days.

--Query

--CTE to get the daywise avg bp per patient
WITH bp_record AS 
 (
    SELECT 
        inp_no,
        AVG(invasive_sbp) AS avg_invasive_sbp, -- Avg sbp for the day
        AVG(invasive_diastolic_blood_pressure) AS avg_invasive_dbp,  -- Avg dbp for the day
		DATE(charttime) AS bp_day
    FROM nursingchart
	WHERE invasive_sbp IS NOT NULL AND invasive_diastolic_blood_pressure IS NOT NULL
    GROUP BY inp_no, DATE(charttime)
), 
--CTE to get the 3 consecutive days BP records
consecutive_days_data AS (
	SELECT 
        inp_no,
        avg_invasive_sbp,
		avg_invasive_dbp,
        bp_day,
        LAG(avg_invasive_sbp, 1) OVER (PARTITION BY inp_no ORDER BY bp_day) AS prev_day1_avg_sbp,
        LAG(avg_invasive_sbp, 2) OVER (PARTITION BY inp_no ORDER BY bp_day) AS prev_day2_avg_sbp,
		LAG(avg_invasive_dbp, 1) OVER (PARTITION BY inp_no ORDER BY bp_day) AS prev_day1_avg_dbp,
        LAG(avg_invasive_dbp, 2) OVER (PARTITION BY inp_no ORDER BY bp_day) AS prev_day2_avg_dbp,
		LAG(bp_day, 1) OVER (PARTITION BY inp_no ORDER BY bp_day) AS prev_day1,
        LAG(bp_day, 2) OVER (PARTITION BY inp_no ORDER BY bp_day) AS prev_day2
    FROM bp_record
)
SELECT 
    inp_no,
	bp_day,
    avg_invasive_sbp,
    prev_day1_avg_sbp,
    prev_day2_avg_sbp,
	avg_invasive_dbp,
	prev_day1_avg_dbp,
    prev_day2_avg_dbp
FROM consecutive_days_data 
WHERE 
	    prev_day1_avg_sbp IS NOT NULL AND prev_day2_avg_sbp IS NOT NULL  
    AND avg_invasive_sbp < prev_day1_avg_sbp
    AND prev_day1_avg_sbp < prev_day2_avg_sbp
	AND prev_day1_avg_dbp IS NOT NULL AND prev_day2_avg_dbp IS NOT NULL
	AND avg_invasive_dbp < prev_day1_avg_dbp
    AND prev_day1_avg_dbp < prev_day2_avg_dbp
	AND DATE(prev_day1) = DATE(bp_day) - INTERVAL '1 day' ----to check consecutive days
    AND DATE(prev_day2) = DATE(bp_day) - INTERVAL '2 day'; 

--Output: –Since dataset is not having consecutive days record output has no values

--Q.21 How was general health of patients who had a breathing rate > 20?

--Query

SELECT
    b.patient_id, 
	o.sf36_generalhealth AS generalhealth,
    MAX(n.breathing) AS max_breathing
FROM 
    outcome o
JOIN 
    baseline b
    ON o.patient_id=b.patient_id
JOIN 
    nursingchart n
    ON b.inp_no=n.inp_no
WHERE 
    n.breathing >20 
	AND o.sf36_generalhealth IS NOT NULL--...Ensuring non-null general health values
GROUP BY
    (b.patient_id), o.sf36_generalhealth
ORDER BY 
    max_breathing;


--Q.22 List patients with heart_rate more than two standard deviations from the average.

--Query

WITH twostdev AS 
( 
 SELECT  AVG(heart_rate) AS mean_hr,
         STDDEV_POP (heart_rate) AS stdev_hr
 FROM nursingchart 
),
heartrate AS (
	SELECT 
	  b.patient_id, n.heart_rate,
	DENSE_RANK() OVER (PARTITION BY b.patient_id ORDER BY n.heart_rate DESC) AS Rank_heart_rate
	FROM 
	  baseline b 
	JOIN 
	  nursingchart n 
	  ON b.inp_no=n.inp_no 
	JOIN 
	  twostdev ts 
	  ON true
	WHERE 
	  n.heart_rate > (ts.mean_hr + 2*ts.stdev_hr) -- Considering STDDEV on +ve side
	  OR n.heart_rate < (ts.mean_hr - 2*ts.stdev_hr) -- Considering STDDEV on -ve side  
)
SELECT DISTINCT patient_id, heart_rate
FROM 
  heartrate 
WHERE 
  Rank_heart_rate =1;


--Q.23 Create a trigger to raise notice and prevent deletion of a record from baseline table.

--Query

CREATE OR REPLACE FUNCTION record_deletion_notice ()
 RETURNS TRIGGER 
 LANGUAGE plpgsql
 AS
$$
BEGIN
 RAISE NOTICE 'Record deletion is not allowed'; -- Raising Notice
 RAISE EXCEPTION 'Exception: Deletion not allowed'; -- Preventing deletion 
 RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER record_deletion_notice
BEFORE DELETE ON baseline
FOR EACH ROW EXECUTE FUNCTION record_deletion_notice();

DELETE FROM baseline WHERE age = 57; --Triggering the Exception 

SELECT * FROM baseline;

--As part of Cleaning up:

Drop FUNCTION record_deletion_notice () CASCADE;

--Q.24 Use a CTE to get all patients with temperature readings above 38.

--Query

WITH temp_above_38 AS (
  SELECT
    b.patient_id, 
	n.temperature,
  DENSE_RANK() OVER (PARTITION BY b.patient_id ORDER BY n.temperature DESC) AS Rank_temp
  FROM 
    baseline b
  JOIN 
    nursingchart n 
    ON n.inp_no=b.inp_no
  WHERE 
	n.temperature > 38
)
SELECT DISTINCT patient_id, temperature 
FROM 
 temp_above_38 
WHERE
 Rank_temp = 1


--Q.25 Develop a stored procedure to insert a new patient into the patients table and return the new patient ID.

--Query

DROP TABLE IF EXISTS patient_table; -- Only needed if want to create a new table 
DROP PROCEDURE IF EXISTS InsertPatient;

-- New Patient table as there is existing patient table in dataset
CREATE TABLE IF NOT EXISTS patient_table
(
  patient_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY, -- Auto generates unique Patient Id
  age INT, 
  patient_name TEXT
);
CREATE OR REPLACE PROCEDURE 
   InsertPatient(OUT pt_id BIGINT, IN pt_age INT, IN pt_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO patient_table(age, patient_name)
  VALUES (pt_age, pt_name)
  RETURNING patient_id INTO pt_id; -- Return generated patient Id
END;
$$;

DO $$ 
DECLARE
  id_pt BIGINT;
BEGIN
  CALL InsertPatient(id_pt, 50, 'JASON');
  RAISE NOTICE 'Inserted patient with patient_id: %', id_pt;
  CALL InsertPatient(id_pt, 29, 'Reena');
  RAISE NOTICE 'Inserted patient with patient_id: %', id_pt;
  CALL InsertPatient(id_pt, 60, 'Bloom');
  RAISE NOTICE 'Inserted patient with patient_id: %', id_pt;
END $$;

SELECT * FROM patient_table; -- optional : return the table with patient data

--As part of Cleaning up:

DROP TABLE IF EXISTS patient_table; 
DROP PROCEDURE IF EXISTS InsertPatient;

--Q.26 Find a correlation between blood sugar levels and discharge time from ICU.

--Query

SELECT CORR(EXTRACT(EPOCH FROM b.icu_discharge_time), n.blood_sugar) AS correlation 
FROM 
  baseline b
JOIN 
  nursingchart n 
  ON n.inp_no = b.inp_no 
WHERE 
   n.blood_sugar IS NOT NULL AND
   b.icu_discharge_time IS NOT NULL;

--Output: It shows a Weak Negative Correlation between blood sugar levels and discharge time from ICU which indicates that the two variables move in opposite directions.

--Q.27 Divide the patients into 3 age groups.

--Query 1

SELECT COUNT(patient_id) FILTER(WHERE(age<30)) AS "Under 30 Years",
       COUNT(patient_id) FILTER(WHERE(age>=30 AND age<=60)) AS "30-60 years",
	   COUNT(patient_id) FILTER(WHERE(age>60)) AS "OVER 60 Years"
FROM baseline;

--Query 2

SELECT COUNT(CASE WHEN(age<30)THEN patient_id ELSE NULL END) AS "Under 30 Years",
       COUNT(CASE WHEN(age>=30 AND age<=60)THEN patient_id ELSE NULL END) AS "30-60 years",
	   COUNT(CASE WHEN(age>60)THEN patient_id ELSE NULL END) AS "Over 60 Years"
FROM baseline;


--Q.28 Show the hour(as a time slot like 9 AM - 10 AM) when least discharges happen

--Query

CREATE OR REPLACE PROCEDURE ExtractDatetime()
LANGUAGE plpgsql
AS $$
BEGIN
  DROP TABLE IF EXISTS discharge_data_time;
  CREATE TEMP TABLE IF NOT EXISTS discharge_data_time( PatientID INT, extract_hour INT, extract_hour_slot TEXT );
  TRUNCATE discharge_data_time; 
  
  INSERT INTO discharge_data_time(PatientID, extract_hour, extract_hour_slot)
   SELECT 
	patient_id,
	extracted_hour, 
	CASE -- Converting 24 hr clock to 12 hours with AM/PM 
		WHEN extracted_Hour = 0 THEN '12AM - 1AM' 
		WHEN extracted_Hour < 11 THEN 
			extracted_Hour::TEXT || 'AM - ' || 
			(extracted_Hour + 1)::TEXT || 'AM'
		WHEN extracted_Hour = 11 THEN '11AM - 12PM'
		WHEN extracted_Hour = 12 THEN '12PM - 1PM'
		WHEN extracted_Hour = 23 THEN '11PM - 12AM'
		ELSE 
			(extracted_Hour - 12)::TEXT || 'PM - ' ||
			(extracted_Hour - 11)::TEXT || 'PM'
	END AS TimeSlot 
   FROM (
    SELECT patient_id, EXTRACT(HOUR FROM icu_discharge_time) AS extracted_hour
    FROM baseline
  ) AS extracted_data;
END;
$$;

CALL ExtractDatetime();
SELECT extract_hour_slot, COUNT(extract_hour) AS discharge_per_hr 
FROM 
 discharge_data_time
GROUP BY 
 extract_hour_slot 
ORDER BY COUNT
 (extract_hour_slot) 
ASC LIMIT 1;

--As part of Cleaning up:

DROP TABLE IF EXISTS discharge_data_time; 
DROP PROCEDURE IF EXISTS ExtractDatetime();

--Q.29 Display 3 random patients who had UTI.

--Query

SELECT * 
FROM 
  baseline 
WHERE 
  infectionsite='UTI'
ORDER BY RANDOM() 
LIMIT 3 ;


--Q.30 List the average length of stay for patients diagnosed with soft tissue infections.

--Query

SELECT AVG (t.stoptime - t.starttime) 
FROM 
  transfer t 
JOIN
  baseline b
  ON b.patient_id=t.patient_id 
WHERE 
  b.infectionsite = 'Soft Tissue' 


--Q.31 Create a table called Patient1952 to store all patients born in 1952 with their age and sex info.

--Query

DROP TABLE IF EXISTS Patient1952;
CREATE TABLE IF NOT EXISTS Patient1952 AS
SELECT 
 patient_id, age, sex, EXTRACT(YEAR FROM icu_discharge_time) AS extracted_YEAR  
FROM 
 baseline 
WHERE 
  (EXTRACT(YEAR FROM icu_discharge_time) - age) = 1952; -- Formula: discharged Year - age = Birth Year
SELECT * 
FROM 
  Patient1952 

--As part of Cleaning up:

DROP TABLE IF EXISTS Patient1952; 

--Q.32 Give the highest temperature, and highest heart rate recorded of all the patients in surgery for each day

--Query

SELECT
	DATE(n.charttime) AS record_day,
	MAX (n.temperature) AS highest_temp, 
	MAX (n.heart_rate) AS heighest_hr
FROM 
    nursingchart n
JOIN 
    baseline b
    ON n.inp_no=b.inp_no
WHERE 
    b.admitdept = 'Surgery'
GROUP BY 
    record_day
ORDER BY 
    record_day;

--SELECT * from baseline where admitdept='Surgery'

--Q.33.  "List all patients whose heart rate increased by over 30% from the previous reading and the time when it happened.
--List all occurences of heart rate increase. Use Windows functions to achieve this."

--Query:

SELECT 
    b.patient_id,  -- Include patient_id from baseline
    nc.inp_no, 
    nc.charttime,
    nc.heart_rate,
    prev_heart_rate,
    ROUND(heart_rate_increase_percentage::INT, 2) AS heart_rate_increase_percentage  -- Round the percentage to 2 decimal places
FROM (
    SELECT 
        inp_no, 
        charttime,
        heart_rate,
        LAG(heart_rate) OVER (PARTITION BY inp_no ORDER BY charttime) AS prev_heart_rate,
        CASE 
            WHEN LAG(heart_rate) OVER (PARTITION BY inp_no ORDER BY charttime) = 0 
                 OR LAG(heart_rate) OVER (PARTITION BY inp_no ORDER BY charttime) IS NULL 
            THEN NULL
            ELSE (heart_rate - LAG(heart_rate) OVER (PARTITION BY inp_no ORDER BY charttime)) * 100.0 / LAG(heart_rate) OVER (PARTITION BY inp_no ORDER BY charttime)
        END AS heart_rate_increase_percentage
    FROM 
        nursingchart
) AS nc
JOIN 
    baseline b ON nc.inp_no = b.inp_no  -- Join with baseline to get patient_id
WHERE 
    prev_heart_rate IS NOT NULL  -- Ensures there was a previous heart rate reading
    AND heart_rate_increase_percentage > 30  -- Filter for heart rate increase of over 30%
ORDER BY 
    b.patient_id, nc.charttime;

--Q.34. List patients who had milk and soft food but produced no urine.

--Query:

SELECT * FROM nursingchart WHERE milk IS NOT NULL AND soft_food IS NOT NULL AND urine_volume = 0;

--Output : – Empty resultset. Got no patients who had milk and softfood but produced no urine. 

--Q.35. Using crosstab, show number of times each patient was transferred to each department.

--Query:

CREATE EXTENSION IF NOT EXISTS tablefunc;
--With Cross tab 
SELECT * 
FROM crosstab(
    $$ 
    SELECT DISTINCT patient_id, transferdept, count(transferdept) AS transfertimes 
    FROM transfer 
    GROUP BY patient_id, transferdept 
    ORDER BY patient_id, transferdept
    $$,
    $$ 
    VALUES ('ICU'), ('Surgery'), ('Medical Specialties') 
    $$ 
) 
AS CT(
    PatientID INT, 
    DPT1 INT, 
    DPT2 INT, 
    DPT3 INT
);

--As part of Cleaning up:

DROP EXTENSION IF EXISTS tablefunc; 

--Q.36. Produce a list of 100 normally distributed age values. Set the mean as the 3rd lowest age in the table, and assume the standard deviation from the mean is 3.

--Query:

WITH age_data AS (
    SELECT DISTINCT age  -- Ensure distinct ages
    FROM baseline
    ORDER BY age
    LIMIT 3  -- Get the 3 lowest distinct ages
),
mean_age AS (
    SELECT age
    FROM age_data
    ORDER BY age
    LIMIT 1 OFFSET 2  -- This will get the 3rd lowest age as the mean
)
SELECT 
    round(mean_age.age + (random() - 0.5) * 18)::int AS generated_age  -- Standard deviation set to 3
FROM generate_series(1, 100) gs,
     mean_age;

--Q.37. Display the patients who engage in vigorous physical activity and have no body pain.

--Query:

SELECT    
    patient_id,
    sf36_activitylimit_vigorousactivity, 
    sf36_pain_bodypainpast4wk
FROM
    outcome 
where 
    sf36_activitylimit_vigorousactivity IS NOT NULL 
    AND 
    sf36_pain_bodypainpast4wk='1_None';


--Q.38. Create a view on outcome table to show patients with poor health.

--Query:

--Creating a view for poor health patients

CREATE VIEW PoorHealthPatients AS
SELECT patient_id,sf36_generalhealth FROM outcome where sf36_generalhealth='5_Poor';

--Running the View

SELECT * FROM PoorHealthPatients;

--As part of Cleaning up:

DROP VIEW PoorHealthPatients; 

--Q.39. Create a procedure to check if a disease code exists.

--Query:

CREATE OR REPLACE PROCEDURE diseaseexists(diseasecode TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM icd WHERE icd_code = diseasecode) THEN
        RAISE NOTICE 'Disease code exists';
    ELSE
        RAISE NOTICE 'Disease code does not exist';
    END IF;
END;
$$;

--Procedure Call:
--Existing Disease code:
call diseaseexists('G93.812');

--In Existing Disease code:
call diseaseexists('G900.812');

--As part of Cleaning up:
DROP PROCEDURE diseaseexists(diseasecode TEXT); 

--Q.40. Which drug was most administered among patients who have never been intubated?

--Query:

SELECT DISTINCT drugname, count(drugname) AS mostused 
FROM drugs 
WHERE patient_id IN (
    SELECT patient_id 
    FROM baseline 
    WHERE inp_no IN (
        SELECT inp_no 
        FROM public.nursingchart 
        WHERE extubation = true -- Filter for patients who were never intubated
    )
)
GROUP BY patient_id, drugname
ORDER BY mostused DESC
LIMIT 1;  -- To show the most administered drug

--Q.41. Add a column birthyear to baseline column based on age.

--Query:

ALTER TABLE baseline
ADD birthyear int;

UPDATE baseline
SET birthyear =Extract(YEAR FROM (icu_discharge_time))-age;
SELECT * FROM 
    baseline;

--As part of Cleaning up:
ALTER TABLE baseline
DROP COLUMN IF EXISTS birthyear;

--Q.42. Use regular expression to find disease names that end in 'itis'.

--Query:

SELECT DISTINCT icd_desc
FROM icd
WHERE icd_desc ~ 'itis$';

--Q.43. Write a stored procedure to generate a summary report for a patient ID specified by user, including blood sugar, temperature, heart rate and drug administration.

--Query:

CREATE OR REPLACE PROCEDURE generate_patient_report(patient_id_input INT)
LANGUAGE plpgsql
AS $$
DECLARE
    blood_sugar_avg NUMERIC;
    temperature_avg NUMERIC;
    heart_rate_avg NUMERIC;
    drug_count INT;
BEGIN
    -- Get average blood sugar for the patient from the nursingchart table, joined with baseline
    SELECT Round(AVG(nc.blood_sugar)::Int,2) INTO blood_sugar_avg
    FROM nursingchart nc
    JOIN baseline b ON nc.inp_no = b.inp_no
    WHERE b.patient_id = patient_id_input;

    -- Get average temperature for the patient from the nursingchart table, joined with baseline
    SELECT Round(AVG(nc.temperature)::Int,2) INTO temperature_avg
    FROM nursingchart nc
    JOIN baseline b ON nc.inp_no = b.inp_no
    WHERE b.patient_id = patient_id_input;

    -- Get average heart rate for the patient from the nursingchart table, joined with baseline
    SELECT Round(AVG(nc.heart_rate)::Int,2) INTO heart_rate_avg
    FROM nursingchart nc
    JOIN baseline b ON nc.inp_no = b.inp_no
    WHERE b.patient_id = patient_id_input;

    -- Get count of drugs administered to the patient from the drugs table, joined with baseline
    SELECT COUNT(*) INTO drug_count
    FROM drugs d
    JOIN baseline b ON d.patient_id = b.patient_id
    WHERE b.patient_id = patient_id_input;

    -- Output the summary report using RAISE NOTICE
    RAISE NOTICE 'Patient ID: %, Blood Sugar Average: %, Temperature Average: %, Heart Rate Average: %, Drug Administered Count: %',
        patient_id_input, blood_sugar_avg, temperature_avg, heart_rate_avg, drug_count;

END;
$$;

--Procedure Call:
 
CALL generate_patient_report('6291268')

--As part of Cleaning up:
DROP PROCEDURE generate_patient_report;

--Q.44. Create an index on any column in outcome table and also write a query to delete that index.

--Query:

CREATE INDEX health on outcome (sf36_generalhealth NULLS LAST);
--INDEX created successfully to keep NULLS in the LAST

SELECT * FROM outcome; --Displaying the Table

DROP INDEX health; -- Dropping the Index

--Q.45. Display the sf36_generalhealth of all patients whose blood sugar has a standard deviation of more than 2 from the average.

--Query:

WITH blood_sugar_stats AS (
    -- Calculate the average and standard deviation of blood sugar for each patient
    SELECT 
        base.patient_id,
        AVG(nc.blood_sugar) AS avg_blood_sugar,
        STDDEV(nc.blood_sugar) AS stddev_blood_sugar
    FROM 
        nursingchart nc
    JOIN 
        baseline base ON nc.inp_no = base.inp_no
    GROUP BY 
        base.patient_id
),
patients_above_stddev AS (
    -- Filter out patients whose blood sugar has a standard deviation of more than 2 from the Average
    SELECT 
        bss.patient_id
    FROM 
        blood_sugar_stats bss
    WHERE 
        bss.stddev_blood_sugar > 2
)
SELECT 
    o.patient_id,
    o.sf36_generalhealth
FROM 
    outcome o
JOIN 
    patients_above_stddev pas ON o.patient_id = pas.patient_id
WHERE
	o.sf36_generalhealth is not null
ORDER BY 
    o.patient_id;

--Q.46. Show the average time spent across different departments among alive patients, and among dead patients.

--Query:

SELECT 
    transferdept,
    follow_vital,
    Round(AVG(EXTRACT(EPOCH FROM (stoptime - starttime)) / 3600),2) AS avg_time_hours
FROM 
    transfer t
JOIN 
    outcome o ON t.patient_id = o.patient_id
WHERE 
    o.follow_vital IN ('Alive', 'Death')  -- Filter based on patient status
GROUP BY 
    transferdept, follow_vital
ORDER BY 
    transferdept, follow_vital;

--Q.47. Write a query to list all the users in the database.

--Query:

SELECT rolname 
FROM pg_roles;

--Q.48. For each patient, find their maximum blood oxygen saturation while they were in the ICU , and display if it is above or below the average value among all patients.

--Query:

WITH max_oxy_per_patient AS (
    -- Get the maximum blood oxygen saturation for each patient while in the ICU
    SELECT 
        b.patient_id,
        MAX(nc.blood_oxygen_saturation) AS max_oxygen
    FROM 
        nursingchart nc
    JOIN 
        baseline b ON nc.inp_no = b.inp_no
    WHERE 
        b.admitdept = 'ICU'  -- Only consider ICU admissions
    GROUP BY 
        b.patient_id
),
avg_oxy AS (
    -- Calculate the average blood oxygen saturation for all patients
    SELECT 
        round(AVG(blood_oxygen_saturation)::Int,2) AS avg_oxygen
    FROM 
        nursingchart
)
SELECT 
    m.patient_id,
    m.max_oxygen,
    a.avg_oxygen,
    CASE 
        WHEN m.max_oxygen > a.avg_oxygen THEN 'Above Average'
        WHEN m.max_oxygen < a.avg_oxygen THEN 'Below Average'
        ELSE 'Equal to Average'
    END AS oxygen_status
FROM 
    max_oxy_per_patient m, 
    avg_oxy a
ORDER BY 
    oxygen_status DESC;
    

--Q.49. For each department, find the percentage of alive patients whose general health was poor after discharge.

--Query:

SELECT 
    discharge_dept, 
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE follow_vital = 'Alive'
            AND sf36_generalhealth = '5_Poor' 
            AND follow_date > ICU_discharge_time
        ) / COUNT(*), 2
    ) AS poor_health_percentage
FROM 
    outcome o
JOIN 
    baseline b
ON 
    o.patient_id = b.patient_id
WHERE 
    ICU_discharge_time IS NOT NULL
GROUP BY 
    discharge_dept;


--Q.50. Write a function that takes a date and returns the average temperature recorded for that day.

--Query:

CREATE OR REPLACE FUNCTION Avg_Temp(date_input timestamp without time zone)
RETURNS Numeric  AS $$
BEGIN
RETURN COALESCE(( -- Used COALESCE for ERROR Handling
	SELECT Round( AVG(temperature),2)
	FROM nursingchart  
	WHERE DATE(charttime)=DATE(date_input )
	),NULL);
END;
$$Language plpgsql;

-- SELECT is used to call function and display the result.

SELECT 'Average Temp:' , Avg_Temp('2019-02-23 00:00:00') As Avg_temp;

-- Error Handled if the date is not available in the table:

SELECT 'Average Temp:' , Avg_Temp('2025-02-23 00:00:00') As Avg_temp;

--As part of Cleaning up:
DROP FUNCTION Avg_Temp(date_input timestamp without time zone);

--Q.51. Show the time spent in ICU for each patient that transferred to ICU from surgery.

--Query:

WITH surgery_to_icu_transfers AS (
    SELECT
        patient_id,
        inp_no,
        transferdept,
        starttime,
        stoptime,
        LAG(transferdept) OVER (PARTITION BY patient_id ORDER BY starttime) AS prev_dept,
        LEAD(transferdept) OVER (PARTITION BY patient_id ORDER BY starttime) AS next_dept
    FROM 
        transfer
)
SELECT 
    patient_id,
    inp_no,
    starttime AS icu_starttime,
    stoptime AS icu_endtime,
	prev_dept,
	next_dept,
    Round(EXTRACT(EPOCH FROM (stoptime - starttime)) / 3600,2) AS time_spent_hours
FROM 
    surgery_to_icu_transfers
WHERE 
    prev_dept = 'Surgery' AND transferdept = 'ICU';

--Q.52. List all the drugs that were administered between 4 and 5 AM.

--Query:

SELECT DISTINCT drugname, drug_time::TIME
FROM drugs
WHERE drug_time::TIME>='04:00:00' AND drug_time::TIME<='05:00:00'

--Q.53.	Rank each patient based on the number of times they went to ICU.

--Query:

SELECT DISTINCT 
    patient_id,
    COUNT(transferdept) AS icu_visits,
    RANK() OVER (ORDER BY COUNT(transferdept) DESC) AS rank_patients_toICU
FROM 
    transfer
WHERE 
    transferdept = 'ICU'
GROUP BY 
    patient_id
ORDER BY 
    rank_patients_toICU;

--Q.54.	Create a function to calculate the percentage of patients admitted into each department.

--Query:

CREATE OR REPLACE FUNCTION patient_percentage()
RETURNS TABLE(department TEXT, percentage NUMERIC) AS $$
BEGIN
    RETURN QUERY (
        SELECT admitdept, ROUND(100.0 * COUNT(*) / SUM(COUNT(*))OVER (),2)As Percentage
        FROM baseline
        GROUP BY admitdept
    );
END;
$$ LANGUAGE plpgsql;

--Function Call:

SELECT * FROM patient_percentage();

--As part of Cleaning up:
DROP FUNCTION patient_percentage();

--Q.55.	Calculate the variance and standard deviation of oxygen flow readings across different admin departments.

--Query:

SELECT 
admitdept,
ROUND(VARIANCE(CAST(oxygen_flow AS Numeric)),2) As variance,
ROUND(STDDEV(CAST(oxygen_flow AS Numeric)),2)AS standard_deviation
FROM nursingchart n
JOIN baseline b 
ON n.inp_no=b.inp_no
GROUP BY admitdept;

--Q.56.	Use a nested query to calculate the max blood_sugar among patients whose average is below 120

--Query:

SELECT MAX(blood_sugar) AS max_blood_sugar
FROM nursingchart
WHERE inp_no IN(SELECT inp_no
FROM nursingchart
GROUP BY inp_no
HAVING AVG(blood_sugar)<120)

--Q.57.	List all transfers that started due to a change in disease.

--Query:

WITH cte AS (
    SELECT DISTINCT 
        patient_id, 
        startreason, 
        stopreason, 
        LAG(stopreason) OVER (PARTITION BY patient_id ORDER BY starttime) AS previous_stopreason,
        LEAD(startreason) OVER (PARTITION BY patient_id ORDER BY starttime) AS next_startreason,
		transferdept
    FROM 
        transfer
)
SELECT 
    patient_id, 
	previous_stopreason,
    startreason,
	transferdept  
FROM 
    cte
WHERE 
    startreason = 'Transfer' 
    AND previous_stopreason = 'Disease change';

--Q.58.	Show the number of drugs administered to every patient aged 65 or older.

--Query:

SELECT drugs.patient_id, COUNT(*) AS drug_count
FROM drugs
JOIN baseline ON drugs.patient_id = baseline.patient_id
WHERE age >= 65
GROUP BY drugs.patient_id
ORDER BY drug_count desc;

--Q.59.	Find the patients report feeling happy all the time.

--Query:

SELECT 
   patient_id,
   sf36_emotional_happyperson
FROM 
   outcome
WHERE 
   sf36_emotional_happyperson = '1_All of the time';



--Q.60. List the patients that were discharged in December of any year.

--Query:

SELECT patient_id, inp_no
FROM baseline
WHERE EXTRACT(MONTH FROM icu_discharge_time) = 12;

--Q.61.	List the last 100 patients that were discharged.

--Query:

SELECT *
FROM baseline
ORDER BY icu_discharge_time DESC
LIMIT 100;

--Q.62.	 Create a role that cannot create other roles and expires on 12/31/24.

--Query:

CREATE ROLE role_limit WITH NOINHERIT LOGIN PASSWORD 'Password';
ALTER ROLE role_limit NOCREATEROLE;
ALTER ROLE role_limit VALID UNTIL '2024-12-31'

--Dropping the role as part of Cleaning up:
DROP ROLE role_limit 

--Q.63.	Find instances where a patient was transferred into the same department twice within a day.

--Query:

SELECT DISTINCT
    patient_id, 
    inp_no, 
    transferdept, 
    COUNT(*) AS transfer_count
FROM 
    transfer
GROUP BY 
    patient_id, 
    inp_no, 
    transferdept, 
    DATE(starttime)
HAVING 
    COUNT(*) = 2; -- Exactly 2 transfers into the same department on the same day

--Q.64.	Use nested CTEs to calculate the median temperature of patients over 60 years old while in ICU.

--Query:

WITH filtered_data AS (
    SELECT distinct patient_id,temperature
    FROM nursingchart
    JOIN baseline ON nursingchart.inp_no = baseline.inp_no
    WHERE baseline.age > 60 -- Patients over 60 years age
	AND temperature is not null -- Temperature should not be null
	AND baseline.admitdept = 'ICU' --Patients in ICU
),
ranked_data AS (
    SELECT patient_id,temperature, 
           ROW_NUMBER() OVER (ORDER BY temperature) AS row_num,
           COUNT(*) OVER (PARTITION BY patient_id) AS total_count
    FROM filtered_data
)
SELECT DISTINCT round(AVG(temperature),2) AS median_temperature
FROM ranked_data
WHERE 
    row_num IN (
        -- Select the middle row(s) for median calculation
        (total_count + 1) / 2, 
        (total_count + 2) / 2
    )
GROUP BY 
    patient_id

/*Q.65. Show the average sodium value for each patient.*/

--Query:

SELECT DISTINCT 
    patient_id, 
    ROUND(AVG(CAST(labvalue AS DECIMAL)), 2) AS "average_NA"
FROM 
    lab l
JOIN 
    baseline b ON l.inp_no = b.inp_no
WHERE 
    item = 'Sodium (NA)' 
    AND labvalue IS NOT NULL
GROUP BY 
    patient_id
ORDER BY
	patient_id
	
/*Q.66. For each department show the count of patients whose condition got worse a year after discharge.*/

--Query:

SELECT 
    discharge_dept, 
    COUNT(patient_id) AS patient_count
FROM 
    outcome
WHERE 
    sf36_oneyearcomparehealthcondition = '5_Much worse now than one year ago'
GROUP BY 
    discharge_dept
	
/*Q.67. Identify the patients who have the same systolic blood pressure values recorded for more than two consecutive days.*/

--Query:

WITH consecutive_bp AS (
    SELECT 
        inp_no,
        invasive_sbp,
        charttime,
        ROW_NUMBER() OVER (PARTITION BY inp_no ORDER BY charttime) - 
        ROW_NUMBER() OVER (PARTITION BY inp_no, invasive_sbp ORDER BY charttime) AS grp
    FROM 
        nursingchart
		WHERE invasive_sbp is not null
),
grouped_bp AS (
    SELECT 
        inp_no,
        invasive_sbp,
        COUNT(*) AS consecutive_days
    FROM 
        consecutive_bp
    GROUP BY 
        inp_no, invasive_sbp, grp
    HAVING 
        COUNT(*) > 2
)
SELECT DISTINCT
    inp_no, 
    invasive_sbp, 
    consecutive_days
FROM 
    grouped_bp
	
/*Q.68. Show the 9th youngest patient and if they are alive or not.*/

--Query:

WITH YoungestPatients AS (
    SELECT o.follow_vital, o.patient_id, b.age,
           DENSE_RANK() OVER (ORDER BY b.age) AS age_rank
    FROM outcome AS o
    JOIN baseline AS b
    ON o.patient_id = b.patient_id
)
SELECT follow_vital, patient_id, age
FROM YoungestPatients
WHERE age_rank = 9

/*Q.69. Show the bar distribution of ventilator modes for Pneumonia patients. Hint: Do not consider null values.*/

--Query:

SELECT 
    RPAD(breathing_pattern, 40, ' ') AS ventilator_mode,  -- Right pads the ventilator mode to a length of 40
    COUNT(*) AS mode_count,
    RPAD('', (COUNT(*) / 40)::int, '▰') AS mode_count_bar  -- Creates a visual bar of length proportional to the count
FROM baseline b
JOIN nursingchart n ON b.inp_no = n.inp_no
WHERE 
    infectionsite = 'Pneumonia'  
    AND breathing_pattern IS NOT NULL  
GROUP BY breathing_pattern
ORDER BY mode_count desc

/*Q.70. Create a view on baseline table with a check option on admit department .*/

--Query:

CREATE VIEW baseline_view AS
SELECT *
FROM baseline
WHERE admitdept = 'ICU'
WITH LOCAL CHECK OPTION

--To test the Check Option Inserting 2 rows

--1. Where admitdept = ICU = Succeed
--Insert Query: 
INSERT INTO baseline_view (patient_id, inp_no, age, sex, admitdept, infectionsite, icu_discharge_time)
VALUES (1234567, '9876543', 50, 'Female', 'ICU', 'Liver', '2019-02-03 12:48:24');

--2. Where admitdept = Surgery = Failed
--Insert Query: 
INSERT INTO baseline_view (patient_id, inp_no, age, sex, admitdept, infectionsite, icu_discharge_time)
VALUES (120000, '9876500', 50, 'Female', 'Surgery', 'Liver', '2019-02-03 12:48:24');

--Dropping as part of Cleaning up:
DROP VIEW baseline_view;

/*Q.71. How many patients were admitted to Surgery within 30 days of getting discharged?*/

--Query:

WITH discharged_patients AS (
    SELECT 
        patient_id,
        inp_no,
        starttime AS discharge_time
    FROM transfer
    WHERE stopreason = 'Patient pre discharge'
),
surgery_admissions AS (
    SELECT 
        patient_id,
        inp_no,
        starttime AS admission_time
    FROM transfer
    WHERE transferdept = 'Surgery' AND stopreason = 'be hospitalized'
)
SELECT 
   d.patient_id, d.discharge_time, s.admission_time,
    (s.admission_time::date - d.discharge_time::date) AS diff_in_days
FROM discharged_patients d
JOIN surgery_admissions s 
    ON d.patient_id = s.patient_id
    AND s.admission_time <= d.discharge_time + INTERVAL '30 DAY'
ORDER BY diff_in_days DESC;

/*Q.72. What percentage of the patients with blood oxygen saturation < 90 are alive?*/

--Query:

WITH LowOxygenPatients AS (
    SELECT 
        n.inp_no, 
        o.patient_id, 
        o.follow_vital
    FROM 
        outcome o 
    JOIN 
        baseline b ON b.patient_id = o.patient_id
    JOIN 
        nursingchart n ON n.inp_no = b.inp_no
    WHERE 
        blood_oxygen_saturation < 90 
        AND follow_vital IS NOT NULL
),
AlivePatients AS (
    SELECT COUNT(*) AS alive_count
    FROM LowOxygenPatients
    WHERE follow_vital = 'Alive'
),
TotalPatients AS (
    SELECT COUNT(*) AS total_count
    FROM LowOxygenPatients
)
SELECT 
    CAST(CASE 
            WHEN t.total_count = 0 THEN 0
            ELSE ROUND((a.alive_count::DECIMAL / t.total_count::DECIMAL) * 100, 2)
         END AS TEXT) || '%' AS percentage_of_patients
FROM 
    AlivePatients a
JOIN 
    TotalPatients t ON true;
	
/*Q.73. List the tables where column Patient_ID is present.(display column position number with respective table also)*/

--Query:

SELECT 
    table_name,
    ordinal_position AS column_position
FROM  information_schema.columns
WHERE  column_name = 'patient_id'
ORDER BY  table_name, column_position

/*Q.74. Find the average heart rate of patients under 40.*/

--Query:

SELECT 
    b.patient_id, 
    ROUND(CAST(AVG(n.heart_rate) AS NUMERIC), 2) AS avg_heart_rate
FROM 
    nursingchart n
JOIN 
    baseline b ON n.inp_no = b.inp_no
WHERE 
    b.age < 40 AND n.heart_rate IS NOT NULL
GROUP BY 
    b.patient_id;
	
/*Q.75. Use CTE to calculate the percentage of patients with hypoproteinemia who had to be intubated.*/

--Query:

WITH hypoproteinemia_patients AS (
    SELECT  distinct patient_id,inp_no,icd_desc
    FROM icd 
    WHERE 
        icd_desc = 'hypoproteinemia'
),
intubated_patients AS(
	SELECT distinct patient_id
	FROM nursingchart n
	JOIN  hypoproteinemia_patients h
	ON n.inp_no=h.inp_no
	WHERE 
        endotracheal_intubation_depth IS NOT NULL
)
SELECT 
   ROUND((COUNT (DISTINCT i.patient_id) * 100.0 / COUNT(DISTINCT h.patient_id)),2) AS percentage_intubated
FROM 
    hypoproteinemia_patients h
 LEFT JOIN 
    intubated_patients i
ON 
    h.patient_id = i.patient_id
	
/*Q.76. Identify patients whose breathing tube has been removed.*/

--Query:

SELECT DISTINCT patient_id
FROM baseline b
JOIN nursingchart n
    ON b.inp_no = n.inp_no
WHERE extubation = 'true'
ORDER BY patient_id;

/*Q.77. Compare each diastolic blood pressure value with the previous reading. And show previous and current value*/

--Query:

SELECT 
    inp_no,
    charttime,
    invasive_diastolic_blood_pressure AS current_value_dbp,
    LAG(invasive_diastolic_blood_pressure) OVER (PARTITION BY inp_no ORDER BY charttime) AS previous_value_dbp,
    invasive_diastolic_blood_pressure - LAG(invasive_diastolic_blood_pressure) 
	OVER (PARTITION BY inp_no ORDER BY charttime) AS difference_dbp
FROM 
    nursingchart
WHERE 
    invasive_diastolic_blood_pressure IS NOT NULL
ORDER BY 
    inp_no, charttime;
	
/*Q.78. List patients who have more than 500 entries in the nursing chart.*/

--Query:

SELECT 
    b.patient_id,
    n.inp_no,
    COUNT(n.inp_no) AS no_of_entries
FROM 
    nursingchart n
INNER JOIN 
    baseline b
ON 
    n.inp_no = b.inp_no
GROUP BY 
    b.patient_id, n.inp_no
HAVING 
    COUNT(n.inp_no) > 500
ORDER BY 
    no_of_entries DESC;  -- Orders the result in descending order, so the patients with the most entries are shown first
	
/*Q.79. Display month name and the number of patients discharged from the ICU in that month.*/

--Query:

SELECT
    TO_CHAR(icu_discharge_time, 'YYYY') AS Year,
    TO_CHAR(icu_discharge_time, 'FMMonth') AS month_name, -- FM for removing padding spaces
    COUNT(patient_id) AS patient_count
FROM 
    baseline
WHERE 
    admitdept = 'ICU'
    AND icu_discharge_time IS NOT NULL
GROUP BY 
    TO_CHAR(icu_discharge_time, 'YYYY'),
    TO_CHAR(icu_discharge_time, 'MM'),  -- Use month number for grouping
    TO_CHAR(icu_discharge_time, 'FMMonth')  -- Group by the month name as well
ORDER BY 
    Year, 
    TO_CHAR(icu_discharge_time, 'MM');  -- Correct chronological order of months
	
/*Q.80. Write a function that calculates the percentage of people who had moderate body pain after 4 weeks.*/

--Query:

CREATE OR REPLACE FUNCTION calculate_moderate_body_pain_percentage()
RETURNS NUMERIC AS $$
DECLARE
    total_patients INTEGER;
    moderate_pain_patients INTEGER;
    percentage NUMERIC;
BEGIN
    -- Use a single query to get both counts
    SELECT 
        count(*) FILTER (WHERE sf36_pain_bodypainpast4wk IS NOT NULL) AS total_patients,
        count(*) FILTER (WHERE sf36_pain_bodypainpast4wk = '4_Moderate') AS moderate_pain_patients
    INTO total_patients, moderate_pain_patients
    FROM outcome;
    -- Avoid division by zero
    IF total_patients > 0 THEN
        percentage := ROUND((moderate_pain_patients * 100.0 / total_patients), 2);
    ELSE
        percentage := 0; -- If no patients, percentage is 0
    END IF;
RETURN percentage;
END;
$$ LANGUAGE plpgsql;

--Function Call:

SELECT * FROM calculate_moderate_body_pain_percentage()

--Dropping as part of Cleaning up:
DROP FUNCTION calculate_moderate_body_pain_percentage();