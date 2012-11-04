/*
    SQLToolKit/Sequence 1.0.2g
	Copyright Federico Razzoli 2012
	
	This file is part of SQLToolKit/Sequence.
	
    SQLToolKit/Sequence is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by
    the Free Software Foundation, version 3 of the License.
	
    SQLToolKit/Sequence is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.
	
    You should have received a copy of the GNU Affero General Public License
    along with SQLToolKit/Sequence.  If not, see <http://www.gnu.org/licenses/>.
*/

/*
	Tests STK/Sequence using STK/Unit:
	https://github.com/santec/STK-Unit
*/


-- create & select db
CREATE DATABASE IF NOT EXISTS `test_stk_sequence`;
USE `test_stk_sequence`;


DELIMITER ||


DROP PROCEDURE IF EXISTS `before_all_tests`;
DROP PROCEDURE IF EXISTS `set_up`;
DROP PROCEDURE IF EXISTS `tear_down`;
DROP PROCEDURE IF EXISTS `after_all_tests`;


-- Magic Routines

CREATE PROCEDURE set_up()
	LANGUAGE SQL
BEGIN
	-- drop all sequences
	TRUNCATE TABLE `stk_sequence`.`SEQUENCES`;
END;


CREATE PROCEDURE after_all_tests()
	LANGUAGE SQL
BEGIN
	-- drop all sequences
	TRUNCATE TABLE `stk_sequence`.`SEQUENCES`;
END;


-- Test Routines


DROP PROCEDURE IF EXISTS `test_installation`;
CREATE PROCEDURE test_installation()
	LANGUAGE SQL
	COMMENT 'Test that everything is installed'
BEGIN
	CALL `stk_unit`.`assert_table_exists`('stk_sequence', 'SEQUENCES', 'Table SEQUENCES not found');
	CALL `stk_unit`.`assert_routine_exists`('stk_sequence', 'sequence_create', 'Routine sequence_create not found');
END;


DROP PROCEDURE IF EXISTS `test_sequence_create`;
CREATE PROCEDURE test_sequence_create()
	LANGUAGE SQL
	COMMENT 'Test sequence_create, sequence_get'
BEGIN
	-- variables to be passed to sequence_get()
	DECLARE s_inc      BIGINT;
	DECLARE s_min      BIGINT;
	DECLARE s_max      BIGINT;
	DECLARE s_cycle    BOOL;
	DECLARE s_comment  TEXT;
	
	-- all values explicit
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, TRUE, 150, 'X');
	CALL `stk_sequence`.sequence_get('my_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      10,      'my_sequence: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      100,     'my_sequence: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      350,     'my_sequence: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    TRUE,    'my_sequence: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  'X',
		CONCAT('my_sequence: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
	
	-- test default values for ASC sequence
	CALL `stk_sequence`.sequence_create('asc_sequence', NULL, NULL, NULL, NULL, NULL, 'asc');
	CALL `stk_sequence`.sequence_get('asc_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      1,      'my_sequence: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      1,      'my_sequence: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      9223372036854775807 - 1, 'my_sequence: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    FALSE,   'my_sequence: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  'asc',
		CONCAT('my_sequence: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
	
	-- test default values for DESC sequence
	CALL `stk_sequence`.sequence_create('desc_sequence', -1, NULL, NULL, NULL, NULL, 'desc');
	CALL `stk_sequence`.sequence_get('desc_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      -1,      'my_sequence: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      -9223372036854775807 - -1,     'my_sequence: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      -1,      'my_sequence: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    FALSE,   'my_sequence: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  'desc',
		CONCAT('my_sequence: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
	
	-- non-existing sequence
	CALL `stk_unit`.expect_any_exception();
	CALL `stk_sequence`.sequence_get('not-exists', s_inc, s_min, s_max, s_cycle, s_comment);
END;


DROP PROCEDURE IF EXISTS `test_sequence_alter`;
CREATE PROCEDURE test_sequence_alter()
	LANGUAGE SQL
	COMMENT 'Test sequence_create, sequence_get'
BEGIN
	-- variables to be passed to sequence_get()
	DECLARE s_inc      BIGINT;
	DECLARE s_min      BIGINT;
	DECLARE s_max      BIGINT;
	DECLARE s_cycle    BOOL;
	DECLARE s_comment  TEXT;
	
	-- create sequence
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, TRUE, 150, 'X');
	
	-- all values untouched
	CALL `stk_sequence`.sequence_alter('my_sequence', NULL, NULL, NULL, NULL, NULL);
	CALL `stk_sequence`.sequence_get('my_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      10,      'case1: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      100,     'case1: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      350,     'case1: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    TRUE,    'case1: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  'X',
		CONCAT('case1: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
	
	-- touch only comment
	-- (test 1 value)
	CALL `stk_sequence`.sequence_alter('my_sequence', NULL, NULL, NULL, NULL, '');
	CALL `stk_sequence`.sequence_get('my_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      10,      'case2: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      100,     'case2: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      350,     'case2: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    TRUE,    'case2: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  '',
		CONCAT('case2: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
	
	-- touch all but comment
	-- (test mixed touch/untouch with more than 1 value modified)
	CALL `stk_sequence`.sequence_alter('my_sequence', 1, 0, 100, FALSE, NULL);
	CALL `stk_sequence`.sequence_get('my_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      1,       'case3: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      0,       'case3: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      100,     'case3: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    FALSE,   'case3: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  '',
		CONCAT('case3: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
	
	-- touch all
	-- (test complete list)
	CALL `stk_sequence`.sequence_alter('my_sequence', -1, -100, 0, TRUE, 'comm');
	CALL `stk_sequence`.sequence_get('my_sequence', s_inc, s_min, s_max, s_cycle, s_comment);
	CALL `stk_unit`.assert_equals(s_inc,      -1,      'case4: wrong s_inc');
	CALL `stk_unit`.assert_equals(s_min,      -100,    'case4: wrong s_min');
	CALL `stk_unit`.assert_equals(s_max,      0,       'case4: wrong s_max');
	CALL `stk_unit`.assert_equals(s_cycle,    TRUE,    'case4: wrong s_cycle');
	CALL `stk_unit`.assert_equals(s_comment,  'comm',
		CONCAT('case4: wrong s_comment, got: ', IFNULL(s_comment, 'NULL')));
END;


DROP PROCEDURE IF EXISTS `test_duplicate_sequence`;
CREATE PROCEDURE test_duplicate_sequence()
	LANGUAGE SQL
	COMMENT 'Test sequence_create'
BEGIN
	-- create
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, FALSE, 150, 'X');
	-- create again
	CALL `stk_unit`.expect_any_exception();
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, FALSE, 150, 'X');
END;


DROP PROCEDURE IF EXISTS `test_sequence_exists`;
CREATE PROCEDURE test_sequence_exists()
	LANGUAGE SQL
	COMMENT 'Test sequence_exists'
BEGIN
	DECLARE res BOOL;
	
	-- exists
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, FALSE, 150, 'X');
	SET res = `stk_sequence`.sequence_exists('my_sequence');
	CALL `stk_unit`.assert_true(res, 'Sequence exists');
	
	-- not exists
	SET res = `stk_sequence`.sequence_exists('not-exists');
	CALL `stk_unit`.assert_false(res, 'Sequence does not exist');
END;


DROP PROCEDURE IF EXISTS `test_sequence_drop`;
CREATE PROCEDURE test_sequence_drop()
	LANGUAGE SQL
	COMMENT 'Test sequence_exists_drop'
BEGIN
	DECLARE res BOOL;
	
	-- create sequence, drop, and check that not exists
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, FALSE, 150, 'X');
	CALL `stk_sequence`.sequence_drop('my_sequence');
	SET res = `stk_sequence`.sequence_exists('not-exists');
	CALL `stk_unit`.assert_false(res, 'Sequence has not been dropped');
END;


DROP PROCEDURE IF EXISTS `test_sequence_rename`;
CREATE PROCEDURE test_sequence_rename()
	LANGUAGE SQL
	COMMENT 'Test test_sequence_rename'
BEGIN
	DECLARE res BOOL;
	
	-- create sequence, drop, and check that not exists
	CALL `stk_sequence`.sequence_create('my_sequence', 10, 100, 350, FALSE, 150, 'X');
	CALL `stk_sequence`.sequence_rename('my_sequence', 'your_sequence');
	
	-- old name must not exist anymore
	SET res = `stk_sequence`.sequence_exists('my_sequence');
	CALL `stk_unit`.assert_false(res, 'Old name still exists');
	
	-- new name must exist
	SET res = `stk_sequence`.sequence_exists('your_sequence');
	CALL `stk_unit`.assert_true(res, 'New name does not exist');
	
	-- duplicate error
	CALL `stk_sequence`.sequence_create('her_sequence', 10, 100, 350, FALSE, 150, 'X');
	CALL `stk_unit`.expect_any_exception();
	CALL `stk_sequence`.sequence_rename('your_sequence', 'her_sequence');
END;


DROP PROCEDURE IF EXISTS `test_setval`;
CREATE PROCEDURE test_setval()
	LANGUAGE SQL
	COMMENT 'Test setval'
BEGIN
	DECLARE res BIGINT SIGNED;
	
	CALL `stk_sequence`.sequence_create('my_sequence', 1, 1, 100, FALSE, 1, '');
	DO `stk_sequence`.`nextval`('my_sequence'); -- 1
	
	-- set to 10, is_called = TRUE
	SET res = `stk_sequence`.`setval`('my_sequence', 10, TRUE);
	-- test returned value
	CALL `stk_unit`.assert_equals(res, 10, 'setval: does not return 2nd arg');
	-- test that last called value is now 10
	CALL `stk_unit`.assert_equals(`stk_sequence`.`currval`('my_sequence'), 10,
		'setval (is_called=true): currval does not match');
	
	-- set to 20, is_called = FALSE
	SET res = `stk_sequence`.`setval`('my_sequence', 20, FALSE);
	-- test that last called value is still 10
	CALL `stk_unit`.assert_equals(`stk_sequence`.`currval`('my_sequence'), 10,
		'setval (is_called=false): first currval does not match');
	-- test advancement
	DO `stk_sequence`.`nextval`('my_sequence');
	CALL `stk_unit`.assert_equals(`stk_sequence`.`currval`('my_sequence'), 20,
		'setval (is_called=false): second currval does not match');
	
	-- test incorrect params
	CALL `stk_unit`.expect_any_exception();
	DO `stk_sequence`.`setval`('my_sequence', 10, NULL);
END;


DROP PROCEDURE IF EXISTS `test_nextval_increment`;
CREATE PROCEDURE test_nextval_increment()
	LANGUAGE SQL
	COMMENT 'Test normal increment, not rotation'
BEGIN
	-- positive inc
	CALL `stk_sequence`.sequence_create('my_sequence',
		2,      -- increment
		0,      -- min
		100,    -- max
		TRUE,   -- rotate
		0,      -- start
		'');
	
	-- test initial value
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	CALL `stk_unit`.assert_equals(@val, 0,
		CONCAT('nextval: value does not match; expected 0, got: ', IFNULL(@val, 'NULL')));
	
	-- test ASC increment
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	CALL `stk_unit`.assert_equals(@val, 2,
		CONCAT('nextval: value does not match; expected 2, got: ', IFNULL(@val, 'NULL')));
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	CALL `stk_unit`.assert_equals(@val, 4,
		CONCAT('nextval: value does not match; expected 4, got: ', IFNULL(@val, 'NULL')));
	
	-- negative inc
	CALL `stk_sequence`.sequence_create('your_sequence',
		-10,    -- increment
		-100,   -- min
		5,      -- max
		TRUE,   -- rotate
		5,      -- start
		'');
	
	-- test initial value
	SET @val = `stk_sequence`.`nextval`('your_sequence');
	CALL `stk_unit`.assert_equals(@val, 5,
		CONCAT('nextval: value does not match; expected 5, got: ', IFNULL(@val, 'NULL')));
	
	-- test DESC increment
	SET @val = `stk_sequence`.`nextval`('your_sequence');
	CALL `stk_unit`.assert_equals(@val, -5,
		CONCAT('nextval: value does not match; expected -5, got: ', IFNULL(@val, 'NULL')));
	SET @val = `stk_sequence`.`nextval`('your_sequence');
	CALL `stk_unit`.assert_equals(@val, -15,
		CONCAT('nextval: value does not match; expected -15, got: ', IFNULL(@val, 'NULL')));
	
END;


DROP PROCEDURE IF EXISTS `test_nextval_start`;
CREATE PROCEDURE test_nextval_start()
	LANGUAGE SQL
	COMMENT 'Test nextval - start param'
BEGIN
	-- test explicit assignment
	CALL `stk_sequence`.sequence_create('my_sequence',
		1,      -- increment
		1,      -- min
		100,    -- max
		TRUE,   -- rotate
		10,     -- start
		'');
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	CALL `stk_unit`.assert_equals(@val, 10,
		CONCAT('nextval: value does not match; expected 10, got: ', IFNULL(@val, 'NULL')));
	
	-- test default for ASC sequence
	CALL `stk_sequence`.sequence_create('our_sequence',
		1,      -- increment
		1,      -- min
		100,    -- max
		TRUE,   -- rotate
		NULL,   -- start
		'');
	SET @val = `stk_sequence`.`nextval`('our_sequence');
	CALL `stk_unit`.assert_equals(@val, 1,
		CONCAT('nextval: value does not match; expected 1, got: ', IFNULL(@val, 'NULL')));
	
	-- test default for DESC sequence
	CALL `stk_sequence`.sequence_create('her_sequence',
		-1,     -- increment
		1,      -- min
		100,    -- max
		TRUE,   -- rotate
		NULL,   -- start
		'');
	SET @val = `stk_sequence`.`nextval`('her_sequence');
	CALL `stk_unit`.assert_equals(@val, 100,
		CONCAT('nextval: value does not match; expected 100, got: ', IFNULL(@val, 'NULL')));
END;


DROP PROCEDURE IF EXISTS `test_nextval_rotation`;
CREATE PROCEDURE test_nextval_rotation()
	LANGUAGE SQL
	COMMENT 'Test nextval - rotation'
BEGIN
	-- ASC
	CALL `stk_sequence`.sequence_create('my_sequence',
		3,     -- increment
		10,    -- min
		15,    -- max
		TRUE,  -- rotate
		10,    -- start
		'');
	
	-- advance to 13
	SET @val = `stk_sequence`.`nextval`('my_sequence'); -- 10
	SET @val = `stk_sequence`.`nextval`('my_sequence'); -- 13
	CALL `stk_unit`.assert_equals(@val, 13,
		CONCAT('nextval: value does not match; expected 13, got: ', IFNULL(@val, 'NULL')));
	
	-- test ASC rotation
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	CALL `stk_unit`.assert_equals(@val, 10,
		CONCAT('nextval: value does not match; after rotation expected 10, got: ', IFNULL(@val, 'NULL')));
	
	-- DESC
	CALL `stk_sequence`.sequence_create('their_sequence',
		-3,     -- increment
		-15,    -- min
		-10,    -- max
		TRUE,   -- rotate
		-10,    -- start
		'');
	
	-- advance to -13
	SET @val = `stk_sequence`.`nextval`('their_sequence'); --  -10
	SET @val = `stk_sequence`.`nextval`('their_sequence'); --  -13
	CALL `stk_unit`.assert_equals(@val, -13,
		CONCAT('nextval: value does not match; expected -13, got: ', IFNULL(@val, 'NULL')));
	
	-- test DESC rotation
	SET @val = `stk_sequence`.`nextval`('their_sequence');
	CALL `stk_unit`.assert_equals(@val, -10,
		CONCAT('nextval: value does not match; after rotation expected -10, got: ', IFNULL(@val, 'NULL')));
	
	-- redundant... i know
	CALL `stk_sequence`.sequence_create('her_sequence',
		-5,     -- increment
		-50,    -- min
		-10,    -- max
		TRUE,   -- rotate
		-50,    -- start
		'');
	SET @val = `stk_sequence`.`nextval`('her_sequence'); --  -50
	SET @val = `stk_sequence`.`nextval`('her_sequence'); --  -14
	CALL `stk_unit`.assert_equals(@val, -14,
		CONCAT('nextval: value does not match; after rotation expected -14, got: ', IFNULL(@val, 'NULL')));
END;


DROP PROCEDURE IF EXISTS `test_nextval_no_rotation_asc`;
CREATE PROCEDURE test_nextval_no_rotation_asc()
	LANGUAGE SQL
	COMMENT 'Test nextval - rotation not allowed, ASC sequence'
BEGIN
	CALL `stk_sequence`.sequence_create('my_sequence',
		100,    -- increment
		1,      -- min
		1000,   -- max
		FALSE,  -- rotate
		999,    -- start
		'');
	
	SET @val = `stk_sequence`.`nextval`('my_sequence'); -- 999
	CALL `stk_unit`.`expect_any_exception`();
	SET @val = `stk_sequence`.`nextval`('my_sequence');
END;


DROP PROCEDURE IF EXISTS `test_nextval_no_rotation_desc`;
CREATE PROCEDURE test_nextval_no_rotation_desc()
	LANGUAGE SQL
	COMMENT 'Test nextval - rotation not allowed, DESC sequence'
BEGIN
	CALL `stk_sequence`.sequence_create('my_sequence',
		-100,   -- increment
		1000,   -- min
		1,      -- max
		FALSE,  -- rotate
		5,      -- start
		'');
	
	SET @val = `stk_sequence`.`nextval`('my_sequence'); -- 5
	CALL `stk_unit`.`expect_any_exception`();
	SET @val = `stk_sequence`.`nextval`('my_sequence');
END;


DROP PROCEDURE IF EXISTS `test_currval`;
CREATE PROCEDURE test_currval()
	LANGUAGE SQL
	COMMENT 'Test currval'
BEGIN
	-- destroy log
	DROP TEMPORARY TABLE IF EXISTS `stk_sequence`.`sequence_session_log`;
	
	-- test when log not exists
	SET @val = `stk_sequence`.`currval`('my_sequence');
	CALL `stk_unit`.assert_null(@val,
		CONCAT('currval: expected NULL, got: ', IFNULL(@val, 'NULL')));
	
	-- test for called value
	CALL `stk_sequence`.sequence_create('my_sequence', 1, 1, 100, TRUE, 1, 'X');
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	SET @val = `stk_sequence`.`currval`('my_sequence');
	CALL `stk_unit`.assert_equals(@val, 1,
		CONCAT('currval: expected 1, got: ', IFNULL(@val, 'NULL')));
	
	-- test for not-existing sequence:
	-- no exception expected
	SET @val = `stk_sequence`.`currval`('not-exist');
	CALL `stk_unit`.assert_null(@val,
		CONCAT('currval: expected NULL, got: ', IFNULL(@val, 'NULL')));
END;

DROP PROCEDURE IF EXISTS `test_lastval`;
CREATE PROCEDURE test_lastval()
	LANGUAGE SQL
	COMMENT 'Test lastval'
BEGIN
	-- WARNING: with stk_unit, there is no way to check that this routine is thread-safe
	
	-- destroy log
	DROP TEMPORARY TABLE IF EXISTS `stk_sequence`.`sequence_session_log`;
	
	-- test when log not exists
	SET @val = `stk_sequence`.`lastval`();
	CALL `stk_unit`.assert_null(@val,
		CONCAT('lastval: expected NULL, got: ', IFNULL(@val, 'NULL')));
	
	-- test for called value
	CALL `stk_sequence`.sequence_create('my_sequence', 1, 1, 100, TRUE, 1, 'X');
	SET @val = `stk_sequence`.`nextval`('my_sequence');
	SET @val = `stk_sequence`.`lastval`();
	CALL `stk_unit`.assert_equals(@val, 1,
		CONCAT('lastval: expected 1, got: ', IFNULL(@val, 'NULL')));
END;

DROP PROCEDURE IF EXISTS `test_get_version`;
CREATE PROCEDURE test_get_version()
	LANGUAGE SQL
	COMMENT 'Test get_version'
BEGIN
	CALL `stk_unit`.assert_true(`stk_sequence`.`get_version`() LIKE BINARY 'STK/Sequence %.%.%',
		'get_version() does not return a proper string');
END;

||

DELIMITER ;

