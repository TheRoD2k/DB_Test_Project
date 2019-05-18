--DROP TABLE IF EXISTS WAREHOUSE CASCADE ;
CREATE TABLE IF NOT EXISTS WAREHOUSE(
  warehouse_id         SERIAL PRIMARY KEY,
  warehouse_desc       VARCHAR(255),
  rent_price_amt       DECIMAL(10,2) NOT NULL,
  functioning_flg      BOOLEAN NOT NULL
);

CREATE VIEW WAREHOUSE_VIEW AS
  SELECT * FROM WAREHOUSE
  WHERE functioning_flg = TRUE;

--DROP TABLE IF EXISTS GAME_LIST CASCADE;
CREATE TABLE IF NOT EXISTS GAME_LIST(
  game_id             INTEGER PRIMARY KEY,
  platform_desc       VARCHAR(50) NOT NULL,
  game_nm             VARCHAR(100) NOT NULL,
  game_desc           VARCHAR(255),
  launch_dt           TIMESTAMP(8),
  standard_price_amt  DECIMAL(7,2) NOT NULL
);

CREATE VIEW NEW_GAMES_VIEW AS
  SELECT * FROM GAME_LIST
  WHERE launch_dt > '2015-01-01';

--DROP TABLE IF EXISTS GAME_IN_STOCK CASCADE;
CREATE TABLE IF NOT EXISTS GAME_IN_STOCK(
  stock_record_id    INTEGER PRIMARY KEY,
  warehouse_id  INTEGER REFERENCES WAREHOUSE(warehouse_id),
  game_id       INTEGER REFERENCES GAME_LIST(game_id),
  in_stock_amt  INTEGER NOT NULL,
  price_amt     DECIMAL(7,2) NOT NULL
);

CREATE VIEW STOCK_VIEW AS
  SELECT game_id, price_amt FROM GAME_IN_STOCK
WHERE in_stock_amt > 0;

--DROP TABLE IF EXISTS EMPLOYEE_LIST CASCADE;
CREATE TABLE IF NOT EXISTS EMPLOYEE_LIST(
  employee_id   INTEGER PRIMARY KEY,
  employee_nm   VARCHAR(100) NOT NULL,
  employee_desc VARCHAR(255) NOT NULL,
  hired_dt      TIMESTAMP(8) NOT NULL,
  fired_dt      TIMESTAMP(8)
);

CREATE VIEW EMPLOYEE_LIST_VIEW AS
  SELECT employee_id, employee_nm, employee_desc FROM EMPLOYEE_LIST
  WHERE fired_dt IS NULL;

--DROP TABLE IF EXISTS EMPLOYEE CASCADE;
CREATE TABLE IF NOT EXISTS EMPLOYEE(
  employee_record_id  INTEGER PRIMARY KEY,
  warehouse_id        INTEGER REFERENCES WAREHOUSE(warehouse_id),
  employee_id         INTEGER REFERENCES EMPLOYEE_LIST(employee_id) NOT NULL,
  updated_on_dt       TIMESTAMP(8) NOT NULL,
  current_salary_amt  DECIMAL(10,2) NOT NULL,
  position_desc       VARCHAR(255),
  head_id             INTEGER REFERENCES EMPLOYEE_LIST(employee_id)
);

CREATE VIEW NOT_BOUND_EMPLOYEE AS
  SELECT warehouse_id, employee_id, head_id FROM EMPLOYEE
  WHERE warehouse_id IS NULL;

--DROP TABLE IF EXISTS SUPPLIER CASCADE;
CREATE TABLE IF NOT EXISTS SUPPLIER(
  supplier_record_id  INTEGER PRIMARY KEY,
  supplier_id         INTEGER  NOT NULL,
  updated_on_dt       TIMESTAMP(8) NOT NULL,
  manager_id          INTEGER REFERENCES EMPLOYEE(employee_record_id),
  supplier_nm         VARCHAR(100),
  supplier_desc       VARCHAR(255)
);

CREATE VIEW SUPPLIER_RECORD_VIEW AS
  SELECT supplier_id, manager_id, updated_on_dt FROM SUPPLIER;

--DROP TABLE IF EXISTS SUPPLY CASCADE;
CREATE TABLE IF NOT EXISTS SUPPLY(
  supply_id     INTEGER PRIMARY KEY,
  game_id       INTEGER REFERENCES GAME_LIST(game_id),
  warehouse_id  INTEGER REFERENCES WAREHOUSE(warehouse_id),
  purchase_dt   TIMESTAMP(8) NOT NULL,
  supplier_id   INTEGER REFERENCES SUPPLIER(supplier_record_id),
  price_amt     DECIMAL(7,2) NOT NULL,
  bought_cnt    INTEGER NOT NULL
);

CREATE VIEW ADVANCED_SUPPLY_VIEW AS
  SELECT supply_id, SUPPLY.warehouse_id, purchase_dt, price_amt*bought_cnt AS outcome,
         WAREHOUSE.warehouse_desc, WAREHOUSE.functioning_flg FROM
                                        (WAREHOUSE INNER JOIN SUPPLY ON SUPPLY.warehouse_id = WAREHOUSE.warehouse_id);

--DROP TABLE IF EXISTS PURCHASE CASCADE;
CREATE TABLE IF NOT EXISTS PURCHASE(
  purchase_id       INTEGER PRIMARY KEY,
  stock_record_id   INTEGER REFERENCES GAME_IN_STOCK(stock_record_id),
  purchase_dttm     TIMESTAMP(12) NOT NULL,
  selling_price_amt DECIMAL(7,2) NOT NULL,
  seller_id         INTEGER REFERENCES EMPLOYEE(employee_record_id),
  manager_id        INTEGER REFERENCES EMPLOYEE(employee_record_id),
  sold_cnt          INTEGER NOT NULL
);

DROP VIEW IF EXISTS ADVANCED_PURCHASE_VIEW;
CREATE VIEW ADVANCED_PURCHASE_VIEW AS
  SELECT purchase_id, purchase_dttm, PURCHASE.stock_record_id, GAME_IN_STOCK.game_id, selling_price_amt*sold_cnt AS income, GAME_IN_STOCK.warehouse_id,
         selling_price_amt, GAME_IN_STOCK.price_amt AS actual_price FROM PURCHASE INNER JOIN GAME_IN_STOCK
          ON GAME_IN_STOCK.stock_record_id = PURCHASE.stock_record_id;


--DROP TABLE IF EXISTS SALARY_PAID CASCADE;
CREATE TABLE IF NOT EXISTS SALARY_PAID(
  payment_id INTEGER PRIMARY KEY,
  employee_id INTEGER REFERENCES EMPLOYEE_LIST(employee_id),
  payment_dttm TIMESTAMP(12) NOT NULL,
  salary_amt DECIMAL(10,2) NOT NULL,
  bonus_amt DECIMAL(10,2)
);

CREATE VIEW SALARY_PAID_VIEW AS
  SELECT employee_id, payment_dttm, salary_amt+bonus_amt AS sum_paid FROM SALARY_PAID;

--1 запрос
--Вывести ID продавцов, продавших наибольшее количество копий продукта, их имена и количество проданных единиц
SELECT DT1.employee_id, EMPLOYEE_LIST.employee_nm, DT1.sold_sum FROM
  ( SELECT EMPLOYEE.employee_id, sum(sold_cnt) AS sold_sum FROM PURCHASE INNER JOIN EMPLOYEE
    ON PURCHASE.seller_id = EMPLOYEE.employee_record_id
    GROUP BY EMPLOYEE.employee_id
    ) AS DT1
INNER JOIN EMPLOYEE_LIST
ON DT1.employee_id = EMPLOYEE_LIST.employee_id;

--2 запрос
--Получить грязную прибыль за данный период для каждого склада
SELECT GAME_IN_STOCK.warehouse_id, warehouse_desc, cast(sum(selling_price_amt*sold_cnt) AS DECIMAL(38, 2)) AS dirty_income
FROM PURCHASE, GAME_IN_STOCK, WAREHOUSE
WHERE PURCHASE.stock_record_id = GAME_IN_STOCK.stock_record_id
  AND WAREHOUSE.warehouse_id = GAME_IN_STOCK.warehouse_id
  AND PURCHASE.purchase_dttm BETWEEN '2000-01-01' AND '2019-05-31'
GROUP BY GAME_IN_STOCK.warehouse_id, warehouse_desc;

--3 запрос
--Получить самый популярный продукт, проданный по цене ниже стандартной
WITH TEMPO(game_id, copies_sold) AS
(SELECT GAME_IN_STOCK.game_id, sum(PURCHASE.sold_cnt) AS copies_sold FROM PURCHASE INNER JOIN GAME_IN_STOCK
ON PURCHASE.stock_record_id = GAME_IN_STOCK.stock_record_id
WHERE PURCHASE.selling_price_amt < GAME_IN_STOCK.price_amt
  AND PURCHASE.purchase_dttm BETWEEN '2000-01-01' AND '2019-05-31'
GROUP BY GAME_IN_STOCK.game_id)
SELECT TEMPO.game_id, GAME_LIST.game_nm, TEMPO.copies_sold FROM TEMPO, GAME_LIST
WHERE copies_sold = (SELECT max(copies_sold) FROM TEMPO)
  AND GAME_LIST.game_id = TEMPO.game_id;

--4 запрос
--Посчитать общий доход/общую убыль за какой-то период
SELECT cast(sum(temp_sum) AS DECIMAL(38,2)) AS total_income FROM
  ((SELECT sum(purchase.sold_cnt * purchase.selling_price_amt) AS temp_sum FROM  PURCHASE
    WHERE purchase_dttm BETWEEN '2000-01-01' AND '2019-05-31')
UNION ALL
  (SELECT sum(-SUPPLY.bought_cnt*SUPPLY.price_amt) AS temp_sum FROM SUPPLY
    WHERE SUPPLY.purchase_dt BETWEEN '2000-01-01' AND '2019-05-31')
UNION ALL
  (SELECT sum(WAREHOUSE.rent_price_amt) *
              ((12 * (DATE_PART('year', '2019-05-31'::date) - DATE_PART('year', '2000-01-01'::date))
                  + DATE_PART('month', '2019-05-31'::date) - DATE_PART('month', '2000-01-01'::date))) AS temp_sum FROM WAREHOUSE)) AS DT;

--5 запрос
--TO BE CONTINUED

--CRUD1
INSERT INTO GAME_LIST VALUES (0000, 'PS4', 'GAME', NULL, NULL, 1000.00);
UPDATE GAME_LIST SET game_nm = 'ALTEREDNAME', game_desc = 'ALTEREDPLATFORM' WHERE game_id = 0000;
SELECT * FROM GAME_LIST WHERE game_id = 0000;
DELETE FROM GAME_LIST WHERE game_id = 0000;

--CRUD2
INSERT INTO EMPLOYEE_LIST VALUES (0000, 'Aaa', 'DESC', '2000-01-01', NULL);
UPDATE EMPLOYEE_LIST SET employee_nm = 'Bbb', employee_desc = 'ALTEREDDESC' WHERE employee_id = 0000;
SELECT * FROM EMPLOYEE_LIST WHERE employee_id = 0000;
DELETE FROM EMPLOYEE_LIST WHERE employee_id = 0000;