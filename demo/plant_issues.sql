-- =============================================================================
--  myblitzaudit demo — plants the issues the reports are meant to find
--  Run against a scratch MySQL 8.0 instance:
--    mysql -uroot -p < demo/plant_issues.sql
--  Every choice here is deliberate: it is a museum of bad practice.
-- =============================================================================

DROP DATABASE IF EXISTS shopdb;
DROP DATABASE IF EXISTS support;

-- ---------------------------------------------------------------------------
-- shopdb
-- ---------------------------------------------------------------------------
CREATE DATABASE shopdb DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE shopdb;

-- PK, but no unique constraint on email and no index on created_at
CREATE TABLE customers (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email       VARCHAR(255) NOT NULL,
  full_name   VARCHAR(120),
  country     CHAR(2),
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Foreign key with no supporting index on customer_id: every parent delete
-- takes a table lock scan
CREATE TABLE orders (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT UNSIGNED NOT NULL,
  status       VARCHAR(20) NOT NULL DEFAULT 'new',
  total_cents  BIGINT NOT NULL DEFAULT 0,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB;

-- Composite PK, redundant single-column index on order_id
CREATE TABLE order_items (
  order_id   BIGINT UNSIGNED NOT NULL,
  line_no    SMALLINT UNSIGNED NOT NULL,
  sku        VARCHAR(64) NOT NULL,
  qty        INT NOT NULL DEFAULT 1,
  unit_cents INT NOT NULL DEFAULT 0,
  PRIMARY KEY (order_id, line_no),
  KEY idx_order_id (order_id),
  CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders(id)
) ENGINE=InnoDB;

-- No primary key at all: InnoDB builds a hidden 6-byte row id, and replication
-- has to scan the whole table for every update
CREATE TABLE product_views (
  product_sku VARCHAR(64),
  viewed_at   DATETIME,
  session_id  CHAR(36),
  KEY idx_sku (product_sku)
) ENGINE=InnoDB;

-- MyISAM in 2026: no transactions, no crash recovery, table-level locking
CREATE TABLE legacy_audit (
  id      INT NOT NULL AUTO_INCREMENT,
  action  VARCHAR(64),
  payload TEXT,
  PRIMARY KEY (id)
) ENGINE=MyISAM;

-- latin1 column in an utf8mb4 database: silent mojibake on the way in
CREATE TABLE newsletter (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  address VARCHAR(255) CHARACTER SET latin1 NOT NULL,
  sent_at DATETIME
) ENGINE=InnoDB;

-- Unused index plus a duplicate of the primary key
CREATE TABLE sessions (
  id          CHAR(36) NOT NULL PRIMARY KEY,
  customer_id INT UNSIGNED,
  payload     TEXT,
  last_seen   DATETIME NOT NULL,
  KEY idx_id_dup (id),
  KEY idx_never_used (last_seen, payload(10))
) ENGINE=InnoDB;

CREATE VIEW v_recent_orders AS
  SELECT o.id, o.status, o.total_cents, c.email
  FROM orders o JOIN customers c ON c.id = o.customer_id
  WHERE o.created_at >= NOW() - INTERVAL 30 DAY;

CREATE PROCEDURE sp_close_stale_orders()
  MODIFIES SQL DATA
  UPDATE orders SET status = 'closed'
  WHERE status = 'new' AND created_at < NOW() - INTERVAL 90 DAY;

CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON orders
FOR EACH ROW SET NEW.status = NEW.status;

-- ---------------------------------------------------------------------------
-- support
-- ---------------------------------------------------------------------------
CREATE DATABASE support DEFAULT CHARACTER SET utf8mb3;
USE support;

CREATE TABLE tickets (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  subject    VARCHAR(255),
  body       MEDIUMTEXT,
  opened_at  DATETIME NOT NULL,
  closed_at  DATETIME NULL,
  KEY idx_subject (subject(40))
) ENGINE=InnoDB;

CREATE TABLE attachments (
  id        BIGINT AUTO_INCREMENT PRIMARY KEY,
  ticket_id BIGINT NOT NULL,
  filename  VARCHAR(255),
  content   LONGBLOB,
  CONSTRAINT fk_att_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Accounts that will light up the security section
-- ---------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'reporting'@'%' IDENTIFIED WITH mysql_native_password BY '';
GRANT SELECT ON shopdb.* TO 'reporting'@'%';

CREATE USER IF NOT EXISTS 'app'@'%' IDENTIFIED BY 'app_password_123';
GRANT ALL PRIVILEGES ON shopdb.* TO 'app'@'%';

-- ---------------------------------------------------------------------------
-- Some volume so sizes and statistics are not all zero
-- ---------------------------------------------------------------------------
USE shopdb;
INSERT INTO customers (email, full_name, country)
SELECT CONCAT('user', n, '@example.com'), CONCAT('Customer ', n),
       ELT(1 + (n % 5), 'FR', 'DE', 'ES', 'IT', 'BE')
FROM (SELECT a.N + b.N * 10 + 1 AS n FROM
      (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
      (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b) seq;

INSERT INTO orders (customer_id, status, total_cents, created_at)
SELECT 1 + (n % 100), ELT(1 + (n % 3), 'new', 'paid', 'shipped'),
       1000 + (n * 37), NOW() - INTERVAL (n % 180) DAY
FROM (SELECT a.N + b.N * 10 + 1 AS n FROM
      (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
      (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b) seq;

INSERT INTO order_items (order_id, line_no, sku, qty, unit_cents)
SELECT o.id, 1, CONCAT('SKU-', LPAD(o.id % 40, 4, '0')), 1 + (o.id % 3), 500 + (o.id % 20) * 25
FROM orders o;

INSERT INTO support.tickets (subject, body, opened_at)
SELECT CONCAT('Ticket ', n), REPEAT('body text ', 20), NOW() - INTERVAL (n % 60) DAY
FROM (SELECT a.N + b.N * 10 + 1 AS n FROM
      (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
      (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b) seq;

ANALYZE TABLE customers, orders, order_items, product_views, sessions;
