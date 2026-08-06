-- ============================================================================
-- High-volume sample-data test runner — Campus Space Management System (G09)
-- File: tests/sample-data/run-tests.sql
-- Purpose: End-to-end test runner for the high-volume dataset:
--   1. executes the generator (outputs/14-data-generator-G09/high-volume-sample-data-G09.sql)
--   2. runs the assertions  (tests/sample-data/assertions.sql)
--   3. runs the negative tests (tests/sample-data/negative-tests.sql)
-- Usage:
--   sqlcmd -b -i tests/sample-data/run-tests.sql
-- Exit code 0 = all phases passed; non-zero = a phase failed and aborted.
--
-- NOTE: this file is meant to be executed with sqlcmd (batch separator GO),
--       not inside SSMS's SQLCMD mode only — it relies on :r includes.
-- ============================================================================

:setvar DbName "CampusSpaceManagementSystem"

USE [$(DbName)];
GO

PRINT '============================================================';
PRINT 'Phase 1: high-volume sample-data generation';
PRINT '============================================================';
:r ..\..\outputs\14-data-generator-G09\high-volume-sample-data-G09.sql

PRINT '============================================================';
PRINT 'Phase 2: sample-data assertions';
PRINT '============================================================';
:r assertions.sql

PRINT '============================================================';
PRINT 'Phase 3: negative tests';
PRINT '============================================================';
:r negative-tests.sql

PRINT '============================================================';
PRINT 'ALL TEST PHASES COMPLETED SUCCESSFULLY';
PRINT '============================================================';
GO
