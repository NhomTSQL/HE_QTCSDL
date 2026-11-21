-- 21_test_infra_tree.sql
-- HQTCSDL-56: test cay ha tang. Chay lai nhieu lan an toan: tao 1 room test rieng (TEST56-ROOM) voi
-- 2 rack, 3 node (MAINTENANCE nen SQL Agent job bo qua), 2 container; don du lieu test cu o dau va don sach o cuoi.
-- Yeu cau: da chay 01-04 va 20.
--
-- KICH BAN                                                   KET QUA MONG DOI
-- T1  usp_get_room_subtree cho room test                     8 dong: 1 ROOM, 2 RACK, 3 NODE, 2 CONTAINER
-- T2  depth                                                  ROOM 0, RACK 1, NODE 2, CONTAINER 3
-- T3  thu tu duyet                                           cha luon truoc con; dung 1 goc, la room test
-- T4  2 container thuoc dung node 1                          2 container co parent_key = NODE:<node 1>
-- T5  room khong ton tai                                     loi 51070
-- T6  room seed ROOM-A01                                     so rack/node/container bang so dem tu bang goc
-- T7  vw_infra_tree (toan cay)                               room test o depth 1, cay con 7 dong, sau nhat depth 4, co SITE goc

USE AR_IMMS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

-- Don du lieu test cu (rooms xoa day chuyen xuong rack, node, container nho ON DELETE CASCADE)
DELETE FROM rooms WHERE code = N'TEST56-ROOM';

DECLARE @site_id INT = (SELECT MIN(id) FROM sites);
IF @site_id IS NULL
    THROW 51119, N'FAIL: chua co site seed (chay 03_seed_data.sql).', 1;

INSERT INTO rooms (site_id, name, code) VALUES (@site_id, N'TEST56 room', N'TEST56-ROOM');
DECLARE @room_id INT = (SELECT id FROM rooms WHERE code = N'TEST56-ROOM');

INSERT INTO racks (room_id, name, code) VALUES
    (@room_id, N'TEST56 rack 1', N'TEST56-R1'),
    (@room_id, N'TEST56 rack 2', N'TEST56-R2');
DECLARE @rack1 INT = (SELECT id FROM racks WHERE code = N'TEST56-R1');
DECLARE @rack2 INT = (SELECT id FROM racks WHERE code = N'TEST56-R2');

INSERT INTO nodes (rack_id, name, hostname, ip_address, status) VALUES
    (@rack1, N'TEST56 node 1', N'srv-test56-1', N'192.168.10.241', N'MAINTENANCE'),
    (@rack1, N'TEST56 node 2', N'srv-test56-2', N'192.168.10.242', N'MAINTENANCE'),
    (@rack2, N'TEST56 node 3', N'srv-test56-3', N'192.168.10.243', N'MAINTENANCE');
DECLARE @node1 INT = (SELECT id FROM nodes WHERE hostname = N'srv-test56-1');

INSERT INTO containers (node_id, container_id, name, image) VALUES
    (@node1, N'test56-c1', N'TEST56 container 1', N'nginx:latest'),
    (@node1, N'test56-c2', N'TEST56 container 2', N'redis:latest');

DECLARE @t TABLE (
    seq INT IDENTITY(1,1), node_key NVARCHAR(30), parent_key NVARCHAR(30), node_type NVARCHAR(20),
    ref_id INT, name NVARCHAR(100), code NVARCHAR(100), status NVARCHAR(20),
    depth INT, path NVARCHAR(1000), sort_key VARCHAR(400));

INSERT @t (node_key, parent_key, node_type, ref_id, name, code, status, depth, path, sort_key)
EXEC dbo.usp_get_room_subtree @room_id = @room_id;

-- T1
IF (SELECT COUNT(*) FROM @t) <> 8
    THROW 51120, N'FAIL T1: cay con cua room test phai co dung 8 dong.', 1;
IF (SELECT COUNT(*) FROM @t WHERE node_type = N'ROOM') <> 1
   OR (SELECT COUNT(*) FROM @t WHERE node_type = N'RACK') <> 2
   OR (SELECT COUNT(*) FROM @t WHERE node_type = N'NODE') <> 3
   OR (SELECT COUNT(*) FROM @t WHERE node_type = N'CONTAINER') <> 2
    THROW 51121, N'FAIL T1: phai co 1 ROOM, 2 RACK, 3 NODE, 2 CONTAINER.', 1;
PRINT N'PASS T1 cay con room test: 8 dong (1 room, 2 rack, 3 node, 2 container)';

-- T2
IF EXISTS (SELECT 1 FROM @t WHERE depth <> CASE node_type
        WHEN N'ROOM' THEN 0 WHEN N'RACK' THEN 1 WHEN N'NODE' THEN 2 WHEN N'CONTAINER' THEN 3 END)
    THROW 51122, N'FAIL T2: depth sai (ROOM 0, RACK 1, NODE 2, CONTAINER 3).', 1;
PRINT N'PASS T2 depth dung theo cap';

-- T3
IF EXISTS (SELECT 1 FROM @t c INNER JOIN @t p ON p.node_key = c.parent_key WHERE p.seq > c.seq)
    THROW 51123, N'FAIL T3: co dong con nam truoc cha.', 1;
IF (SELECT COUNT(*) FROM @t c
    WHERE c.parent_key IS NULL OR NOT EXISTS (SELECT 1 FROM @t p WHERE p.node_key = c.parent_key)) <> 1
    THROW 51124, N'FAIL T3: phai co dung 1 goc.', 1;
IF (SELECT TOP 1 ref_id FROM @t ORDER BY seq) <> @room_id
    THROW 51125, N'FAIL T3: goc cua cay phai la room test.', 1;
PRINT N'PASS T3 thu tu duyet: cha truoc con, dung 1 goc la room test';

-- T4
IF (SELECT COUNT(*) FROM @t
    WHERE node_type = N'CONTAINER' AND parent_key = N'NODE:' + CAST(@node1 AS NVARCHAR(10))) <> 2
    THROW 51126, N'FAIL T4: 2 container phai thuoc node 1.', 1;
PRINT N'PASS T4 2 container thuoc dung node 1';

-- T5
DECLARE @err INT = 0;
BEGIN TRY
    EXEC dbo.usp_get_room_subtree @room_id = -1;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER();
END CATCH;
IF @err <> 51070
    THROW 51127, N'FAIL T5: room khong ton tai phai bao loi 51070.', 1;
PRINT N'PASS T5 room khong ton tai (loi 51070)';

-- T6: room seed, so dong tung loai phai bang so dem tu bang goc
DECLARE @seed_room INT = (SELECT id FROM rooms WHERE code = N'ROOM-A01');
IF @seed_room IS NULL
    THROW 51128, N'FAIL T6: thieu room seed ROOM-A01 (chay 03_seed_data.sql).', 1;
DELETE FROM @t;
INSERT @t (node_key, parent_key, node_type, ref_id, name, code, status, depth, path, sort_key)
EXEC dbo.usp_get_room_subtree @room_id = @seed_room;
IF (SELECT COUNT(*) FROM @t WHERE node_type = N'ROOM') <> 1
   OR (SELECT COUNT(*) FROM @t WHERE node_type = N'RACK')
        <> (SELECT COUNT(*) FROM racks WHERE room_id = @seed_room)
   OR (SELECT COUNT(*) FROM @t WHERE node_type = N'NODE')
        <> (SELECT COUNT(*) FROM nodes n INNER JOIN racks r ON r.id = n.rack_id WHERE r.room_id = @seed_room)
   OR (SELECT COUNT(*) FROM @t WHERE node_type = N'CONTAINER')
        <> (SELECT COUNT(*) FROM containers c INNER JOIN nodes n ON n.id = c.node_id
            INNER JOIN racks r ON r.id = n.rack_id WHERE r.room_id = @seed_room)
    THROW 51129, N'FAIL T6: so rack/node/container cua room seed khong khop bang goc.', 1;
PRINT N'PASS T6 room seed ROOM-A01: so luong khop bang goc';

-- T7: view toan cay
DECLARE @room_sort VARCHAR(400) = (SELECT sort_key FROM dbo.vw_infra_tree WHERE node_type = N'ROOM' AND ref_id = @room_id);
IF @room_sort IS NULL
    THROW 51130, N'FAIL T7: room test khong co trong vw_infra_tree.', 1;
IF (SELECT depth FROM dbo.vw_infra_tree WHERE node_type = N'ROOM' AND ref_id = @room_id) <> 1
    THROW 51131, N'FAIL T7: room phai o depth 1 (duoi site).', 1;
IF (SELECT COUNT(*) FROM dbo.vw_infra_tree WHERE sort_key LIKE @room_sort + '/%') <> 7
   OR (SELECT MAX(depth) FROM dbo.vw_infra_tree WHERE sort_key LIKE @room_sort + '/%') <> 4
    THROW 51132, N'FAIL T7: cay con trong view phai co 7 dong, sau nhat depth 4.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.vw_infra_tree WHERE node_type = N'SITE' AND ref_id = @site_id AND depth = 0)
    THROW 51133, N'FAIL T7: thieu dong SITE goc depth 0.', 1;
PRINT N'PASS T7 vw_infra_tree: room depth 1, cay con 7 dong, sau nhat depth 4, co site goc';

-- Don dep
DELETE FROM rooms WHERE id = @room_id;
PRINT N'=== HQTCSDL-56: 7 kich ban cay ha tang deu PASS, da don du lieu test ===';
GO