/*
    SQLToolKit/Sequence
	Copyright Federico Razzoli 2012 2013
	
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

SQLToolKit/Sequence implementation based on:
* http://www.postgresql.org/docs/9.2/static/sql-createsequence.html
* http://www.postgresql.org/docs/9.2/static/sql-altersequence.html
* http://www.postgresql.org/docs/9.2/static/sql-dropsequence.html
* http://www.postgresql.org/docs/9.2/static/functions-sequence.html

With the following exceptions:
* SEQUENCEs are global, not at database-level
* No TEMPORARY sequences
* Can't SELECT from a SEQUENCE
* currval() and lastval() dont throw errore - if no value, return NULL
* get() and exists()
* To CREATE, ALTER and DROP, use create(), alter(), rename(), drop()
** No OWNED BY clause
** No CACHE clause
* nextval() - 3rd param is not optional
* SEQUENCE's are transactional, so new values will rollback - if no newer value has been generated by another thread in the meanwhile

Bonus:
* Added SEQUENCES information table

*/


DELIMITER ||


-- create & select db
CREATE DATABASE IF NOT EXISTS `stk_sequence`;
USE `stk_sequence`;


CREATE TABLE IF NOT EXISTS `SEQUENCES`
(
	`SEQUENCE_NAME`  CHAR(64)         NOT NULL,
	`INCREMENT`      INTEGER SIGNED   NOT NULL           COMMENT 'Default: 1',
	`MINVALUE`       BIGINT SIGNED    NOT NULL           COMMENT 'Default: 0 or -9223372036854775808',
	`MAXVALUE`       BIGINT SIGNED    NOT NULL           COMMENT 'Default: 9223372036854775808 or -1',
	`CYCLE`          BOOLEAN          NOT NULL           COMMENT 'Default: FALSE; if TRUE, value can rotate',
	`START`          BIGINT SIGNED    NOT NULL           COMMENT 'First generated value. Default: min/max',
	`CURRVAL`        BIGINT SIGNED    NULL DEFAULT NULL  COMMENT 'Current value. Default: NULL',
	`COMMENT`        CHAR(64)         NOT NULL           COMMENT 'Use this column to comment a SEQUENCE',
	
	PRIMARY KEY (`SEQUENCE_NAME`)
)
	ENGINE = InnoDB
	DEFAULT CHARACTER SET = ascii
	DEFAULT COLLATE = ascii_bin
	COMMENT = 'Internal. Contains SEQUENCEs definition & status';


/**
 *	Administrative Routines
 */


DROP FUNCTION IF EXISTS `get_version`;
CREATE FUNCTION `get_version`()
	RETURNS CHAR(40)
	LANGUAGE SQL
	DETERMINISTIC
	NO SQL
	COMMENT 'Return version info'
BEGIN
	RETURN 'STK/Sequence 1.1.0g';
END;


DROP PROCEDURE IF EXISTS `install_lib`;
CREATE PROCEDURE `install_lib`()
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Execute this as root before using this lib'
BEGIN
	-- add obj user, who can access Internal objects
	IF NOT EXISTS (SELECT 1 FROM `mysql`.`user` WHERE `User` = 'obj_stk_sequence') THEN
		CREATE USER 'obj_stk_sequence'@'localhost';
	END IF;
	GRANT EXECUTE ON `stk_sequence`.* TO 'obj_stk_sequence'@'localhost';
	GRANT SELECT, LOCK TABLES, CREATE TEMPORARY TABLES, INSERT, UPDATE, DELETE ON `stk_sequence`.* TO 'obj_stk_sequence'@'localhost';
END;


DROP PROCEDURE IF EXISTS `uninstall_lib`;
CREATE PROCEDURE `uninstall_lib`()
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Execute this as root before using this lib'
BEGIN
	-- drop & revoke obj user
	IF EXISTS (SELECT 1 FROM `mysql`.`user` WHERE `User` = 'obj_stk_sequence') THEN
		REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'obj_stk_sequence'@'localhost';
		DROP USER 'obj_stk_sequence'@'localhost';
	END IF;
END;


DROP PROCEDURE IF EXISTS `grant_to`;
CREATE PROCEDURE `grant_to`(IN `username` CHAR(80))
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Grant someone the right to use this lib'
BEGIN
	DECLARE `eof`       BOOL      DEFAULT FALSE;
	DECLARE `obj_name`  CHAR(64)  DEFAULT '';
	
	DECLARE `cur_routines` CURSOR FOR
		SELECT `ROUTINE_NAME`
			FROM `information_schema`.`ROUTINES`
			WHERE `ROUTINE_SCHEMA` = 'stk_sequence'
				AND `ROUTINE_NAME` NOT IN ('grant_to', 'install')
				AND `ROUTINE_COMMENT` NOT LIKE 'Internal.%';
	
	DECLARE `cur_tables` CURSOR FOR
		SELECT `TABLE_NAME`
			FROM `information_schema`.`TABLES`
			WHERE `TABLE_SCHEMA` = 'stk_sequence'
				AND `TABLE_COMMENT` NOT LIKE 'Internal.%';
	
	DECLARE CONTINUE HANDLER FOR
		NOT FOUND
		SET `eof` = TRUE;
	
	
	-- grant permissions on routines
	
	OPEN `cur_routines`;
	
	`lp_routines`:
	LOOP
		FETCH NEXT FROM `cur_routines` INTO `obj_name`;
		
		IF `eof` IS NOT FALSE THEN
			LEAVE `lp_routines`;
		END IF;
		
		SET @`stk.sequence.sql` = CONCAT('GRANT EXECUTE ON PROCEDURE `stk_sequence`.`', `obj_name`, '` TO ''', `username`,'''@''%'';');
		
		PREPARE __STK_stmt_grant FROM @`stk.sequence.sql`;
		EXECUTE __STK_stmt_grant;
		DEALLOCATE PREPARE __STK_stmt_grant;
	END LOOP;
	
	CLOSE `cur_routines`;
	
	-- grant permissions on tables
	
	OPEN `cur_tables`;
	
	`lp_tables`:
	LOOP
		FETCH NEXT FROM `cur_tables` INTO `obj_name`;
		
		IF `eof` IS NOT FALSE THEN
			LEAVE `lp_tables`;
		END IF;
		
		SET @`stk.sequence.sql` = CONCAT('GRANT EXECUTE ON PROCEDURE `stk_sequence`.`', `obj_name`, '` TO ''', `username`,'''@''%'';');
		
		PREPARE __STK_stmt_grant FROM @`stk.sequence.sql`;
		EXECUTE __STK_stmt_grant;
		DEALLOCATE PREPARE __STK_stmt_grant;
	END LOOP;
	
	CLOSE `cur_tables`;
END;


/**
 *		Core
 */


DROP PROCEDURE IF EXISTS `create`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' PROCEDURE `create`(IN `s_name` CHAR(64),
                                 IN `s_increment` INTEGER, IN `s_minvalue` BIGINT, IN `s_maxvalue` BIGINT,
								 IN `s_cycle` BOOLEAN, IN `s_start` BIGINT,
								 IN `s_comment` CHAR(64))
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Create a new sequence'
BEGIN
	-- duplicate sequence error
	DECLARE CONTINUE HANDLER
		FOR 1062
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.create] - SEQUENCE already exists';
	
	-- set default values
	
	-- default increment
	IF `s_increment` IS NULL THEN
		SET `s_increment` = 1;
	END IF;
	
	-- default max, min, currval
	IF `s_increment` > 0 THEN
		-- ascnding
		IF `s_minvalue` IS NULL THEN
			SET `s_minvalue` = 1;
		END IF;
		IF `s_maxvalue` IS NULL THEN
			SET `s_maxvalue` = 9223372036854775807 - `s_increment`;
		END IF;
		IF `s_start` IS NULL THEN
			SET `s_start` = `s_minvalue`;
		END IF;
	ELSE
		-- descending
		IF `s_minvalue` IS NULL THEN
			SET `s_minvalue` = -9223372036854775807 - `s_increment`;
		END IF;
		IF `s_maxvalue` IS NULL THEN
			SET `s_maxvalue` = -1;
		END IF;
		IF `s_start` IS NULL THEN
			SET `s_start` = `s_maxvalue`;
		END IF;
	END IF;
	
	-- default increment
	IF `s_cycle` IS NULL THEN
		SET `s_cycle` = FALSE;
	END IF;
	
	-- default comment
	IF `s_comment` IS NULL THEN
		SET `s_comment` = '';
	END IF;
	
	-- create sequence
	INSERT INTO `SEQUENCES`
		SET
			`SEQUENCE_NAME`  = s_name,
			`INCREMENT`      = s_increment,
			`MINVALUE`       = s_minvalue,
			`MAXVALUE`       = s_maxvalue,
			`CYCLE`          = s_cycle,
			`START`          = s_start,
			`COMMENT`        = s_comment;
END;


DROP PROCEDURE IF EXISTS `alter`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' PROCEDURE `alter`(IN `s_name` CHAR(64),
                         IN `s_increment` INTEGER, IN `s_minvalue` BIGINT, IN `s_maxvalue` BIGINT,
						 IN `s_cycle` BOOLEAN,
						 IN `s_comment` CHAR(64))
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Create a new sequence'
BEGIN
	-- UPDATE SET clause
	DECLARE set_clause    TEXT  DEFAULT '';
	-- UPDATE SET clause has begun
	DECLARE set_is_empty  BOOL  DEFAULT TRUE;
	-- backup @__stk_sql in case it exists
	DECLARE tmp_val       TEXT  DEFAULT NULL;
	
	-- duplicate sequence error
	DECLARE CONTINUE HANDLER
		FOR 1062
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.alter] - SEQUENCE already exists';
	
	-- set default values
	
	-- default increment
	IF `s_increment` IS NOT NULL THEN
		-- add pair
		SET set_clause = CONCAT(set_clause, '`INCREMENT` = ', s_increment);
		SET set_is_empty = FALSE;
	END IF;
	
	-- default minvalue
	IF `s_minvalue` IS NOT NULL THEN
		-- add separator
		IF set_is_empty IS NOT TRUE THEN
			SET set_clause = CONCAT(set_clause, ', ');
		END IF;
		-- add pair
		SET set_clause = CONCAT(set_clause, '`MINVALUE` = ', s_minvalue);
		SET set_is_empty = FALSE;
	END IF;
	
	-- default maxvalue
	IF `s_maxvalue` IS NOT NULL THEN
		-- add separator
		IF set_is_empty IS NOT TRUE THEN
			SET set_clause = CONCAT(set_clause, ', ');
		END IF;
		-- add pair
		SET set_clause = CONCAT(set_clause, '`MAXVALUE` = ', s_maxvalue);
		SET set_is_empty = FALSE;
	END IF;
	
	-- default cycle
	IF `s_cycle` IS NOT NULL THEN
		-- add separator
		IF set_is_empty IS NOT TRUE THEN
			SET set_clause = CONCAT(set_clause, ', ');
		END IF;
		-- add pair
		SET set_clause = CONCAT(set_clause, '`CYCLE` = ', s_cycle);
		SET set_is_empty = FALSE;
	END IF;
	
	-- default comment
	IF `s_comment` IS NOT NULL THEN
		-- add separator
		IF set_is_empty IS NOT TRUE THEN
			SET set_clause = CONCAT(set_clause, ', ');
		END IF;
		-- add pair
		SET set_clause = CONCAT(set_clause, '`COMMENT` = ''', s_comment, '''');
		SET set_is_empty = FALSE;
	END IF;
	
	-- alter sequence
	IF set_is_empty IS NOT TRUE THEN
		SET tmp_val = @__stk_sql;
		-- compose statement
		SET @__stk_sql = CONCAT(
			'UPDATE `stk_sequence`.`SEQUENCES` ',
				'SET ', set_clause, ' ',
				'WHERE `SEQUENCE_NAME` = ''', s_name, ''';'
		);
		PREPARE __stk_stmt_eval FROM @__stk_sql;
		SET @__stk_sql = tmp_val;
		SET tmp_val = NULL;
		EXECUTE __stk_stmt_eval;
		DEALLOCATE PREPARE __stk_stmt_eval;
	END IF;
END;


DROP PROCEDURE IF EXISTS `get`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' PROCEDURE `get`(IN `s_name` CHAR(64),
                       OUT `s_increment` INTEGER, OUT `s_minvalue` BIGINT, OUT `s_maxvalue` BIGINT,
					   OUT `s_cycle` BOOLEAN, OUT `s_comment` CHAR(64))
	LANGUAGE SQL
	READS SQL DATA
	COMMENT 'Get info about a SEQUENCE'
BEGIN
	DECLARE CONTINUE HANDLER
		FOR NOT FOUND
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.get] - SEQUENCE does not exists';
	
	SELECT
		       `INCREMENT`, `MINVALUE`, `MAXVALUE`, `CYCLE`, `COMMENT`
		FROM   `stk_sequence`.`SEQUENCES`
		WHERE  `SEQUENCE_NAME` = s_name
		INTO   `s_increment`, `s_minvalue`, `s_maxvalue`, `s_cycle`, `s_comment`;
END;


DROP FUNCTION IF EXISTS `exists`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' FUNCTION `exists`(`s_name` CHAR(64))
	RETURNS BOOL
	NOT DETERMINISTIC
	READS SQL DATA
	LANGUAGE SQL
	COMMENT 'Return TRUE if SEQUENCE exists, else FALSE'
BEGIN
	RETURN (
		EXISTS (
			SELECT 1
				FROM   `stk_sequence`.`SEQUENCES`
				WHERE  `SEQUENCE_NAME` = s_name
		)
	);
END;


DROP PROCEDURE IF EXISTS `drop`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' PROCEDURE `drop`(IN `s_name` CHAR(64))
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Drop sequence'
BEGIN
	-- drop
	DELETE FROM `SEQUENCES` WHERE `SEQUENCE_NAME` = s_name;
	
	-- check if 1 has been dropped
	IF ROW_COUNT() < 1 THEN
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.drop] - SEQUENCE does not exists';
	END IF;
END;


DROP PROCEDURE IF EXISTS `rename`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' PROCEDURE `rename`(IN `s_old_name` CHAR(64), IN `s_new_name` CHAR(64))
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Rename sequence'
BEGIN
	-- duplicate sequence error
	DECLARE CONTINUE HANDLER
		FOR 1062
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.rename] - SEQUENCE already exists';
	
	IF `s_old_name` IS NULL OR `s_new_name` IS NULL OR `s_old_name` = `s_new_name` THEN
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.rename] - Invalid parameters';
	END IF;
	
	-- rename
	UPDATE     `stk_sequence`.`SEQUENCES`
		SET    `SEQUENCE_NAME` = s_new_name
		WHERE  `SEQUENCE_NAME` = s_old_name;
	
	-- check if 1 has been dropped
	IF ROW_COUNT() < 1 THEN
		SIGNAL SQLSTATE VALUE '45000'
			SET MESSAGE_TEXT = '[stk_sequence.rename] - Old SEQUENCE does not exists';
	END IF;
END;


DROP PROCEDURE IF EXISTS `log_value`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' PROCEDURE `log_value`(IN `s_name` CHAR(64), IN `val` BIGINT SIGNED)
	LANGUAGE SQL
	MODIFIES SQL DATA
	COMMENT 'Internal. Log last generated value'
BEGIN
	-- session log table may not exist
	CREATE TEMPORARY TABLE IF NOT EXISTS `stk_sequence`.`sequence_session_log`
	(
		`timestamp`      TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP
		                                               NOT NULL COMMENT 'Value generation timestamp',
		`sequence_name`  CHAR(64) CHARACTER SET ascii  NOT NULL COMMENT 'SEQUENCE from which the value was read',
		`value`          BIGINT UNSIGNED               NOT NULL COMMENT 'Value that was read',
		PRIMARY KEY (`sequence_name`)
	)
		ENGINE      = MEMORY
		COMMENT     = 'Logs values read by this session, they can be re-read'
		ROW_FORMAT  = FIXED
		MIN_ROWS    = 1;
	
	-- new value replaces old
	REPLACE INTO `stk_sequence`.`sequence_session_log`
			(`sequence_name`, `value`)
		VALUES
			(s_name, val);
END;


-- Set new value for the sequence, if it exists.
-- Does not validate the value.
-- If is_called is FALSE, when nextval() is called, the value will advance before returning.
DROP FUNCTION IF EXISTS `setval`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' FUNCTION setval(`s_name` CHAR(64), `new_value` BIGINT SIGNED, `is_called` BOOL)
	RETURNS BIGINT SIGNED
	NOT DETERMINISTIC
	MODIFIES SQL DATA
	LANGUAGE SQL
	COMMENT 'Change current value for a sequence and returns it'
BEGIN
	IF (s_name + new_value + is_called) IS NULL THEN
		IF s_name IS NULL THEN
			SIGNAL SQLSTATE VALUE '45000' SET
				MESSAGE_TEXT  = '[stk_sequence.setval] `s_name` argument is NULL';
		ELSEIF new_value IS NULL THEN
			SIGNAL SQLSTATE VALUE '45000' SET
				MESSAGE_TEXT  = '[stk_sequence.setval] `new_value` argument is NULL';
		ELSE
			SIGNAL SQLSTATE VALUE '45000' SET
				MESSAGE_TEXT  = '[stk_sequence.setval] `is_called` argument is NULL';
		END IF;
	END IF;
	
	IF is_called IS NOT TRUE THEN
		-- set currval to NULL & update start;
		-- next generated value will be start
		UPDATE
				   `stk_sequence`.`SEQUENCES`
			SET
			       `CURRVAL`        = NULL,
				   `START`          = new_value
			WHERE  `SEQUENCE_NAME`  = s_name;
	ELSE
		-- update SEQUENCE
		UPDATE
				   `stk_sequence`.`SEQUENCES`
			SET    `CURRVAL`        = new_value
			WHERE  `SEQUENCE_NAME`  = s_name;
		
		-- log generated value as if it was called
		CALL `stk_sequence`.`log_value`(s_name, new_value);
	END IF;
	
	-- for compatibility with PostgreSQL
	RETURN new_value;
END;


DROP FUNCTION IF EXISTS `nextval`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' FUNCTION `nextval`(`s_name` CHAR(64))
	RETURNS BIGINT SIGNED
	NOT DETERMINISTIC
	MODIFIES SQL DATA
	LANGUAGE SQL
	COMMENT 'Advance a sequence and return new value'
BEGIN
	-- can rotate?
	DECLARE rotate    BIGINT SIGNED;
	-- start value
	DECLARE v_start   BIGINT SIGNED;
	-- increment
	DECLARE v_inc     BIGINT SIGNED;
	-- minvalue
	DECLARE v_min     BIGINT SIGNED;
	-- maxvalue
	DECLARE v_max     BIGINT SIGNED;
	-- currval
	DECLARE v_cur     BIGINT SIGNED;
	-- output
	DECLARE next_val  BIGINT SIGNED;
	
	-- bound & direction
	DECLARE v_begin   BIGINT SIGNED;
	DECLARE v_end     BIGINT SIGNED;
	DECLARE v_sign    TINYINT SIGNED;
	
	-- get & lock sequence status
	SELECT
			   `INCREMENT`, `MINVALUE`, `MAXVALUE`, `CURRVAL`, `CYCLE`, `START`
		FROM   `stk_sequence`.`SEQUENCES`
		WHERE  `SEQUENCE_NAME` = s_name
		INTO   `v_inc`, `v_min`, `v_max`, `v_cur`, `rotate`, `v_start`
		FOR UPDATE;
	
	IF v_cur IS NULL THEN
		-- first value
		SET next_val = v_start;
	ELSE
		-- increment value
		SET next_val = v_cur + v_inc;
		
		-- set bounds
		IF v_inc > 0 THEN
			SET v_begin  = v_min;
			SET v_end    = v_max;
			SET v_sign   = +1;
		ELSE
			SET v_begin  = v_max;
			SET v_end    = v_min;
			SET v_sign   = -1;
		END IF;
		
		-- out of range?
		IF next_val NOT BETWEEN v_min AND v_max THEN
			IF rotate IS NOT TRUE THEN
				-- can't rotate: throw error
				SIGNAL SQLSTATE VALUE '45000'
					SET MESSAGE_TEXT = '[stk_sequence.nextval] - SEQUENCE reached minvalue or maxvalue';
			ELSE
				-- rotate
				SET next_val = v_begin + ((next_val - v_end) /* * v_sign */ ) - v_sign;
			END IF;
		END IF;
	END IF;
	
	-- update sequence
	UPDATE
			   `stk_sequence`.`SEQUENCES`
		SET    `CURRVAL`        = next_val
		WHERE  `SEQUENCE_NAME`  = s_name;
	
	-- log result at session level
	CALL `stk_sequence`.`log_value`(s_name, next_val);
	
	RETURN next_val;
END;


DROP FUNCTION IF EXISTS `currval`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' FUNCTION `currval`(`s_name` CHAR(64))
	RETURNS BIGINT SIGNED
	LANGUAGE SQL
	NOT DETERMINISTIC
	READS SQL DATA
	COMMENT 'Return last value generated by given SEQUENCE for this session, or NULL'
BEGIN
	DECLARE res BIGINT SIGNED;
	
	-- SQLEXCEPTION = table not exist, nextval() never called;
	-- NOT FOUND: record not exist, never called for that SEQUENCE
	-- so, return NULL
	DECLARE CONTINUE HANDLER
		FOR NOT FOUND, 1146
		RETURN NULL;
	
	-- last called value should be logged in this table
	RETURN (
			SELECT
					`value`
				FROM `stk_sequence`.`sequence_session_log`
				WHERE `sequence_name` = s_name
		);
END;


DROP FUNCTION IF EXISTS `lastval`;
CREATE DEFINER = 'obj_stk_sequence'@'localhost' FUNCTION `lastval`()
	RETURNS BIGINT SIGNED
	LANGUAGE SQL
	NOT DETERMINISTIC
	READS SQL DATA
	COMMENT 'Return last value generated any SEQUENCE for this session, or NULL'
BEGIN
	DECLARE res BIGINT SIGNED;
	
	-- SQLEXCEPTION = table not exist, nextval() never called;
	-- NOT FOUND: record not exist, never called for that SEQUENCE
	-- so, return NULL
	DECLARE CONTINUE HANDLER
		FOR NOT FOUND, 1146
		RETURN NULL;
	
	-- last called value should be logged in this table
	RETURN (
			SELECT
					      `value`
				FROM      `stk_sequence`.`sequence_session_log`
				ORDER BY  `timestamp` DESC
				LIMIT     1
		);
END;


||

DELIMITER ;
