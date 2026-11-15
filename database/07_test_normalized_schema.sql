-- Run after 01-05 and 06_verify_seed_data.sql.
-- Expected: the valid and two negative cases print PASS; all test writes roll back.
USE AR_IMMS;
GO

SET NOCOUNT ON;

DECLARE @telemetry_before BIGINT;
DECLARE @test_error_number INT;
SELECT @telemetry_before = COUNT_BIG(*)
FROM telemetry_metrics telemetry
INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
WHERE telemetry.node_id = 1 AND metric.code = N'cpu_usage_percent';

BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_record_telemetry
        @node_id = 1,
        @metric_type = N'cpu_usage_percent',
        @value = 55.0,
        @unit = N'C';

    THROW 51040, N'Expected the procedure to reject a unit that does not match the metric type.', 1;
END TRY
BEGIN CATCH
    SET @test_error_number = ERROR_NUMBER();
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    IF @test_error_number <> 51031
        THROW;
END CATCH;

IF (
    SELECT COUNT_BIG(*)
    FROM telemetry_metrics telemetry
    INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
    WHERE telemetry.node_id = 1 AND metric.code = N'cpu_usage_percent'
) <> @telemetry_before
    THROW 51041, N'Rejected telemetry input must not write a measurement.', 1;

PRINT N'PASS: telemetry rejects a non-canonical unit without writing data.';

BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.sp_record_telemetry
        @node_id = 1,
        @metric_type = N'cpu_usage_percent',
        @value = 95.0,
        @unit = N'%';

    IF NOT EXISTS (
        SELECT 1
        FROM telemetry_metrics telemetry
        INNER JOIN metric_types metric ON metric.id = telemetry.metric_type_id
        WHERE telemetry.node_id = 1
          AND metric.code = N'cpu_usage_percent'
          AND telemetry.value = 95.0
    )
        THROW 51043, N'Expected the valid telemetry measurement to be recorded.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM alerts
        WHERE node_id = 1
          AND alert_type = N'cpu_usage_percent_OVERLOAD'
          AND severity = N'CRITICAL'
          AND status = N'OPEN'
    )
        THROW 51044, N'Expected a critical telemetry value to create an alert.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

PRINT N'PASS: valid critical telemetry is recorded and creates an alert.';

BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO telemetry_metrics (node_id, metric_type_id, value)
    VALUES (1, -2147483648, 1.0);

    THROW 51042, N'Expected the metric type foreign key to reject an unknown metric.', 1;
END TRY
BEGIN CATCH
    SET @test_error_number = ERROR_NUMBER();
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    IF @test_error_number <> 547
        THROW;
END CATCH;

PRINT N'PASS: telemetry metric type foreign key rejects an unknown metric.';

-- Test case: duplicate rack slot within one rack must fail with SQL Server
-- unique-key error 2601/2627; the attempted insert is rolled back.
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @rack_id INT, @rack_position_u INT;
    SELECT TOP (1) @rack_id = rack_id, @rack_position_u = rack_position_u
    FROM dbo.nodes
    ORDER BY id;

    INSERT INTO dbo.nodes (rack_id, name, hostname, ip_address, rack_position_u)
    VALUES (@rack_id, N'__dup_slot_test__', N'__dup_slot_test__', N'0.0.0.0', @rack_position_u);

    THROW 51045, N'Expected duplicate (rack_id, rack_position_u) to be rejected.', 1;
END TRY
BEGIN CATCH
    SET @test_error_number = ERROR_NUMBER();
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    IF @test_error_number NOT IN (2601, 2627)
        THROW;
END CATCH;

PRINT N'PASS: nodes reject duplicate (rack_id, rack_position_u).';
GO
