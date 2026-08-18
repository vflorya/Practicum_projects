
 * Решаем ad hoc задачи
 *
 * Автор:Флоря Виктория Александровна
 * Дата:31.01.2026
*/

-- Задача 1: Время активности объявлений
-- CTE с фильтрованными данными.Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Используем id объявлений (СТЕ filtered_id), которые не содержат выбросы при анализе данных
	 activity_time AS(
	    SELECT 
	    EXTRACT(YEAR FROM a.first_day_exposition) AS year,
	    f.id,
        t.type,
        c.city,
        f.rooms,
        f.total_area,
        f.floors_total,
        f.balcony,
        a.last_price,
        a.days_exposition,
        -- Сегментируем по регионам Санкт-Петербург и ЛенОбл
          CASE 
        WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
        ELSE 'ЛенОбл'
    	END AS region,
    	-- Сегментируем по дням активности объявлений
        CASE 
	        WHEN a.days_exposition IS NULL THEN 'non category' -- Объявления не снятые с продажи
            WHEN a.days_exposition < 30 THEN 'до 1-го месяца'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до 3-х месяцев'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'от 3-х до 6 месяцев'
            ELSE 'более 6-ти месяцев'
        END AS days_exposition_segment,
		ROUND((a.last_price / f.total_area)::numeric,2) AS price_per_m2 -- Стоимость м2 квартиры
         FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a ON f.id
 = a.id
     JOIN real_estate.city
 AS c ON f.city_id = c.city_id
    JOIN real_estate.type AS t ON f.type_id = t.type_id
    WHERE t.type='город' AND EXTRACT(YEAR FROM a.first_day_exposition) IN (2018,2017,2016,2015)-- Фильтрация по типу данных город и годам 
    GROUP BY  a.first_day_exposition, f.id, t.type, c.city, f.rooms, a.last_price, f.total_area, f.floors_total, a.days_exposition, f.city_id 
	)
	SELECT 
	region,
	days_exposition_segment, -- Сегмент активности объявлений
	COUNT(*) AS total_ads, -- Количество объявлений по сегментам
   	ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY region)),0) AS percentage,--!! Доля объявлений в разрезе каждого региона (сумма по региону =100%)
	ROUND(AVG(price_per_m2)::numeric,2) AS avg_price_per_m2, -- Средняя стоимость м2 в сегменте
	ROUND(AVG(total_area)::numeric,1) AS avg_area_m2, -- Средняя площадь м2 в сегменте
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms ) AS mediana_rooms, -- Медиана по количеству комнат
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floors_total ) AS mediana_floors_total, -- Медиана этажности дома
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS mediana_balcony, --медиана кол-ва балконов
	ROUND(AVG(last_price)::numeric,2) AS avg_price -- Средняя стоимость квартиры в сегменте
	FROM activity_time 
	WHERE id IN (SELECT * FROM filtered_id) -- Отфильтрованные id от аномалий
	GROUP BY region,days_exposition_segment
	ORDER BY total_ads DESC;

--Задача 2: Сезонность объявлений
    
 -- Определим аномальные значения (выбросы) по значению перцентилей:

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Сезонность по размещению объявлений
SELECT 
	TO_CHAR (a.first_day_exposition, 'Month' ) AS "месяц_объявлений", -- Месяц публикации объявления
	'Размещение' AS action_type,
	COUNT(*) AS total_ads, -- Количество размещенных объявлений по месяцам
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage_of_placement, --!! Процент от общего количества размещенных объявлений
	ROUND(AVG(a.days_exposition)) AS avg_days_to_sell,-- Средняя длительность дней нахождения на сайте
    ROUND(AVG(a.last_price))  AS avg_price, -- Средняя стоимость квартиры в объявлении
    ROUND( AVG(a.last_price / f.total_area)) AS price_per_m2, -- Средняя стоимость м2 квартиры
    ROUND(AVG(total_area)::numeric,1) AS avg_area_m2 -- Средняя площадь м2 в сегменте  
FROM real_estate.advertisement AS a
JOIN real_estate.flats AS f ON a.id = f.id
JOIN real_estate.type AS t ON t.type_id = f.type_id
WHERE f.id
 IN (SELECT * FROM filtered_id) AND EXTRACT(YEAR FROM a.first_day_exposition) IN (2015,2016,2017,2018) AND t.type='город'-- Исключаем не заполненные даты и 2018 г.
GROUP BY "месяц_объявлений"
UNION ALL
--Сезонность по снятию
SELECT 
	TO_CHAR ((a.first_day_exposition + INTERVAL '1 DAY' * a.days_exposition ),'Month') AS "месяц_объявлений", -- Месяц снятия объявления на основании даты снятия
	'Снятие' AS action_type,
	COUNT(*) AS total_ads, -- Количество размещенных объявлений по месяцам
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage_of_removal, --!! Процент от общего количества снятых объявлений
	ROUND(AVG(a.days_exposition)) AS avg_days_to_sell,-- Средняя длительность дней нахождения на сайте
    ROUND(AVG(a.last_price))  AS avg_price, -- Средняя стоимость квартиры в объявлении
    ROUND( AVG(a.last_price / f.total_area)) AS price_per_m2,-- Средняя стоимость м2 квартиры
    ROUND(AVG(total_area)::numeric,1) AS avg_area_m2 -- Средняя площадь м2 в сегменте 
FROM real_estate.advertisement AS a
JOIN real_estate.flats AS f ON a.id = f.id
JOIN real_estate.type AS t ON t.type_id = f.type_id
WHERE f.id
 IN (SELECT * FROM filtered_id) AND EXTRACT(YEAR FROM a.first_day_exposition) IN (2015,2016,2017,2018) AND t.type='город' -- Исключаем не заполненные даты и 2018 г.
GROUP BY "месяц_объявлений"
ORDER BY action_type, total_ads DESC;



