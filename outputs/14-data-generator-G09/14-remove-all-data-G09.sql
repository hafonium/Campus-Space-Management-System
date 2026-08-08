-- ============================================================================
-- Reset ALL data then re-seed the demo dataset — Campus Space Management System
-- File: 14-remove-all-data-G09.sql
-- Description: Deletes every row from every table (in FK-safe order) and
-- reseeds the IDENTITY columns so the database returns to the empty,
-- post-Phase-2 state. The schema itself is NOT dropped. Afterwards the
-- hand-written demonstration dataset (06-sample-data style, realistic
-- values, Vietnamese names/phones/notes with no diacritics) is re-inserted
-- so the database is never left empty.
-- Run ONLY when you intend to wipe the whole database (sample + generated).
-- ============================================================================

USE CampusSpaceManagementSystem;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

-- ----------------------------------------------------------------------------
-- 1. DELETE leaf tables first (respect FK chain)
--    child -> parent order:
--    ACKNOWLEDGEMENT -> BOOKING, MAINTENANCE_RECORD
--    ROLE_USAGE_POLICY -> ROLE, USAGE_POLICY
--    DEPARTMENT_USAGE_POLICY -> DEPARTMENT, USAGE_POLICY
--    SPACE_FACILITY -> SPACE, FACILITY
--    BOOKING -> USER, SPACE
--    MAINTENANCE_RECORD -> USER, SPACE
--    USER -> ROLE, DEPARTMENT
--    SPACE -> USAGE_POLICY
-- ----------------------------------------------------------------------------
DELETE FROM dbo.ACKNOWLEDGEMENT;
DELETE FROM dbo.ROLE_USAGE_POLICY;
IF OBJECT_ID('dbo.DEPARTMENT_USAGE_POLICY', 'U') IS NOT NULL
    EXEC ('DELETE FROM dbo.DEPARTMENT_USAGE_POLICY;');
DELETE FROM dbo.SPACE_FACILITY;
DELETE FROM dbo.BOOKING;
DELETE FROM dbo.MAINTENANCE_RECORD;
DELETE FROM dbo.[USER];
IF OBJECT_ID('dbo.gen_user_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_user_marker;
IF OBJECT_ID('dbo.gen_policy_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_policy_marker;
IF OBJECT_ID('dbo.gen_space_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_space_marker;
IF OBJECT_ID('dbo.gen_facility_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_facility_marker;
IF OBJECT_ID('dbo.gen_maintenance_marker', 'U') IS NOT NULL
    DELETE FROM dbo.gen_maintenance_marker;
DELETE FROM dbo.SPACE;
DELETE FROM dbo.USAGE_POLICY;
DELETE FROM dbo.FACILITY;
DELETE FROM dbo.ROLE;
IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NOT NULL
    EXEC ('DELETE FROM dbo.DEPARTMENT;');
IF OBJECT_ID('dbo.SEMESTER', 'U') IS NOT NULL
    EXEC ('DELETE FROM dbo.SEMESTER;');

-- ----------------------------------------------------------------------------
-- 2. Reseed IDENTITY columns so the next inserts start from 1
-- ----------------------------------------------------------------------------
DBCC CHECKIDENT (ROLE, RESEED, 0);
IF OBJECT_ID('dbo.DEPARTMENT', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.DEPARTMENT', RESEED, 0);
IF OBJECT_ID('dbo.SEMESTER', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.SEMESTER', RESEED, 0);
DBCC CHECKIDENT (USAGE_POLICY, RESEED, 0);
DBCC CHECKIDENT ([USER], RESEED, 0);
DBCC CHECKIDENT (FACILITY, RESEED, 0);
DBCC CHECKIDENT (BOOKING, RESEED, 0);
DBCC CHECKIDENT (MAINTENANCE_RECORD, RESEED, 0);

COMMIT TRANSACTION;

-- ============================================================================
-- 3. RE-SEED the hand-written demo dataset (06 sample style)
--    Phase 2 schema: users reference ROLE / DEPARTMENT, spaces reference
--    USAGE_POLICY, maintenance records carry impact_level.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 ROLE (six standard roles)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.ROLE (role_name)
SELECT v.role_name
FROM (VALUES ('student'), ('lecturer'), ('teaching_assistant'),
             ('department_administrator'), ('facility_staff'),
             ('facility_manager')) v(role_name)
WHERE NOT EXISTS (SELECT 1 FROM dbo.ROLE r WHERE r.role_name = v.role_name);

DECLARE @RoleStudent INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'student');
DECLARE @RoleLecturer INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'lecturer');
DECLARE @RoleTA INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'teaching_assistant');
DECLARE @RoleAdmin INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'department_administrator');
DECLARE @RoleStaff INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'facility_staff');
DECLARE @RoleManager INT = (SELECT role_id FROM dbo.ROLE WHERE role_name = 'facility_manager');

-- ----------------------------------------------------------------------------
-- 3.2 DEPARTMENT (demo departments; no diacritics)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.DEPARTMENT (department_name)
SELECT v.department_name
FROM (VALUES ('Khoa Cong nghe Thong tin'),
             ('Phong Quan ly Co so vat chat')) v(department_name)
WHERE NOT EXISTS (SELECT 1 FROM dbo.DEPARTMENT d
                  WHERE d.department_name = v.department_name);

DECLARE @DeptIT INT = (SELECT department_id FROM dbo.DEPARTMENT
                        WHERE department_name = 'Khoa Cong nghe Thong tin');
DECLARE @DeptFacilities INT = (SELECT department_id FROM dbo.DEPARTMENT
                               WHERE department_name = 'Phong Quan ly Co so vat chat');

-- ----------------------------------------------------------------------------
-- 3.3 SEMESTER (demo academic periods)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.SEMESTER (semester_name, start_date, end_date)
SELECT v.semester_name, v.start_date, v.end_date
FROM (VALUES ('Hoc ky 1 nam hoc 2025 - 2026', '2025-09-01', '2026-01-10'),
             ('Hoc ky 2 nam hoc 2025 - 2026', '2026-02-02', '2026-06-30')) v(semester_name, start_date, end_date)
WHERE NOT EXISTS (SELECT 1 FROM dbo.SEMESTER s
                  WHERE s.semester_name = v.semester_name);

-- ----------------------------------------------------------------------------
-- 3.4 USAGE_POLICY (demo policies; legacy text keeps pending bookings manual)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.USAGE_POLICY (policy_name, max_duration_minutes, requires_business_hours, legacy_policy_text)
SELECT v.policy_name, v.max_duration_minutes, v.requires_business_hours, v.legacy_policy_text
FROM (VALUES
    ('Chinh sach giang duong',
     240, 1,
     'Uu tien cho cac bai giang hoc thuat, le ket nap va hoi thao cong khai. Yeu cau su kien ben ngoai can su chap thuan cua truong khoa it nhat 14 ngay truoc.'),
    ('Chinh sach lop hoc',
     180, 1,
     'Lop hoc chuan cho cac mon dai cuong va bai tap. Khong thuc pham va do uong ngoai nuoc loc. May chieu va bang trang san sang.'),
    ('Chinh sach phong may tinh',
     240, 1,
     'Phong may tinh phuc vu mon hoc va bai tap cua khoa Cong nghe Thong tin. Khong cai dat phan mem ben ngoai khi chua duoc phe duyet.'),
    ('Chinh sach phong thi nghiem',
     480, 0,
     'Khong gian lam viec cho do an tot nghiep. Truy cap 24/7 bang the. Phai dang ky thiet bi muon.'),
    ('Chinh sach phong hop',
     120, 1,
     'Phong hop co he thong hop video. Toi da 2 gio lien tuc vao ngay lam viec. Dung tiec khi co phe duyet.'),
    ('Chinh sach sinh hoat sinh vien',
     300, 0,
     'Khong gian sinh hoat chung. Ngoi tu do tru cac su kien dat phong. Nhom dat phong can it nhat mot sinh vien to chuc.')) v(policy_name, max_duration_minutes, requires_business_hours, legacy_policy_text)
WHERE NOT EXISTS (SELECT 1 FROM dbo.USAGE_POLICY p
                  WHERE p.policy_name = v.policy_name);

DECLARE @PolAuditorium INT = (SELECT policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'Chinh sach giang duong');
DECLARE @PolClassroom INT = (SELECT policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'Chinh sach lop hoc');
DECLARE @PolComputerLab INT = (SELECT policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'Chinh sach phong may tinh');
DECLARE @PolProjectLab INT = (SELECT policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'Chinh sach phong thi nghiem');
DECLARE @PolMeeting INT = (SELECT policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'Chinh sach phong hop');
DECLARE @PolWorkspace INT = (SELECT policy_id FROM dbo.USAGE_POLICY WHERE policy_name = 'Chinh sach sinh hoat sinh vien');

-- ----------------------------------------------------------------------------
-- 3.5 USER (12 demo users; realistic Vietnamese data, no diacritics)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Nguyen Van Anh', 'nguyen.vananh1@hcmus.edu.vn', '0901234001', @RoleStudent, @DeptIT, 'active');
DECLARE @uStudent INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Tran Thi Minh', 'tran.thiminh2@hcmus.edu.vn', '0901234002', @RoleLecturer, @DeptIT, 'active');
DECLARE @uLecturer1 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Le Van Binh', 'le.vanbinh3@hcmus.edu.vn', '0901234003', @RoleLecturer, @DeptIT, 'active');
DECLARE @uLecturer2 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Hoang Thi Hoa', 'hoang.thihoa4@hcmus.edu.vn', '0901234004', @RoleTA, @DeptIT, 'active');
DECLARE @uTA1 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Pham Ngoc Anh', 'pham.ngocanh5@hcmus.edu.vn', '0901234005', @RoleTA, @DeptIT, 'active');
DECLARE @uTA2 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Vu Minh Long', 'vu.minhlong6@hcmus.edu.vn', '0901234006', @RoleStaff, @DeptFacilities, 'active');
DECLARE @uStaff1 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Dinh Bac Hung', 'dinh.bachung7@hcmus.edu.vn', '0901234007', @RoleStaff, @DeptFacilities, 'active');
DECLARE @uStaff2 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Nguyen Le Lam', 'nguyen.lelam8@hcmus.edu.vn', '0901234008', @RoleAdmin, @DeptIT, 'active');
DECLARE @uAdmin1 INT = SCOPE_IDENTITY();

-- Exceptional: suspended and deactivated accounts
INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Tran Thi Thao', 'tran.thithao9@hcmus.edu.vn', '0901234009', @RoleStudent, @DeptIT, 'suspended');
DECLARE @uSuspended INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Le Khai Tam', 'le.khaitam10@hcmus.edu.vn', '0901234010', @RoleAdmin, @DeptIT, 'deactivated');
DECLARE @uDeactivated INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Phan Thanh Huy', 'phan.thanhhuy11@hcmus.edu.vn', '0901234011', @RoleManager, @DeptFacilities, 'active');
DECLARE @uManager1 INT = SCOPE_IDENTITY();

INSERT INTO dbo.[USER] (full_name, email, phone_number, role_id, department_id, account_status)
VALUES ('Dang Ngoc Tu', 'dang.ngoctu12@hcmus.edu.vn', '0901234012', @RoleManager, @DeptFacilities, 'active');
DECLARE @uManager2 INT = SCOPE_IDENTITY();

-- ----------------------------------------------------------------------------
-- 3.6 ROLE_USAGE_POLICY / DEPARTMENT_USAGE_POLICY (demo links)
-- ----------------------------------------------------------------------------
INSERT INTO dbo.ROLE_USAGE_POLICY (role_id, policy_id)
SELECT r.role_id, p.policy_id
FROM (VALUES ('student', 'Chinh sach sinh hoat sinh vien'),
             ('lecturer', 'Chinh sach giang duong'),
             ('teaching_assistant', 'Chinh sach phong may tinh'),
             ('facility_manager', 'Chinh sach phong hop')) v(role_name, policy_name)
JOIN dbo.ROLE r ON r.role_name = v.role_name
JOIN dbo.USAGE_POLICY p ON p.policy_name = v.policy_name
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.ROLE_USAGE_POLICY x
    WHERE x.role_id = r.role_id AND x.policy_id = p.policy_id
);

INSERT INTO dbo.DEPARTMENT_USAGE_POLICY (department_id, policy_id)
SELECT d.department_id, p.policy_id
FROM (VALUES ('Khoa Cong nghe Thong tin', 'Chinh sach lop hoc'),
             ('Khoa Cong nghe Thong tin', 'Chinh sach phong may tinh'),
             ('Phong Quan ly Co so vat chat', 'Chinh sach phong hop')) v(department_name, policy_name)
JOIN dbo.DEPARTMENT d ON d.department_name = v.department_name
JOIN dbo.USAGE_POLICY p ON p.policy_name = v.policy_name
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.DEPARTMENT_USAGE_POLICY x
    WHERE x.department_id = d.department_id AND x.policy_id = p.policy_id
);

-- ============================================================================
-- 4. SPACE (10 demo spaces, all six types, boundary statuses; Phase 2 policy_id)
-- ============================================================================
INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('AUD-MC-1000', 'Giang duong Van hoa', 'auditorium', 'MC', 1, '1000', 500, 'available', @PolAuditorium);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('CR-M3-1006', 'Phong hoc M3 1006', 'classroom', 'M3', 1, '1006', 120, 'available', @PolClassroom);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('CR-DC-1302', 'Phong hoc DC 1302', 'classroom', 'DC', 1, '1302', 80, 'available', @PolClassroom);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('CL-DC-2585', 'Phong may Unix', 'computer_lab', 'DC', 2, '2585', 40, 'available', @PolComputerLab);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('PL-DC-3564', 'Phong do an tot nghiep', 'project_lab', 'DC', 3, '3564', 25, 'in_use', @PolProjectLab);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('MR-DC-3102', 'Phong hop Hoi dong', 'meeting_room', 'DC', 3, '3102', 20, 'available', @PolMeeting);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('SW-STC-0010', 'Khu hoc tap hop tac', 'student_workspace', 'STC', 0, '0010', 60, 'available', @PolWorkspace);

-- Exceptional: unavailable / boundary spaces
INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('CL-MC-3003', 'Phong may MC 3003', 'computer_lab', 'MC', 3, '3003', 35, 'under_maintenance', @PolComputerLab);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('MR-MC-4040', 'Phong hoc MC 4040', 'meeting_room', 'MC', 4, '4040', 15, 'temporarily_closed', @PolMeeting);

INSERT INTO dbo.SPACE (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, policy_id)
VALUES ('MR-DC-1315', 'Phong dien thoai', 'meeting_room', 'DC', 1, '1315', 1, 'retired', @PolMeeting);

-- ============================================================================
-- 5. FACILITY (8 demo facilities; names distinct from generator facilities
--    so the generator's gen_facility_marker bookkeeping cannot touch them)
-- ============================================================================
INSERT INTO dbo.FACILITY (facility_name) VALUES ('May chieu Full HD');
DECLARE @fProj INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('Bang trang tich hop');
DECLARE @fWB INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('He thong loa phong lon');
DECLARE @fMic INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('May tinh de ban');
DECLARE @fPC INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('Thiet bi phat truc tiep');
DECLARE @fLive INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('Dieu hoa khong khi');
DECLARE @fAC INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('Bang thong minh');
DECLARE @fSmart INT = SCOPE_IDENTITY();
INSERT INTO dbo.FACILITY (facility_name) VALUES ('He thong hop truc tuyen');
DECLARE @fVC INT = SCOPE_IDENTITY();

-- ============================================================================
-- 6. BOOKING (22 demo bookings; trigger trg_booking_enforce_rules is active)
-- ============================================================================

-- CR-M3-1006: completed lecture (full lifecycle)
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uLecturer1, 'CR-M3-1006', '2026-01-15 09:00:00', '2026-01-15 11:00:00',
    'lecture', 80, 'completed',
    @uManager1, '2026-01-10 14:30:00', 'Duyet theo lich cua khoa. Phong du suc chua.',
    '2026-01-15 08:55:00', @uStaff1, 'Phong sach, may chieu hoat dong tot, bang trang co but.',
    '2026-01-15 11:05:00', @uStaff2, 'Phong gon gang. Bang da xoa. Thiet bi da tat.',
    'Mon CS 350 buoi 2. Khong co su co nao.'
);

-- CR-M3-1006: completed examination
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uLecturer2, 'CR-M3-1006', '2026-02-20 14:00:00', '2026-02-20 17:00:00',
    'examination', 115, 'completed',
    @uManager1, '2026-02-14 09:15:00', 'Thi giua ky. Suc chua phong du. Khong can them ban.',
    '2026-02-20 13:45:00', @uStaff2, 'De thi dat len ban. May chieu hien thi huong dan.',
    '2026-02-20 17:20:00', @uStaff1, 'Phong da don. Da thu bai thi va giay nham.',
    'Mon CS 240 giua ky. 112 sinh vien du thi, 3 vang mat.'
);

-- CR-M3-1006: approved future booking
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note
) VALUES (
    @uLecturer1, 'CR-M3-1006', '2026-07-10 10:00:00', '2026-07-10 12:00:00',
    'seminar', 40, 'approved',
    @uManager2, '2026-06-25 11:00:00', 'Hoi thao cao hoc. Da duyet. Neu hoc hon hop hay cau hinh phong truc tiep.'
);

-- CR-M3-1006: pending (default status, no decision yet)
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants
) VALUES (
    @uTA1, 'CR-M3-1006', '2026-08-05 13:00:00', '2026-08-05 16:00:00',
    'workshop', 25
);

-- CR-M3-1006: cancelled
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status
) VALUES (
    @uStudent, 'CR-M3-1006', '2026-03-01 09:00:00', '2026-03-01 10:00:00',
    'meeting', 10, 'cancelled'
);

-- CR-M3-1006: no-show
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status
) VALUES (
    @uTA2, 'CR-M3-1006', '2026-04-05 15:00:00', '2026-04-05 17:00:00',
    'student_activity', 10, 'no_show'
);

-- CL-DC-2585: completed lab lecture
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uLecturer2, 'CL-DC-2585', '2026-01-20 10:00:00', '2026-01-20 12:00:00',
    'lecture', 35, 'completed',
    @uManager1, '2026-01-14 16:00:00', 'Buoi thuc hanh CS 246. Da kiem tra bo cong cu truoc.',
    '2026-01-20 09:50:00', @uStaff1, '40 may deu khoi dong duoc. GCC 12.3 xac nhan.',
    '2026-01-20 12:10:00', @uStaff1, 'Hai may hang D bi treo, da bao bo phan IT. Con lai sach.',
    'CS 246 bai thuc hanh 2. Sinh vien hoan thanh bai tap ke thua.'
);

-- CL-DC-2585: approved administrative event
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note
) VALUES (
    @uAdmin1, 'CL-DC-2585', '2026-07-15 09:00:00', '2026-07-15 13:00:00',
    'administrative_event', 15, 'approved',
    @uManager2, '2026-07-01 10:30:00', 'Hop hoi dong khoa. Da duyet. Yeu cau tiec da gui dich vu.'
);

-- CL-DC-2585: back-to-back approved (13:00 end = 14:00 start, no overlap)
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note
) VALUES (
    @uTA1, 'CL-DC-2585', '2026-07-15 14:00:00', '2026-07-15 17:00:00',
    'workshop', 20, 'approved',
    @uManager1, '2026-07-02 09:00:00', 'Hoi thao Git va CI/CD cho tro giang. Da duyet.'
);

-- CL-DC-2585: pending far in the future
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants
) VALUES (
    @uLecturer1, 'CL-DC-2585', '2026-09-01 09:00:00', '2026-09-01 11:00:00',
    'lecture', 30
);

-- AUD-MC-1000: completed large seminar
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uLecturer2, 'AUD-MC-1000', '2026-02-01 08:00:00', '2026-02-01 12:00:00',
    'seminar', 300, 'completed',
    @uManager2, '2026-01-25 15:00:00', 'Hoi nghi khoa hoc nam 2026. Da duyet, nguoi phu trach am thanh da biet.',
    '2026-02-01 07:30:00', @uStaff2, 'Micro va thiet bi phat truc tiep da chay. Den san khau ok.',
    '2026-02-01 12:35:00', @uStaff2, 'Thiet bi da tat va cat. Phong sach. Mot ghe gay hang G da bao.',
    'Hoi nghi khoa hoc 2026. 287 nguoi tham du. 4 phien chinh. Da luu livestream.'
);

-- AUD-MC-1000: future approved examination
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note
) VALUES (
    @uLecturer1, 'AUD-MC-1000', '2026-08-20 09:00:00', '2026-08-20 12:00:00',
    'examination', 450, 'approved',
    @uManager1, '2026-07-15 09:00:00', 'Thi cuoi ky CS 350. Suc chua 500, yeu cau 450 ghe.'
);

-- AUD-MC-1000: rejected with explicit rejection reason
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note, rejection_reason
) VALUES (
    @uLecturer2, 'AUD-MC-1000', '2026-06-15 10:00:00', '2026-06-15 12:00:00',
    'lecture', 200, 'rejected',
    @uManager2, '2026-06-08 15:45:00', 'Trung lich bao tri dieu hoa cua toa nha.',
    'Xung dot lich bao tri: kiem tra HVAC 2026-06-15 06:00-14:00. Vui long dat lai ngay khac.'
);

-- PL-DC-3564 (in_use space): approved workshop
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note
) VALUES (
    @uTA2, 'PL-DC-3564', '2026-08-10 09:00:00', '2026-08-10 17:00:00',
    'workshop', 20, 'approved',
    @uManager1, '2026-07-20 13:00:00', 'Hoi thao review do an. Thiet bi mau da san sang cho 8 nhom.'
);

-- PL-DC-3564: checked-in booking on in_use space
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition
) VALUES (
    @uTA2, 'PL-DC-3564', '2026-07-02 09:00:00', '2026-07-02 17:00:00',
    'workshop', 20, 'checked_in',
    @uManager1, '2026-06-29 13:00:00', 'Hoi thao review do an. Thiet bi mau da san sang.',
    '2026-07-02 09:15:00', @uStaff1, 'Phong sach, thiet bhi mau day du, may da khoi dong.'
);

-- MR-DC-3102: completed small meeting
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uAdmin1, 'MR-DC-3102', '2026-01-10 11:00:00', '2026-01-10 12:00:00',
    'meeting', 8, 'completed',
    @uManager2, '2026-01-08 10:00:00', 'Hop ke hoach khoa. Thoi gian ngan, thiet lap chuan.',
    '2026-01-10 10:55:00', @uStaff1, 'He thong hop video chay tot. Bang trang sach, co but.',
    '2026-01-10 12:02:00', @uStaff1, 'Phong gon gang. Da tat he thong hop video.',
    'Hop ke hoach hoc ky. Bieu quyet thong qua. Khong co su co thiet bi.'
);

-- MR-DC-3102: rejected (capacity too small)
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note, rejection_reason
) VALUES (
    @uStudent, 'MR-DC-3102', '2026-06-10 14:00:00', '2026-06-10 16:00:00',
    'lecture', 60, 'rejected',
    @uManager1, '2026-06-04 11:30:00', 'Phong MR-DC-3102 chi chua duoc 20 cho.',
    'Suc chua phong khong du: MR-DC-3102 chi 20 cho trong khi yeu cau 60 nguoi. Can phong lon hon.'
);

-- MR-DC-3102: pending administrative meeting
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants
) VALUES (
    @uAdmin1, 'MR-DC-3102', '2026-07-20 13:00:00', '2026-07-20 15:00:00',
    'administrative_event', 12
);

-- SW-STC-0010: completed student activity
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uStudent, 'SW-STC-0010', '2026-03-15 14:00:00', '2026-03-15 18:00:00',
    'student_activity', 45, 'completed',
    @uManager1, '2026-03-10 10:00:00', 'Hackathon cua Doi Cong nghe. Da duyet gio mo rong.',
    '2026-03-15 13:50:00', @uStaff2, 'Khu sach, da phat o cam dien. Wifi on dinh cho 50 may.',
    '2026-03-15 18:15:00', @uStaff2, 'Khu da xep lai. Da thu o cam. Mot but bang he.',
    'Hackathon Xuan 2026. 42 nguoi tham du. 3 du an demo.'
);

-- SW-STC-0010: cancelled student activity (suspended user historical)
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status
) VALUES (
    @uSuspended, 'SW-STC-0010', '2026-05-01 09:00:00', '2026-05-01 17:00:00',
    'student_activity', 50, 'cancelled'
);

-- CR-DC-1302: completed guest lecture
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status,
    decision_staff_id, decision_time, decision_note,
    actual_start_time, check_in_staff_id, initial_condition,
    actual_end_time, completion_staff_id, final_condition, usage_notes
) VALUES (
    @uLecturer1, 'CR-DC-1302', '2026-04-10 09:00:00', '2026-04-10 11:30:00',
    'lecture', 75, 'completed',
    @uManager1, '2026-04-05 13:00:00', 'Bai giang khach moi. Da xep cho giu xe cho dien gia.',
    '2026-04-10 08:50:00', @uStaff1, 'Bang thong minh da hieu chinh. Laptop khach ket noi tot.',
    '2026-04-10 11:35:00', @uStaff1, 'Thiet bi an toan. Phong sach. Day HDMI hoi long da bao.',
    'Bai giang khach cua GS. Richter ve Phuong phap kiem chung. 68 nguoi. Rat hieu qua.'
);

-- CR-DC-1302: minimum participants = 1 (boundary)
INSERT INTO dbo.BOOKING (
    requester_id, space_code, requested_start_time, requested_end_time,
    purpose, expected_participants
) VALUES (
    @uTA2, 'CR-DC-1302', '2026-08-25 15:00:00', '2026-08-25 16:00:00',
    'meeting', 1
);

-- ============================================================================
-- 7. MAINTENANCE_RECORD (5 demo records; Phase 2: impact_level)
-- ============================================================================
INSERT INTO dbo.MAINTENANCE_RECORD (
    space_code, reporter_id, assigned_staff_id,
    problem_description, start_time, status, impact_level
) VALUES (
    'CL-MC-3003', @uLecturer2, @uStaff1,
    'Dieu hoa khong lam lanh du. Nhiet do vuot 28C, phong khong dung duoc cho lop hoc.',
    '2026-06-20 08:00:00', 'reported', 'out-of-service'
);

INSERT INTO dbo.MAINTENANCE_RECORD (
    space_code, reporter_id, assigned_staff_id,
    problem_description, start_time, status, impact_level
) VALUES (
    'CL-MC-3003', @uStaff2, @uStaff1,
    'Mot so may hang C khong POST duoc. Nghi RAM loi - may keu beep khi khoi dong.',
    '2026-06-25 09:00:00', 'in_progress', 'out-of-service'
);

-- NULL assigned_staff_id (nullable FK test)
INSERT INTO dbo.MAINTENANCE_RECORD (
    space_code, reporter_id, assigned_staff_id,
    problem_description, start_time, status, impact_level
) VALUES (
    'CR-M3-1006', @uStaff2, NULL,
    'Bong den may chieu mo, nhap nhay khi chieu. Chat luong anh kem.',
    '2026-06-26 14:00:00', 'reported', 'advisory'
);

-- Completed with all required fields
INSERT INTO dbo.MAINTENANCE_RECORD (
    space_code, reporter_id, assigned_staff_id,
    problem_description, start_time, completion_time, status, result_note, impact_level
) VALUES (
    'AUD-MC-1000', @uManager1, @uStaff2,
    'Kenh am thanh 2 khong nhan tin hieu khi phat truc tiep.',
    '2026-06-01 10:00:00', '2026-06-22 16:00:00', 'completed',
    'Da thay jack XLR loi. Hieu chinh am thanh day du. 4 kenh hoat dong. Lich bao tri quy xac lap lai.',
    'advisory'
);

INSERT INTO dbo.MAINTENANCE_RECORD (
    space_code, reporter_id, assigned_staff_id,
    problem_description, start_time, status, impact_level
) VALUES (
    'MR-DC-3102', @uAdmin1, @uStaff1,
    'Dau doc the truoc cua khong phan hoi. Khoa co khong mo duoc, chi dung chia khoa co.',
    '2026-06-27 07:00:00', 'reported', 'advisory'
);

-- ============================================================================
-- 8. SPACE_FACILITY (junction; typical assignments per space type)
-- ============================================================================
-- AUD-MC-1000 (auditorium)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('AUD-MC-1000', @fProj);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('AUD-MC-1000', @fMic);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('AUD-MC-1000', @fLive);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('AUD-MC-1000', @fAC);
-- CR-M3-1006 (classroom)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CR-M3-1006', @fProj);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CR-M3-1006', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CR-M3-1006', @fAC);
-- CR-DC-1302 (classroom)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CR-DC-1302', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CR-DC-1302', @fSmart);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CR-DC-1302', @fAC);
-- CL-DC-2585 (computer lab)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-DC-2585', @fProj);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-DC-2585', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-DC-2585', @fPC);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-DC-2585', @fAC);
-- CL-MC-3003 (computer lab, under maintenance)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-MC-3003', @fProj);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-MC-3003', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-MC-3003', @fPC);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('CL-MC-3003', @fAC);
-- PL-DC-3564 (project lab)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('PL-DC-3564', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('PL-DC-3564', @fPC);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('PL-DC-3564', @fAC);
-- MR-DC-3102 (meeting room)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-DC-3102', @fProj);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-DC-3102', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-DC-3102', @fVC);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-DC-3102', @fAC);
-- MR-MC-4040 (temporarily closed)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-MC-4040', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-MC-4040', @fSmart);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-MC-4040', @fAC);
-- SW-STC-0010 (student workspace)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('SW-STC-0010', @fWB);
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('SW-STC-0010', @fAC);
-- MR-DC-1315 (retired, boundary capacity, minimal facilities)
INSERT INTO dbo.SPACE_FACILITY (space_code, facility_id) VALUES ('MR-DC-1315', @fAC);

PRINT 'Demo data re-seeded.';

-- ============================================================================
-- 9. Verify the reset + reseed
-- ============================================================================
CREATE TABLE #demo_verification (
    tbl VARCHAR(100) NOT NULL,
    rows_now BIGINT NOT NULL
);

INSERT INTO #demo_verification (tbl, rows_now)
SELECT 'ROLE'               AS tbl, COUNT_BIG(*) AS rows_now FROM dbo.ROLE
UNION ALL SELECT 'DEPARTMENT'      , COUNT_BIG(*) FROM dbo.DEPARTMENT
UNION ALL SELECT 'SEMESTER'        , COUNT_BIG(*) FROM dbo.SEMESTER
UNION ALL SELECT 'USAGE_POLICY'    , COUNT_BIG(*) FROM dbo.USAGE_POLICY
UNION ALL SELECT 'USER'            , COUNT_BIG(*) FROM dbo.[USER]
UNION ALL SELECT 'SPACE'           , COUNT_BIG(*) FROM dbo.SPACE
UNION ALL SELECT 'FACILITY'        , COUNT_BIG(*) FROM dbo.FACILITY
UNION ALL SELECT 'BOOKING'         , COUNT_BIG(*) FROM dbo.BOOKING
UNION ALL SELECT 'MAINTENANCE_RECORD', COUNT_BIG(*) FROM dbo.MAINTENANCE_RECORD
UNION ALL SELECT 'SPACE_FACILITY'  , COUNT_BIG(*) FROM dbo.SPACE_FACILITY
UNION ALL SELECT 'ROLE_USAGE_POLICY', COUNT_BIG(*) FROM dbo.ROLE_USAGE_POLICY
UNION ALL SELECT 'DEPARTMENT_USAGE_POLICY', COUNT_BIG(*) FROM dbo.DEPARTMENT_USAGE_POLICY
UNION ALL SELECT 'ACKNOWLEDGEMENT' , COUNT_BIG(*) FROM dbo.ACKNOWLEDGEMENT;

SELECT 'RESEED' AS phase, tbl, rows_now
FROM #demo_verification
ORDER BY tbl;

DROP TABLE #demo_verification;

PRINT 'All data removed; demo sample re-seeded. Database is ready for reuse.';
