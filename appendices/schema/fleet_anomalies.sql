-- Canonical QuestDB Table Schema for fleet_anomalies
-- Ingests real-time inference results from fleet-anomalies Kafka topic

CREATE TABLE IF NOT EXISTS fleet_anomalies (
  timestamp             TIMESTAMP,
  manufacturer          SYMBOL,
  agv_id                SYMBOL,
  vehicle_key           SYMBOL,
  window_start          STRING,
  window_end            STRING,
  model_name            SYMBOL,
  model_version         SYMBOL,
  anomaly_score         DOUBLE,
  warning_threshold     DOUBLE,
  anomaly_threshold     DOUBLE,
  classification        SYMBOL,
  top_features_summary  STRING,
  top_feature_1         SYMBOL,
  top_feature_1_contrib DOUBLE,
  top_feature_2         SYMBOL,
  top_feature_2_contrib DOUBLE,
  top_feature_3         SYMBOL,
  top_feature_3_contrib DOUBLE
) TIMESTAMP(timestamp) PARTITION BY DAY TTL 7 DAYS WAL;

ALTER TABLE fleet_anomalies SET TTL 7 DAYS;
