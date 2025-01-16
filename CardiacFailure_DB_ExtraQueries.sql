/* Cardiac Failure DB Additional Solutions */

--Q1)	Create Stacked Line chart for number of Patients based on BMI Range.
  
/*Comments- Created a Stacked Line chart using the graph visualiser, picture is attached in the word document.*/

--Q2)	Display number of patients by gender and age category. Display using a Bar Chart.

SELECT 
    concat(agecat||' years') as Age_Category,
    sum (CASE WHEN d1.gender = 'Male' THEN 1 ELSE 0 END) AS Male_Patients,
    sum( CASE WHEN d1.gender = 'Female' THEN 1 ELSE 0 END) AS Female_Patients
FROM
    demography d1 where agecat is not null
GROUP BY
    agecat order by 1

/*Comments- Created a Bar chart using the graph visualiser, picture is attached in the word document.*/

--Q3. How do age categories and the presence of chronic conditions (diabetes, cerebrovascular disease, chronic obstructive pulmonary disease) affect the average length of hospital stay?

SELECT d.agecat, 
       ph.diabetes, 
       ph.cerebrovascular_disease, 
       ph.chronic_obstructive_pulmonary_disease,
       round(AVG(h.dischargeday)) AS avg_length_of_stay
FROM hospitalization_discharge h
JOIN patienthistory ph ON h.inpatient_number = ph.inpatient_number
JOIN demography d ON h.inpatient_number = d.inpatient_number
WHERE ph.diabetes = 1 OR 
      ph.cerebrovascular_disease = 1 OR 
      ph.chronic_obstructive_pulmonary_disease = 1
GROUP BY d.agecat, ph.diabetes, ph.cerebrovascular_disease, ph.chronic_obstructive_pulmonary_disease
ORDER BY avg_length_of_stay DESC;

--Q4. Calculate bmi and compare it to the table column bmi to show if they are same or different.

select inpatient_number,weight,height,ROUND((weight / POWER(height, 2))::int,2) as calc_bmi,ROUND(bmi::int,2) as table_bmi,
ROUND((weight / POWER(height, 2))::int,2) = ROUND(bmi::int,2) as Same_orDifferent
from demography where weight is not null

--Q5-How does the distribution of patients vary across different Killip grades, and what insights can be drawn from the severity of their conditions? Show it in a pie chart.

/*Comments- Created a Pie chart using the graph visualiser, picture is attached in the word document.*/

alter table cardiaccomplications
add column  killip_grade_Category varchar;

/*Update Script*/

UPDATE cardiaccomplications
SET killip_grade_Category=
 case
   when killip_grade=1 then '1: no clinical signs of heart failure.'
   when killip_grade=2 then '2: elevated jugular venous pressure'
   when killip_grade=3 then '3: acute pulmonary edema.'
   when killip_grade=4 then '4: cardiogenic shock or hypotension'
   else 'unknown'
 end;
 select count(*),killip_grade,killip_grade_Category from cardiaccomplications
group by killip_grade,killip_grade_Category 
order by killip_grade

--Q6. What is the size of the all the public tables in KB including indexes or additional objects

select pg_total_relation_size('cardiaccomplications')/1024 as cardiaccomplications_kb,
pg_total_relation_size('demography')/1024 as demography_kb,
pg_total_relation_size('hospitalization_discharge')/1024 as hospitalization_discharge_kb,
pg_total_relation_size('labs')/1024 as labs_kb,
pg_total_relation_size('patient_precriptions')/1024 as patient_prescriptions_kb,
pg_total_relation_size('patienthistory')/1024 as patienthistory_kb,
pg_total_relation_size('responsivenes')/1024 as responsivenes_kb

--Q7) Write a query to make the patientid length = 12

select inpatient_number,lpad(inpatient_number::text, 12, '0') AS new_inpatient_number from demography;

--Q8) Write an Sql query to fetch only odd rows/even rows from the demography table

 select * from demography where mod(sno,2) <> 0 --Odd Rows
 
 select * from demography where mod(sno,2) = 0 --Even Rows

--Q9) What is the mean,median,standard deviation,skewness for all patients GCS score

WITH mean_median_sd AS
(
 SELECT 
  AVG(GCS) AS mean_GCS,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY GCS) AS median_GCS,
  STDDEV(GCS) AS stddev_GCS
   FROM RESPONSIVENES
)
SELECT MEAN_GCS,MEDIAN_GCS,STDDEV_GCS,
 ROUND(3 * (mean_GCS - median_GCS)::NUMERIC / stddev_GCS, 2) AS skewness_GCS
  FROM mean_median_sd;

/*10) Q24 from Main Questions
. Divide discharge day by visit times for any 10 patients without using mathematical operators like '/' */

-- Providing alternate answer: Using the DIV() in the result set as we used generate series formula in our Main answer.

select inpatient_number,dischargeday,visit_times,Div(dischargeday,visit_times) from hospitalization_discharge limit 10


