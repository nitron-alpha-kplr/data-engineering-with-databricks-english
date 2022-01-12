-- Databricks notebook source
-- MAGIC %md-sandbox
-- MAGIC 
-- MAGIC <div style="text-align: center; line-height: 0; padding-top: 9px;">
-- MAGIC   <img src="https://databricks.com/wp-content/uploads/2018/03/db-academy-rgb-1200px.png" alt="Databricks Learning" style="width: 600px">
-- MAGIC </div>

-- COMMAND ----------

-- MAGIC %md
-- MAGIC # Lab: Migrating a SQL Pipeline to Delta Live Tables
-- MAGIC 
-- MAGIC This notebook will be completed by you to implement a DLT pipeline using SQL. It is **not intended** to be executed interactively, but rather to be deployed as a pipeline once you have completed your changes.
-- MAGIC 
-- MAGIC To aid in completion of this Notebook, please refer to the <a href="https://docs.databricks.com/data-engineering/delta-live-tables/delta-live-tables-language-ref.html#sql" target="_blank">DLT syntax documentation</a>.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Declare Bronze Table
-- MAGIC 
-- MAGIC Declare a bronze table that ingests JSON data incrementally (using Auto Loader) from the simulated cloud source. Here you will need to substitue the value obtained from the <a href="$./DEWD 3.3 - DLT Migration Lab Setup" target="_blank">companion setup Notebook</a>.
-- MAGIC 
-- MAGIC As we did previously, include two additional columns:
-- MAGIC * `receipt_time` that records a timestamp as returned by `current_timestamp()` 
-- MAGIC * `dataset` that notes the source. For now set this column to the literal value `"recordings"`

-- COMMAND ----------

-- ANSWER
CREATE INCREMENTAL LIVE TABLE recordings_bronze
AS SELECT current_timestamp() receipt_time, "recordings" dataset, *
  FROM cloud_files("${source}", "json", map("cloudFiles.schemaHints", "time DOUBLE"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### PII File
-- MAGIC 
-- MAGIC Using a similar CTAS syntax, create a live **view** into the CSV data found at */mnt/training/healthcare/patient*.
-- MAGIC 
-- MAGIC To properly configure Auto Loader for this source, you will need to specify the following additional parameters:
-- MAGIC 
-- MAGIC | option | value |
-- MAGIC | --- | --- |
-- MAGIC | `header` | `true` |
-- MAGIC | `cloudFiles.inferColumnTypes` | `true` |
-- MAGIC 
-- MAGIC <img src="https://files.training.databricks.com/images/icon_note_24.png"/> Auto Loader configurations for CSV can be found <a href="https://docs.databricks.com/spark/latest/structured-streaming/auto-loader-csv.html" target="_blank">here</a>.

-- COMMAND ----------

-- ANSWER
CREATE INCREMENTAL LIVE VIEW pii
AS SELECT *
  FROM cloud_files("/mnt/training/healthcare/patient", "csv", map("header", "true", "cloudFiles.inferColumnTypes", "true"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Declare Silver Tables
-- MAGIC 
-- MAGIC The first of the silver tables, `recordings_parsed`, will subscribe to the `recordings` dataset in the multiplex `recordings_bronze` table and cast the fields as follows:
-- MAGIC 
-- MAGIC 
-- MAGIC | Field | Type |
-- MAGIC | --- | --- |
-- MAGIC | `device_id` | `INTEGER` |
-- MAGIC | `mrn` | `LONG` |
-- MAGIC | `heartrate` | `DOUBLE` |
-- MAGIC | `time` | `TIMESTAMP` (example provided below) |

-- COMMAND ----------

-- ANSWER

CREATE INCREMENTAL LIVE TABLE recordings_parsed
AS SELECT 
  CAST(device_id AS INTEGER) device_id, 
  CAST(mrn AS LONG) mrn, 
  CAST(heartrate AS DOUBLE) heartrate, 
  CAST(FROM_UNIXTIME(time, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) time 
  FROM STREAM(live.recordings_bronze)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Enriching Data and Quality Control
-- MAGIC 
-- MAGIC Create a second silver table, `recordings_enriched` that enriches the data from `recordings_parsed` with data from the `pii` view, using an inner join on the common `mrn` field.
-- MAGIC 
-- MAGIC Implement quality control by applying a contraint to drop records with an invalid `heartrate` (that is, not greater than zero). 

-- COMMAND ----------

-- ANSWER

CREATE INCREMENTAL LIVE TABLE recordings_enriched
  (CONSTRAINT positive_heartrate EXPECT (heartrate > 0) ON VIOLATION DROP ROW)
AS SELECT device_id, a.mrn, name, time, heartrate
  FROM STREAM(live.recordings_parsed) a
  INNER JOIN STREAM(live.pii) b
  ON a.mrn = b.mrn

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Gold Table
-- MAGIC 
-- MAGIC Create a gold table, `daily_patient_avg`, that aggregates `recordings_enriched` by `mrn`, `name`, and `date` and delivers the following columns:
-- MAGIC 
-- MAGIC | Column name | Value |
-- MAGIC | --- | --- |
-- MAGIC | `mrn` | `mrn` from source |
-- MAGIC | `name` | `name` from source |
-- MAGIC | `avg_heartrate` | Average `heartrate` from the grouping |
-- MAGIC | `date` | Date extracted from `time` |

-- COMMAND ----------

-- ANSWER

CREATE INCREMENTAL LIVE TABLE daily_patient_avg
  COMMENT "Daily mean heartrates by patient"
AS SELECT mrn, name, MEAN(heartrate) avg_heartrate, DATE(time) `date`
  FROM STREAM(live.recordings_enriched)
  GROUP BY mrn, name, DATE(time)

-- COMMAND ----------

-- MAGIC %md-sandbox
-- MAGIC &copy; 2022 Databricks, Inc. All rights reserved.<br/>
-- MAGIC Apache, Apache Spark, Spark and the Spark logo are trademarks of the <a href="https://www.apache.org/">Apache Software Foundation</a>.<br/>
-- MAGIC <br/>
-- MAGIC <a href="https://databricks.com/privacy-policy">Privacy Policy</a> | <a href="https://databricks.com/terms-of-use">Terms of Use</a> | <a href="https://help.databricks.com/">Support</a>
