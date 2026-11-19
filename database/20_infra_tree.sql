-- 20_infra_tree.sql
-- HQTCSDL-56: view/CTE cay ha tang (site -> room -> rack -> node -> container).
-- Chay lai nhieu lan an toan (CREATE OR ALTER). Khong sua vw_hierarchy_tree cu trong 04.
-- Test case: database/21_test_infra_tree.sql (cay con cua 1 room, thu tu cha truoc con, room khong ton tai).

USE AR_IMMS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- View: moi dong la 1 canh cha-con cua cay ha tang. node_key = LOAI:id, parent_key la node_key cua cha.
-- Test case: SELECT * FROM vw_infra_edges WHERE node_type = N'RACK'; expected: moi rack co parent_key = ROOM:<room_id>.
CREATE OR ALTER VIEW vw_infra_edges AS
SELECT CAST(N'SITE:' + CAST(s.id AS NVARCHAR(10)) AS NVARCHAR(30)) AS node_key,
       CAST(NULL AS NVARCHAR(30)) AS parent_key,
       CAST(N'SITE' AS NVARCHAR(20)) AS node_type,
       s.id AS ref_id,
       CAST(s.name AS NVARCHAR(100)) AS name,
       CAST(s.code AS NVARCHAR(100)) AS code,
       CAST(NULL AS NVARCHAR(20)) AS status
FROM sites s
UNION ALL
SELECT CAST(N'ROOM:' + CAST(r.id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'SITE:' + CAST(r.site_id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'ROOM' AS NVARCHAR(20)),
       r.id,
       CAST(r.name AS NVARCHAR(100)),
       CAST(r.code AS NVARCHAR(100)),
       CAST(NULL AS NVARCHAR(20))
FROM rooms r
UNION ALL
SELECT CAST(N'RACK:' + CAST(rk.id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'ROOM:' + CAST(rk.room_id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'RACK' AS NVARCHAR(20)),
       rk.id,
       CAST(rk.name AS NVARCHAR(100)),
       CAST(rk.code AS NVARCHAR(100)),
       CAST(NULL AS NVARCHAR(20))
FROM racks rk
UNION ALL
SELECT CAST(N'NODE:' + CAST(n.id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'RACK:' + CAST(n.rack_id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'NODE' AS NVARCHAR(20)),
       n.id,
       CAST(n.name AS NVARCHAR(100)),
       CAST(n.hostname AS NVARCHAR(100)),
       CAST(n.status AS NVARCHAR(20))
FROM nodes n
UNION ALL
SELECT CAST(N'CONTAINER:' + CAST(c.id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'NODE:' + CAST(c.node_id AS NVARCHAR(10)) AS NVARCHAR(30)),
       CAST(N'CONTAINER' AS NVARCHAR(20)),
       c.id,
       CAST(c.name AS NVARCHAR(100)),
       CAST(c.container_id AS NVARCHAR(100)),
       CAST(c.status AS NVARCHAR(20))
FROM containers c;
GO

-- View: CTE de quy duyet toan bo cay tu site. depth 0 = site, 1 = room, 2 = rack, 3 = node, 4 = container.
-- sort_key de sap xep theo thu tu duyet (cha truoc con), path la duong dan ten.
-- Test case: SELECT * FROM vw_infra_tree ORDER BY sort_key; expected: moi room nam duoi dung site cua no.
CREATE OR ALTER VIEW vw_infra_tree AS
WITH tree AS (
    SELECT e.node_key, e.parent_key, e.node_type, e.ref_id, e.name, e.code, e.status,
           CAST(0 AS INT) AS depth,
           CAST(e.name AS NVARCHAR(1000)) AS path,
           CAST(N'/' + RIGHT(REPLICATE('0', 9) + CAST(e.ref_id AS VARCHAR(9)), 9) AS VARCHAR(400)) AS sort_key
    FROM vw_infra_edges e
    WHERE e.parent_key IS NULL
    UNION ALL
    SELECT c.node_key, c.parent_key, c.node_type, c.ref_id, c.name, c.code, c.status,
           t.depth + 1,
           CAST(t.path + N' / ' + c.name AS NVARCHAR(1000)),
           CAST(t.sort_key + '/' + RIGHT(REPLICATE('0', 9) + CAST(c.ref_id AS VARCHAR(9)), 9) AS VARCHAR(400))
    FROM vw_infra_edges c
    INNER JOIN tree t ON c.parent_key = t.node_key
)
SELECT node_key, parent_key, node_type, ref_id, name, code, status, depth, path, sort_key
FROM tree;
GO

-- SP: 1 truy van tra ve toan bo cay con cua 1 Room (room, rack, node, container) theo thu tu duyet.
-- depth tinh tu room (0 = room, 1 = rack, 2 = node, 3 = container).
-- Test case: room co 2 rack, 3 node, 2 container -> 8 dong; room khong ton tai -> loi 51070.
CREATE OR ALTER PROCEDURE usp_get_room_subtree
    @room_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.rooms WHERE id = @room_id)
        THROW 51070, N'Room not found.', 1;

    WITH tree AS (
        SELECT e.node_key, e.parent_key, e.node_type, e.ref_id, e.name, e.code, e.status,
               CAST(0 AS INT) AS depth,
               CAST(e.name AS NVARCHAR(1000)) AS path,
               CAST(N'/' + RIGHT(REPLICATE('0', 9) + CAST(e.ref_id AS VARCHAR(9)), 9) AS VARCHAR(400)) AS sort_key
        FROM dbo.vw_infra_edges e
        WHERE e.node_type = N'ROOM' AND e.ref_id = @room_id
        UNION ALL
        SELECT c.node_key, c.parent_key, c.node_type, c.ref_id, c.name, c.code, c.status,
               t.depth + 1,
               CAST(t.path + N' / ' + c.name AS NVARCHAR(1000)),
               CAST(t.sort_key + '/' + RIGHT(REPLICATE('0', 9) + CAST(c.ref_id AS VARCHAR(9)), 9) AS VARCHAR(400))
        FROM dbo.vw_infra_edges c
        INNER JOIN tree t ON c.parent_key = t.node_key
    )
    SELECT node_key, parent_key, node_type, ref_id, name, code, status, depth, path, sort_key
    FROM tree
    ORDER BY sort_key;
END;
GO

PRINT N'=== HQTCSDL-56: view/CTE cay ha tang san sang ===';
GO