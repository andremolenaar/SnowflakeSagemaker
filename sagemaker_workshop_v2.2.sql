/*----------------------------------------------------------------------------
Snowflake and Sagemaker Dev Days Virtual Workshop V1.4
Configure Snowflake environment and load data into Snowflake from S3

Execute each section at a time following the steps

  Author:   Andries Engelbrecht
  Updated:  Original

  Update: October 28, 2019
  Add Internal stage, table for Sagemaker Churn Results
  Add analytic query to join results back to customer churn table

  Update: November19, 2019
  Update S3 bucket for customer source data
  Add cleanup

  Update: April15, 2020
  Fix reset CLeanup & Reset section to prevent errors
  Fix comments on External stages
  Change S3 bucket for Dev Days

----------------------------------------------------------------------------*/


USE ROLE ACCOUNTADMIN;

/* ---------------------------------------------------------------------------
First we configure the required Warehouse, Role, User & Database
for the workshop
----------------------------------------------------------------------------*/

--Create Warehouse for MLAI work
CREATE OR REPLACE WAREHOUSE SAGEMAKER_WH
  WITH WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 120
  AUTO_RESUME = true;

--Create ROLE and USER for Sagemaker to access Snowflake
CREATE OR REPLACE ROLE SAGEMAKER_ROLE COMMENT='SageMaker Role';
GRANT ALL ON WAREHOUSE SAGEMAKER_WH TO ROLE SAGEMAKER_ROLE;

GRANT ROLE SAGEMAKER_ROLE TO ROLE SYSADMIN;
GRANT ROLE SAGEMAKER_ROLE TO ROLE ACCOUNTADMIN;


CREATE OR REPLACE USER SAGEMAKER PASSWORD='AWSSF123'
    DEFAULT_ROLE=SAGEMAKER_ROLE
    DEFAULT_WAREHOUSE=SAGEMAKER_WH
    DEFAULT_NAMESPACE=ML_WORKSHOP.PUBLIC
    COMMENT='SageMaker User';
GRANT ROLE SAGEMAKER_ROLE TO USER SAGEMAKER;
GRANT ROLE SAGEMAKER_ROLE TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

--Create Databasse and Schema
--Grant access to Sagemaker Role

CREATE DATABASE IF NOT EXISTS ML_WORKSHOP;
GRANT USAGE ON DATABASE ML_WORKSHOP TO ROLE SAGEMAKER_ROLE;
GRANT ALL ON SCHEMA ML_WORKSHOP.PUBLIC TO ROLE SAGEMAKER_ROLE;


--Create Table to load Customer Churn data from S3
USE ML_WORKSHOP.PUBLIC;
USE WAREHOUSE SAGEMAKER_WH;

CREATE OR REPLACE TABLE CUSTOMER_CHURN (
	Cust_ID INT,
    State varchar(10),
	Account_Length INT,
	Area_Code INT,
	Phone varchar(10),
	Intl_Plan varchar(10),
	VMail_Plan varchar(10),
	VMail_Message INT,
	Day_Mins FLOAT,
	Day_Calls INT,
	Day_Charge  FLOAT,
	Eve_Mins FLOAT,
	Eve_Calls INT,
	Eve_Charge FLOAT,
	Night_Mins FLOAT,
	Night_Calls INT,
	Night_Charge FLOAT,
	Intl_Mins FLOAT,
	Intl_Calls INT,
	Intl_Charge FLOAT,
	CustServ_Calls INT,
	Churn varchar(10)
);

GRANT ALL ON TABLE CUSTOMER_CHURN TO ROLE SAGEMAKER_ROLE;

--Create Table for ML_Results from SageMaker
CREATE OR REPLACE TABLE ML_RESULTS (
	Churn_IN INT,
    Cust_ID INT,
    Churn_Score REAL
);

GRANT ALL ON TABLE ML_RESULTS TO ROLE SAGEMAKER_ROLE;


/*-----------------------------------------------------------------------
Configure External and Internal Data Stages in Snowflake
to load data into Snowflake.

S3 Stages make it easy to load and unload data at large scale
-------------------------------------------------------------------------*/

--Create CSV ship header file format
CREATE OR REPLACE FILE FORMAT CSVHEADER
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 0;

GRANT USAGE ON FILE FORMAT CSVHEADER TO ROLE SAGEMAKER_ROLE;

--Use an External Stage to Load data from S3
CREATE OR REPLACE STAGE CHURN_DATA
  url='s3://snowflake-corp-se-workshop/sagemaker-snowflake-devdays-v1/sourcedata/';

GRANT USAGE ON STAGE CHURN_DATA TO ROLE SAGEMAKER_ROLE;

/*-------------------------------------------------------------------------
Using a public S3 bucket for the workshop,
you can use credentials by adding the following to the stage creation


  credentials=(aws_key_id='************',
               aws_secret_key='*******************');

-------------------------------------------------------------------------*/


--Create Internal Stage for loading SageMaker results
CREATE OR REPLACE STAGE ML_RESULTS
FILE_FORMAT = (TYPE = CSV);

--Grant Stage Object Piviliges to SAGEMAKER_ROLE
GRANT READ, WRITE ON STAGE ML_RESULTS TO ROLE SAGEMAKER_ROLE;


/*--List and view the files in the external stage
LIST @CHURN_DATA;

SELECT $1,$2 FROM @CHURN_DATA/ LIMIT 10;
--*/

/*-----------------------------------------------------------------------
Load the Churn Data using the SAGEMAKER_ROLE
and do some quick analyis of the Churn Data
------------------------------------------------------------------------*/

--Switch to SAGEMAKER_ROLE
USE ROLE SAGEMAKER_ROLE;

--Load data from the External Stage to Snowflake table
COPY INTO CUSTOMER_CHURN FROM @CHURN_DATA/ FILE_FORMAT = (FORMAT_NAME = CSVHEADER);

--Let's do some quick analysis on the data loaded
SELECT * FROM CUSTOMER_CHURN LIMIT 10;

-- Get the avg VMAIL MESSAGES by STATE and INTL_PLAN for customers with VMAIL_PLAN
SELECT STATE, INTL_PLAN, AVG(VMAIL_MESSAGE)
FROM CUSTOMER_CHURN
WHERE VMAIL_PLAN = 'yes'
GROUP BY 1,2 ORDER BY AVG(VMAIL_MESSAGE) DESC;


/*-------------------------------------------------------------------------------*/
/*-------------------- Time to switch to SageMaker for ML -----------------------*/
/*-------------------------------------------------------------------------------*/

SELECT CURRENT_ACCOUNT();


/*--------------------------------------------------------------------------------
Get the ML Results returned from Sagemaker and perform some SQL Reporting
---------------------------------------------------------------------------------*/

--Load ML Results data from Internal Stage
COPY INTO ML_RESULTS FROM @ML_RESULTS;

--Now we will use it to identify geographies with high probability of customer churn
--Join the ML Results back to the customer table using customer ID
--Identify & rank States with 10 or more customers with churn score of 0.75 and higher
SELECT C.STATE, COUNT(DISTINCT(C.CUST_ID))
FROM ML_RESULTS M INNER JOIN  CUSTOMER_CHURN C on M.CUST_ID = C.CUST_ID
WHERE M.CHURN_SCORE >= 0.75
GROUP BY C.STATE
HAVING COUNT(DISTINCT(C.CUST_ID)) >= 10
ORDER BY COUNT(C.CUST_ID) DESC;













/*-----------------------
Clean up & Reset
------------------------*/

USE ROLE ACCOUNTADMIN;

DROP DATABASE IF EXISTS ML_WORKSHOP;
DROP ROLE IF EXISTS SAGEMAKER_ROLE;
DROP USER IF EXISTS SAGEMAKER;
