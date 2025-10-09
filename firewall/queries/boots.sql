/* This query is used to create the external table for the alb logs. */

CREATE EXTERNAL TABLE IF NOT EXISTS alb_logs (
    type STRING,
    time STRING,
    elb STRING,
    client_ip STRING,
    client_port INT,
    target_ip STRING,
    target_port INT,
    request_processing_time DOUBLE,
    target_processing_time DOUBLE,
    response_processing_time DOUBLE,
    elb_status_code INT,
    target_status_code STRING,
    received_bytes BIGINT,
    sent_bytes BIGINT,
    request_verb STRING,
    request_url STRING,
    request_proto STRING,
    user_agent STRING,
    ssl_cipher STRING,
    ssl_protocol STRING,
    target_group_arn STRING,
    trace_id STRING,
    domain_name STRING,
    chosen_cert_arn STRING,
    matched_rule_priority STRING,
    request_creation_time STRING,
    actions_executed STRING,
    redirect_url STRING,
    error_reason STRING,
    target_port_list STRING,
    target_status_code_list STRING,
    classification STRING,
    classification_reason STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
    'serialization.format' = '1',
    'input.regex' = '([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*)[:-]([0-9]*) ([-.0-9]*) ([-.0-9]*) ([-.0-9]*) (|[-0-9]*) (-|[-0-9]*) ([-0-9]*) ([-0-9]*) \"([^ ]*) ([^ ]*) (- |[^ ]*)\" \"([^\"]*)\" ([A-Z0-9-_]+) ([A-Za-z0-9.-]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" ([-.0-9]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^ ]*)\" \"([^\s]+?)\" \"([^\s]+)\" \"([^ ]*)\" \"([^ ]*)\"'
)
LOCATION 's3://openhistoricalmap-elb-logs/alb_production/AWSLogs/618380242247/elasticloadbalancing/us-east-1/';

/* This query is used to find the bots in the alb logs. */
SELECT
    user_agent,
    client_ip,
    COUNT(*) AS request_count
FROM
    alb_logs
WHERE
    from_iso8601_timestamp(time) >= (now() - interval '48' hour)
    AND
    (LOWER(user_agent) LIKE '%bot%' OR LOWER(user_agent) LIKE '%spider%' OR LOWER(user_agent) LIKE '%crawler%')
GROUP BY
    user_agent,
    client_ip
ORDER BY
    request_count DESC
LIMIT 50;
