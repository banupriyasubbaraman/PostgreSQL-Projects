/* Cardiac Failure Database SQL Project */

--Q1. Update the demography table. Add a random age  for each patient that falls within their respective age category. This newly added age should be an integer.		"(Note: Please complete questions 1 and 2 first, as several subsequent questions depend on them)”

ALTER TABLE demography
   ADD COLUMN age integer

/*The Substring gets us the first 2 numbers from the age range and then Random function calculates any Random number within the Range. Here we can use any number from 1 to 8 as that is the difference between the first Age range 21 - 29 */

UPDATE demography SET age = ROUND(CAST(SUBSTRING(agecat,1,2)as integer) +(RANDOM() * 7)) 

SELECT age,agecat FROM demography where age is not null

--Q2. Calculate patient's year of birth using admission date from the hospitalization_discharge and add to the demography table.	

ALTER TABLE demography
   ADD COLUMN yearofbirth integer

UPDATE demography SET yearofbirth =  CAST(EXTRACT(year from hd.admission_date)as integer) - demography.age FROM hospitalization_discharge hd WHERE hd.inpatient_number = demography.inpatient_number

SELECT hd.inpatient_number,d.age,d.yearofbirth,hd.admission_date FROM hospitalization_discharge hd,demography d WHERE hd.inpatient_number = d.inpatient_number

--Q3. Create a User defined function that returns the age in years of any patient as a calculation from year of birth	

CREATE OR REPLACE FUNCTION Patient_Age_in_Years(inpatient_num bigint) RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
Age_years INTEGER;
BEGIN
SELECT EXTRACT(YEAR FROM CURRENT_DATE) - yearofbirth into Age_years
from public.demography
where inpatient_number = inpatient_num;
RETURN Age_years;
END;
$$;

--Calling the Function:

select Patient_Age_in_Years(743087) /*Calling the Function by providing any patient id –to find their age in years*/

--Q4. What % of the dataset is male vs female?	

SELECT gender, CONCAT(ROUND(COUNT(*) * 100.00/ (SELECT COUNT(*) FROM demography),0),'%') as Gender_Perc
FROM demography WHERE gender is not null
GROUP BY gender 
	
--Q5. How many patients in this dataset are farmers?	

SELECT occupation,COUNT(inpatient_number) AS No_of_Patients FROM DEMOGRAPHY WHERE OCCUPATION = 'farmer' GROUP BY occupation
	
--Q6. Group the patients by age category and display it as a pie chart	

/*Comments- Created a pie chart using the graph visualiser, picture is attached in the word document.*/

SELECT COUNT(inpatient_number) AS No_of_Patients,agecat as Age_Category FROM DEMOGRAPHY WHERE agecat IS NOT NULL GROUP BY agecat ORDER BY agecat        	

--Q7. Divide BMI into slabs of 5 and show the count of patients within each one, without using case statements.	
/* Split the Patients as per BMI based on WHO standards*/

SELECT COUNT(inpatient_number) AS No_of_Patients, CONCAT('Less Than 18.5 - Under_Weight_Patients') AS BMI_Range,1 AS BMI_Slab FROM demography WHERE bmi <= 18.5
UNION
SELECT COUNT(inpatient_number) AS No_of_Patients, CONCAT('Between 18.5 and 24.9 - Healthy_Weight_Patients') AS BMI_Range, 2 AS BMI_Slab FROM demography WHERE bmi > 18.5 AND bmi <= 24.9
UNION
SELECT COUNT(inpatient_number) AS No_of_Patients, CONCAT('Between 25 and 29.9 - Over_Weight_Patients') AS BMI_Range, 3 AS BMI_Slab FROM demography WHERE bmi >= 25 AND bmi <= 29.9
UNION
SELECT COUNT(inpatient_number) AS No_of_Patients, CONCAT('Between 30 and 50 - Reaching_Obese') AS BMI_Range,4 AS BMI_Slab FROM demography WHERE bmi >= 30 AND bmi <= 50
UNION
SELECT COUNT(inpatient_number) AS No_of_Patients, CONCAT('Greater than 50 - Obese') AS BMI_Range, 5 AS BMI_Slab FROM demography WHERE bmi > 50
ORDER BY BMI_Slab

--Q8. What % of the dataset is over 70 years old		

SELECT COUNT(*) as CountAbove70Years,CONCAT(ROUND(COUNT(*) * 100.00/ (SELECT COUNT(*) FROM demography),0),'%') AS Perc_Above70years_old FROM demography WHERE age > 70

--Q9. What age group was least likely to be readmitted within 28 days	

SELECT min(d.agecat) as Age_Group_Least_Admitted_within_28Days FROM HOSPITALIZATION_DISCHARGE HD, DEMOGRAPHY D
WHERE HD.INPATIENT_NUMBER = D.INPATIENT_NUMBER and re_admission_within_28_days =0

--Q10. Create a procedure to insert a column with a serial number for all rows in demography.

/* Creating the procedure to alter the demography table to include sno column as Identity column which works more optimized and better than serial column */
CREATE PROCEDURE public."Insert_Serial_Column_Demography"()
LANGUAGE 'sql'
AS $BODY$
ALTER TABLE demography
ADD COLUMN sno integer NOT NULL GENERATED ALWAYS AS IDENTITY;
$BODY$;
ALTER PROCEDURE public."Insert_Serial_Column_Demography"()
OWNER TO postgres;

--PROCEDURE CALL: /* Calling the Stored Procedure */

CALL public."Insert_Serial_Column_Demography"()

/* Viewing the table to see if the column got added and generated serially.*/

SELECT * FROM demography

--Q11. what was the average time to readmission among men?	

SELECT ROUND(AVG(hd.readmission_time_days_from_admission)) AS AVG_TIMEINDAYS_READMISSION_MEN FROM hospitalization_discharge hd,demography d WHERE hd.inpatient_number = d.inpatient_number AND d.gender = 'Male' AND readmission_time_days_from_admission IS NOT NULL

/*Q"12. Display NYHA_cardiac_function_classification as Class I: No symptoms of heart failure
 Class II: Symptoms of heart failure with moderate exertion
 Class III: Symptoms of heart failure with minimal exertion  
and show the most common type of heart failure for each classification"	*/

/*Chosen case when classification as 1, 2 and 3 as required and displaying based on the max count of Heart Failures for each Classification.*/

SELECT nyha_cardiac_function_classification,type_of_heart_failure as Common_Type_Heart_Failure,count(type_of_heart_failure) as count_HeartFailures,
CASE
 WHEN nyha_cardiac_function_classification = 1 THEN 'Class I: No symptoms of heart failure'
 WHEN nyha_cardiac_function_classification = 2 THEN 'Class II: Symptoms of heart failure with moderate exertion'
 WHEN nyha_cardiac_function_classification = 3 THEN 'Class III: Symptoms of heart failure with minimal exertion'
ELSE 'No Class Specified'
END AS "NYHA_cardiac_function_classification"
FROM cardiaccomplications where nyha_cardiac_function_classification = 1 or nyha_cardiac_function_classification = 2 or nyha_cardiac_function_classification = 3
GROUP BY type_of_heart_failure,nyha_cardiac_function_classification ORDER BY count_HeartFailures desc limit 2

/*OUTPUT shows only 2 and 3 Cardiac Function Classification as 1 does not exist and have used LIMIT Function to not show 4 as per the question.*/

--Q13. Identify any columns relating to echocardiography and create a severity score for cardiac function. Add this column to the table

--1. ALTER TABLE STATEMENT TO ADD THE NEW COLUMN SEVERITY_SCORE

ALTER TABLE cardiaccomplications
ADD COLUMN severity_score INTEGER

/*2. UPDATE STATEMENT TO ADD THE VALUES TO THE NEWLY ADDED SEVERITY_SCORE COLUMN OF THE TABLE AND CASE STATEMENTS TO GET THE SEVERITY SCORE OF ALL THE COLUMNS RELATED TO ECHOCARDIOGRAPHY  */

/* Found 8 columns from the cardiaccomplications table related to the Echocardiography analysis. Took 8 columns related to Echocardiography analysis
Attached the Q13_Parameters_Value_SeverityScore excel sheet holding all the parameter values and Severity score calculation details.
*/

UPDATE cardiaccomplications SET severity_score =
CASE
WHEN myocardial_infarction = 0 Then 0
WHEN myocardial_infarction = 1 THEN 3
ELSE 0
END +
CASE
WHEN lvef BETWEEN 50 AND 70 Then 0
WHEN lvef BETWEEN 40 AND 49 THEN 1
WHEN lvef BETWEEN 30 AND 39 THEN 2
WHEN lvef < 30 THEN 3
ELSE 0
END +
CASE
WHEN left_ventricular_end_diastolic_diameter_LV < 37 Then 0
WHEN left_ventricular_end_diastolic_diameter_LV BETWEEN 37 AND 56 THEN 1
WHEN left_ventricular_end_diastolic_diameter_LV BETWEEN 57 AND 65 THEN 2
WHEN left_ventricular_end_diastolic_diameter_LV > 65 THEN 3
ELSE 0
END +
CASE
WHEN mitral_valve_EMS < 0.6 Then 0
WHEN mitral_valve_EMS BETWEEN 0.6 AND 0.9 THEN 1
WHEN mitral_valve_EMS BETWEEN 1.0 AND 1.5 THEN 2
WHEN mitral_valve_EMS > 1.5 THEN 3
ELSE 0
END +
CASE
WHEN mitral_valve_AMS >= 0.12 Then 0
WHEN mitral_valve_AMS BETWEEN 0.09 AND 0.12 THEN 1
WHEN mitral_valve_AMS BETWEEN 0.05 AND 0.09 THEN 2
WHEN mitral_valve_AMS < 0.05 THEN 3
ELSE 0
END +
CASE
WHEN EA > 0.8 Then 0
WHEN EA BETWEEN 0.8 AND 1.5 THEN 1
WHEN EA BETWEEN 0.4 AND 0.8 THEN 2
WHEN EA < 0.4 THEN 3
ELSE 0
END +
CASE
WHEN tricuspid_valve_return_velocity <= 2.8 Then 0
WHEN tricuspid_valve_return_velocity BETWEEN 2.9 AND 3.1 THEN 1
WHEN tricuspid_valve_return_velocity BETWEEN 3.2 AND 3.4 THEN 2
WHEN tricuspid_valve_return_velocity >= 3.5 THEN 3
ELSE 0
END +
CASE
WHEN tricuspid_valve_return_pressure <= 25 Then 0
WHEN tricuspid_valve_return_pressure BETWEEN 26 AND 50 THEN 1
WHEN tricuspid_valve_return_pressure BETWEEN 51 AND 70 THEN 2
WHEN tricuspid_valve_return_pressure > 70 THEN 3
ELSE 0
END

/*3. SELECT STATEMENT TO SEE THE NEWLY ADDED COLUMN WITH ALL THE SEVERITY VALUES:*/

SELECT inpatient_number, severity_score, myocardial_infarction, LVEF, left_ventricular_end_diastolic_diameter_LV, mitral_valve_EMS, mitral_valve_AMS, EA,tricuspid_valve_return_velocity, tricuspid_valve_return_pressure
FROM cardiaccomplications
	
--Q14. What is the average height of women in cms?

SELECT Round(AVG(height)*100) AS AVG_HT_Women_CMS FROM demography WHERE gender IN (SELECT gender FROM demography WHERE  gender = 'Female')

--Q15. Using the cardiac severity column from q13, find the correlation between hospital outcomes and cardiac severity	

SELECT
CORR(CASE WHEN hd.outcome_during_hospitalization = 'Dead' THEN 1
ELSE 0 END, cc.severity_score) AS Correlation_Dead_SevScore,
CORR(CASE WHEN hd.outcome_during_hospitalization = 'Alive' THEN 1
ELSE 0 END, cc.severity_score) AS Correlation_Alive_SevScore,
CORR(CASE WHEN hd.outcome_during_hospitalization = 'DischargeAgainstOrder' THEN 1
ELSE 0 END, cc.severity_score) AS Correlation_Discharge_SevScore
FROM
public.hospitalization_discharge hd
JOIN
public.cardiaccomplications cc
ON hd.inpatient_number = cc.inpatient_number

/*
Industry Standards Interpretation of Correlation Coefficient
 0 to 0.1: Very weak positive correlation.
 0.1 to 0.3: Weak positive correlation.
 0.3 to 0.5: Moderate positive correlation.
 0.5 to 0.7: Strong positive correlation.
 0.7 to 1: Very strong positive correlation.
 Negative values: Indicate a negative correlation, where as one variable increases, the other tends to decrease."

Correlation Analysis of Output:
Dead vs Severity Score: It is a very weak positive correlation for Dead Hospital Outcome vs Severity Score which means that the Severity scores does contribute for the Dead Hospital Outcome but its very weak.
Both Alive and Discharge Hospital Outcomes vs Severity Score: have Negative Correlations which means the Severity Scores does not contribute for these Outcomes. They have Negative Correlation.
*/

--Q16. Show the no. of patients for everyday in March 2017. Show the date in March along with the days between the previous recorded day in march and the current.

SELECT COUNT(inpatient_number) AS No_of_Patients,admission_date AS March_2017,
admission_date - (LAG(admission_date,1) OVER(ORDER BY admission_date)) PreviousRecordedDay FROM hospitalization_discharge 
WHERE admission_date BETWEEN '2017-03-01 00:00:00' AND '2017-04-01 00:00:00' GROUP BY admission_date ORDER BY admission_date

--Q17. Create a view that combines patient demographic details of your choice along with pre-exisiting heart conditions like MI,CHF and PVD

CREATE or REPLACE VIEW Patient_demographic_heartconditions AS
SELECT d.inpatient_number,d.gender,d.age,
   c.myocardial_infarction,
   c.congestive_heart_failure,
   c.peripheral_vascular_disease
FROM demography d  JOIN cardiaccomplications c
ON c.inpatient_number =d.inpatient_number
WHERE c.myocardial_infarction = 1 or
   c.congestive_heart_failure = 1 or
   c.peripheral_vascular_disease = 1;
   
/*SELECT QUERY:*/
select * from Patient_demographic_heartconditions


--Q18. Create a function to calculate total number of unique patients for every drug. Results must be returned as long as the first few characters match the user input.	
--1) Query to create Function:

CREATE OR REPLACE Function Unique_Patient_Count_by_drug (drug_prefix text)
RETURNS integer
as $$
Begin 
 Return(
select count (distinct inpatient_number) 
from patient_precriptions
where drug_name like drug_prefix || '%'  );
 end;
 $$ language plpgsql;

--2) Query to Call Function with first few characters of the Drug:
 
select Unique_Patient_Count_by_drug('Asp');

/*Q19. break up the drug names in patient_precriptions at the ""spaces"" and display only the second string without using Substring. Show unique drug names along with newly broken up string*/

SELECT distinct drug_name,split_part(drug_name,' ',2) AS second_string 
FROM patient_precriptions;

--Q20. Select the drug names starting with E and has x in any position after

SELECT DISTINCT drug_name FROM patient_precriptions
WHERE drug_name LIKE 'E%' AND drug_name LIKE '%x%';
		
/*Q21. Create a cross tab to show the count of readmissions within 28 days, 3 months,6 months as rows and admission ward as columns	expected result: https://drive.google.com/file/d/16bBRrSNTK7zPUPEwr7uc9fGd6bH77Exu/view?usp=drive_link*/

SELECT
    '180Days' AS admission_time,
    SUM(CASE WHEN admission_ward = 'Cardiology' AND re_admission_within_6_months = 1 THEN 1 else 0  END) AS Cardiology,
    SUM(CASE WHEN admission_ward = 'ICU' AND re_admission_within_6_months = 1 THEN 1 else 0 END) AS ICU,
    SUM(CASE WHEN admission_ward = 'GeneralWard' AND re_admission_within_6_months = 1 THEN 1 else 0 END) AS GeneralWard,
    SUM(CASE WHEN admission_ward = 'Others' AND re_admission_within_6_months = 1 THEN 1 else 0 END) AS Others
FROM hospitalization_discharge
UNION ALL
SELECT
    '28Days' AS admission_time,
    SUM(CASE WHEN admission_ward = 'Cardiology' AND re_admission_within_28_days = 1 THEN 1 else 0 END) AS Cardiology,
    SUM(CASE WHEN admission_ward = 'ICU' AND re_admission_within_28_days = 1 THEN 1 else 0 END) AS ICU,
    SUM(CASE WHEN admission_ward = 'GeneralWard' AND re_admission_within_28_days = 1 THEN 1 else 0 END) AS GeneralWard,
    SUM(CASE WHEN admission_ward = 'Others' AND re_admission_within_28_days = 1 THEN 1 else 0 END) AS Others
FROM hospitalization_discharge
UNION ALL
SELECT
    '90Days' AS admission_time,
    SUM(CASE WHEN admission_ward = 'Cardiology' AND re_admission_within_3_months = 1 THEN 1 else 0 END) AS Cardiology,
    SUM(CASE WHEN admission_ward = 'ICU' AND re_admission_within_3_months = 1 THEN 1 else 0 END) AS ICU,
    SUM(CASE WHEN admission_ward = 'GeneralWard' AND re_admission_within_3_months = 1 THEN 1 else 0 END) AS GeneralWard,
    SUM(CASE WHEN admission_ward = 'Others' AND re_admission_within_3_months = 1 THEN 1 else 0 END) AS Others
FROM hospitalization_discharge
UNION ALL
SELECT
    'DWithin6months' AS admission_time,
    SUM(CASE WHEN admission_ward = 'Cardiology' AND death_within_6_months = 1 THEN 1 else 0 END) AS Cardiology,
    SUM(CASE WHEN admission_ward = 'ICU' AND death_within_6_months = 1 THEN 1 else 0 END) AS ICU,
    SUM(CASE WHEN admission_ward = 'GeneralWard' AND death_within_6_months = 1 THEN 1 else 0 END) AS GeneralWard,
    SUM(CASE WHEN admission_ward = 'Others' AND death_within_6_months = 1 THEN 1 else 0 END) AS Others
FROM hospitalization_discharge;

--Q22. Create a trigger to stop patient records from being deleted from the demography table	

 CREATE OR REPLACE FUNCTION Stop_Deleting_Demography()
 Returns 
 Trigger as $$
 Begin
    Raise Exception 'Delete records from demography is not allowed';
 End;
 $$
 Language plpgsql;
Create or Replace Trigger Stop_Demography_Delete
 Before Delete on demography
 For Each row
 Execute Function Stop_Deleting_Demography();

--DELETE QUERY:

DELETE FROM demography

--Q23. What is the total number of days between the earliest admission and the latest	

SELECT (max(admission_date)- min(admission_date)) as total_days
 FROM hospitalization_discharge;

--Q24. Divide discharge day by visit times for any 10 patients without using mathematical operators like '/'

 select inpatient_number,dischargeday,visit_times,
 (select count(*)-1
 from generate_series(0,dischargeday,visit_times)) as quotient
 from hospitalization_discharge
 limit 10;

--Q25. Show the count of patients by first letter of admission_way.

SELECT left(admission_way,1) as First_letter,
count(distinct inpatient_number) as patient_count
FROM hospitalization_discharge
group by left(admission_way,1);
	
/*Q26. Display an array of personal markers:gender, BMI, pulse, MAP for every patient. The result should look like this	https://drive.google.com/file/d/1GtFGgoyROL--xrVqV49V9oyUfMSWm8tt/view?usp=drive_link*/	

Select d.inpatient_number,
Array[d.gender:: Text,
      Round(d.bmi::Numeric,2):: Text,
	  Round(l.pulse ::Numeric,2):: Text,
	  Round(l.map_value ::Numeric,0):: Text
	  ] as Personal_markers
from labs l join demography d on l.inpatient_number = d.inpatient_number;

--Q27. Display medications With LastName contains 'hydro' and display it as 'H20'.	

select distinct drug_name,
(case when drug_name like '%hydro%' then 'H2O' else drug_name end) as New_drug_name
from patient_precriptions
where drug_name like '%hydro%';

--Q28. Create a trigger to raise notice and prevent deletion of the view created in question 17	

Create or Replace Function Prevent_view_deletion()
Returns Event_Trigger as $$
begin
  Raise Notice 'Deletion of view Patient_demographic_heartconditions is not allowed';
end;
$$
language plpgsql;
Create Event Trigger Prevent_View_Delete
on sql_drop
When TAG in ('DROP VIEW')
Execute Function Prevent_view_deletion();

--QUERY TO DROP VIEW: 
Drop view Patient_demographic_heartconditions;

--Q29. How many unique patients have cancer?	

select count(distinct inpatient_number)  from patienthistory
where leukemia = 1 or malignant_lymphoma = 1;

/* solid_tumor field is not considered because it may or may not be cancerous*/


--Q30. Show the moving average of number of patient admitted every 3 months.

Select 
Date_Trunc('month',admission_date) as Month,
count(inpatient_number) as No_of_admissions,
round(avg(count(inpatient_number)) over (order by Date_Trunc('month',admission_date) 
Rows between 2 preceding and current row ),2) as Moving_avg_3months
from hospitalization_discharge
group by Date_Trunc('month',admission_date)
order by Month;
	
--Q31. Write a query to get a list of patient IDs' who recieved oxygen therapy and had a high respiration rate in February 2017

select l.inpatient_number from labs l join hospitalization_discharge h 
on l.inpatient_number = h.inpatient_number 
where h.oxygen_inhalation = 'OxygenTherapy' and 
l.respiration > 20  and 
h.admission_date::date >= '2017-02-01' and 
h.admission_date::date < '2017-03-01';
	
--Q32. Display patients with heart failure type: "both" along with highest MAP and highest pulse without using limit	

select * from cardiaccomplications;
select l.inpatient_number,c.type_of_heart_failure,
  round(cast(max(l.map_value) as decimal(5,2)),2) as high_map,
  max(l.pulse) as high_pulse
from labs l join cardiaccomplications c on l.inpatient_number = c.inpatient_number
where type_of_heart_failure = 'Both'
group by l.inpatient_number,2
fetch first 10 rows only;

--Q33. Create a stored procedure that displas any message on the screen without using any tables/views.	

create procedure message()   /* creating procedure named message()*/
language plpgsql 
as $$ 
begin
	raise notice 'This is a random message';  /*printing message*/
end;
$$;

call message();  /* calling stored procedure named message*/
	
--Q34. In healthy people, monocytes make up about 1%-9% of total white blood cells. Calculate avg monocyte percentages among each age group.	

with age_grouped as (
    select 
        case
            when d.age between 0 AND 10 then '0-10'
            when d.age between 11 AND 20 then '11-20'
            when d.age between 21 AND 30 then '21-30'
            when d.age between 31 AND 40 then '31-40'
            when d.age between 41 AND 50 then '41-50'
            when d.age between 51 AND 60 then '51-60'
            when d.age between 61 AND 70 then '61-70'
            when d.age between 71 AND 80 then '71-80'
            else '81+'
        end as age_group,
        l.monocyte_ratio
    from labs l
    join demography d on l.inpatient_number = d.inpatient_number
)
select age_group,avg(monocyte_ratio)*100 as avg_monocyte_percentage
from age_grouped group by age_group;

/*Q"35. Create a table that stores any Patient Demographics of your choice as the parent table. Create a child table that contains systolic_blood_pressure,diastolic_blood_pressure per patient and inherits all columns from the parent table"	*/

create table parent_table (
    inpatient_number SERIAL PRIMARY KEY,
    gender CHAR(1),
    bmi DECIMAL(5, 2),
    occupation VARCHAR(50),
    age INT,
    year_of_birth INT
);
CREATE TABLE child_table (
    systolic_blood_pressure INT,
    diastolic_blood_pressure INT
) INHERITS (parent_table);

--INSERT QUERY:

INSERT INTO child_table (
    inpatient_number, gender, bmi, occupation, age, year_of_birth,
    systolic_blood_pressure, diastolic_blood_pressure
) VALUES (
    2011, 'F', 22.9, 'Doctor', 38, 1986,
    120, 67
);

--SELECT QUERY:

select * from child_table;


--Q36. Write a select statement with no table or view attached to it	

SELECT 'Mandy' as name, 38 as age, 'Formula-1 Racer' as Occupation;

--Q37. Create a re-usable function to calculate the percentage of patients for any group. Use this function to calculate % of patients in each admission ward.	

create function group_percentage(
    group_value text
)
returns decimal as $$
declare
    total_no_patients int;
    group_count int;
    percentage decimal;
begin
    select count(*) into total_no_patients from hospitalization_discharge;-- Calculating total number of patients
    -- Calculating number of patients in the each group
    select count(*) into group_count from hospitalization_discharge where admission_ward = group_value;
    -- Calculating percentage if the count of patients is not 0
    if total_no_patients > 0 then
        percentage := round((group_count * 100.0) / total_no_patients,2);
    else
        percentage := 0;
    end if;
    return percentage;
end;
$$ language plpgsql;

--SELECT QUERY:

select admission_ward,group_percentage(admission_ward) as percentage
from hospitalization_discharge group by admission_ward;

--Q38. Write a query that shows if CCI score is an even or odd number for any 10 patients	

select inpatient_number,cci_score,
	case 
		when (cast(cci_score as integer)%2)=0 then 'Even' -- changing the datatype and checking whether the number is even or not.
		when cci_score is null then 'Null'  -- if the cci_score is null it should display null
		else 'Odd'
	end as even_odd
from patienthistory order by random() limit 10; -- using random() for generating any 10 records from dataset.
	
--Q39. Using windows functions show the number of hospitalizations in the previous month and the next month	

select
    extract(month from admission_date) as month_start,  
    count(inpatient_number) as current_month_hospitalizations,
    coalesce(
        lag(count(*)) over (order by extract(month from admission_date)),0) as previous_month_hospitalizations,
    coalesce(
        lead(count(*)) over (order by extract(month from admission_date)),0) as next_month_hospitalizations
from
    hospitalization_discharge
group by  extract (month from admission_date) order by month_start;

--Q40. Write a function to get comma-separated values of patient details based on patient number entered by the user. (Use a maximum of 6 columns from different tables)	
create function patient_details(patient_number text)
returns TEXT as $$
declare
    result TEXT;
begin
    select into result  -- using concat() for displaying the comma-separated values of patient details
        CONCAT(
            d.inpatient_number::TEXT, ', ',
            COALESCE(d.age::TEXT, 'N/A'), ', ', --coalesce is used for handling null values
            COALESCE(l.white_blood_cell::TEXT, 'N/A'), ', ',
            COALESCE(cc.killip_grade::TEXT, 'N/A'), ', ',
            COALESCE(r.consciousness, 'N/A'), ', ',
            COALESCE(ph.diabetes::TEXT, 'N/A')
        )
    from
        demography d
    join labs l on d.inpatient_number = l.inpatient_number
	join responsivenes r on d.inpatient_number = r.inpatient_number
	join cardiaccomplications cc on d.inpatient_number = cc.inpatient_number
	join patienthistory ph on d.inpatient_number = ph.inpatient_number
    where 
        d.inpatient_number = patient_number::bigint;
    return result;
end;
$$ language plpgsql;

--FUNCTION CALL WITH PATIENT ID:

select patient_details('760822');

--Q41. Which patients were on more than 15 prescribed drugs? What was their age and outcome? show the results without using a subquery		

/* Taken patients with more than 15 prescribed drugs*/

select
    prescriptions.inpatient_number, 
    demography.age, 
    hospitaldiacharge.outcome_during_hospitalization,
    count(prescriptions.drug_name) as drug_count
from 
    patient_precriptions prescriptions
join 
    demography demography on prescriptions.inpatient_number = demography.inpatient_number
join 
    hospitalization_discharge hospitaldiacharge on prescriptions.inpatient_number = hospitaldiacharge.inpatient_number
group by 
    prescriptions.inpatient_number, demography.age, hospitaldiacharge.outcome_during_hospitalization
having 
    count(prescriptions.drug_name) > 15;

/*Q42. Write a PLSQL block to return the patient ID and gender from demography for a patient if the ID exists and raise an exception if the patient id is not found. Do this without writing or storing a function. Patient ID can be hard-coded for the block*/	

DO
$$
DECLARE
    v_patient_id INTEGER := 0101010;  -- Hard-coded patient ID
    v_gender TEXT;  -- Gender declared as TEXT
BEGIN
    -- Attempt to retrieve the gender of the patient with the given ID
    SELECT gender INTO v_gender FROM demography
    WHERE inpatient_number = v_patient_id;
	IF v_gender IS NULL THEN -- Check if gender is NULL, indicating the patient ID was not found
        RAISE EXCEPTION 'Error: Patient with ID % not found.', v_patient_id;
    ELSE
        -- Output the patient ID and gender if found
        RAISE NOTICE 'Patient ID: %', v_patient_id;
        RAISE NOTICE 'Gender: %', v_gender;
    END IF;
END;
$$;

--Q43. Display any 10 random patients along with their type of heart failure	

select inpatient_number,type_of_heart_failure from cardiaccomplications order by random() limit 10;

--Q44. How many unique drug names have a length >20 letters?	

select count(distinct drug_name) as count_unique_drugname from patient_precriptions where length(drug_name)>20;

--Q45. Rank patients using CCI Score as your base. Use a windows function to rank them in descending order. With the highest no. of comorbidities ranked 1.		

WITH comorbidity_count AS (
    SELECT 
        inpatient_number,
        cci_score,
        -- Calculate the number of comorbidities once in the CTE
        (COALESCE(cerebrovascular_disease, 0) +
         COALESCE(dementia, 0) +
         COALESCE(chronic_obstructive_pulmonary_disease, 0) +
         COALESCE(connective_tissue_disease, 0) +
         COALESCE(peptic_ulcer_disease, 0) +
         COALESCE(diabetes, 0) +
         COALESCE(moderate_to_severe_chronic_kidney_disease, 0) +
         COALESCE(hemiplegia, 0) +
         COALESCE(leukemia, 0) +
         COALESCE(malignant_lymphoma, 0) +
         COALESCE(solid_tumor, 0) +
         COALESCE(liver_disease, 0) +
         COALESCE(aids, 0)
        ) AS num_comorbidities
    FROM 
        patienthistory
)
SELECT 
    inpatient_number,
    cci_score,
    num_comorbidities,
   
    RANK() OVER (ORDER BY cci_score DESC, num_comorbidities DESC) AS rank -- Rank by CCI score and num_comorbidities
FROM comorbidity_count where cci_score is not null;

--Q46. What ratio of patients who are responsive to sound vs pain?	

select 
    (sum(case when consciousness='ResponsiveToSound' then 1 else 0 end) /
    nullif(sum(case when consciousness='ResponsiveToPain' then 1 else 0 end), 0)) as sound_pain_ratio
from
    responsivenes;

--Q47. Use a windows function to return all admission ways along with occupation which is related to the highest MAP value		

/* Used windows Rank() to show the list of all admission ways, occupation and their highest map values.*/	

with admission_rank as
(select
hd.admission_way,
d.occupation,
l.map_value,
rank()over(partition by hd.admission_way order by l.map_value desc) as rank_map from hospitalization_discharge hd
join demography d on hd.inpatient_number = d.inpatient_number
join labs l on hd.inpatient_number= l.inpatient_number
order by 1,2,3 )
select distinct admission_way,occupation, map_value
from admission_rank
where rank_map =1

--Q48. Display the patients with the highest BMI.		

select inpatient_number, bmi from demography where bmi=(SELECT MAX(BMI) FROM DEMOGRAPHY)
/* Displaying patients with highest bmi */

--Q49. Find the list of Patients who has leukopenia.

select inpatient_number,white_blood_cell as Leukopenia_Patient
from
(
select inpatient_number,white_blood_cell,
case when white_blood_cell<3.0E9 then 'leukopenia'
else 'N/A' end as leukopenia_patient from labs
)
where leukopenia_patient='leukopenia' order by 2 desc;

/*Leukopenia refers to Less than 4,500 cells per microliter (4.5 × 109/L) */

--Q50. What is the most frequent weekday of admission?	

SELECT case when EXTRACT(DOW FROM admission_date)=1 then 'Monday' 
when EXTRACT(DOW FROM admission_date)=2 then 'Tuesday'
when EXTRACT(DOW FROM admission_date)=3 then 'Wednesday'
when EXTRACT(DOW FROM admission_date)=4 then 'Thursday'
when EXTRACT(DOW FROM admission_date)=5 then 'Friday'
when EXTRACT(DOW FROM admission_date)=6 then 'Saturday'
when EXTRACT(DOW FROM admission_date)=0 then 'Sunday'
end
as weekday,count(*) as count 
from hospitalization_discharge
group by weekday
order by count desc
limit 1;

--Q51. Create a console bar chart using the '▰' symbol for count of patients in any age category where theres more than 100 patients"	

select agecat ,count(*) as patient_count,RPAD('',(COUNT(inpatient_number)/40)::int, '▰') as Patient_Count_Bar
from demography
group by agecat
having count(*) >100 order by 2;

--Q52. Find the variance of the patients' D_dimer value and display it along with the correlation to CCI score and display them together.

/* Used Var_pop() and covar_pop() so that the variance and correlation are calculated and does not return NULL values.*/

with vari as
(
select a.inpatient_number,(var_pop(a.d_dimer)) as variance_d_Dimer,a.d_dimer
,b.cci_score 
from labs a
join patienthistory b
on a.inpatient_number=b.inpatient_number
where a.d_dimer is not null
group by a.inpatient_number,a.d_dimer
,b.cci_score
),
cohr as
(
select 
covar_pop((a.variance_d_Dimer),b.cci_score) as d_dimer_cci_correlation
from
vari a
join
patienthistory b
on a.inpatient_number=b.inpatient_number
)
select cohr.*,vari.variance_d_Dimer
from
cohr,vari
order by 1 desc

/*ANALYSIS OF OUTPUT:
As the correlation between cci and Variance of d_dimer returns 0, its a very weak positive correlation between them.*/
		
--Q53. Which adm ward had the lowest rate of Outcome Death?	

select admission_ward,count(*) as low_rate_death from hospitalization_discharge
where
outcome_during_hospitalization = 'Dead'
group by admission_ward
order by 2 asc limit 3
/*All the 3 wards are having same lowest rate of outcome Death*/

--Q54. What % of those in a coma also have diabetes. Use the GCS scale to evaluate.	

with tot as
(
select count(distinct inpatient_number) as total_cnt from patienthistory 
),
comat as /*this sql will give patient number who are having coma and also diabetes*/
(select count(inpatient_number) as coma_cnt from responsivenes where gcs<=8)
,
dbt as
(
select count(inpatient_number) as coma_diabetes_cnt from patienthistory where inpatient_number in
(
select inpatient_number from responsivenes where gcs<=8
)
and diabetes=1
)
select total_cnt,coma_diabetes_cnt,round((coma_diabetes_cnt::decimal*100/total_cnt*100::decimal),2) as Percentage_Coma_Dbt
from
tot,comat,dbt

--Q55. Display the drugs prescribed by the youngest patient

select inpatient_number,drug_name from patient_precriptions where inpatient_number = (select inpatient_number from demography order by agecat asc limit 1)

--Q56. Create a view on the public.responsivenes table using the check constraint

create view view_responsiveness  as 
select *
from responsivenes
with local check option;

--SELECT QUERY:

select * from view_responsiveness

--Q57. Determine if a word is a palindrome and display true or false. Create a temporary table and store any words of your choice for this question	

create temporary table words_temp(word text);

--QUERY FOR INSERT STATEMENT:

insert into  words_temp(word)
values('mom'),('dad'),('brother'),('noon'),('sister'),('girl');

--QUERY TO CHECK FOR PALINDROME:

select word,word=reverse(word) as palindrome_w
from words_temp;

--Q58. How many visits were common among those with a readmission in 6 months	

/*Limited to only most common visits*/

select visit_times, count(inpatient_number) as patient_count
from hospitalization_discharge
where re_admission_within_6_months = 1
group by visit_times
order by visit_times
limit 1


--Q59. What is the size of the database Cardiac_Failure

select pg_database_size('Cardiac_Failure')/1024 as Cardiac_Failure_DB_KB;	

--Q60. Find the greatest common denominator and the lowest common multiple of the numbers 365 and 300. show it in one query

select gcd(365,300) as great_common_d,
(365*300)/gcd(365,300) as least_common_m;
		
/*Q61. Group patients by destination of discharge and show what % of all patients in each group was re-admitted within 28 days.Partition these groups as 2: high rate of readmission, low rate of re-admission. Use windows functions	*/

WITH re_admit_pt AS (
    SELECT 
        destinationdischarge,
        count(distinct inpatient_number) AS total_patients
        FROM 
       hospitalization_discharge
    GROUP BY 
        destinationdischarge

)
,readmit_rates AS (
    SELECT distinct
        hospitalization_discharge.destinationdischarge,
        total_patients,
    case when re_admission_within_28_days=1 then count(inpatient_number) over(partition by hospitalization_discharge.destinationdischarge) 
	end as readmitted_patients
	--count(inpatient_number) as pt_cnt,destinationdischarge 
from hospitalization_discharge
join
re_admit_pt
on lower(hospitalization_discharge.destinationdischarge)=lower(re_admit_pt.destinationdischarge)
where re_admission_within_28_days=1 
)
SELECT 
    destinationdischarge,
    total_patients,
    readmitted_patients,
	round((readmitted_patients::numeric/total_patients)*100,2) as Percentage_Patients_Readmitted,
       CASE 
        WHEN (readmitted_patients::numeric/total_patients)*100>7 THEN 'high rate of readmission'
        ELSE 'low rate of readmission'
    END AS readmission_criteria
FROM 
    readmit_rates;

--Q62. What is the size of the table labs in KB without the indexes or additional objects	

select pg_relation_size('labs')/1024 as lab_size_kb;

--Q63. concatenate age, gender and patient ID with a ';' in between without using the || operator

select concat(coalesce(age,'0'),' ; ',coalesce(gender,'NA'),' ; ',inpatient_number) concat_demography from demography order by 1 desc;

/*To handle null values,coalesce used*/

--Q64. Display a reverse of any 5 drug names

select drug_name, reverse(drug_name) as drug_name_rev from patient_precriptions
limit 5;

--Q65. What is the variance from mean for all patients GCS score

    SELECT var_samp(GCS)/AVG(GCS) AS variance_from_mean FROM responsivenes 
  
--CONSIDERING NULL VALUES ALSO—

--Q66. Using a while loop and a raise notice command, print the 7 times table as the result	

DO $$
DECLARE  
         END_POINT  INT:=10;
		  TIMES  INT:=1;
		  SEVEN_TIMES   INT:=1;
BEGIN
	WHILE(TIMES<=END_POINT)LOOP
	SEVEN_TIMES=7*TIMES;
	RAISE NOTICE '7 * % = %', TIMES,SEVEN_TIMES;
	TIMES=TIMES+1;
END LOOP;
END;
$$

--Q67. show month number and month name next to each other(admission_date), ensure that month number is always 2 digits. eg, 5 should be 05"	

SELECT admission_date,LPAD(EXTRACT(MONTH FROM cast(admission_date as date)):: TEXT,2,'0') AS MONTH_ONLY ,
 TO_CHAR(admission_date, 'FMMonth') AS MONTH_NAME
FROM hospitalization_discharge

--Q68. How many patients with both heart failures had kidney disease or cancer.

/* solid_tumor field is not considered for calculation because it may or may not be cancerous*/

SELECT count(patienthistory.inpatient_number) as Total_Patient_Count,sum(patienthistory.moderate_to_severe_chronic_kidney_disease) as Kidney_Dis_Patients,
sum(patienthistory.leukemia + patienthistory.malignant_lymphoma) as Cancer_Patients,
cardiaccomplications.type_of_heart_failure from patienthistory
JOIN cardiaccomplications on patienthistory.inpatient_number=cardiaccomplications.inpatient_number
WHERE 
    cardiaccomplications.type_of_heart_failure = 'Both'
    AND (patienthistory.malignant_lymphoma = 1 OR patienthistory.moderate_to_severe_chronic_kidney_disease = 1 OR 
	patienthistory.leukemia=1)
	group by cardiaccomplications.type_of_heart_failure

--Q69. Return the number of bits and the number of characters for every value in the column: Occupation	

SELECT distinct Occupation,LENGTH(Occupation),(LENGTH(Occupation)*8) as bits FROM demography where occupation is not null;

--Q70. Create a stored procedure that adds a column to table cardiaccomplications. The column should just be the todays date

CREATE OR REPLACE PROCEDURE ADD_column()
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        ALTER TABLE cardiaccomplications
        ADD COLUMN today_date DATE;
   
    END;
	
	UPDATE cardiaccomplications
    SET today_date = CURRENT_DATE;
END;
$$;

--QUERY TO CALL THE PROCEDURE:

CALL ADD_column();

--SELECT QUERY:

select * from cardiaccomplications;

--Q71. What is the 2nd highest BMI of the patients with 5 highest myoglobin values. Use windows functions in solution	

select demography.inpatient_number,labs.myoglobin,
max(demography.bmi) over(partition by labs.myoglobin order by labs.myoglobin desc) as Second_highestBMI from demography
join labs
on demography.inpatient_number=labs.inpatient_number
where labs.myoglobin is not null
limit 5 offset 1;

--Q72. What is the standard deviation from mean for all patients pulse

SELECT STDDEV_SAMP(pulse)/AVG(pulse) as CV_Pulse FROM LABS

/*The coefficient of variation (CV) is a commonly used metric - it denotes the dispersion of the data relative to the mean. It is measured as the ratio of the standard deviation to the mean */


--Q73. Create a procedure to drop the age column from demography	
	
--DROPPING AGE COLUMN:

CREATE OR REPLACE PROCEDURE drop_column()
LANGUAGE plpgsql
AS $$
BEGIN
        ALTER TABLE demography
        drop column age;
       END;
	$$;

--QUERY TO CALL PROCEDURE:

CALL drop_column();

--SELECT QUERY:

select * from demography;

--Q74. What was the average CCI score for those with a BMI>30 vs for those <30

SELECT 
avg(patienthistory.cci_score) as avg_cci_score,
case
when demography.bmi < 30  then 'less_than_30'
WHEN demography.bmi > 30 THEN 'more than 30'
ELSE 'no bmi'
END AS bmi_range
FROM patienthistory
join 
demography 
on patienthistory.inpatient_number=demography.inpatient_number
group by bmi_range

--Q75. Write a trigger after insert on the Patient Demography table. if the BMI >40, warn for high risk of heart risks

CREATE FUNCTION HIGH_HEART_RISK()
RETURNS Trigger AS $$
BEGIN 
IF new.BMI >40 THEN 
 RAISE NOTICE 'This patient have high risk of heart risks';
end if ;
end;
$$ language plpgsql;

create Trigger High_BMI
after insert on Demography
for each row
EXECUTE FUNCTION HIGH_HEART_RISK();

--QUERY TO INSERT

INSERT INTO demography (inpatient_number, gender, agecat, bmi)
VALUES (15, 'male', 30-40, 46);

--Q76. Most obese patients belong to which age group and gender. You may make an assumption for what qualifies as obese based on your research	

select inpatient_number,bmi,agecat,gender from demography
order by bmi desc limit 2

--Q77. Show all response details of a patient in a JSON array	

CREATE or replace FUNCTION PATIENT(ID integer)
RETURNS JSON AS 
$$
DECLARE 
   PATIENT_Response responsivenes%ROWTYPE;
BEGIN
  
   SELECT inpatient_number, eye_opening,verbal_response,movement,consciousness,gcs
   INTO PATIENT_Response
   FROM responsivenes
   WHERE inpatient_number = ID;

    RETURN json_build_object
	(
      'inpatient_number', PATIENT_Response.inpatient_number,
      'eye_opening', PATIENT_Response.eye_opening,
      'verbal_response',PATIENT_Response.verbal_response,
      'movement', PATIENT_Response.movement,
      'conciousness', PATIENT_Response.consciousness,
      'gcs', PATIENT_Response.gcs
     
   );
END;
$$ LANGUAGE plpgsql;
select PATIENT(8);

--Q78. Update the table public.patienthistory. Set type_ii_respiratory_failure to be upper case,query the results of the updated table without writing a second query

UPDATE public.patienthistory
SET type_ii_respiratory_failure=UPPER(type_ii_respiratory_failure)
RETURNING *;
	
--Q79. Find all patients using Digoxin or Furosemide using regex

SELECT* FROM patient_precriptions
WHERE drug_name ~* '(Digoxin|Furosemide)'
		
--Q80. Using a recursive query, show any 10 patients linked to the drug: "Furosemide injection"

WITH RECURSIVE drug_use AS (
    SELECT * 
    FROM  patient_precriptions
    WHERE drug_name = 'Furosemide injection'
    UNION ALL
    SELECT pr.*
    FROM drug_use d
    JOIN patient_precriptions pr ON d.inpatient_number = pr.inpatient_number
)
SELECT * 
FROM drug_use
limit 10;