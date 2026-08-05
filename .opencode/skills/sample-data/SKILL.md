---
name: sample-data
description: Generate comprehensive sample data preparation SQL scripts (INSERT statements) to support testing of normal operations and important exceptional cases. Use this skill to populate a database schema with realistic data.
---

# Sample Data Preparation

## Purpose
This skill guides the agent in generating a realistic, purpose-built dataset to populate a database schema for testing. The generated SQL INSERT statements must cover standard, day-to-day operations as well as important edge cases and exceptions, ensuring the database constraints and business logic can be thoroughly validated.

## When to use
Use this skill when:
- the user provides a database schema (DDL) and asks for sample data.
- the user asks to insert realistic sample data to support testing.
- the task is specifically focused on "Sample Data Preparation" or generating INSERT scripts.

Do not use this skill when:
- the user asks for Database Schema Definition (DDL) generation.
- the user wants to execute queries to analyze data (DQL).

## Inputs
The agent should expect:
- The finalized SQL Schema (DDL) including tables, data types, constraints, and relationships.
- Business requirements or logical design documents detailing valid data rules.
- Specific scenarios for edge cases requested by the user.

## Workflow

### Step 1: Analyze Dependencies and Relationships
- Identify the topological sort order of the tables to ensure parent tables are populated before child tables (handling Foreign Keys).

### Step 2: Extract Business Constraints and Edge Cases
- Scan the provided DDL/Schema for all formal restrictions: `CHECK` constraints, `UNIQUE` constraints, `DEFAULT` values, and `TRIGGER` enforcement (e.g., overlapping dates, availability statuses).
- Cross-reference with the provided business requirements to identify conceptual rules.
- Explicitly list the boundary conditions and edge cases that need testing for these constraints.

### Step 3: Formulate Data Generation Strategy
- Plan a cohesive narrative for the data (e.g., realistic names, dates, amounts).
- Design standard data representing normal operations (the "happy path").
- Map the constraints identified in Step 2 to target rows that will test these exceptional cases (e.g., values right on the edge of failing a constraint, complex multi-table relationships).
Before this step, read `references/data-generation-guidelines.md`.

### Step 4: Generate SQL INSERT Statements
- Write the `INSERT INTO` statements in the correct dependency order.
- Group the statements by table.
- Include inline SQL comments separating normal operation data from exceptional case data.
- **Dynamic Identity Handling:** Do NOT hardcode IDs for `IDENTITY` columns and do NOT use `SET IDENTITY_INSERT`. Let the database auto-generate primary keys. Use T-SQL variables (e.g., `DECLARE @NewUserId INT;`) and `SCOPE_IDENTITY()` to capture newly generated IDs immediately after an insert, then use those variables for related child table insertions.
Before this step, read `references/sql-insert-syntax-guide.md`.

### Step 5: Write Scenario Documentation
- Create a bulleted list documenting the specific test cases embedded in the sample data.
- Detail exactly which constraint or business rule each exceptional case is designed to test.
- Clearly differentiate between "Normal Operations" scenarios and "Exceptional Cases" scenarios.

## Output template
Use this exact structure:

### 1. Sample Data SQL Script

```sql
-- Select your database if necessary (e.g., USE [DatabaseName];)

-- 1. [Parent Table Name 1]
-- Normal Operations
INSERT INTO [Table] (...) VALUES (...);
-- Exceptional Cases
INSERT INTO [Table] (...) VALUES (...);

-- 2. [Child Table Name 1]
...
```

### 2. Scenario Documentation

**Normal Operations Covered:**
* Scenario 1: [Explanation of which rows depict this and why]
* Scenario 2: [Explanation]

**Exceptional Cases Covered:**
* Scenario 1 (Edge Case/Exception): [Explanation of the rows and the intended test]
* Scenario 2 (Edge Case/Exception): [Explanation]

## Review checklist
Before finishing, read `references/sample-data-review-checklist.md` and verify:
- insertion order respects all Foreign Key dependencies.
- the data is realistic and avoids lazy placeholder text.
- both normal and exceptional scenarios are explicitly covered.

## High-volume generation mode

Use high-volume mode when the requested BOOKING population is 100,000 rows
or more.

In this mode:

- Generate a parameterized T-SQL data-generation program, not one literal
  INSERT per row.
- Use deterministic set-based generation with a fixed seed.
- Target the Phase 2 schema after the schema migration has been applied.
- Generate at least three complete academic years.
- Stage and validate data before loading it into the target tables.
- Generate cancellations, no-shows, maintenance records, advisory maintenance,
  acknowledgements, and booking-acknowledgement links.
- Provide executable assertions and negative tests.
- Provide before-and-after index benchmarks.
- Do not mark the task complete merely because the SQL compiles.
- The task is complete only after all assertions pass against SQL Server.

### Required scale parameters

The generated script must support:

- 100,000 bookings by default
- up to 500,000 bookings without changing the SQL source
- a deterministic seed
- configurable academic-year start
- configurable batch size

### Performance restrictions

Do not:

- emit hundreds of thousands of literal VALUES clauses
- use a cursor for large table generation
- execute one INSERT per generated booking
- benchmark indexed queries without first capturing an unindexed baseline