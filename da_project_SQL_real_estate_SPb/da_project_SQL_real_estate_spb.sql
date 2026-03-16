/* Анализ данных для агентства недвижимости
 * 
 * Автор: Десислава Макеева
 * Дата: 25-12-2024
*/

-- Фильтрация данных от аномальных значений
-- Определение аномальных значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    )
-- объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- 1. Время активности объявлений:
--  Определение сегментов рынка недвижимости Санкт-Петербурга и городов Ленинградской области, которые 
--    имеют наиболее короткие или длинные сроки активности объявлений
--  Подсчет характеристик недвижимости, которые влияют на время активности объявлений:  площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов 
--   Сравнение как меняются зависимости между двумя регионами (Санкт-Петербург и Лен. область)

--  аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_price::NUMERIC/total_area) AS sqm_price_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price::NUMERIC/total_area) AS sqm_price_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement USING(id)
),
--  id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
ads_categorized AS (
	SELECT f.id AS id,
			CASE WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург' ELSE 'ЛенОбл' END AS city_category,
			first_day_exposition,
			CASE WHEN days_exposition <=30 THEN 'меньше месяца' 
				 WHEN days_exposition BETWEEN 31 AND 90 THEN 'от 1 до 3 месяцев'
				 WHEN days_exposition BETWEEN 91 AND 180 THEN 'от 3 до 6 месяцев'
				 WHEN days_exposition >=181 THEN 'больше 6 месяцев'
				 ELSE 'не продано' END AS activity_category,
			total_area,
			last_price,
			last_price::NUMERIC/total_area AS sq_m_price,
			rooms,
			ceiling_height,
			floor,
			floors_total,
			is_apartment,
			open_plan,
			balcony,
			airports_nearest,
			parks_around3000,
			ponds_around3000
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.city USING(city_id)
	LEFT JOIN real_estate.type USING(type_id)
	LEFT JOIN real_estate.advertisement USING(id)
	INNER JOIN filtered_id AS fi ON f.id = fi.id
	WHERE type='город'  
		  --убираем аномальные значение по стоимости квадратного метра
		  AND last_price::NUMERIC/total_area BETWEEN (SELECT sqm_price_limit_l FROM limits) AND (SELECT sqm_price_limit_h FROM limits) 
         )
--  объявления без выбросов:
SELECT city_category, activity_category, 
	   COUNT(id) AS total_ads,
	   ROUND(AVG(sq_m_price)::numeric,2) AS avg_sqm_price, 
	   ROUND(AVG(total_area)::numeric,2) AS avg_area,	
	   PERCENTILE_DISC(0.5)WITHIN GROUP (ORDER BY rooms) AS rooms_median, 
	   PERCENTILE_DISC(0.5)WITHIN GROUP (ORDER BY balcony) AS balcony_median,
	   PERCENTILE_DISC(0.5)WITHIN GROUP (ORDER BY floors_total) AS floors_total_median,
	   PERCENTILE_DISC(0.5)WITHIN GROUP (ORDER BY floor) AS floor_median,	   
	   ROUND(AVG(airports_nearest)::numeric) AS avg_airport_nearest,
	   ROUND(AVG(parks_around3000)::numeric,2) AS avg_parks,
	   ROUND(AVG(ponds_around3000)::numeric,2) AS avg_ponds
FROM ads_categorized
GROUP BY city_category,activity_category
ORDER BY city_category, avg_area DESC;


-- Задача 2: Сезонность объявлений
-- 
-- 1. Анализ динамики активности покупателей: в какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? 
-- 2. Анализ периодов активной публикации объявлений и периодов, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)
-- 3. Влияние сезонных колебаний на среднюю стоимость кв.м. и  ср.площади квартир в объявлении

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY last_price::NUMERIC/total_area) AS sqm_price_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price::NUMERIC/total_area) AS sqm_price_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement USING(id)
),
--  id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
 monthly_data AS(--таблица со всеми необходимыми данными для расчетов
   SELECT f.id, total_area,
   last_price::real/total_area AS sqm_price,
   EXTRACT(MONTH FROM first_day_exposition) AS exp_month,
   EXTRACT(YEAR FROM first_day_exposition) AS exp_year,
   EXTRACT(MONTH FROM (first_day_exposition::date + days_exposition::int)::date) AS sale_month,
   EXTRACT(YEAR FROM (first_day_exposition::date + days_exposition::int)::date) AS sale_year
   FROM real_estate.flats AS f
   LEFT JOIN real_estate.advertisement AS a USING(id)
   LEFT JOIN real_estate.TYPE AS t USING(type_id)
   INNER JOIN filtered_id AS fid ON f.id=fid.id --фильтр по выбросам по характеристикам
   WHERE last_price::NUMERIC/total_area BETWEEN (SELECT sqm_price_limit_l FROM limits) AND (SELECT sqm_price_limit_h FROM limits) --фильтр выбросов по цене кв.м.
   AND TYPE='город'
   ), 
exposition_activity AS(
	SELECT exp_month,
 		COUNT(id) AS total_ads,
 		ROUND(AVG(total_area)::numeric,1) AS avg_total_area_exp
 	FROM monthly_data
 	WHERE exp_year BETWEEN 2015 AND 2018 --фильтрация неполных годов
 	GROUP BY exp_month),
sale_activity AS (
	SELECT sale_month,
 		COUNT(id) AS total_sells,
 		ROUND(AVG(sqm_price)::numeric) AS avg_sqm_price_sold,
 		ROUND(AVG(total_area)::numeric,1) AS avg_total_area_sold
 	FROM monthly_data
 	WHERE sale_year BETWEEN 2015 AND 2018
 	GROUP BY sale_month)
SELECT exp_month AS month,
	total_ads,
	total_sells,
	ROUND(total_ads::numeric/SUM(total_ads)OVER(),2) AS ad_exp_ratio,
	ROUND(total_sells::numeric/SUM(total_sells)OVER(),2) AS sells_ratio,
	RANK()OVER(ORDER BY total_ads DESC) AS exposition_rank,
	RANK()OVER(ORDER BY total_sells DESC) AS sells_rank,
	avg_sqm_price_sold, avg_total_area_exp, avg_total_area_sold
FROM exposition_activity
JOIN sale_activity AS s ON sale_month=exp_month
ORDER BY month;

-- 3: Анализ рынка недвижимости Ленобласти
-- Топ населённых пунктов Ленинградской области, которые наиболее активно публикуют объявления о продаже недвижимости
--
-- Топ населённых пунктов Ленинградской области, где самая высокая доля снятых с публикации объявлений 
--
-- Сравнение средней стоимости одного квадратного метра и средней площади продаваемых квартир в различных населённых пунктах 
--
-- Населенные пункты с самыми экстремальными значениями по продолжительности публикации объявлений
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
    JOIN real_estate.advertisement USING(id)
),
--  id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
SELECT city, 
	COUNT(a.id) AS total_ads, 
	COUNT(days_exposition) AS sold_ads, 
	ROUND(COUNT(days_exposition)::numeric/COUNT(a.id),2) AS sold_ratio,
	NTILE(3)OVER(ORDER BY COUNT(a.id) DESC) AS activity_groups,
	RANK()OVER(ORDER BY COUNT(days_exposition)::numeric/COUNT(a.id) DESC) AS sold_ratio_rank,
	ROUND(AVG(last_price::numeric/total_area)) AS avg_sqm_price,
	ROUND(AVG(total_area::numeric),1) AS avg_area,
	ROUND(AVG(days_exposition::numeric)) AS avg_exposition
FROM real_estate.advertisement AS a
LEFT JOIN real_estate.flats AS f USING(id)
LEFT JOIN real_estate.city USING(city_id)
JOIN filtered_id USING(id)
WHERE city <> 'Санкт-Петербург'
GROUP BY city
HAVING COUNT(a.id)>50
ORDER BY sold_ratio_rank;
