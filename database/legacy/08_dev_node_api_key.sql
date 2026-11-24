-- 08_dev_node_api_key.sql
-- CHI DUNG CHO DEV/TEST: tao agent demo cho node dau tien voi API-key demo.
-- Key goc: demo-node-key-001 (DB chi luu hash SHA-256, khong luu key goc).
-- Chay lai nhieu lan van an toan.

USE AR_IMMS;
GO

DECLARE @node_id INT = (SELECT MIN(id) FROM nodes);
DECLARE @hash NVARCHAR(255) =
    LOWER(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 'demo-node-key-001'), 2));

IF @node_id IS NULL
    THROW 51040, N'Chua co node nao trong bang nodes.', 1;

IF EXISTS (SELECT 1 FROM data_collector_agents
           WHERE node_id = @node_id AND agent_version = N'dev-demo')
    UPDATE data_collector_agents
    SET api_key_hash = @hash, status = 'ACTIVE'
    WHERE node_id = @node_id AND agent_version = N'dev-demo';
ELSE
    INSERT INTO data_collector_agents (node_id, agent_version, status, api_key_hash)
    VALUES (@node_id, N'dev-demo', 'ACTIVE', @hash);

PRINT N'=== Da tao/cap nhat agent demo voi API-key demo ===';
GO