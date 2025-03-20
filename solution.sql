-- Этап 1. Создание и заполнение БД
CREATE SCHEMA raw_data;

CREATE TABLE raw_data.sales (
    id INTEGER PRIMARY KEY, /* id из CSV-файла. В нормализованных таблицах будет использоваться автоинкремент, но здесь он не нужен. */
    auto CHARACTER varying(50) NOT NULL, /* Длину до 50 символов для учёта длинных названий. */
    gasoline_consumption NUMERIC(3, 1), /* NUMERIC(3, 1) для точного хранения значений с одной десятичной цифрой. */
    price NUMERIC(9, 2), /* NUMERIC(9, 2) для точного хранения до семизначной суммы с двумя десятичными знаками. */
    date DATE, /* Используем тип DATE для хранения даты. */
    person_name CHARACTER varying(70), /* VARCHAR(70) для хранения длинных ФИО. */
    phone CHARACTER varying(35), /* VARCHAR(35) для хранения номера телефона, включая возможные символы. */
    discount INTEGER CHECK (discount >= 0 AND discount <= 100), /* INTEGER с ограничением от 0 до 100. */
    brand_origin CHARACTER varying(50) /* VARCHAR(50) для хранения названия страны. */
);

CREATE SCHEMA car_shop;

CREATE TABLE car_shop.brands (
    brand_id SERIAL PRIMARY KEY,
    brand_name VARCHAR(50) NOT NULL,
    origin_country VARCHAR(50) NOT NULL
);

CREATE TABLE car_shop.car_models (
    model_id SERIAL PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    brand_id INT,
    FOREIGN KEY (brand_id) REFERENCES car_shop.brands(brand_id)
);

CREATE TABLE car_shop.colors (
    color_id SERIAL PRIMARY KEY,
    color_name VARCHAR(50) NOT NULL
);

CREATE TABLE car_shop.customers (
    customer_id SERIAL PRIMARY KEY,
    person_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE
);

/* Заполняем таблицы */

INSERT INTO car_shop.brands (brand_name, origin_country)
SELECT DISTINCT SPLIT_PART(auto, ' ', 1), brand_origin   -- Извлекаем только бренд без цвета и модели
FROM raw_data.sales;

INSERT INTO car_shop.car_models (model_name, brand_id)
SELECT DISTINCT 
    TRIM(split_part(split_part(auto, ',', 1), ' ', 2)),  -- Извлекаем только модель без цвета
    b.brand_id
FROM raw_data.sales s
JOIN car_shop.brands b ON b.brand_name = split_part(s.auto, ' ', 1);

INSERT INTO car_shop.colors (color_name)
SELECT DISTINCT TRIM(split_part(auto, ',', 2))   -- Извлекаем только цвет
FROM raw_data.sales
WHERE split_part(auto, ',', 2) IS NOT NULL;

INSERT INTO car_shop.customers (person_name, phone)
SELECT DISTINCT person_name, phone
FROM raw_data.sales;

CREATE TABLE car_shop.sales_new (
    sale_id SERIAL PRIMARY KEY,
    model_id INT NOT NULL,
    color_id INT NOT NULL,
    customer_id INT NOT NULL,
    price NUMERIC(9, 2) NOT NULL,
    sale_date DATE NOT NULL,
    discount INT CHECK (discount BETWEEN 0 AND 100),
    FOREIGN KEY (model_id) REFERENCES car_shop.car_models(model_id),
    FOREIGN KEY (color_id) REFERENCES car_shop.colors(color_id),
    FOREIGN KEY (customer_id) REFERENCES car_shop.customers(customer_id)
);

INSERT INTO car_shop.sales_new (model_id, color_id, customer_id, price, sale_date, discount)
SELECT 
    cm.model_id,
    cl.color_id,
    cu.customer_id,
    s.price,
    s.date,
    COALESCE(s.discount, 0)  -- Если скидка пустая, ставим 0
FROM raw_data.sales s
JOIN car_shop.car_models cm ON cm.model_name = TRIM(split_part(split_part(s.auto, ',', 1), ' ', 2))  -- отделяем не только запятой, но и пробелом
JOIN car_shop.colors cl ON cl.color_name = TRIM(split_part(s.auto, ',', 2))
JOIN car_shop.customers cu ON cu.person_name = s.person_name AND cu.phone = s.phone; 


-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
SELECT (SUM(CASE WHEN gasoline_consumption IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS nulls_percentage_gasoline_consumption
FROM raw_data.sales;


---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.
SELECT 
    b.brand_name, 
    EXTRACT(YEAR FROM sn.sale_date) AS year,
    ROUND(AVG(sn.price*(1-sn.discount/100)), 2) AS price_avg 
FROM car_shop.brands b
INNER JOIN car_shop.car_models cm ON cm.brand_id = b.brand_id 
INNER JOIN car_shop.sales_new sn ON sn.model_id = cm.model_id
GROUP BY b.brand_name, year
ORDER BY b.brand_name ASC, year ASC;


---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
SELECT 
    EXTRACT(MONTH FROM sale_date) AS month,
    EXTRACT(YEAR FROM sale_date) AS year,
    ROUND(AVG(price*(1-discount/100)), 2) AS price_avg 
FROM car_shop.sales_new 
WHERE EXTRACT(YEAR FROM sale_date) = 2022
GROUP BY month, year
ORDER BY month ASC;


---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.
SELECT c.person_name, STRING_AGG((b.brand_name||' '||cm.model_name), ',') AS cars
FROM car_shop.customers c 
INNER JOIN car_shop.sales_new sn ON c.customer_id = sn.customer_id 
INNER JOIN car_shop.car_models cm ON cm.model_id = sn.model_id
INNER JOIN car_shop.brands b ON cm.brand_id  = b.brand_id
GROUP BY c.person_name
ORDER BY c.person_name ASC;

----Задание 5 из 6. Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля с разбивкой по стране без учёта скидки. 
Цена в колонке price дана с учётом скидки.
SELECT b.origin_country, 
    MAX(sn.price/(1-sn.discount/100)) AS price_max, 
    MIN(sn.price/(1-sn.discount/100)) AS price_min
FROM car_shop.brands b 
INNER JOIN car_shop.car_models cm ON cm.brand_id  = b.brand_id
INNER JOIN car_shop.sales_new sn ON cm.model_id = sn.model_id
GROUP BY b.origin_country;
  
---- Задание 5. Напишите запрос, который покажет количество всех пользователей из США.

SELECT COUNT(customer_id) AS persons_from_usa_count
FROM car_shop.customers
WHERE phone LIKE '+1%';


