

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."late_stop_status" AS ENUM (
    'pending',
    'approved',
    'rejected'
);


ALTER TYPE "public"."late_stop_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_unexpected_shipment"("p_route_id" "uuid", "p_pickup_stop_id" "uuid", "p_laboratory_id" "uuid", "p_laboratory_client_id" "uuid", "p_shipment_ref" "text" DEFAULT NULL::"text", "p_proof_photo_url" "text" DEFAULT NULL::"text") RETURNS TABLE("shipment_id" "uuid", "delivery_stop_id" "uuid", "delivery_stop_type" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_delivery_stop_id UUID;
  v_delivery_stop_type TEXT;
  v_shipment_id UUID;
  v_shipment_ref TEXT;
BEGIN
  -- Trouver le stop de dépôt (depot_dropoff ou lab_dropoff) pour cette route
  SELECT id, stop_type INTO v_delivery_stop_id, v_delivery_stop_type
  FROM driver_route_stops 
  WHERE route_id = p_route_id 
    AND stop_type IN ('depot_dropoff', 'lab_dropoff')
  ORDER BY 
    CASE 
      WHEN stop_type = 'depot_dropoff' THEN 1 
      WHEN stop_type = 'lab_dropoff' THEN 2 
    END
  LIMIT 1;
  
  -- Vérifier qu'on a trouvé un stop de livraison
  IF v_delivery_stop_id IS NULL THEN
    RAISE EXCEPTION 'Aucun stop de dépôt trouvé pour la route %', p_route_id;
  END IF;
  
  -- Générer une référence de shipment si pas fournie
  IF p_shipment_ref IS NULL THEN
    SELECT CONCAT('Récupération inattendue - ', l.name) INTO v_shipment_ref
    FROM laboratories l
    WHERE l.id = p_laboratory_id;
  ELSE
    v_shipment_ref := p_shipment_ref;
  END IF;
  
  -- Créer le shipment avec unexpected = true
  INSERT INTO driver_route_shipments (
    shipment_ref,
    laboratory_id,
    pickup_stop_id,
    delivery_stop_id,
    pickup_status,
    delivery_status,
    route_id,
    laboratory_client_id,
    shipment_type,
    proof_photo_url,
    unexpected
  ) VALUES (
    v_shipment_ref,
    p_laboratory_id,
    p_pickup_stop_id,
    v_delivery_stop_id,
    'completed', -- Déjà récupéré puisque photo prise
    'pending',   -- En attente de livraison au dépôt
    p_route_id,
    p_laboratory_client_id,
    'client_pickup',
    p_proof_photo_url,
    true         -- NOUVEAU: Marquer comme inattendu
  ) RETURNING id INTO v_shipment_id;
  
  -- Retourner les informations du shipment créé
  RETURN QUERY SELECT v_shipment_id, v_delivery_stop_id, v_delivery_stop_type;
END;
$$;


ALTER FUNCTION "public"."add_unexpected_shipment"("p_route_id" "uuid", "p_pickup_stop_id" "uuid", "p_laboratory_id" "uuid", "p_laboratory_client_id" "uuid", "p_shipment_ref" "text", "p_proof_photo_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_route_state"("p_route_id" "uuid") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH route_stats AS (
        SELECT 
            r.id,
            r.status,
            r.total_distance_km,
            r.estimated_duration_minutes,
            COUNT(DISTINCT s.id) AS stops_count,
            COUNT(DISTINCT sh.id) AS shipments_count,
            MAX(s.stop_order) AS max_stop_order,
            COUNT(DISTINCT s.location_id) AS unique_locations,
            COUNT(CASE WHEN s.stop_type = 'client' THEN 1 END) AS client_stops,
            COUNT(CASE WHEN s.stop_type = 'lab_pickup' THEN 1 END) AS lab_pickup_stops,
            COUNT(CASE WHEN s.stop_type = 'lab_dropoff' THEN 1 END) AS lab_dropoff_stops,
            COUNT(CASE WHEN s.stop_type = 'depot_pickup' THEN 1 END) AS depot_pickup_stops,
            COUNT(CASE WHEN s.stop_type = 'depot_dropoff' THEN 1 END) AS depot_dropoff_stops
        FROM driver_routes r
        LEFT JOIN driver_route_stops s ON s.route_id = r.id
        LEFT JOIN driver_route_shipments sh ON sh.route_id = r.id
        WHERE r.id = p_route_id
        GROUP BY r.id, r.status, r.total_distance_km, r.estimated_duration_minutes
    ),
    consecutive_clients AS (
        SELECT COUNT(*) AS consecutive_client_count
        FROM (
            SELECT 
                s1.id AS stop1_id,
                s2.id AS stop2_id,
                s1.location_id,
                s1.stop_order AS order1,
                s2.stop_order AS order2
            FROM driver_route_stops s1
            JOIN driver_route_stops s2 
                ON s1.route_id = s2.route_id 
                AND s1.location_id = s2.location_id
                AND s2.stop_order = s1.stop_order + 1
                AND s1.stop_type = 'client'
                AND s2.stop_type = 'client'
            WHERE s1.route_id = p_route_id
        ) AS pairs
    )
    SELECT json_build_object(
        'route_id', rs.id,
        'status', rs.status,
        'total_distance_km', rs.total_distance_km,
        'estimated_duration_minutes', rs.estimated_duration_minutes,
        'stops_count', rs.stops_count,
        'shipments_count', rs.shipments_count,
        'max_stop_order', rs.max_stop_order,
        'unique_locations', rs.unique_locations,
        'stop_types', json_build_object(
            'client', rs.client_stops,
            'lab_pickup', rs.lab_pickup_stops,
            'lab_dropoff', rs.lab_dropoff_stops,
            'depot_pickup', rs.depot_pickup_stops,
            'depot_dropoff', rs.depot_dropoff_stops
        ),
        'consecutive_client_stops', cc.consecutive_client_count,
        'needs_fusion', cc.consecutive_client_count > 0
    ) INTO v_result
    FROM route_stats rs, consecutive_clients cc;
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."analyze_route_state"("p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_driver_statistics"("p_driver_id" "uuid", "p_period_start" "date", "p_period_end" "date") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_basic_stats RECORD;
  v_stops_stats RECORD;
  v_shipments_stats RECORD;
  v_weekly_activity JSONB;
  v_hourly_distribution JSONB;
  v_client_coverage JSONB;
BEGIN
  -- Suppression des anciennes statistiques pour cette période
  DELETE FROM driver_statistics 
  WHERE driver_id = p_driver_id 
    AND period_start = p_period_start 
    AND period_end = p_period_end;

  -- Calcul des statistiques de base (routes)
  SELECT 
    COUNT(DISTINCT dr.date) as working_days,
    COALESCE(AVG(dr.estimated_duration)/60.0, 0) as avg_duration_hours,
    COALESCE(SUM(dr.total_distance_km), 0) as total_distance,
    COUNT(dr.id) as total_routes,
    COUNT(CASE WHEN dr.status = 'completed' THEN 1 END) as completed_routes
  INTO v_basic_stats
  FROM driver_routes dr
  WHERE dr.driver_id = p_driver_id
    AND dr.date BETWEEN p_period_start AND p_period_end;

  -- Calcul des statistiques d'arrêts (séparément)
  SELECT 
    COUNT(drs.id) as total_stops,
    COALESCE(AVG(route_stops.stop_count), 0) as avg_stops_per_route
  INTO v_stops_stats
  FROM driver_routes dr
  LEFT JOIN driver_route_stops drs ON dr.id = drs.route_id
  LEFT JOIN (
    SELECT route_id, COUNT(*) as stop_count
    FROM driver_route_stops
    GROUP BY route_id
  ) route_stops ON dr.id = route_stops.route_id
  WHERE dr.driver_id = p_driver_id
    AND dr.date BETWEEN p_period_start AND p_period_end;

  -- Calcul des statistiques de shipments (séparément)
  SELECT 
    COUNT(CASE WHEN dsh.pickup_status = 'completed' THEN 1 END) as completed_pickups,
    COUNT(CASE WHEN dsh.delivery_status = 'completed' THEN 1 END) as completed_deliveries,
    COUNT(CASE WHEN dsh.pickup_status IS NOT NULL THEN 1 END) as total_pickups,
    COUNT(CASE WHEN dsh.delivery_status IS NOT NULL THEN 1 END) as total_deliveries
  INTO v_shipments_stats
  FROM driver_routes dr
  LEFT JOIN driver_route_shipments dsh ON dr.id = dsh.route_id
  WHERE dr.driver_id = p_driver_id
    AND dr.date BETWEEN p_period_start AND p_period_end;

  -- Calcul des données d'activité hebdomadaire (heures de travail par jour)
  SELECT jsonb_agg(
    jsonb_build_object(
      'day', day_name,
      'hours', COALESCE(ROUND(avg_hours, 1), 0)
    ) ORDER BY day_num
  ) INTO v_weekly_activity
  FROM (
    SELECT 
      day_name,
      day_num,
      AVG(dr.estimated_duration / 60.0) as avg_hours
    FROM (
      SELECT 'Lun' as day_name, 1 as day_num
      UNION SELECT 'Mar', 2
      UNION SELECT 'Mer', 3
      UNION SELECT 'Jeu', 4
      UNION SELECT 'Ven', 5
    ) days
    LEFT JOIN driver_routes dr ON EXTRACT(DOW FROM dr.date) = days.day_num
      AND dr.driver_id = p_driver_id
      AND dr.date BETWEEN p_period_start AND p_period_end
    GROUP BY day_name, day_num
  ) daily_stats;

  -- Calcul de la distribution horaire (activité livraisons/récupérations par jour)
  SELECT jsonb_agg(
    jsonb_build_object(
      'day', day_name,
      'deliveries', COALESCE(deliveries, 0),
      'pickups', COALESCE(pickups, 0)
    ) ORDER BY day_num
  ) INTO v_hourly_distribution
  FROM (
    SELECT 
      day_name,
      day_num,
      SUM(CASE WHEN dsh.delivery_status = 'completed' THEN 1 ELSE 0 END) as deliveries,
      SUM(CASE WHEN dsh.pickup_status = 'completed' THEN 1 ELSE 0 END) as pickups
    FROM (
      SELECT 'Lun' as day_name, 1 as day_num
      UNION SELECT 'Mar', 2
      UNION SELECT 'Mer', 3
      UNION SELECT 'Jeu', 4
      UNION SELECT 'Ven', 5
      UNION SELECT 'Sam', 6
      UNION SELECT 'Dim', 0
    ) days
    LEFT JOIN driver_routes dr ON EXTRACT(DOW FROM dr.date) = days.day_num
      AND dr.driver_id = p_driver_id
      AND dr.date BETWEEN p_period_start AND p_period_end
    LEFT JOIN driver_route_shipments dsh ON dr.id = dsh.route_id
    GROUP BY day_name, day_num
  ) daily_stats;

  -- Calcul des clients assignés à ce livreur (pas les plus visités)
  SELECT jsonb_agg(
    jsonb_build_object(
      'name', client_name,
      'lat', latitude,
      'lng', longitude,
      'type', client_type
    )
  ) INTO v_client_coverage
  FROM (
    SELECT 
      COALESCE(lc.name, l.formatted_address) as client_name,
      l.latitude,
      l.longitude,
      lc.client_type
    FROM laboratory_clients lc
    JOIN locations l ON lc.location_id = l.id
    WHERE lc.driver_id = p_driver_id
    ORDER BY lc.name
  ) client_stats;

  -- Insertion des statistiques calculées
  INSERT INTO driver_statistics (
    driver_id,
    period_start,
    period_end,
    total_working_days,
    average_duration_hours,
    total_distance_km,
    average_distance_per_day,
    total_routes,
    completed_routes,
    total_stops,
    average_stops_per_route,
    total_pickups,
    total_deliveries,
    completed_pickups,
    completed_deliveries,
    route_completion_rate,
    pickup_success_rate,
    delivery_success_rate,
    weekly_activity,
    hourly_distribution,
    client_coverage
  ) VALUES (
    p_driver_id,
    p_period_start,
    p_period_end,
    GREATEST(v_basic_stats.working_days, 0),
    v_basic_stats.avg_duration_hours,
    v_basic_stats.total_distance,
    CASE WHEN v_basic_stats.working_days > 0 THEN v_basic_stats.total_distance / v_basic_stats.working_days ELSE 0 END,
    v_basic_stats.total_routes,
    v_basic_stats.completed_routes,
    v_stops_stats.total_stops,
    v_stops_stats.avg_stops_per_route,
    v_shipments_stats.total_pickups,
    v_shipments_stats.total_deliveries,
    v_shipments_stats.completed_pickups,
    v_shipments_stats.completed_deliveries,
    CASE WHEN v_basic_stats.total_routes > 0 THEN (v_basic_stats.completed_routes::DECIMAL / v_basic_stats.total_routes) * 100 ELSE 0 END,
    CASE WHEN v_shipments_stats.total_pickups > 0 THEN (v_shipments_stats.completed_pickups::DECIMAL / v_shipments_stats.total_pickups) * 100 ELSE 0 END,
    CASE WHEN v_shipments_stats.total_deliveries > 0 THEN (v_shipments_stats.completed_deliveries::DECIMAL / v_shipments_stats.total_deliveries) * 100 ELSE 0 END,
    v_weekly_activity,
    v_hourly_distribution,
    v_client_coverage
  );
END;
$$;


ALTER FUNCTION "public"."calculate_driver_statistics"("p_driver_id" "uuid", "p_period_start" "date", "p_period_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_laboratory_statistics"("p_laboratory_id" "uuid", "p_period_start" "date", "p_period_end" "date") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_stats_id UUID;
    v_total_shipments INTEGER := 0;
    v_completed_shipments INTEGER := 0;
    v_failed_shipments INTEGER := 0;
    v_success_rate DECIMAL(5,2) := 0.00;
    v_failure_rate DECIMAL(5,2) := 0.00;
    v_most_client_id UUID;
    v_most_client_name TEXT;
    v_most_count INTEGER := 0;
    v_least_client_id UUID;
    v_least_client_name TEXT;
    v_least_count INTEGER := 999999;
    v_weekly_activity JSONB;
    v_market_share JSONB;
    v_lab_volume INTEGER := 0;
    v_total_volume INTEGER := 0;
BEGIN
    -- 1. Calculer les statistiques générales (shipments)
    SELECT 
        COUNT(*) as total,
        COUNT(CASE WHEN pickup_status = 'completed' AND delivery_status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN pickup_status = 'failed' OR delivery_status = 'failed' THEN 1 END) as failed
    INTO v_total_shipments, v_completed_shipments, v_failed_shipments
    FROM driver_route_shipments drs
    JOIN driver_routes dr ON drs.route_id = dr.id
    WHERE drs.laboratory_id = p_laboratory_id
      AND dr.date BETWEEN p_period_start AND p_period_end;
    
    -- Calculer les pourcentages
    IF v_total_shipments > 0 THEN
        v_success_rate := ROUND((v_completed_shipments::DECIMAL / v_total_shipments) * 100, 2);
        v_failure_rate := ROUND((v_failed_shipments::DECIMAL / v_total_shipments) * 100, 2);
    END IF;
    
    -- 2. Trouver le client le plus visité (STOPS, pas shipments)
    SELECT lc.id, lc.name, COUNT(DISTINCT drs.id) as visit_count
    INTO v_most_client_id, v_most_client_name, v_most_count
    FROM laboratory_clients lc
    JOIN locations loc ON lc.location_id = loc.id
    JOIN driver_route_stops drs ON drs.location_id = loc.id
    JOIN driver_routes dr ON drs.route_id = dr.id
    WHERE lc.laboratory_id = p_laboratory_id
      AND dr.date BETWEEN p_period_start AND p_period_end
      AND drs.stop_type IN ('client', 'client_pickup', 'client_delivery', 'client_both')
    GROUP BY lc.id, lc.name
    ORDER BY visit_count DESC
    LIMIT 1;
    
    -- 3. Trouver le client le moins visité (avec au moins 1 visite)
    SELECT lc.id, lc.name, COUNT(DISTINCT drs.id) as visit_count
    INTO v_least_client_id, v_least_client_name, v_least_count
    FROM laboratory_clients lc
    JOIN locations loc ON lc.location_id = loc.id
    JOIN driver_route_stops drs ON drs.location_id = loc.id
    JOIN driver_routes dr ON drs.route_id = dr.id
    WHERE lc.laboratory_id = p_laboratory_id
      AND dr.date BETWEEN p_period_start AND p_period_end
      AND drs.stop_type IN ('client', 'client_pickup', 'client_delivery', 'client_both')
    GROUP BY lc.id, lc.name
    HAVING COUNT(DISTINCT drs.id) > 0
    ORDER BY visit_count ASC
    LIMIT 1;
    
    -- 4. Calculer l'activité hebdomadaire avec moyennes des autres labos
    WITH lab_daily_stats AS (
        -- Activité du laboratoire sélectionné par jour de semaine
        SELECT 
            EXTRACT(DOW FROM dr.date) as day_of_week,
            CASE EXTRACT(DOW FROM dr.date)
                WHEN 1 THEN 'Lun'
                WHEN 2 THEN 'Mar'
                WHEN 3 THEN 'Mer'
                WHEN 4 THEN 'Jeu'
                WHEN 5 THEN 'Ven'
                WHEN 6 THEN 'Sam'
                WHEN 0 THEN 'Dim'
            END as day_name,
            COUNT(CASE WHEN drs.shipment_type = 'client_delivery' THEN 1 END) as deliveries,
            COUNT(CASE WHEN drs.shipment_type = 'client_pickup' THEN 1 END) as pickups
        FROM driver_route_shipments drs
        JOIN driver_routes dr ON drs.route_id = dr.id
        WHERE drs.laboratory_id = p_laboratory_id
          AND dr.date BETWEEN p_period_start AND p_period_end
        GROUP BY EXTRACT(DOW FROM dr.date)
    ),
    other_labs_avg AS (
        -- Moyenne par jour de semaine pour les AUTRES laboratoires
        SELECT 
            EXTRACT(DOW FROM dr.date) as day_of_week,
            CASE EXTRACT(DOW FROM dr.date)
                WHEN 1 THEN 'Lun'
                WHEN 2 THEN 'Mar'
                WHEN 3 THEN 'Mer'
                WHEN 4 THEN 'Jeu'
                WHEN 5 THEN 'Ven'
                WHEN 6 THEN 'Sam'
                WHEN 0 THEN 'Dim'
            END as day_name,
            -- Moyenne des livraisons par laboratoire par jour de semaine
            ROUND(
                COUNT(CASE WHEN drs.shipment_type = 'client_delivery' THEN 1 END)::DECIMAL 
                / NULLIF(COUNT(DISTINCT drs.laboratory_id), 0), 
                1
            ) as avg_deliveries,
            -- Moyenne des récupérations par laboratoire par jour de semaine
            ROUND(
                COUNT(CASE WHEN drs.shipment_type = 'client_pickup' THEN 1 END)::DECIMAL 
                / NULLIF(COUNT(DISTINCT drs.laboratory_id), 0), 
                1
            ) as avg_pickups
        FROM driver_route_shipments drs
        JOIN driver_routes dr ON drs.route_id = dr.id
        WHERE drs.laboratory_id != p_laboratory_id -- EXCLURE le labo sélectionné
          AND dr.date BETWEEN p_period_start AND p_period_end
        GROUP BY EXTRACT(DOW FROM dr.date)
    ),
    all_days AS (
        -- S'assurer que tous les jours de la semaine sont présents (avec VALUES)
        SELECT * FROM (VALUES 
            (0, 'Dim'),
            (1, 'Lun'),
            (2, 'Mar'),
            (3, 'Mer'),
            (4, 'Jeu'),
            (5, 'Ven'),
            (6, 'Sam')
        ) AS days(day_of_week, day_name)
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'name', ad.day_name,
            'deliveries', COALESCE(lds.deliveries, 0),
            'pickups', COALESCE(lds.pickups, 0),
            'avgDeliveries', COALESCE(ola.avg_deliveries, 0),
            'avgPickups', COALESCE(ola.avg_pickups, 0)
        )
        ORDER BY ad.day_of_week
    ) INTO v_weekly_activity
    FROM all_days ad
    LEFT JOIN lab_daily_stats lds ON ad.day_of_week = lds.day_of_week
    LEFT JOIN other_labs_avg ola ON ad.day_of_week = ola.day_of_week;
    
    -- 5. Calculer les parts de marché
    -- Volume du laboratoire
    SELECT COUNT(*) INTO v_lab_volume
    FROM driver_route_shipments drs
    JOIN driver_routes dr ON drs.route_id = dr.id
    WHERE drs.laboratory_id = p_laboratory_id
      AND dr.date BETWEEN p_period_start AND p_period_end;
    
    -- Volume total tous laboratoires
    SELECT COUNT(*) INTO v_total_volume
    FROM driver_route_shipments drs
    JOIN driver_routes dr ON drs.route_id = dr.id
    WHERE dr.date BETWEEN p_period_start AND p_period_end;
    
    -- Format JSON pour parts de marché
    v_market_share := jsonb_build_object(
        'lab_volume', v_lab_volume,
        'total_volume', v_total_volume,
        'lab_percentage', CASE WHEN v_total_volume > 0 THEN ROUND((v_lab_volume::DECIMAL / v_total_volume) * 100, 1) ELSE 0 END,
        'other_percentage', CASE WHEN v_total_volume > 0 THEN ROUND(((v_total_volume - v_lab_volume)::DECIMAL / v_total_volume) * 100, 1) ELSE 0 END
    );
    
    -- 6. Insérer ou mettre à jour les statistiques
    INSERT INTO laboratory_statistics (
        laboratory_id, period_start, period_end,
        total_shipments, completed_shipments, failed_shipments,
        success_rate, failure_rate,
        most_delivered_client_id, most_delivered_client_name, most_delivered_count,
        least_delivered_client_id, least_delivered_client_name, least_delivered_count,
        weekly_activity, market_share_data,
        calculated_at
    ) VALUES (
        p_laboratory_id, p_period_start, p_period_end,
        v_total_shipments, v_completed_shipments, v_failed_shipments,
        v_success_rate, v_failure_rate,
        v_most_client_id, v_most_client_name, COALESCE(v_most_count, 0),
        v_least_client_id, v_least_client_name, COALESCE(v_least_count, 0),
        COALESCE(v_weekly_activity, '[]'::jsonb), v_market_share,
        NOW()
    )
    ON CONFLICT (laboratory_id, period_start, period_end) 
    DO UPDATE SET
        total_shipments = EXCLUDED.total_shipments,
        completed_shipments = EXCLUDED.completed_shipments,
        failed_shipments = EXCLUDED.failed_shipments,
        success_rate = EXCLUDED.success_rate,
        failure_rate = EXCLUDED.failure_rate,
        most_delivered_client_id = EXCLUDED.most_delivered_client_id,
        most_delivered_client_name = EXCLUDED.most_delivered_client_name,
        most_delivered_count = EXCLUDED.most_delivered_count,
        least_delivered_client_id = EXCLUDED.least_delivered_client_id,
        least_delivered_client_name = EXCLUDED.least_delivered_client_name,
        least_delivered_count = EXCLUDED.least_delivered_count,
        weekly_activity = EXCLUDED.weekly_activity,
        market_share_data = EXCLUDED.market_share_data,
        calculated_at = NOW(),
        updated_at = NOW()
    RETURNING id INTO v_stats_id;
    
    RETURN v_stats_id;
END;
$$;


ALTER FUNCTION "public"."calculate_laboratory_statistics"("p_laboratory_id" "uuid", "p_period_start" "date", "p_period_end" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calculate_laboratory_statistics"("p_laboratory_id" "uuid", "p_period_start" "date", "p_period_end" "date") IS 'Calcule les statistiques d''un laboratoire avec moyenne des autres labos. IMPORTANT: most/least delivered compte les VISITES (stops), weekly_activity inclut avgDeliveries/avgPickups des autres labos.';



CREATE OR REPLACE FUNCTION "public"."check_orphan_shipments"("p_route_id" "uuid") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_orphan_count INT;
    v_orphan_shipments JSON;
BEGIN
    WITH orphans AS (
        SELECT s.id, s.shipment_ref, s.pickup_stop_id, s.delivery_stop_id
        FROM driver_route_shipments s
        WHERE s.route_id = p_route_id
          AND (
              NOT EXISTS (
                  SELECT 1 FROM driver_route_stops st 
                  WHERE st.id = s.pickup_stop_id
              )
              OR NOT EXISTS (
                  SELECT 1 FROM driver_route_stops st 
                  WHERE st.id = s.delivery_stop_id
              )
          )
        LIMIT 10
    )
    SELECT 
        COUNT(*) AS orphan_count,
        json_agg(row_to_json(orphans)) AS orphan_shipments
    INTO v_orphan_count, v_orphan_shipments
    FROM orphans;
    
    RETURN json_build_object(
        'orphan_count', COALESCE(v_orphan_count, 0),
        'orphan_shipments', COALESCE(v_orphan_shipments, '[]'::json)
    );
END;
$$;


ALTER FUNCTION "public"."check_orphan_shipments"("p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_pending_routes"("target_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    DELETE FROM driver_routes
    WHERE status IN ('pending', 'optimized')
    AND date = target_date;
    
    RAISE NOTICE 'Routes pending/optimized supprimées pour la date %', target_date;
END;
$$;


ALTER FUNCTION "public"."cleanup_pending_routes"("target_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_driver_shipments"("p_route_id" "uuid", "p_driver_id" "uuid", "shipments_data" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    shipment_record JSONB;
    pickup_stop_id UUID;
    delivery_stop_id UUID;
    shipment_ref TEXT;
    specific_shipment_type TEXT;
    client_name TEXT;
    lab_name TEXT;
BEGIN
    FOR shipment_record IN SELECT * FROM jsonb_array_elements(shipments_data)
    LOOP
        -- Récupérer les stops correspondants
        SELECT drs.id INTO pickup_stop_id
        FROM driver_route_stops drs
        WHERE drs.route_id = p_route_id
        AND drs.location_id = (shipment_record->>'from_location_id')::UUID;
        
        SELECT drs.id INTO delivery_stop_id
        FROM driver_route_stops drs
        WHERE drs.route_id = p_route_id
        AND drs.location_id = (shipment_record->>'to_location_id')::UUID;
        
        -- Récupérer les noms pour la référence
        SELECT lc.name INTO client_name
        FROM laboratory_clients lc
        WHERE lc.id = (shipment_record->>'responsible_client_id')::UUID;
        
        SELECT lab.name INTO lab_name
        FROM laboratories lab
        WHERE lab.id = (shipment_record->>'laboratory_id')::UUID;
        
        -- CORRECTION : Générer shipment_ref et shipment_type UNIFORMES selon la logique métier
        CASE (shipment_record->>'shipment_type')::TEXT
            WHEN 'lab_to_client' THEN 
                -- Livraison normale : labo → client
                shipment_ref := 'Livraison ' || COALESCE(client_name, 'Client');
                specific_shipment_type := 'client_delivery';
            WHEN 'client_to_lab' THEN 
                -- Récupération normale : client → labo
                shipment_ref := 'Récupération ' || COALESCE(client_name, 'Client');
                specific_shipment_type := 'client_pickup';
            WHEN 'lab_to_depot' THEN 
                -- CORRECTION : Livraison avec flag (labo → dépôt pour le client)
                -- Affiché comme une livraison normale pour les autres apps
                shipment_ref := 'Livraison ' || COALESCE(client_name, 'Client');
                specific_shipment_type := 'client_delivery';
            WHEN 'client_to_depot' THEN 
                -- CORRECTION : Récupération avec flag (client → dépôt)
                -- Affiché comme une récupération normale pour les autres apps
                shipment_ref := 'Récupération ' || COALESCE(client_name, 'Client');
                specific_shipment_type := 'client_pickup';
            ELSE 
                shipment_ref := 'Shipment ' || (shipment_record->>'shipment_type')::TEXT;
                specific_shipment_type := (shipment_record->>'shipment_type')::TEXT;
        END CASE;
        
        -- Créer le driver_route_shipment avec AFFICHAGE UNIFORME
        INSERT INTO driver_route_shipments (
            shipment_ref,
            laboratory_id,
            pickup_stop_id,
            delivery_stop_id,
            pickup_time,
            delivery_time,
            pickup_status,
            delivery_status,
            issue_type,
            issue_description,
            proof_photo_url,
            route_id,
            laboratory_client_id,
            shipment_type,
            unexpected,
            is_late_shipment,
            created_at,
            updated_at
        ) VALUES (
            shipment_ref,
            (shipment_record->>'laboratory_id')::UUID,
            pickup_stop_id,
            delivery_stop_id,
            NULL, -- pickup_time
            NULL, -- delivery_time  
            'pending', -- pickup_status
            'pending', -- delivery_status
            NULL, -- issue_type
            NULL, -- issue_description
            NULL, -- proof_photo_url
            p_route_id,
            (shipment_record->>'responsible_client_id')::UUID,
            specific_shipment_type, -- client_delivery ou client_pickup TOUJOURS
            false, -- unexpected
            false, -- is_late_shipment
            NOW(), -- created_at
            NOW()  -- updated_at
        );
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."create_driver_shipments"("p_route_id" "uuid", "p_driver_id" "uuid", "shipments_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_necessary_stops"("p_route_id" "uuid", "shipments_data" "jsonb") RETURNS TABLE("stop_id" "uuid", "location_id" "uuid", "stop_type" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    shipment_record JSONB;
    stop_order_counter INTEGER := 1;
    pickup_stop_id UUID;
    delivery_stop_id UUID;
    depot_location_id UUID;
    pickup_stop_type TEXT;
    delivery_stop_type TEXT;
BEGIN
    -- Récupérer le dépôt
    SELECT d.location_id INTO depot_location_id
    FROM depot d WHERE d.is_active = true LIMIT 1;
    
    -- Pour chaque shipment, créer des STOPS DÉDIÉS avec la logique correcte
    FOR shipment_record IN SELECT * FROM jsonb_array_elements(shipments_data)
    LOOP
        -- DÉTERMINER LES BONS STOP_TYPE selon la logique métier
        CASE (shipment_record->>'shipment_type')::TEXT
            WHEN 'lab_to_client' THEN 
                pickup_stop_type := 'lab_pickup';
                delivery_stop_type := 'client';
                
            WHEN 'lab_to_depot' THEN 
                pickup_stop_type := 'lab_pickup';
                delivery_stop_type := 'depot_dropoff';
                
            WHEN 'client_to_lab' THEN 
                pickup_stop_type := 'client';
                delivery_stop_type := 'lab_dropoff';
                
            WHEN 'client_to_depot' THEN 
                pickup_stop_type := 'client';
                delivery_stop_type := 'depot_dropoff';
                
            ELSE
                pickup_stop_type := 'client';
                delivery_stop_type := 'client';
        END CASE;
        
        -- CRÉER UN STOP PICKUP DÉDIÉ (pas de partage)
        INSERT INTO driver_route_stops (
            route_id,
            location_id,
            stop_order,
            stop_type,
            created_at
        ) VALUES (
            p_route_id,
            (shipment_record->>'from_location_id')::UUID,
            stop_order_counter,
            pickup_stop_type, -- TYPE DÉDIÉ AU SHIPMENT
            NOW()
        ) RETURNING id INTO pickup_stop_id;
        
        stop_order_counter := stop_order_counter + 1;
        
        RETURN QUERY SELECT 
            pickup_stop_id, 
            (shipment_record->>'from_location_id')::UUID, 
            pickup_stop_type;
        
        -- CRÉER UN STOP DELIVERY DÉDIÉ (pas de partage)
        INSERT INTO driver_route_stops (
            route_id,
            location_id,
            stop_order,
            stop_type,
            created_at
        ) VALUES (
            p_route_id,
            (shipment_record->>'to_location_id')::UUID,
            stop_order_counter,
            delivery_stop_type, -- TYPE DÉDIÉ AU SHIPMENT
            NOW()
        ) RETURNING id INTO delivery_stop_id;
        
        stop_order_counter := stop_order_counter + 1;
        
        RETURN QUERY SELECT 
            delivery_stop_id, 
            (shipment_record->>'to_location_id')::UUID, 
            delivery_stop_type;
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."create_necessary_stops"("p_route_id" "uuid", "shipments_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_client_complete"("client_id_param" "uuid", "location_id_param" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
BEGIN
  -- Supprimer les photos liées à la location
  DELETE FROM public.location_photos
  WHERE location_id = location_id_param;

  -- Supprimer le client
  DELETE FROM public.laboratory_clients
  WHERE id = client_id_param;

  -- Supprimer la location
  DELETE FROM public.locations
  WHERE id = location_id_param;

  RETURN TRUE;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Erreur lors de la suppression: %', SQLERRM;
    RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."delete_client_complete"("client_id_param" "uuid", "location_id_param" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_lab_tour_shipments"("lab_tour_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  DELETE FROM lab_tour_shipments lts
  WHERE lts.lab_tour_id = delete_lab_tour_shipments.lab_tour_id;
END;
$$;


ALTER FUNCTION "public"."delete_lab_tour_shipments"("lab_tour_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_shipments_for_lab_tour"("lab_tour_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    DELETE FROM shipments s
    WHERE s.lab_tour_id = delete_shipments_for_lab_tour.lab_tour_id;
END;
$$;


ALTER FUNCTION "public"."delete_shipments_for_lab_tour"("lab_tour_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."determine_driver_shipments"("driver_id" "uuid", "target_date" "date") RETURNS TABLE("lab_tour_shipment_id" "uuid", "shipment_type" "text", "from_location_id" "uuid", "to_location_id" "uuid", "laboratory_id" "uuid", "responsible_client_id" "uuid", "laboratory_name" "text", "client_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    WITH depot_info AS (
        SELECT d.location_id as depot_location_id
        FROM depot d WHERE d.is_active = true LIMIT 1
    )
    SELECT DISTINCT
        lts.id as lab_tour_shipment_id,
        lts.shipment_type,
        lts.from_location_id,
        lts.to_location_id,
        lt.laboratory_id,
        -- LOGIQUE CORRECTE sans produit cartésien
        CASE 
            WHEN lts.shipment_type = 'lab_to_depot' THEN (
                -- Pour lab_to_depot, trouver le client responsable (is_pickup_depot = true)
                SELECT lc.id 
                FROM laboratory_clients lc
                JOIN lab_tour_stops lts2 ON lts2.client_id = lc.id
                WHERE lts2.tour_id = lt.id 
                AND lc.is_pickup_depot = true 
                AND lts2.has_delivery = true
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            WHEN lts.shipment_type = 'client_to_depot' THEN (
                -- Pour client_to_depot, le client à l'origine
                SELECT lc.id 
                FROM laboratory_clients lc
                WHERE lc.location_id = lts.from_location_id
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            WHEN lts.shipment_type = 'lab_to_client' THEN (
                -- Pour lab_to_client, le client destination
                SELECT lc.id 
                FROM laboratory_clients lc
                WHERE lc.location_id = lts.to_location_id
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            WHEN lts.shipment_type = 'client_to_lab' THEN (
                -- Pour client_to_lab, le client source
                SELECT lc.id 
                FROM laboratory_clients lc
                WHERE lc.location_id = lts.from_location_id
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            ELSE NULL
        END as responsible_client_id,
        lab.name as laboratory_name,
        CASE 
            WHEN lts.shipment_type = 'lab_to_depot' THEN (
                SELECT lc.name 
                FROM laboratory_clients lc
                JOIN lab_tour_stops lts2 ON lts2.client_id = lc.id
                WHERE lts2.tour_id = lt.id 
                AND lc.is_pickup_depot = true 
                AND lts2.has_delivery = true
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            WHEN lts.shipment_type = 'client_to_depot' THEN (
                SELECT lc.name 
                FROM laboratory_clients lc
                WHERE lc.location_id = lts.from_location_id
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            WHEN lts.shipment_type = 'lab_to_client' THEN (
                SELECT lc.name 
                FROM laboratory_clients lc
                WHERE lc.location_id = lts.to_location_id
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            WHEN lts.shipment_type = 'client_to_lab' THEN (
                SELECT lc.name 
                FROM laboratory_clients lc
                WHERE lc.location_id = lts.from_location_id
                AND lc.driver_id = determine_driver_shipments.driver_id
                LIMIT 1
            )
            ELSE 'Unknown'
        END as client_name
    FROM lab_tour_shipments lts
    JOIN lab_tours lt ON lts.lab_tour_id = lt.id
    JOIN laboratories lab ON lt.laboratory_id = lab.id
    CROSS JOIN depot_info di
    WHERE lt.date = target_date
    AND lt.status IN ('validated', 'pending_changes')
    -- Filtrer pour ne garder que les shipments pertinents pour ce chauffeur
    AND (
        -- Le shipment concerne une location de ce chauffeur
        EXISTS (
            SELECT 1 FROM laboratory_clients lc2 
            WHERE lc2.driver_id = determine_driver_shipments.driver_id
            AND lc2.location_id IN (lts.from_location_id, lts.to_location_id)
        )
        OR 
        -- Ou c'est un shipment lab/depot impliquant ce chauffeur
        (
            (lts.from_location_id = lab.location_id OR lts.to_location_id = lab.location_id)
            AND EXISTS (
                SELECT 1 FROM laboratory_clients lc3 
                JOIN lab_tour_stops lts3 ON lts3.client_id = lc3.id
                WHERE lc3.driver_id = determine_driver_shipments.driver_id
                AND lts3.tour_id = lt.id
            )
        )
        OR
        -- Ou c'est un shipment depot impliquant ce chauffeur
        (
            (lts.from_location_id = di.depot_location_id OR lts.to_location_id = di.depot_location_id)
            AND EXISTS (
                SELECT 1 FROM laboratory_clients lc4 
                JOIN lab_tour_stops lts4 ON lts4.client_id = lc4.id
                WHERE lc4.driver_id = determine_driver_shipments.driver_id
                AND lts4.tour_id = lt.id
            )
        )
    );
END;
$$;


ALTER FUNCTION "public"."determine_driver_shipments"("driver_id" "uuid", "target_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."driver_statistics_health_report"() RETURNS TABLE("metric" "text", "value" "text", "status" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    'Total livreurs'::TEXT,
    COUNT(*)::TEXT,
    CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'WARNING' END::TEXT
  FROM drivers
  
  UNION ALL
  
  SELECT 
    'Statistiques récentes'::TEXT,
    COUNT(*)::TEXT,
    CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'WARNING' END::TEXT
  FROM driver_statistics
  WHERE calculated_at >= CURRENT_DATE - INTERVAL '7 days'
  
  UNION ALL
  
  SELECT 
    'Dernière mise à jour'::TEXT,
    COALESCE(MAX(calculated_at)::TEXT, 'Jamais'),
    CASE 
      WHEN MAX(calculated_at) >= CURRENT_DATE - INTERVAL '1 day' THEN 'OK'
      WHEN MAX(calculated_at) >= CURRENT_DATE - INTERVAL '7 days' THEN 'WARNING'
      ELSE 'CRITICAL'
    END::TEXT
  FROM driver_statistics
  
  UNION ALL
  
  SELECT 
    'Routes avec données'::TEXT,
    COUNT(DISTINCT dr.id)::TEXT,
    CASE WHEN COUNT(DISTINCT dr.id) > 0 THEN 'OK' ELSE 'INFO' END::TEXT
  FROM driver_routes dr
  WHERE dr.date >= CURRENT_DATE - INTERVAL '30 days';
END;
$$;


ALTER FUNCTION "public"."driver_statistics_health_report"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_driver_routes"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_current_date DATE := CURRENT_DATE; -- Utiliser la date du jour directement
    v_driver_id UUID;
    v_driver_route_id UUID;
    v_depot_location_id UUID;
    v_current_stop_order INTEGER;
    
    -- Variables pour les stops
    v_depot_pickup_needed BOOLEAN;
    v_depot_dropoff_needed BOOLEAN;
    v_depot_pickup_id UUID;
    v_depot_dropoff_id UUID;
    
    -- Variables pour les labs et clients
    v_lab_id UUID;
    v_lab_name TEXT;
    v_lab_location_id UUID;
    v_lab_pickup_id UUID;
    v_lab_dropoff_id UUID;
    v_client_id UUID;
    v_client_name TEXT;
    v_client_location_id UUID;
    v_client_pickup_id UUID;
    v_client_delivery_id UUID;
    
    -- Tables pour stocker les IDs
    v_lab_pickups JSONB := '{}'::JSONB;
    v_lab_dropoffs JSONB := '{}'::JSONB;
    v_client_pickups JSONB := '{}'::JSONB;
    v_client_deliveries JSONB := '{}'::JSONB;
    
    -- Variables pour les shipments
    v_shipment_type TEXT;
    v_from_location_id UUID;
    v_to_location_id UUID;
    v_pickup_stop_id UUID;
    v_delivery_stop_id UUID;
BEGIN
    -- Récupérer le dépôt actif
    SELECT location_id INTO v_depot_location_id
    FROM depot 
    WHERE is_active = true
    LIMIT 1;
    
    IF v_depot_location_id IS NULL THEN
        RAISE EXCEPTION 'Aucun dépôt actif trouvé';
    END IF;
    
    -- Supprimer d'abord les tournées existantes en statut 'pending' ou 'optimized' pour la date du jour
    DELETE FROM driver_routes
    WHERE status IN ('pending', 'optimized')
    AND date = v_current_date;
    
    -- Pour chaque chauffeur impliqué dans une tournée de cette date
    FOR v_driver_id IN 
        SELECT DISTINCT d.id
        FROM drivers d
        JOIN laboratory_clients lc ON lc.driver_id = d.id
        JOIN lab_tour_stops lts ON lts.client_id = lc.id
        JOIN lab_tours lt ON lts.tour_id = lt.id
        WHERE lt.status IN ('validated', 'pending_changes') -- Filtrer uniquement sur ces deux statuts
        AND lt.date = v_current_date -- Uniquement pour la date du jour
    LOOP
        -- Créer la route pour ce chauffeur
        INSERT INTO driver_routes (
            driver_id, date, status, created_at, updated_at
        ) VALUES (
            v_driver_id, v_current_date, 'pending', NOW(), NOW()
        ) RETURNING id INTO v_driver_route_id;
        
        -- Initialiser le compteur d'ordre des stops
        v_current_stop_order := 1;
        
        -- Réinitialiser les variables
        v_depot_pickup_needed := FALSE;
        v_depot_dropoff_needed := FALSE;
        v_depot_pickup_id := NULL;
        v_depot_dropoff_id := NULL;
        v_lab_pickups := '{}'::JSONB;
        v_lab_dropoffs := '{}'::JSONB;
        v_client_pickups := '{}'::JSONB;
        v_client_deliveries := '{}'::JSONB;
        
        -- ÉTAPE 1: VÉRIFIER LES BESOINS EN STOPS
        
        -- Vérifier si des colis partent du dépôt
        SELECT EXISTS (
            SELECT 1
            FROM lab_tour_shipments shipment
            JOIN lab_tours lt ON shipment.lab_tour_id = lt.id
            JOIN lab_tour_stops lts ON lts.tour_id = lt.id
            JOIN laboratory_clients lc ON lts.client_id = lc.id
            WHERE lt.date = v_current_date
            AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
            AND lc.driver_id = v_driver_id
            AND shipment.from_location_id = v_depot_location_id
        ) INTO v_depot_pickup_needed;
        
        -- Vérifier si des colis arrivent au dépôt
        SELECT EXISTS (
            SELECT 1
            FROM lab_tour_shipments shipment
            JOIN lab_tours lt ON shipment.lab_tour_id = lt.id
            JOIN lab_tour_stops lts ON lts.tour_id = lt.id
            JOIN laboratory_clients lc ON lts.client_id = lc.id
            WHERE lt.date = v_current_date
            AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
            AND lc.driver_id = v_driver_id
            AND shipment.to_location_id = v_depot_location_id
        ) INTO v_depot_dropoff_needed;
        
        -- ÉTAPE 2: CRÉATION DES STOPS
        
        -- Créer le depot_pickup si nécessaire
        IF v_depot_pickup_needed THEN
            INSERT INTO driver_route_stops (
                route_id, location_id, stop_order, stop_type, created_at
            ) VALUES (
                v_driver_route_id, v_depot_location_id, v_current_stop_order, 'depot_pickup', NOW()
            ) RETURNING id INTO v_depot_pickup_id;
            
            v_current_stop_order := v_current_stop_order + 1;
        END IF;
        
        -- Créer les lab_pickup (origine = laboratoire)
        FOR v_lab_id, v_lab_name, v_lab_location_id IN
            SELECT DISTINCT 
                lab.id, 
                lab.name, 
                lab.location_id
            FROM 
                lab_tour_shipments shipment
            JOIN 
                lab_tours lt ON shipment.lab_tour_id = lt.id
            JOIN 
                laboratories lab ON lt.laboratory_id = lab.id
            JOIN 
                lab_tour_stops lts ON lts.tour_id = lt.id
            JOIN 
                laboratory_clients lc ON lts.client_id = lc.id
            WHERE 
                lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
                AND lc.driver_id = v_driver_id
                AND shipment.from_location_id = lab.location_id
        LOOP
            INSERT INTO driver_route_stops (
                route_id, location_id, stop_order, stop_type, created_at
            ) VALUES (
                v_driver_route_id, v_lab_location_id, v_current_stop_order, 'lab_pickup', NOW()
            ) RETURNING id INTO v_lab_pickup_id;
            
            v_lab_pickups := jsonb_set(v_lab_pickups, ARRAY[v_lab_id::text], to_jsonb(v_lab_pickup_id::text));
            v_current_stop_order := v_current_stop_order + 1;
        END LOOP;
        
        -- Créer les lab_dropoff (destination = laboratoire)
        FOR v_lab_id, v_lab_name, v_lab_location_id IN
            SELECT DISTINCT 
                lab.id, 
                lab.name, 
                lab.location_id
            FROM 
                lab_tour_shipments shipment
            JOIN 
                lab_tours lt ON shipment.lab_tour_id = lt.id
            JOIN 
                laboratories lab ON lt.laboratory_id = lab.id
            JOIN 
                lab_tour_stops lts ON lts.tour_id = lt.id
            JOIN 
                laboratory_clients lc ON lts.client_id = lc.id
            WHERE 
                lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
                AND lc.driver_id = v_driver_id
                AND shipment.to_location_id = lab.location_id
        LOOP
            INSERT INTO driver_route_stops (
                route_id, location_id, stop_order, stop_type, created_at
            ) VALUES (
                v_driver_route_id, v_lab_location_id, v_current_stop_order, 'lab_dropoff', NOW()
            ) RETURNING id INTO v_lab_dropoff_id;
            
            v_lab_dropoffs := jsonb_set(v_lab_dropoffs, ARRAY[v_lab_id::text], to_jsonb(v_lab_dropoff_id::text));
            v_current_stop_order := v_current_stop_order + 1;
        END LOOP;
        
        -- Créer les client stops (pour tous les clients concernés)
        FOR v_client_id, v_client_name, v_client_location_id IN
            SELECT DISTINCT 
                lc.id, 
                lc.name, 
                lc.location_id
            FROM 
                lab_tour_stops lts
            JOIN 
                lab_tours lt ON lts.tour_id = lt.id
            JOIN 
                laboratory_clients lc ON lts.client_id = lc.id
            WHERE 
                lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
                AND lc.driver_id = v_driver_id
                AND lts.has_pickup = TRUE
        LOOP
            -- Créer un stop pour pickup chez le client
            INSERT INTO driver_route_stops (
                route_id, location_id, stop_order, stop_type, client_actions, created_at
            ) VALUES (
                v_driver_route_id, v_client_location_id, v_current_stop_order, 'client', 'pickup', NOW()
            ) RETURNING id INTO v_client_pickup_id;
            
            v_client_pickups := jsonb_set(v_client_pickups, ARRAY[v_client_id::text], to_jsonb(v_client_pickup_id::text));
            v_current_stop_order := v_current_stop_order + 1;
        END LOOP;
        
        -- Créer les client stops pour la livraison (delivery)
        FOR v_client_id, v_client_name, v_client_location_id IN
            SELECT DISTINCT 
                lc.id, 
                lc.name, 
                lc.location_id
            FROM 
                lab_tour_stops lts
            JOIN 
                lab_tours lt ON lts.tour_id = lt.id
            JOIN 
                laboratory_clients lc ON lts.client_id = lc.id
            WHERE 
                lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
                AND lc.driver_id = v_driver_id
                AND lts.has_delivery = TRUE
        LOOP
            -- Créer un stop pour delivery chez le client
            INSERT INTO driver_route_stops (
                route_id, location_id, stop_order, stop_type, client_actions, created_at
            ) VALUES (
                v_driver_route_id, v_client_location_id, v_current_stop_order, 'client', 'delivery', NOW()
            ) RETURNING id INTO v_client_delivery_id;
            
            v_client_deliveries := jsonb_set(v_client_deliveries, ARRAY[v_client_id::text], to_jsonb(v_client_delivery_id::text));
            v_current_stop_order := v_current_stop_order + 1;
        END LOOP;
        
        -- Créer le depot_dropoff si nécessaire
        IF v_depot_dropoff_needed THEN
            INSERT INTO driver_route_stops (
                route_id, location_id, stop_order, stop_type, created_at
            ) VALUES (
                v_driver_route_id, v_depot_location_id, v_current_stop_order, 'depot_dropoff', NOW()
            ) RETURNING id INTO v_depot_dropoff_id;
        END IF;

        -- ÉTAPE 3: GÉNÉRER LES SHIPMENTS
        
        -- Traiter tous les shipments des tournées laboratoire pour ce chauffeur
        FOR v_lab_id, v_client_id, v_shipment_type, v_from_location_id, v_to_location_id IN
            SELECT 
                lt.laboratory_id,
                lts.client_id,
                -- Type de shipment selon l'origine et la destination
                CASE 
                    WHEN shipment.from_location_id = lab.location_id AND shipment.to_location_id = lc.location_id THEN 'lab_to_client'
                    WHEN shipment.from_location_id = lc.location_id AND shipment.to_location_id = lab.location_id THEN 'client_to_lab'
                    WHEN shipment.from_location_id = lab.location_id AND shipment.to_location_id = v_depot_location_id THEN 'lab_to_depot'
                    WHEN shipment.from_location_id = v_depot_location_id AND shipment.to_location_id = lab.location_id THEN 'depot_to_lab'
                    WHEN shipment.from_location_id = lc.location_id AND shipment.to_location_id = v_depot_location_id THEN 'client_to_depot'
                    WHEN shipment.from_location_id = v_depot_location_id AND shipment.to_location_id = lc.location_id THEN 'depot_to_client'
                    ELSE 'unknown'
                END,
                shipment.from_location_id,
                shipment.to_location_id
            FROM 
                lab_tour_shipments shipment
            JOIN 
                lab_tours lt ON shipment.lab_tour_id = lt.id
            JOIN 
                laboratories lab ON lt.laboratory_id = lab.id
            JOIN 
                lab_tour_stops lts ON lts.tour_id = lt.id
            JOIN 
                laboratory_clients lc ON lts.client_id = lc.id
            WHERE 
                lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes') -- Mise à jour ici
                AND lc.driver_id = v_driver_id
                -- Ne pas inclure les shipments avec des laboratoires ou clients sans localisation connue
                AND lab.location_id IS NOT NULL
                AND lc.location_id IS NOT NULL
                -- Exclure les retours au dépôt qui sont générés automatiquement
                AND (shipment.from_location_id != v_depot_location_id OR shipment.to_location_id != v_depot_location_id)
        LOOP
            -- Déterminer les IDs de pickup et delivery
            CASE v_shipment_type
                WHEN 'lab_to_client' THEN
                    v_pickup_stop_id := (v_lab_pickups->>v_lab_id::text)::UUID;
                    v_delivery_stop_id := (v_client_deliveries->>v_client_id::text)::UUID;
                WHEN 'client_to_lab' THEN
                    v_pickup_stop_id := (v_client_pickups->>v_client_id::text)::UUID;
                    v_delivery_stop_id := (v_lab_dropoffs->>v_lab_id::text)::UUID;
                WHEN 'lab_to_depot' THEN
                    v_pickup_stop_id := (v_lab_pickups->>v_lab_id::text)::UUID;
                    v_delivery_stop_id := v_depot_dropoff_id;
                WHEN 'depot_to_lab' THEN
                    v_pickup_stop_id := v_depot_pickup_id;
                    v_delivery_stop_id := (v_lab_dropoffs->>v_lab_id::text)::UUID;
                WHEN 'client_to_depot' THEN
                    v_pickup_stop_id := (v_client_pickups->>v_client_id::text)::UUID;
                    v_delivery_stop_id := v_depot_dropoff_id;
                WHEN 'depot_to_client' THEN
                    v_pickup_stop_id := v_depot_pickup_id;
                    v_delivery_stop_id := (v_client_deliveries->>v_client_id::text)::UUID;
                ELSE
                    v_pickup_stop_id := NULL;
                    v_delivery_stop_id := NULL;
            END CASE;
            
            -- Créer le shipment seulement si les deux stops existent
            IF v_pickup_stop_id IS NOT NULL AND v_delivery_stop_id IS NOT NULL THEN
                -- Déterminer le type de shipment spécifique pour client
                DECLARE
                    v_specific_shipment_type TEXT;
                BEGIN
                    v_specific_shipment_type := CASE
                        WHEN v_shipment_type IN ('lab_to_client', 'depot_to_client', 'lab_to_depot') THEN 'client_delivery'
                        WHEN v_shipment_type IN ('client_to_lab', 'client_to_depot', 'depot_to_lab') THEN 'client_pickup'
                        ELSE v_shipment_type
                    END;
                    
                    INSERT INTO driver_route_shipments (
                        shipment_ref,
                        laboratory_id,
                        laboratory_client_id,
                        pickup_stop_id,
                        delivery_stop_id,
                        pickup_status,
                        delivery_status,
                        created_at,
                        updated_at,
                        route_id,
                        shipment_type
                    ) VALUES (
                        -- Nom du shipment selon le type
                        CASE 
                            WHEN v_shipment_type = 'lab_to_client' THEN 'Livraison ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                            WHEN v_shipment_type = 'client_to_lab' THEN 'Récupération ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                            WHEN v_shipment_type = 'lab_to_depot' THEN 'Retour ' || (SELECT name FROM laboratories WHERE id = v_lab_id)
                            WHEN v_shipment_type = 'depot_to_lab' THEN 'Livraison ' || (SELECT name FROM laboratories WHERE id = v_lab_id)
                            WHEN v_shipment_type = 'client_to_depot' THEN 'Retour ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                            WHEN v_shipment_type = 'depot_to_client' THEN 'Livraison ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                            ELSE 'Shipment ' || v_shipment_type
                        END,
                        v_lab_id,
                        v_client_id,
                        v_pickup_stop_id,
                        v_delivery_stop_id,
                        'pending',
                        'pending',
                        NOW(),
                        NOW(),
                        v_driver_route_id,
                        v_specific_shipment_type  -- Ajout du shipment_type ici
                    );
                END;
            END IF;
        END LOOP;
        
    END LOOP; -- Fin boucle sur les chauffeurs
END;
$$;


ALTER FUNCTION "public"."generate_driver_routes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_driver_routes"("target_date" "date" DEFAULT NULL::"date") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_current_date DATE;
    v_driver_id UUID;
    v_driver_route_id UUID;
    v_depot_location_id UUID;
    v_current_stop_order INTEGER;
    
    -- Variables pour les stops
    v_depot_pickup_needed BOOLEAN;
    v_depot_dropoff_needed BOOLEAN;
    v_depot_pickup_id UUID;
    v_depot_dropoff_id UUID;
    
    -- Variables pour les labs et clients
    v_lab_id UUID;
    v_lab_name TEXT;
    v_lab_location_id UUID;
    v_lab_pickup_id UUID;
    v_lab_dropoff_id UUID;
    v_client_id UUID;
    v_client_name TEXT;
    v_client_location_id UUID;
    v_client_pickup_id UUID;
    v_client_delivery_id UUID;
    
    -- Tables pour stocker les IDs
    v_lab_pickups JSONB := '{}'::JSONB;
    v_lab_dropoffs JSONB := '{}'::JSONB;
    v_client_pickups JSONB := '{}'::JSONB;
    v_client_deliveries JSONB := '{}'::JSONB;
    
    -- Variables pour les shipments
    v_shipment_type TEXT;
    v_from_location_id UUID;
    v_to_location_id UUID;
    v_pickup_stop_id UUID;
    v_delivery_stop_id UUID;
    v_specific_shipment_type TEXT;
    v_shipment_ref TEXT;
BEGIN
    -- Récupérer le dépôt actif
    SELECT location_id INTO v_depot_location_id
    FROM depot 
    WHERE is_active = true
    LIMIT 1;
    
    IF v_depot_location_id IS NULL THEN
        RAISE EXCEPTION 'Aucun dépôt actif trouvé';
    END IF;
    
    -- Si target_date est fourni, traiter uniquement cette date
    -- Sinon, traiter toutes les dates avec des tournées validées
    FOR v_current_date IN 
        SELECT DISTINCT date FROM lab_tours 
        WHERE status IN ('validated', 'pending_changes')
        AND (target_date IS NULL OR date = target_date)
        ORDER BY date
    LOOP
        -- Supprimer d'abord les tournées existantes en statut 'pending' ou 'optimized' pour cette date
        DELETE FROM driver_routes
        WHERE status IN ('pending', 'optimized')
        AND date = v_current_date;
        
        -- Pour chaque chauffeur impliqué dans une tournée de cette date
        FOR v_driver_id IN 
            SELECT DISTINCT d.id
            FROM drivers d
            JOIN laboratory_clients lc ON lc.driver_id = d.id
            JOIN lab_tour_stops lts ON lts.client_id = lc.id
            JOIN lab_tours lt ON lts.tour_id = lt.id
            WHERE lt.status IN ('validated', 'pending_changes')
            AND lt.date = v_current_date
        LOOP
            -- Créer une nouvelle tournée pour ce chauffeur
            INSERT INTO driver_routes (
                driver_id, date, status, created_at, updated_at
            ) VALUES (
                v_driver_id, v_current_date, 'pending', NOW(), NOW()
            ) RETURNING id INTO v_driver_route_id;
            
            -- Initialiser le compteur d'ordre des stops
            v_current_stop_order := 1;
            
            -- Réinitialiser les variables
            v_depot_pickup_needed := FALSE;
            v_depot_dropoff_needed := FALSE;
            v_depot_pickup_id := NULL;
            v_depot_dropoff_id := NULL;
            v_lab_pickups := '{}'::JSONB;
            v_lab_dropoffs := '{}'::JSONB;
            v_client_pickups := '{}'::JSONB;
            v_client_deliveries := '{}'::JSONB;
            
            -- ÉTAPE 1: VÉRIFIER LES BESOINS EN STOPS
            
            -- Vérifier si des colis partent du dépôt pour ce chauffeur
            SELECT EXISTS (
                SELECT 1
                FROM lab_tour_shipments shipment
                JOIN lab_tours lt ON shipment.lab_tour_id = lt.id
                JOIN lab_tour_stops lts ON lts.tour_id = lt.id
                JOIN laboratory_clients lc ON lts.client_id = lc.id
                WHERE lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes')
                AND lc.driver_id = v_driver_id
                AND shipment.from_location_id = v_depot_location_id
            ) INTO v_depot_pickup_needed;
            
            -- Vérifier si des colis arrivent au dépôt pour ce chauffeur
            SELECT EXISTS (
                SELECT 1
                FROM lab_tour_shipments shipment
                JOIN lab_tours lt ON shipment.lab_tour_id = lt.id
                JOIN lab_tour_stops lts ON lts.tour_id = lt.id
                JOIN laboratory_clients lc ON lts.client_id = lc.id
                WHERE lt.date = v_current_date
                AND lt.status IN ('validated', 'pending_changes')
                AND lc.driver_id = v_driver_id
                AND shipment.to_location_id = v_depot_location_id
            ) INTO v_depot_dropoff_needed;
            
            -- ÉTAPE 2: CRÉATION DES STOPS
            
            -- Créer le depot_pickup si nécessaire
            IF v_depot_pickup_needed THEN
                INSERT INTO driver_route_stops (
                    route_id, location_id, stop_order, stop_type, created_at
                ) VALUES (
                    v_driver_route_id, v_depot_location_id, v_current_stop_order, 'depot_pickup', NOW()
                ) RETURNING id INTO v_depot_pickup_id;
                
                v_current_stop_order := v_current_stop_order + 1;
            END IF;
            
            -- Créer les lab_pickup (origine = laboratoire) - MODIFICATION ICI
            FOR v_lab_id, v_lab_name, v_lab_location_id IN
                SELECT DISTINCT 
                    lab.id, 
                    lab.name, 
                    lab.location_id
                FROM 
                    lab_tour_shipments shipment
                JOIN 
                    lab_tours lt ON shipment.lab_tour_id = lt.id
                JOIN 
                    laboratories lab ON lt.laboratory_id = lab.id
                JOIN 
                    lab_tour_stops lts ON lts.tour_id = lt.id
                JOIN 
                    laboratory_clients lc ON lts.client_id = lc.id
                WHERE 
                    lt.date = v_current_date
                    AND lt.status IN ('validated', 'pending_changes')
                    AND lc.driver_id = v_driver_id
                    AND shipment.from_location_id = lab.location_id
                    AND shipment.to_location_id = lc.location_id  -- AJOUT : Filtrer par client de ce chauffeur
            LOOP
                INSERT INTO driver_route_stops (
                    route_id, location_id, stop_order, stop_type, created_at
                ) VALUES (
                    v_driver_route_id, v_lab_location_id, v_current_stop_order, 'lab_pickup', NOW()
                ) RETURNING id INTO v_lab_pickup_id;
                
                v_lab_pickups := jsonb_set(v_lab_pickups, ARRAY[v_lab_id::text], to_jsonb(v_lab_pickup_id::text));
                v_current_stop_order := v_current_stop_order + 1;
            END LOOP;
            
            -- Créer les lab_dropoff (destination = laboratoire) - MODIFICATION ICI
            FOR v_lab_id, v_lab_name, v_lab_location_id IN
                SELECT DISTINCT 
                    lab.id, 
                    lab.name, 
                    lab.location_id
                FROM 
                    lab_tour_shipments shipment
                JOIN 
                    lab_tours lt ON shipment.lab_tour_id = lt.id
                JOIN 
                    laboratories lab ON lt.laboratory_id = lab.id
                JOIN 
                    lab_tour_stops lts ON lts.tour_id = lt.id
                JOIN 
                    laboratory_clients lc ON lts.client_id = lc.id
                WHERE 
                    lt.date = v_current_date
                    AND lt.status IN ('validated', 'pending_changes')
                    AND lc.driver_id = v_driver_id
                    AND shipment.to_location_id = lab.location_id
                    AND shipment.from_location_id = lc.location_id  -- AJOUT : Filtrer par client de ce chauffeur
            LOOP
                INSERT INTO driver_route_stops (
                    route_id, location_id, stop_order, stop_type, created_at
                ) VALUES (
                    v_driver_route_id, v_lab_location_id, v_current_stop_order, 'lab_dropoff', NOW()
                ) RETURNING id INTO v_lab_dropoff_id;
                
                v_lab_dropoffs := jsonb_set(v_lab_dropoffs, ARRAY[v_lab_id::text], to_jsonb(v_lab_dropoff_id::text));
                v_current_stop_order := v_current_stop_order + 1;
            END LOOP;
            
            -- Créer les client stops (RETOUR À LA LOGIQUE ANCIENNE avec lab_tour_stops)
            FOR v_client_id, v_client_name, v_client_location_id IN
                SELECT DISTINCT 
                    lc.id, 
                    lc.name, 
                    lc.location_id
                FROM 
                    lab_tour_stops lts
                JOIN 
                    lab_tours lt ON lts.tour_id = lt.id
                JOIN 
                    laboratory_clients lc ON lts.client_id = lc.id
                WHERE 
                    lt.date = v_current_date
                    AND lt.status IN ('validated', 'pending_changes')
                    AND lc.driver_id = v_driver_id
                    AND lts.has_pickup = TRUE
            LOOP
                -- Créer un stop pour pickup chez le client
                INSERT INTO driver_route_stops (
                    route_id, location_id, stop_order, stop_type, client_actions, created_at
                ) VALUES (
                    v_driver_route_id, v_client_location_id, v_current_stop_order, 'client', 'pickup', NOW()
                ) RETURNING id INTO v_client_pickup_id;
                
                v_client_pickups := jsonb_set(v_client_pickups, ARRAY[v_client_id::text], to_jsonb(v_client_pickup_id::text));
                v_current_stop_order := v_current_stop_order + 1;
            END LOOP;
            
            -- Créer les client stops pour la livraison (delivery) - RETOUR À LA LOGIQUE ANCIENNE
            FOR v_client_id, v_client_name, v_client_location_id IN
                SELECT DISTINCT 
                    lc.id, 
                    lc.name, 
                    lc.location_id
                FROM 
                    lab_tour_stops lts
                JOIN 
                    lab_tours lt ON lts.tour_id = lt.id
                JOIN 
                    laboratory_clients lc ON lts.client_id = lc.id
                WHERE 
                    lt.date = v_current_date
                    AND lt.status IN ('validated', 'pending_changes')
                    AND lc.driver_id = v_driver_id
                    AND lts.has_delivery = TRUE
            LOOP
                -- Créer un stop pour delivery chez le client
                INSERT INTO driver_route_stops (
                    route_id, location_id, stop_order, stop_type, client_actions, created_at
                ) VALUES (
                    v_driver_route_id, v_client_location_id, v_current_stop_order, 'client', 'delivery', NOW()
                ) RETURNING id INTO v_client_delivery_id;
                
                v_client_deliveries := jsonb_set(v_client_deliveries, ARRAY[v_client_id::text], to_jsonb(v_client_delivery_id::text));
                v_current_stop_order := v_current_stop_order + 1;
            END LOOP;
            
            -- Créer le depot_dropoff si nécessaire
            IF v_depot_dropoff_needed THEN
                INSERT INTO driver_route_stops (
                    route_id, location_id, stop_order, stop_type, created_at
                ) VALUES (
                    v_driver_route_id, v_depot_location_id, v_current_stop_order, 'depot_dropoff', NOW()
                ) RETURNING id INTO v_depot_dropoff_id;
            END IF;

            -- ÉTAPE 3: GÉNÉRER LES SHIPMENTS - RETOUR À LA LOGIQUE ANCIENNE
            
            -- Traiter tous les shipments des tournées laboratoire pour ce chauffeur
            FOR v_lab_id, v_client_id, v_shipment_type, v_from_location_id, v_to_location_id IN
                SELECT 
                    lt.laboratory_id,
                    lts.client_id,
                    -- Type de shipment selon l'origine et la destination (LOGIQUE ANCIENNE)
                    CASE 
                        WHEN shipment.from_location_id = lab.location_id AND shipment.to_location_id = lc.location_id THEN 'lab_to_client'
                        WHEN shipment.from_location_id = lc.location_id AND shipment.to_location_id = lab.location_id THEN 'client_to_lab'
                        WHEN shipment.from_location_id = lab.location_id AND shipment.to_location_id = v_depot_location_id THEN 'lab_to_depot'
                        WHEN shipment.from_location_id = v_depot_location_id AND shipment.to_location_id = lab.location_id THEN 'depot_to_lab'
                        WHEN shipment.from_location_id = lc.location_id AND shipment.to_location_id = v_depot_location_id THEN 'client_to_depot'
                        WHEN shipment.from_location_id = v_depot_location_id AND shipment.to_location_id = lc.location_id THEN 'depot_to_client'
                        ELSE 'unknown'
                    END,
                    shipment.from_location_id,
                    shipment.to_location_id
                FROM 
                    lab_tour_shipments shipment
                JOIN 
                    lab_tours lt ON shipment.lab_tour_id = lt.id
                JOIN 
                    laboratories lab ON lt.laboratory_id = lab.id
                JOIN 
                    lab_tour_stops lts ON lts.tour_id = lt.id
                JOIN 
                    laboratory_clients lc ON lts.client_id = lc.id
                WHERE 
                    lt.date = v_current_date
                    AND lt.status IN ('validated', 'pending_changes')
                    AND lc.driver_id = v_driver_id
                    -- Ne pas inclure les shipments avec des laboratoires ou clients sans localisation connue
                    AND lab.location_id IS NOT NULL
                    AND lc.location_id IS NOT NULL
                    -- CONDITION IMPORTANTE: Exclure les retours au dépôt qui sont générés automatiquement
                    AND (shipment.from_location_id != v_depot_location_id OR shipment.to_location_id != v_depot_location_id)
            LOOP
                -- Déterminer les IDs de pickup et delivery
                CASE v_shipment_type
                    WHEN 'lab_to_client' THEN
                        v_pickup_stop_id := (v_lab_pickups->>v_lab_id::text)::UUID;
                        v_delivery_stop_id := (v_client_deliveries->>v_client_id::text)::UUID;
                    WHEN 'client_to_lab' THEN
                        v_pickup_stop_id := (v_client_pickups->>v_client_id::text)::UUID;
                        v_delivery_stop_id := (v_lab_dropoffs->>v_lab_id::text)::UUID;
                    WHEN 'lab_to_depot' THEN
                        v_pickup_stop_id := (v_lab_pickups->>v_lab_id::text)::UUID;
                        v_delivery_stop_id := v_depot_dropoff_id;
                    WHEN 'depot_to_lab' THEN
                        v_pickup_stop_id := v_depot_pickup_id;
                        v_delivery_stop_id := (v_lab_dropoffs->>v_lab_id::text)::UUID;
                    WHEN 'client_to_depot' THEN
                        v_pickup_stop_id := (v_client_pickups->>v_client_id::text)::UUID;
                        v_delivery_stop_id := v_depot_dropoff_id;
                    WHEN 'depot_to_client' THEN
                        v_pickup_stop_id := v_depot_pickup_id;
                        v_delivery_stop_id := (v_client_deliveries->>v_client_id::text)::UUID;
                    ELSE
                        v_pickup_stop_id := NULL;
                        v_delivery_stop_id := NULL;
                END CASE;
                
                -- Créer le shipment seulement si les deux stops existent
                IF v_pickup_stop_id IS NOT NULL AND v_delivery_stop_id IS NOT NULL THEN
                    -- Déterminer le type de shipment spécifique 
                    v_specific_shipment_type := CASE
                        WHEN v_shipment_type IN ('lab_to_client', 'depot_to_client') THEN 'client_delivery'
                        WHEN v_shipment_type IN ('client_to_lab', 'client_to_depot') THEN 'client_pickup'
                        WHEN v_shipment_type = 'lab_to_depot' THEN 'lab_return'
                        WHEN v_shipment_type = 'depot_to_lab' THEN 'lab_delivery'
                        ELSE v_shipment_type
                    END;
                    
                    -- Générer le shipment_ref
                    v_shipment_ref := CASE 
                        WHEN v_shipment_type = 'lab_to_client' THEN 'Livraison ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                        WHEN v_shipment_type = 'client_to_lab' THEN 'Récupération ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                        WHEN v_shipment_type = 'lab_to_depot' THEN 'Retour ' || (SELECT name FROM laboratories WHERE id = v_lab_id)
                        WHEN v_shipment_type = 'depot_to_lab' THEN 'Livraison ' || (SELECT name FROM laboratories WHERE id = v_lab_id)
                        WHEN v_shipment_type = 'client_to_depot' THEN 'Retour ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                        WHEN v_shipment_type = 'depot_to_client' THEN 'Livraison ' || (SELECT name FROM laboratory_clients WHERE id = v_client_id)
                        ELSE 'Shipment ' || v_shipment_type
                    END;
                    
                    -- INSERT avec tous les champs
                    INSERT INTO driver_route_shipments (
                        shipment_ref,
                        laboratory_id,
                        laboratory_client_id,
                        pickup_stop_id,
                        delivery_stop_id,
                        pickup_status,
                        delivery_status,
                        created_at,
                        updated_at,
                        route_id,
                        shipment_type
                    ) VALUES (
                        v_shipment_ref,
                        v_lab_id,
                        v_client_id,
                        v_pickup_stop_id,
                        v_delivery_stop_id,
                        'pending',
                        'pending',
                        NOW(),
                        NOW(),
                        v_driver_route_id,
                        v_specific_shipment_type
                    );
                END IF;
            END LOOP;
            
        END LOOP;
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."generate_driver_routes"("target_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_driver_routes_v2"("target_date" "date" DEFAULT CURRENT_DATE) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    driver_record RECORD;
    route_id UUID;
    shipments_data JSONB;
BEGIN
    RAISE NOTICE 'Début génération routes v2 pour la date %', target_date;
    
    -- Étape 1: Nettoyer COMPLÈTEMENT dans le bon ordre
    -- 1a. D'abord les shipments
    DELETE FROM driver_route_shipments drs
    WHERE drs.route_id IN (
        SELECT dr.id FROM driver_routes dr
        WHERE dr.status IN ('pending', 'optimized') AND dr.date = target_date
    );
    
    -- 1b. Puis les stops
    DELETE FROM driver_route_stops drs_stops
    WHERE drs_stops.route_id IN (
        SELECT dr.id FROM driver_routes dr
        WHERE dr.status IN ('pending', 'optimized') AND dr.date = target_date
    );
    
    -- 1c. Enfin les routes
    DELETE FROM driver_routes dr
    WHERE dr.status IN ('pending', 'optimized') AND dr.date = target_date;
    
    RAISE NOTICE 'Nettoyage complet effectué pour la date %', target_date;
    
    -- Étape 2: Pour chaque chauffeur impliqué dans des tournées validées
    FOR driver_record IN 
        SELECT DISTINCT d.id, d.full_name
        FROM drivers d
        JOIN laboratory_clients lc ON lc.driver_id = d.id
        JOIN lab_tour_stops lts ON lts.client_id = lc.id
        JOIN lab_tours lt ON lts.tour_id = lt.id
        WHERE lt.status IN ('validated', 'pending_changes')
        AND lt.date = target_date
    LOOP
        RAISE NOTICE 'Traitement du chauffeur % (%)', driver_record.full_name, driver_record.id;
        
        -- Créer la route du chauffeur
        INSERT INTO driver_routes (
            driver_id, date, status, created_at, updated_at
        ) VALUES (
            driver_record.id, target_date, 'pending', NOW(), NOW()
        ) RETURNING id INTO route_id;
        
        -- Étape 3: Déterminer les shipments nécessaires pour ce chauffeur
        SELECT jsonb_agg(
            jsonb_build_object(
                'lab_tour_shipment_id', ds.lab_tour_shipment_id,
                'shipment_type', ds.shipment_type,
                'from_location_id', ds.from_location_id,
                'to_location_id', ds.to_location_id,
                'laboratory_id', ds.laboratory_id,
                'responsible_client_id', ds.responsible_client_id,
                'laboratory_name', ds.laboratory_name,
                'client_name', ds.client_name
            )
        ) INTO shipments_data
        FROM determine_driver_shipments(driver_record.id, target_date) ds
        WHERE ds.responsible_client_id IS NOT NULL;
        
        RAISE NOTICE 'Shipments trouvés pour %: %', driver_record.full_name, COALESCE(jsonb_array_length(shipments_data), 0);
        
        -- Si des shipments ont été trouvés
        IF shipments_data IS NOT NULL AND jsonb_array_length(shipments_data) > 0 THEN
            -- Étape 4: Créer les stops nécessaires
            PERFORM create_necessary_stops(route_id, shipments_data);
            
            -- Étape 5: Créer les driver_route_shipments
            PERFORM create_driver_shipments(route_id, driver_record.id, shipments_data);
        ELSE
            -- Supprimer la route vide
            DELETE FROM driver_routes WHERE id = route_id;
            RAISE NOTICE 'Route supprimée pour % (aucun shipment)', driver_record.full_name;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Génération routes v2 terminée pour la date %', target_date;
END;
$$;


ALTER FUNCTION "public"."generate_driver_routes_v2"("target_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invoice_number"("lab_id" "uuid", "period_start" "date") RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  lab_name TEXT;
  clean_name TEXT;
  invoice_num TEXT;
BEGIN
  -- Récupérer le nom du laboratoire
  SELECT name INTO lab_name FROM laboratories WHERE id = lab_id;
  
  -- Nettoyer le nom (remplacer espaces par underscores, majuscules, caractères spéciaux)
  clean_name := UPPER(
    REGEXP_REPLACE(
      REGEXP_REPLACE(lab_name, '[^a-zA-Z0-9\s]', '', 'g'), -- Supprimer caractères spéciaux
      '\s+', '_', 'g' -- Remplacer espaces par underscores
    )
  );
  
  -- Générer le numéro : NOM_LAB-YYYY-MM
  invoice_num := clean_name || '-' || TO_CHAR(period_start, 'YYYY-MM');
  
  RETURN invoice_num;
END;
$$;


ALTER FUNCTION "public"."generate_invoice_number"("lab_id" "uuid", "period_start" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_lab_tour_shipments"("lab_tour_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  tour_date DATE;
  lab_id UUID;
  lab_name TEXT;
  lab_location_id UUID;
  depot_location_id UUID;
  depot_name TEXT;
  client_record RECORD;
BEGIN
  -- Récupérer les informations de la tournée (date et laboratoire)
  SELECT lt.date, lt.laboratory_id, l.name, l.location_id
  INTO tour_date, lab_id, lab_name, lab_location_id
  FROM lab_tours lt
  JOIN laboratories l ON lt.laboratory_id = l.id
  WHERE lt.id = generate_lab_tour_shipments.lab_tour_id;
  
  -- S'assurer que la tournée existe
  IF tour_date IS NULL THEN
    RAISE EXCEPTION 'La tournée avec ID % n''existe pas', generate_lab_tour_shipments.lab_tour_id;
  END IF;
  
  -- Récupérer l'ID et le nom du dépôt
  SELECT location_id, name INTO depot_location_id, depot_name
  FROM depot 
  WHERE is_active = true
  LIMIT 1;
  
  -- S'assurer qu'un dépôt existe
  IF depot_location_id IS NULL THEN
    RAISE EXCEPTION 'Aucun dépôt actif trouvé dans la base de données';
  END IF;
  
  -- Supprimer d'abord tous les shipments existants pour cette tournée
  PERFORM delete_lab_tour_shipments(generate_lab_tour_shipments.lab_tour_id);
  
  -- Pour chaque arrêt de la tournée avec ses flags clients
  FOR client_record IN (
    SELECT 
      lts.has_delivery, 
      lts.has_pickup,
      c.id AS client_id,
      c.name AS client_name,
      c.location_id AS client_location_id,
      c.is_pickup_depot,
      c.is_return_depot,
      c.is_return_next_day,
      c.depot_is_dentist,
      c.depot_is_lab
    FROM lab_tour_stops lts
    JOIN laboratory_clients c ON lts.client_id = c.id
    WHERE lts.tour_id = generate_lab_tour_shipments.lab_tour_id
  ) LOOP
    
    -- NOUVEAU : Si depot_is_lab est true, le dépôt remplace le laboratoire
    IF client_record.depot_is_lab THEN
      IF client_record.has_delivery THEN
        -- Livraison du dépôt au client
        INSERT INTO lab_tour_shipments (
          lab_tour_id, 
          from_location_id, 
          to_location_id, 
          shipment_type, 
          scheduled_date,
          is_return_next_day,
          client_id
        ) VALUES (
          generate_lab_tour_shipments.lab_tour_id,
          depot_location_id,
          client_record.client_location_id,
          'depot_to_client',
          tour_date,
          client_record.is_return_next_day,
          client_record.client_id
        );
      END IF;
      
      IF client_record.has_pickup THEN
        -- Récupération du client au dépôt
        INSERT INTO lab_tour_shipments (
          lab_tour_id, 
          from_location_id, 
          to_location_id, 
          shipment_type, 
          scheduled_date,
          is_return_next_day,
          client_id
        ) VALUES (
          generate_lab_tour_shipments.lab_tour_id,
          client_record.client_location_id,
          depot_location_id,
          'client_to_depot',
          tour_date,
          client_record.is_return_next_day,
          client_record.client_id
        );
      END IF;
      
    -- Si depot_is_dentist est true, le dépôt remplace le client/dentiste
    ELSIF client_record.depot_is_dentist THEN
      IF client_record.has_delivery THEN
        -- Livraison du labo au dépôt
        INSERT INTO lab_tour_shipments (
          lab_tour_id, 
          from_location_id, 
          to_location_id, 
          shipment_type, 
          scheduled_date,
          is_return_next_day,
          client_id
        ) VALUES (
          generate_lab_tour_shipments.lab_tour_id,
          lab_location_id,
          depot_location_id,
          'lab_to_depot',
          tour_date,
          client_record.is_return_next_day,
          client_record.client_id
        );
      END IF;
      
      IF client_record.has_pickup THEN
        -- Récupération du dépôt au labo
        INSERT INTO lab_tour_shipments (
          lab_tour_id, 
          from_location_id, 
          to_location_id, 
          shipment_type, 
          scheduled_date,
          is_return_next_day,
          client_id
        ) VALUES (
          generate_lab_tour_shipments.lab_tour_id,
          depot_location_id,
          lab_location_id,
          'depot_to_lab',
          tour_date,
          client_record.is_return_next_day,
          client_record.client_id
        );
      END IF;
    ELSE
      -- LOGIQUE NORMALE (pas de depot interaction)
      -- 1. LIVRAISONS (has_delivery = true)
      IF client_record.has_delivery THEN
        -- Déterminer le point de départ selon les flags
        IF client_record.is_pickup_depot THEN
          -- Livraison du lab au dépôt
          INSERT INTO lab_tour_shipments (
            lab_tour_id, 
            from_location_id, 
            to_location_id, 
            shipment_type, 
            scheduled_date,
            is_return_next_day,
            client_id
          ) VALUES (
            generate_lab_tour_shipments.lab_tour_id,
            lab_location_id,
            depot_location_id,
            'lab_to_depot',
            tour_date,
            client_record.is_return_next_day,
            client_record.client_id
          );
        ELSE
          -- Livraison normale du labo au client
          INSERT INTO lab_tour_shipments (
            lab_tour_id, 
            from_location_id, 
            to_location_id, 
            shipment_type, 
            scheduled_date,
            is_return_next_day,
            client_id
          ) VALUES (
            generate_lab_tour_shipments.lab_tour_id,
            lab_location_id,
            client_record.client_location_id,
            'lab_to_client',
            tour_date,
            client_record.is_return_next_day,
            client_record.client_id
          );
        END IF;
      END IF;
      
      -- 2. RÉCUPÉRATIONS (has_pickup = true)
      IF client_record.has_pickup THEN
        -- Déterminer le point d'arrivée selon les flags
        IF client_record.is_return_depot THEN
          -- Récupération du client au dépôt
          INSERT INTO lab_tour_shipments (
            lab_tour_id, 
            from_location_id, 
            to_location_id, 
            shipment_type, 
            scheduled_date,
            is_return_next_day,
            client_id
          ) VALUES (
            generate_lab_tour_shipments.lab_tour_id,
            client_record.client_location_id,
            depot_location_id,
            'client_to_depot',
            tour_date,
            client_record.is_return_next_day,
            client_record.client_id
          );
        ELSE
          -- Récupération normale du client au labo
          INSERT INTO lab_tour_shipments (
            lab_tour_id, 
            from_location_id, 
            to_location_id, 
            shipment_type, 
            scheduled_date,
            is_return_next_day,
            client_id
          ) VALUES (
            generate_lab_tour_shipments.lab_tour_id,
            client_record.client_location_id,
            lab_location_id,
            'client_to_lab',
            tour_date,
            client_record.is_return_next_day,
            client_record.client_id
          );
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."generate_lab_tour_shipments"("lab_tour_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_monthly_invoice"("lab_id" "uuid", "billing_month" "date") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  invoice_id UUID;
  period_start DATE;
  period_end DATE;
  total_amount DECIMAL(10,2) := 0;
  invoice_item RECORD;
BEGIN
  -- Calculer les dates de début et fin du mois
  period_start := DATE_TRUNC('month', billing_month);
  period_end := (DATE_TRUNC('month', billing_month) + INTERVAL '1 month - 1 day')::DATE;
  
  -- Vérifier si une facture existe déjà pour cette période
  IF EXISTS (
    SELECT 1 FROM billing_invoices 
    WHERE laboratory_id = lab_id 
    AND billing_period_start = period_start 
    AND billing_period_end = period_end
  ) THEN
    RAISE EXCEPTION 'Une facture existe déjà pour ce laboratoire et cette période';
  END IF;
  
  -- Créer la facture principale
  INSERT INTO billing_invoices (
    laboratory_id,
    billing_period_start,
    billing_period_end,
    total_amount_euros,
    status
  ) VALUES (
    lab_id,
    period_start,
    period_end,
    0, -- Sera mis à jour après création des items
    'editee'
  ) RETURNING id INTO invoice_id;
  
  -- Créer les lignes de facturation pour chaque client ayant des passages
  FOR invoice_item IN
    SELECT 
      br.client_id,
      br.billing_configuration_id,
      br.pickup_count,
      br.delivery_count,
      br.both_count,
      br.billing_type,
      br.price_per_visit,
      br.monthly_flat_rate,
      br.total_amount_euros
    FROM billing_reports br
    WHERE br.laboratory_id = lab_id
    AND br.billing_month = period_start
    AND br.has_billing_config = true
    AND br.total_visits > 0
  LOOP
    -- Insérer la ligne de facturation
    INSERT INTO billing_invoice_items (
      invoice_id,
      client_id,
      billing_configuration_id,
      delivery_count,
      pickup_count,
      both_count,
      billing_type,
      unit_price,
      flat_rate,
      line_total
    ) VALUES (
      invoice_id,
      invoice_item.client_id,
      invoice_item.billing_configuration_id,
      invoice_item.delivery_count,
      invoice_item.pickup_count,
      invoice_item.both_count,
      invoice_item.billing_type,
      invoice_item.price_per_visit,
      invoice_item.monthly_flat_rate,
      invoice_item.total_amount_euros
    );
    
    -- Ajouter au total
    total_amount := total_amount + invoice_item.total_amount_euros;
  END LOOP;
  
  -- Mettre à jour le montant total de la facture
  UPDATE billing_invoices 
  SET total_amount_euros = total_amount
  WHERE id = invoice_id;
  
  -- Retourner l'ID de la facture créée
  RETURN invoice_id;
END;
$$;


ALTER FUNCTION "public"."generate_monthly_invoice"("lab_id" "uuid", "billing_month" "date") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."generate_monthly_invoice"("lab_id" "uuid", "billing_month" "date") IS 'Génère automatiquement une facture complète pour un laboratoire et un mois donné';



CREATE OR REPLACE FUNCTION "public"."generate_shipments_for_lab_tour"("lab_tour_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    depot_id UUID;
    depot_location_id UUID;
    depot_name TEXT;
    lab_name TEXT;
    lab_id UUID;
    tour_date DATE;
BEGIN
    -- Récupérer les informations du lab tour
    SELECT laboratory_id, date INTO lab_id, tour_date
    FROM lab_tours
    WHERE id = generate_shipments_for_lab_tour.lab_tour_id;
    
    -- Récupérer le dépôt actif et sa localisation
    SELECT id, location_id, name INTO depot_id, depot_location_id, depot_name
    FROM depot 
    WHERE is_active = true 
    LIMIT 1;
    
    -- Récupérer le nom du laboratoire
    SELECT name INTO lab_name
    FROM laboratories
    WHERE id = lab_id;
    
    -- Supprimer d'abord tous les shipments associés à ce lab_tour_id
    DELETE FROM shipments s WHERE s.lab_tour_id = generate_shipments_for_lab_tour.lab_tour_id;
    
    -- 1. Création des shipments PICKUP (livraisons)
    INSERT INTO shipments (
      id, 
      laboratory_id, 
      from_location_id, 
      to_location_id, 
      shipment_type,
      scheduled_date,
      created_at,
      lab_tour_id
    )
    SELECT 
      gen_random_uuid(), 
      lab_id,
      l.location_id,
      lc.location_id,
      'lab "' || lab_name || '" to client "' || COALESCE(lc.name, 'Unknown') || '"',
      tour_date,
      now(),
      generate_shipments_for_lab_tour.lab_tour_id
    FROM laboratory_clients lc
    JOIN laboratories l ON l.id = lab_id
    JOIN lab_tour_stops lts ON lts.client_id = lc.id
    WHERE lts.tour_id = generate_shipments_for_lab_tour.lab_tour_id
    AND lts.has_delivery = true;
    
    -- 2. Création des shipments RETURN (récupérations)
    INSERT INTO shipments (
      id, 
      laboratory_id, 
      from_location_id, 
      to_location_id, 
      shipment_type,
      scheduled_date,
      created_at,
      lab_tour_id
    )
    SELECT 
      gen_random_uuid(), 
      lab_id,
      lc.location_id,
      depot_location_id,
      'client "' || COALESCE(lc.name, 'Unknown') || '" to depot',
      tour_date,
      now(),
      generate_shipments_for_lab_tour.lab_tour_id
    FROM laboratory_clients lc
    JOIN lab_tour_stops lts ON lts.client_id = lc.id
    WHERE lts.tour_id = generate_shipments_for_lab_tour.lab_tour_id
    AND lts.has_pickup = true;
END;
$$;


ALTER FUNCTION "public"."generate_shipments_for_lab_tour"("lab_tour_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_all_clients_by_drivers"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'name', client_name,
      'lat', latitude,
      'lng', longitude,
      'type', client_type,
      'driver_id', driver_id,
      'driver_name', driver_name,
      'driver_sector', driver_sector
    )
  ) INTO result
  FROM (
    SELECT 
      COALESCE(lc.name, l.formatted_address) as client_name,
      l.latitude,
      l.longitude,
      lc.client_type,
      lc.driver_id,
      d.full_name as driver_name,
      d.sector as driver_sector
    FROM laboratory_clients lc
    JOIN locations l ON lc.location_id = l.id
    LEFT JOIN drivers d ON lc.driver_id = d.id
    WHERE lc.driver_id IS NOT NULL -- Seulement les clients avec un livreur assigné
    ORDER BY d.full_name, lc.name
  ) clients_data;
  
  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."get_all_clients_by_drivers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_driver_comparison_data"("p_period_start" "date" DEFAULT (CURRENT_DATE - '30 days'::interval), "p_period_end" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  result JSONB;
BEGIN
  -- Calculer les heures moyennes par jour pour tous les livreurs
  SELECT jsonb_agg(
    jsonb_build_object(
      'day', day_name,
      'average_hours', COALESCE(ROUND(avg_hours, 1), 0)
    ) ORDER BY day_num
  ) INTO result
  FROM (
    SELECT 
      day_name,
      day_num,
      AVG(dr.estimated_duration / 60.0) as avg_hours
    FROM (
      SELECT 'Lun' as day_name, 1 as day_num
      UNION SELECT 'Mar', 2
      UNION SELECT 'Mer', 3
      UNION SELECT 'Jeu', 4
      UNION SELECT 'Ven', 5
    ) days
    LEFT JOIN driver_routes dr ON EXTRACT(DOW FROM dr.date) = days.day_num
      AND dr.date BETWEEN p_period_start AND p_period_end
    GROUP BY day_name, day_num
  ) daily_stats;
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_driver_comparison_data"("p_period_start" "date", "p_period_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_global_driver_statistics"("period_start_param" "date" DEFAULT NULL::"date", "period_end_param" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_date DATE;
  end_date DATE;
  result JSONB;
BEGIN
  -- Définir les dates par défaut (30 derniers jours)
  start_date := COALESCE(period_start_param, CURRENT_DATE - INTERVAL '30 days');
  end_date := COALESCE(period_end_param, CURRENT_DATE);

  -- Version simplifiée avec les vraies colonnes
  SELECT jsonb_build_object(
    'period_start', start_date,
    'period_end', end_date,
    'is_global', true,
    'active_drivers_count', COALESCE(COUNT(DISTINCT dr.driver_id), 0),
    
    -- Métriques temporelles (simplifiées)
    'total_working_days', (end_date - start_date + 1),
    'average_duration_hours', 8.0, -- Valeur par défaut
    'formatted_average_duration', '8h 00min',
    'average_distance_per_day', COALESCE(AVG(dr.total_distance_km), 0),
    
    -- Métriques d'activité
    'total_routes', COALESCE(COUNT(dr.id), 0),
    'completed_routes', COALESCE(COUNT(CASE WHEN dr.status = 'completed' THEN 1 END), 0),
    'total_stops', COALESCE(COUNT(drs.id), 0),
    'average_stops_per_day', COALESCE(COUNT(drs.id)::decimal / GREATEST((end_date - start_date + 1)::decimal, 1), 0),
    'average_stops_per_route', COALESCE(AVG(stops_per_route.stops_count), 0),
    'total_distance_km', COALESCE(SUM(dr.total_distance_km), 0),
    
    -- Métriques de performance (simplifiées)
    'total_pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 0),
    'total_deliveries', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 0),
    'completed_pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' AND drs.completed = true THEN 1 END), 0),
    'completed_deliveries', COALESCE(COUNT(CASE WHEN (drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client') AND drs.completed = true THEN 1 END), 0),
    'route_completion_rate', 
      CASE 
        WHEN COUNT(dr.id) > 0 
        THEN ROUND(COUNT(CASE WHEN dr.status = 'completed' THEN 1 END) * 100.0 / COUNT(dr.id), 2) 
        ELSE 0 
      END,
    'pickup_success_rate', 
      CASE 
        WHEN COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END) > 0 
        THEN ROUND(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' AND drs.completed = true THEN 1 END) * 100.0 / COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 2)
        ELSE 0 
      END,
    'delivery_success_rate', 
      CASE 
        WHEN COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END) > 0 
        THEN ROUND(COUNT(CASE WHEN (drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client') AND drs.completed = true THEN 1 END) * 100.0 / COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 2)
        ELSE 0 
      END,
    
    -- Données graphiques (simplifiées)
    'weekly_activity', jsonb_build_array(
      jsonb_build_object('day', 'Lun', 'hours', 8),
      jsonb_build_object('day', 'Mar', 'hours', 8),
      jsonb_build_object('day', 'Mer', 'hours', 8),
      jsonb_build_object('day', 'Jeu', 'hours', 8),
      jsonb_build_object('day', 'Ven', 'hours', 8)
    ),
    'hourly_distribution', jsonb_build_array(
      jsonb_build_object('day', 'Dim', 'deliveries', 0, 'pickups', 0),
      jsonb_build_object('day', 'Lun', 'deliveries', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 0) / 7, 'pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 0) / 7),
      jsonb_build_object('day', 'Mar', 'deliveries', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 0) / 7, 'pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 0) / 7),
      jsonb_build_object('day', 'Mer', 'deliveries', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 0) / 7, 'pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 0) / 7),
      jsonb_build_object('day', 'Jeu', 'deliveries', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 0) / 7, 'pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 0) / 7),
      jsonb_build_object('day', 'Ven', 'deliveries', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%delivery%' OR drs.stop_type = 'client' THEN 1 END), 0) / 7, 'pickups', COALESCE(COUNT(CASE WHEN drs.stop_type LIKE '%pickup%' THEN 1 END), 0) / 7),
      jsonb_build_object('day', 'Sam', 'deliveries', 0, 'pickups', 0)
    ),
    'client_coverage', '[]'::jsonb,
    
    'calculated_at', NOW()
  ) INTO result
  FROM driver_routes dr
  LEFT JOIN driver_route_stops drs ON dr.id = drs.route_id
  LEFT JOIN (
    SELECT route_id, COUNT(*) as stops_count
    FROM driver_route_stops
    GROUP BY route_id
  ) stops_per_route ON dr.id = stops_per_route.route_id
  WHERE dr.date BETWEEN start_date AND end_date;
  
  RETURN COALESCE(result, jsonb_build_object(
    'period_start', start_date,
    'period_end', end_date,
    'is_global', true,
    'active_drivers_count', 0,
    'total_working_days', (end_date - start_date + 1),
    'average_duration_hours', 0,
    'formatted_average_duration', '0h 00min',
    'average_distance_per_day', 0,
    'total_routes', 0,
    'completed_routes', 0,
    'total_stops', 0,
    'average_stops_per_day', 0,
    'average_stops_per_route', 0,
    'total_distance_km', 0,
    'total_pickups', 0,
    'total_deliveries', 0,
    'completed_pickups', 0,
    'completed_deliveries', 0,
    'route_completion_rate', 0,
    'pickup_success_rate', 0,
    'delivery_success_rate', 0,
    'weekly_activity', jsonb_build_array(),
    'hourly_distribution', jsonb_build_array(),
    'client_coverage', '[]'::jsonb,
    'calculated_at', NOW()
  ));
END;
$$;


ALTER FUNCTION "public"."get_global_driver_statistics"("period_start_param" "date", "period_end_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_stop_orders_after_position"("route_id_param" "uuid", "position_threshold" integer, "increment_value" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Mettre à jour les stop_order des arrêts ORIGINAUX seulement
  -- qui viennent après la position d'insertion  
  UPDATE driver_route_stops 
  SET stop_order = stop_order + increment_value
  WHERE route_id = route_id_param 
    AND stop_order > position_threshold
    AND is_late_stop = false;  -- 🎯 NE DÉCALER QUE LES STOPS ORIGINAUX
    
  -- Log pour debug
  RAISE NOTICE 'Updated % original stops positions after % for route %, increment: %', 
    ROW_COUNT, position_threshold, route_id_param, increment_value;
END;
$$;


ALTER FUNCTION "public"."increment_stop_orders_after_position"("route_id_param" "uuid", "position_threshold" integer, "increment_value" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_laboratory_client_name_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  user_id_from_jwt TEXT;
BEGIN
  -- Extraire l'ID utilisateur du JWT si disponible
  BEGIN
    user_id_from_jwt := current_setting('request.jwt.claims', true)::json->>'sub';
  EXCEPTION WHEN OTHERS THEN
    user_id_from_jwt := NULL;
  END;

  -- Si le nom a changé, l'enregistrer dans la table d'audit
  IF OLD.name IS DISTINCT FROM NEW.name THEN
    INSERT INTO laboratory_clients_audit (
      client_id,
      old_name,
      new_name,
      changed_by,
      operation,
      additional_info
    ) VALUES (
      NEW.id,
      OLD.name,
      NEW.name,
      user_id_from_jwt::UUID,
      'UPDATE',
      jsonb_build_object(
        'timestamp', NOW(),
        'session_info', current_setting('application_name', true)
      )
    );
    
    -- Aussi logger via RAISE NOTICE pour les logs PostgreSQL
    RAISE NOTICE 'CLIENT NAME CHANGED: ID=%, OLD=%, NEW=%, USER=%, TIME=%', 
      NEW.id, OLD.name, NEW.name, user_id_from_jwt, NOW();
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."log_laboratory_client_name_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."maintain_driver_statistics"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  processed_count INTEGER := 0;
  error_count INTEGER := 0;
  result_text TEXT;
BEGIN
  -- Suppression des anciennes statistiques (plus de 90 jours)
  DELETE FROM driver_statistics 
  WHERE calculated_at < NOW() - INTERVAL '90 days';
  
  -- Recalcul des statistiques pour les 30 derniers jours
  BEGIN
    SELECT refresh_all_driver_statistics() INTO result_text;
    processed_count := processed_count + 1;
  EXCEPTION WHEN OTHERS THEN
    error_count := error_count + 1;
  END;
  
  -- Recalcul des statistiques pour la semaine dernière
  BEGIN
    PERFORM refresh_all_driver_statistics(
      CURRENT_DATE - INTERVAL '7 days',
      CURRENT_DATE
    );
    processed_count := processed_count + 1;
  EXCEPTION WHEN OTHERS THEN
    error_count := error_count + 1;
  END;
  
  -- Retourner le résumé
  RETURN 'Maintenance terminée - Processus réussis: ' || processed_count || 
         ', Erreurs: ' || error_count || 
         ', Anciennes données supprimées';
END;
$$;


ALTER FUNCTION "public"."maintain_driver_statistics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_invoice_as_sent"("invoice_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE billing_invoices 
  SET status = 'envoyee'
  WHERE id = invoice_id;
  
  RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."mark_invoice_as_sent"("invoice_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."mark_invoice_as_sent"("invoice_id" "uuid") IS 'Marque une facture comme envoyée et met à jour sent_at automatiquement';



CREATE OR REPLACE FUNCTION "public"."optimize_route"("p_route_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT
    content::JSONB INTO result
  FROM
    http_post(
      'https://akmicemcgohflolembbb.supabase.co/functions/v1/optimize-route',
      jsonb_build_object('routeId', p_route_id),
      'application/json',
      jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', concat('Bearer ', current_setting('supabase_functions.key', true))
      )
    );

  RETURN result;
END;
$$;


ALTER FUNCTION "public"."optimize_route"("p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_duplicate_driver_routes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    existing_route_id UUID;
    existing_status TEXT;
    deleted_count INTEGER := 0;
BEGIN
    -- Chercher une tournée existante pour le même driver_id et date
    SELECT id, status INTO existing_route_id, existing_status
    FROM driver_routes 
    WHERE driver_id = NEW.driver_id 
      AND date = NEW.date 
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID);
    
    -- Si une tournée existe déjà
    IF existing_route_id IS NOT NULL THEN
        
        -- CAS 1: Si la tournée existante est COMPLETED, protéger et rejeter la nouvelle
        IF existing_status = 'completed' THEN
            RAISE NOTICE 'Insertion rejetée: Tournée completed existante pour driver % date % (ID: %)', 
                         NEW.driver_id, NEW.date, existing_route_id;
            -- Empêcher l'insertion de la nouvelle tournée
            RETURN NULL;
        END IF;
        
        -- CAS 2: Tournée existante non-completed, la supprimer (logique normale)
        DELETE FROM driver_routes WHERE id = existing_route_id;
        GET DIAGNOSTICS deleted_count = ROW_COUNT;
        
        RAISE NOTICE 'Tournée % supprimée pour driver % date % (% enregistrements supprimés)', 
                     existing_status, NEW.driver_id, NEW.date, deleted_count;
    END IF;
    
    -- Laisser l'insertion se faire normalement (sauf si RETURN NULL ci-dessus)
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_duplicate_driver_routes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_all_driver_statistics"("p_period_start" "date" DEFAULT (CURRENT_DATE - '30 days'::interval), "p_period_end" "date" DEFAULT CURRENT_DATE) RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  driver_record RECORD;
  stats_count INTEGER := 0;
BEGIN
  FOR driver_record IN 
    SELECT id FROM drivers
  LOOP
    PERFORM calculate_driver_statistics(
      driver_record.id,
      p_period_start,
      p_period_end
    );
    stats_count := stats_count + 1;
  END LOOP;
  
  RETURN 'Statistiques recalculées pour ' || stats_count || ' livreurs';
END;
$$;


ALTER FUNCTION "public"."refresh_all_driver_statistics"("p_period_start" "date", "p_period_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."replace_lab_tour_shipments"("old_lab_tour_id" "uuid", "new_lab_tour_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Générer les nouveaux shipments d'abord
  PERFORM generate_lab_tour_shipments(new_lab_tour_id);
  
  -- Supprimer les anciens seulement après
  PERFORM delete_lab_tour_shipments(old_lab_tour_id);
END;
$$;


ALTER FUNCTION "public"."replace_lab_tour_shipments"("old_lab_tour_id" "uuid", "new_lab_tour_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_invoice_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.invoice_number IS NULL OR NEW.invoice_number = '' THEN
    NEW.invoice_number := generate_invoice_number(NEW.laboratory_id, NEW.billing_period_start);
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_invoice_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_lab_tour_late_stops_reviewed_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Si le statut change de 'pending' vers 'approved' ou 'rejected'
  IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
    NEW.reviewed_at = NOW();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_lab_tour_late_stops_reviewed_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_depot_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_depot_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_driver_statistics_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_driver_statistics_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_lab_tour_late_stops_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_lab_tour_late_stops_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_sent_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Quand le status passe à 'envoyee', on met à jour sent_at
  IF NEW.status = 'envoyee' AND (OLD.status IS NULL OR OLD.status != 'envoyee') THEN
    NEW.sent_at = NOW();
  END IF;
  -- Mettre à jour updated_at
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_sent_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_shipments_stop_reference"("p_route_id" "uuid", "p_old_stop_id" "text", "p_new_stop_id" "text", "p_field" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_updated_count INT;
BEGIN
    IF p_field = 'pickup_stop_id' THEN
        UPDATE driver_route_shipments
        SET pickup_stop_id = p_new_stop_id
        WHERE route_id = p_route_id 
          AND pickup_stop_id = p_old_stop_id;
        
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
        
    ELSIF p_field = 'delivery_stop_id' THEN
        UPDATE driver_route_shipments
        SET delivery_stop_id = p_new_stop_id
        WHERE route_id = p_route_id 
          AND delivery_stop_id = p_old_stop_id;
        
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    ELSE
        RAISE EXCEPTION 'Invalid field name: %', p_field;
    END IF;
    
    RETURN json_build_object(
        'updated_count', v_updated_count,
        'old_stop_id', p_old_stop_id,
        'new_stop_id', p_new_stop_id,
        'field', p_field
    );
END;
$$;


ALTER FUNCTION "public"."update_shipments_stop_reference"("p_route_id" "uuid", "p_old_stop_id" "text", "p_new_stop_id" "text", "p_field" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."administrators" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."administrators" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admins" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."admins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_configurations" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "laboratory_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "billing_type" character varying(20) NOT NULL,
    "price_per_visit" numeric(10,2),
    "monthly_flat_rate" numeric(10,2),
    "effective_from" "date" DEFAULT CURRENT_DATE NOT NULL,
    "effective_to" "date",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_configurations_billing_type_check" CHECK ((("billing_type")::"text" = ANY ((ARRAY['monthly_flat_rate'::character varying, 'per_visit'::character varying])::"text"[]))),
    CONSTRAINT "billing_configurations_check" CHECK ((((("billing_type")::"text" = 'per_visit'::"text") AND ("price_per_visit" IS NOT NULL) AND ("monthly_flat_rate" IS NULL)) OR ((("billing_type")::"text" = 'monthly_flat_rate'::"text") AND ("monthly_flat_rate" IS NOT NULL) AND ("price_per_visit" IS NULL))))
);


ALTER TABLE "public"."billing_configurations" OWNER TO "postgres";


COMMENT ON TABLE "public"."billing_configurations" IS 'Configuration des tarifs de facturation par client de laboratoire';



COMMENT ON COLUMN "public"."billing_configurations"."billing_type" IS 'Type de facturation: monthly_flat_rate ou per_visit';



COMMENT ON COLUMN "public"."billing_configurations"."effective_from" IS 'Date de début de validité de cette configuration';



COMMENT ON COLUMN "public"."billing_configurations"."effective_to" IS 'Date de fin de validité (NULL = active)';



CREATE TABLE IF NOT EXISTS "public"."billing_invoice_items" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "billing_configuration_id" "uuid" NOT NULL,
    "delivery_count" integer DEFAULT 0 NOT NULL,
    "pickup_count" integer DEFAULT 0 NOT NULL,
    "both_count" integer DEFAULT 0 NOT NULL,
    "total_visits" integer GENERATED ALWAYS AS ((("delivery_count" + "pickup_count") + "both_count")) STORED,
    "billing_type" character varying(20) NOT NULL,
    "unit_price" numeric(10,2),
    "flat_rate" numeric(10,2),
    "line_total" numeric(10,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_invoice_items_check" CHECK ((((("billing_type")::"text" = 'per_visit'::"text") AND ("unit_price" IS NOT NULL) AND ("flat_rate" IS NULL)) OR ((("billing_type")::"text" = 'monthly_flat_rate'::"text") AND ("flat_rate" IS NOT NULL) AND ("unit_price" IS NULL))))
);


ALTER TABLE "public"."billing_invoice_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."billing_invoice_items" IS 'Lignes détaillées des factures avec compteurs de passages par client';



COMMENT ON COLUMN "public"."billing_invoice_items"."delivery_count" IS 'Nombre de livraisons seules pour la période';



COMMENT ON COLUMN "public"."billing_invoice_items"."pickup_count" IS 'Nombre de récupérations seules pour la période';



COMMENT ON COLUMN "public"."billing_invoice_items"."both_count" IS 'Nombre de passages livraison+récupération pour la période';



CREATE TABLE IF NOT EXISTS "public"."billing_invoices" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "laboratory_id" "uuid" NOT NULL,
    "invoice_number" character varying(50) NOT NULL,
    "billing_period_start" "date" NOT NULL,
    "billing_period_end" "date" NOT NULL,
    "total_amount_euros" numeric(10,2) DEFAULT 0 NOT NULL,
    "status" character varying(20) DEFAULT 'editee'::character varying NOT NULL,
    "generated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_invoices_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['editee'::character varying, 'envoyee'::character varying])::"text"[])))
);


ALTER TABLE "public"."billing_invoices" OWNER TO "postgres";


COMMENT ON TABLE "public"."billing_invoices" IS 'Factures mensuelles générées pour les laboratoires';



COMMENT ON COLUMN "public"."billing_invoices"."invoice_number" IS 'Numéro de facture au format NOM_LABORATOIRE-YYYY-MM';



COMMENT ON COLUMN "public"."billing_invoices"."status" IS 'Statut: editee (générée) ou envoyee';



COMMENT ON COLUMN "public"."billing_invoices"."sent_at" IS 'Date d envoi (auto-remplie quand status passe à envoyee)';



CREATE TABLE IF NOT EXISTS "public"."driver_route_shipments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "shipment_ref" character varying(100),
    "laboratory_id" "uuid" NOT NULL,
    "pickup_stop_id" "uuid" NOT NULL,
    "delivery_stop_id" "uuid" NOT NULL,
    "pickup_time" timestamp with time zone,
    "delivery_time" timestamp with time zone,
    "pickup_status" character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    "delivery_status" character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    "issue_type" character varying(100),
    "issue_description" "text",
    "proof_photo_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "route_id" "uuid",
    "laboratory_client_id" "uuid",
    "shipment_type" "text",
    "unexpected" boolean DEFAULT false NOT NULL,
    "is_late_shipment" boolean DEFAULT false,
    "is_shared_pickup" boolean DEFAULT false
);


ALTER TABLE "public"."driver_route_shipments" OWNER TO "postgres";


COMMENT ON COLUMN "public"."driver_route_shipments"."laboratory_client_id" IS 'Référence au client du laboratoire pour traçabilité dans l''historique';



COMMENT ON COLUMN "public"."driver_route_shipments"."unexpected" IS 'Indique si ce shipment a été créé de manière inattendue par un livreur (true) ou s''il était planifié (false)';



COMMENT ON COLUMN "public"."driver_route_shipments"."is_late_shipment" IS 'Indique si ce shipment a été créé comme late shipment (ajouté après optimisation de la tournée)';



COMMENT ON COLUMN "public"."driver_route_shipments"."is_shared_pickup" IS 'Indique si ce shipment fait partie d''une collecte partagée';



CREATE TABLE IF NOT EXISTS "public"."driver_route_stops" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "route_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "stop_order" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "stop_type" "text" DEFAULT 'unknown'::"text",
    "client_actions" "text",
    "estimated_arrival_time" character varying(255),
    "estimated_departure_time" character varying(255),
    "distance_from_previous" double precision,
    "duration_from_previous" integer,
    "completed" boolean DEFAULT false,
    "arrival_time" timestamp with time zone,
    "is_late_stop" boolean DEFAULT false,
    "is_shared_pickup_stop" boolean DEFAULT false,
    CONSTRAINT "driver_route_stops_client_actions_check" CHECK ((("client_actions" IS NULL) OR ("client_actions" = ANY (ARRAY['pickup'::"text", 'delivery'::"text", 'both'::"text"])))),
    CONSTRAINT "driver_route_stops_stop_type_check" CHECK (("stop_type" = ANY (ARRAY['lab_pickup'::"text", 'lab_dropoff'::"text", 'depot_pickup'::"text", 'depot_dropoff'::"text", 'client'::"text", 'client_pickup'::"text", 'client_delivery'::"text", 'LAB_PICKUP'::"text", 'LAB_DROPOFF'::"text", 'DEPOT_PICKUP'::"text", 'DEPOT_DROPOFF'::"text", 'CLIENT'::"text"])))
);


ALTER TABLE "public"."driver_route_stops" OWNER TO "postgres";


COMMENT ON COLUMN "public"."driver_route_stops"."stop_type" IS 'Type d''arrêt: lab_pickup, lab_dropoff, depot_pickup, depot_dropoff, client_pickup, client_delivery, client_both';



COMMENT ON COLUMN "public"."driver_route_stops"."arrival_time" IS 'Heure d''arrivée effective du livreur à cet arrêt';



COMMENT ON COLUMN "public"."driver_route_stops"."is_late_stop" IS 'Indique si cet arrêt a été ajouté en dernière minute après optimisation initiale';



COMMENT ON COLUMN "public"."driver_route_stops"."is_shared_pickup_stop" IS 'Indique si ce stop est un point de collecte partagé pour plusieurs laboratoires';



CREATE TABLE IF NOT EXISTS "public"."driver_routes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "status" "text" NOT NULL,
    "estimated_duration" integer,
    "total_distance_km" double precision,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "polyline" "text",
    CONSTRAINT "driver_routes_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'submitted'::"text", 'optimized'::"text", 'validated'::"text", 'in_progress'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."driver_routes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."laboratories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "email" character varying(255),
    "depot_is_lab" boolean DEFAULT false NOT NULL,
    "shared_pickup" boolean DEFAULT false NOT NULL,
    CONSTRAINT "laboratories_shared_pickup_depot_is_lab_check" CHECK ((NOT (("shared_pickup" = true) AND ("depot_is_lab" = true))))
);


ALTER TABLE "public"."laboratories" OWNER TO "postgres";


COMMENT ON COLUMN "public"."laboratories"."depot_is_lab" IS 'Flag indiquant si le laboratoire est en mode "Mika = Labo" - tous les clients doivent livrer/récupérer depuis le dépôt';



COMMENT ON COLUMN "public"."laboratories"."shared_pickup" IS 'Flag indiquant si ce laboratoire participe aux récupérations partagées. Ne peut pas être TRUE si depot_is_lab est TRUE.';



CREATE TABLE IF NOT EXISTS "public"."laboratory_clients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "laboratory_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "client_type" "text" NOT NULL,
    "is_pickup_depot" boolean DEFAULT false,
    "is_return_depot" boolean DEFAULT false,
    "is_return_next_day" boolean DEFAULT false,
    "depot_is_dentist" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "driver_id" "uuid",
    "name" "text",
    "depot_is_lab" boolean DEFAULT false,
    "is_mika_client" boolean DEFAULT false,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "depot_flags_mutual_exclusion" CHECK ((NOT (("depot_is_dentist" = true) AND ("depot_is_lab" = true)))),
    CONSTRAINT "laboratory_clients_client_type_check" CHECK (("client_type" = ANY (ARRAY['dentist'::"text", 'laboratory'::"text", 'depot'::"text"])))
);


ALTER TABLE "public"."laboratory_clients" OWNER TO "postgres";


COMMENT ON COLUMN "public"."laboratory_clients"."driver_id" IS 'The ID of the driver assigned to this client';



COMMENT ON COLUMN "public"."laboratory_clients"."is_active" IS 'client toujours desservi';



CREATE OR REPLACE VIEW "public"."billing_reports" AS
 WITH "client_visits_per_route" AS (
         SELECT DISTINCT "drs"."laboratory_id",
            "lc"."id" AS "client_id",
            "lc"."name" AS "client_name",
            "dr"."id" AS "route_id",
            "dr"."date" AS "route_date",
            "date_trunc"('month'::"text", ("dr"."date")::timestamp with time zone) AS "billing_month",
                CASE
                    WHEN ("bool_or"((("drs"."pickup_status")::"text" = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::"text"[]))) AND "bool_or"((("drs"."delivery_status")::"text" = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::"text"[])))) THEN 'both'::"text"
                    WHEN "bool_or"((("drs"."pickup_status")::"text" = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::"text"[]))) THEN 'pickup'::"text"
                    WHEN "bool_or"((("drs"."delivery_status")::"text" = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::"text"[]))) THEN 'delivery'::"text"
                    ELSE NULL::"text"
                END AS "visit_type"
           FROM (((("public"."driver_route_shipments" "drs"
             JOIN "public"."driver_route_stops" "pickup_stop" ON (("pickup_stop"."id" = "drs"."pickup_stop_id")))
             JOIN "public"."driver_route_stops" "delivery_stop" ON (("delivery_stop"."id" = "drs"."delivery_stop_id")))
             JOIN "public"."driver_routes" "dr" ON (("dr"."id" = "pickup_stop"."route_id")))
             JOIN "public"."laboratory_clients" "lc" ON (("lc"."laboratory_id" = "drs"."laboratory_id")))
          WHERE ((("pickup_stop"."location_id" = "lc"."location_id") OR ("delivery_stop"."location_id" = "lc"."location_id")) AND (("drs"."pickup_status")::"text" <> 'cancelled'::"text") AND (("drs"."delivery_status")::"text" <> 'cancelled'::"text") AND ((("drs"."pickup_status")::"text" = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::"text"[])) OR (("drs"."delivery_status")::"text" = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::"text"[]))))
          GROUP BY "drs"."laboratory_id", "lc"."id", "lc"."name", "dr"."id", "dr"."date"
        ), "monthly_client_stats" AS (
         SELECT "client_visits_per_route"."laboratory_id",
            "client_visits_per_route"."client_id",
            "client_visits_per_route"."client_name",
            "client_visits_per_route"."billing_month",
            "count"(
                CASE
                    WHEN ("client_visits_per_route"."visit_type" = 'pickup'::"text") THEN 1
                    ELSE NULL::integer
                END) AS "pickup_count",
            "count"(
                CASE
                    WHEN ("client_visits_per_route"."visit_type" = 'delivery'::"text") THEN 1
                    ELSE NULL::integer
                END) AS "delivery_count",
            "count"(
                CASE
                    WHEN ("client_visits_per_route"."visit_type" = 'both'::"text") THEN 1
                    ELSE NULL::integer
                END) AS "both_count"
           FROM "client_visits_per_route"
          WHERE ("client_visits_per_route"."visit_type" IS NOT NULL)
          GROUP BY "client_visits_per_route"."laboratory_id", "client_visits_per_route"."client_id", "client_visits_per_route"."client_name", "client_visits_per_route"."billing_month"
        )
 SELECT "mcs"."client_id",
    "mcs"."client_name",
    "mcs"."laboratory_id",
    "l"."name" AS "laboratory_name",
    "mcs"."billing_month",
    "mcs"."pickup_count",
    "mcs"."delivery_count",
    "mcs"."both_count",
    (("mcs"."pickup_count" + "mcs"."delivery_count") + "mcs"."both_count") AS "total_visits",
    "bc"."id" AS "billing_configuration_id",
    "bc"."billing_type",
    "bc"."price_per_visit",
    "bc"."monthly_flat_rate",
        CASE
            WHEN (("bc"."billing_type")::"text" = 'monthly_flat_rate'::"text") THEN "bc"."monthly_flat_rate"
            WHEN (("bc"."billing_type")::"text" = 'per_visit'::"text") THEN ("bc"."price_per_visit" * ((("mcs"."pickup_count" + "mcs"."delivery_count") + "mcs"."both_count"))::numeric)
            ELSE (0)::numeric
        END AS "total_amount_euros",
        CASE
            WHEN ("bc"."id" IS NOT NULL) THEN true
            ELSE false
        END AS "has_billing_config"
   FROM (("monthly_client_stats" "mcs"
     JOIN "public"."laboratories" "l" ON (("l"."id" = "mcs"."laboratory_id")))
     LEFT JOIN "public"."billing_configurations" "bc" ON ((("bc"."client_id" = "mcs"."client_id") AND ("bc"."is_active" = true) AND ("bc"."effective_from" <= CURRENT_DATE) AND (("bc"."effective_to" IS NULL) OR ("bc"."effective_to" >= CURRENT_DATE)))))
  ORDER BY "mcs"."laboratory_id", "mcs"."billing_month" DESC, "mcs"."client_name";


ALTER TABLE "public"."billing_reports" OWNER TO "postgres";


COMMENT ON VIEW "public"."billing_reports" IS 'Vue corrigée: 1 client = 1 passage par tournée, failed=facturé, cancelled=non facturé';



CREATE TABLE IF NOT EXISTS "public"."error_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "user_id" "uuid",
    "user_email" "text",
    "driver_id" "text",
    "error_type" "text" NOT NULL,
    "error_message" "text" NOT NULL,
    "error_stack" "text",
    "error_source" "text",
    "app_version" "text",
    "page_url" "text",
    "user_action" "text",
    "device_type" "text",
    "device_model" "text",
    "os_version" "text",
    "browser_name" "text",
    "browser_version" "text",
    "user_agent" "text",
    "memory_usage" "jsonb",
    "storage_usage" "jsonb",
    "network_status" "jsonb",
    "current_route_id" "text",
    "current_stop_index" integer,
    "pending_sync_actions" integer,
    "severity" "text" DEFAULT 'error'::"text",
    "is_resolved" boolean DEFAULT false,
    "resolution_notes" "text",
    "session_id" "text",
    "occurrence_count" integer DEFAULT 1,
    "first_seen" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "last_seen" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    CONSTRAINT "error_logs_severity_check" CHECK (("severity" = ANY (ARRAY['info'::"text", 'warning'::"text", 'error'::"text", 'critical'::"text"])))
);


ALTER TABLE "public"."error_logs" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."critical_errors_recent" AS
 SELECT "error_logs"."id",
    "error_logs"."created_at",
    "error_logs"."user_email",
    "error_logs"."error_type",
    "error_logs"."error_message",
    "error_logs"."device_type",
    "error_logs"."device_model",
    "error_logs"."os_version",
    "error_logs"."page_url",
    "error_logs"."user_action",
    "error_logs"."occurrence_count"
   FROM "public"."error_logs"
  WHERE (("error_logs"."severity" = 'critical'::"text") AND ("error_logs"."created_at" >= ("now"() - '24:00:00'::interval)) AND ("error_logs"."is_resolved" = false))
  ORDER BY "error_logs"."created_at" DESC;


ALTER TABLE "public"."critical_errors_recent" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."depot" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "location_id" "uuid",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."depot" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."depot_shipments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shipment_id" "uuid" NOT NULL,
    "arrival_time" timestamp with time zone,
    "departure_time" timestamp with time zone,
    "status" "text" DEFAULT 'at_depot'::"text" NOT NULL,
    "handler_name" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."depot_shipments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."driver_statistics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "total_working_days" integer DEFAULT 0,
    "average_start_time" time without time zone,
    "average_end_time" time without time zone,
    "average_duration_hours" numeric(5,2) DEFAULT 0,
    "earliest_start_time" time without time zone,
    "latest_end_time" time without time zone,
    "total_distance_km" numeric(10,2) DEFAULT 0,
    "average_distance_per_day" numeric(10,2) DEFAULT 0,
    "total_stops" integer DEFAULT 0,
    "average_stops_per_day" integer DEFAULT 0,
    "average_stops_per_route" integer DEFAULT 0,
    "total_routes" integer DEFAULT 0,
    "completed_routes" integer DEFAULT 0,
    "total_pickups" integer DEFAULT 0,
    "total_deliveries" integer DEFAULT 0,
    "completed_pickups" integer DEFAULT 0,
    "completed_deliveries" integer DEFAULT 0,
    "route_completion_rate" numeric(5,2) DEFAULT 0,
    "pickup_success_rate" numeric(5,2) DEFAULT 0,
    "delivery_success_rate" numeric(5,2) DEFAULT 0,
    "weekly_activity" "jsonb",
    "hourly_distribution" "jsonb",
    "client_coverage" "jsonb",
    "calculated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."driver_statistics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."drivers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "start_address" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "sector" "text",
    "vehicle_type" "text",
    "start_time" "text",
    "email" character varying(255),
    "place_id" "text",
    "latitude" double precision,
    "longitude" double precision
);


ALTER TABLE "public"."drivers" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."error_stats" AS
 SELECT "error_logs"."error_type",
    "error_logs"."device_type",
    "error_logs"."severity",
    "count"(*) AS "error_count",
    "count"(DISTINCT "error_logs"."user_id") AS "affected_users",
    "min"("error_logs"."created_at") AS "first_occurrence",
    "max"("error_logs"."created_at") AS "last_occurrence",
    "avg"("error_logs"."occurrence_count") AS "avg_occurrences_per_session"
   FROM "public"."error_logs"
  WHERE ("error_logs"."created_at" >= ("now"() - '7 days'::interval))
  GROUP BY "error_logs"."error_type", "error_logs"."device_type", "error_logs"."severity"
  ORDER BY ("count"(*)) DESC;


ALTER TABLE "public"."error_stats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lab_tour_late_stops" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "lab_tour_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "has_pickup" boolean DEFAULT false NOT NULL,
    "has_delivery" boolean DEFAULT false NOT NULL,
    "status" "public"."late_stop_status" DEFAULT 'pending'::"public"."late_stop_status" NOT NULL,
    "urgent_instructions" "text",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "uuid",
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "late_stop_must_have_action" CHECK ((("has_pickup" = true) OR ("has_delivery" = true)))
);


ALTER TABLE "public"."lab_tour_late_stops" OWNER TO "postgres";


COMMENT ON TABLE "public"."lab_tour_late_stops" IS 'Demandes de dernière minute pour les tournées de laboratoire';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."lab_tour_id" IS 'Référence vers la tournée de laboratoire du jour';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."client_id" IS 'Client concerné par la demande urgente';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."has_pickup" IS 'Demande de ramassage en urgence';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."has_delivery" IS 'Demande de livraison en urgence';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."status" IS 'Statut de la demande: pending, approved, rejected';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."urgent_instructions" IS 'Instructions spéciales pour cette demande urgente';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."requested_at" IS 'Horodatage de la demande';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."reviewed_at" IS 'Horodatage de la révision par administrateur';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."reviewed_by" IS 'Administrateur qui a traité la demande';



COMMENT ON COLUMN "public"."lab_tour_late_stops"."rejection_reason" IS 'Raison du rejet si applicable';



CREATE TABLE IF NOT EXISTS "public"."lab_tour_shipments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "lab_tour_id" "uuid" NOT NULL,
    "from_location_id" "uuid" NOT NULL,
    "to_location_id" "uuid" NOT NULL,
    "shipment_type" "text" NOT NULL,
    "scheduled_date" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_return_next_day" boolean DEFAULT false,
    "client_id" "uuid"
);


ALTER TABLE "public"."lab_tour_shipments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lab_tour_stops" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tour_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "has_delivery" boolean DEFAULT false,
    "has_pickup" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."lab_tour_stops" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lab_tours" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "laboratory_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "status" "text" NOT NULL,
    "submission_time" timestamp with time zone,
    "pickup_time" time without time zone,
    "return_time" time without time zone,
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "lab_tours_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'submitted'::"text", 'validated'::"text", 'rejected'::"text", 'pending_changes'::"text"])))
);


ALTER TABLE "public"."lab_tours" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."laboratory_clients_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "old_name" "text",
    "new_name" "text",
    "changed_by" "uuid",
    "changed_at" timestamp with time zone DEFAULT "now"(),
    "operation" "text" NOT NULL,
    "additional_info" "jsonb"
);


ALTER TABLE "public"."laboratory_clients_audit" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."laboratory_statistics" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "laboratory_id" "uuid" NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "total_shipments" integer DEFAULT 0,
    "completed_shipments" integer DEFAULT 0,
    "failed_shipments" integer DEFAULT 0,
    "success_rate" numeric(5,2) DEFAULT 0.00,
    "failure_rate" numeric(5,2) DEFAULT 0.00,
    "most_delivered_client_id" "uuid",
    "most_delivered_client_name" "text",
    "most_delivered_count" integer DEFAULT 0,
    "least_delivered_client_id" "uuid",
    "least_delivered_client_name" "text",
    "least_delivered_count" integer DEFAULT 0,
    "weekly_activity" "jsonb",
    "market_share_data" "jsonb",
    "calculated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."laboratory_statistics" OWNER TO "postgres";


COMMENT ON TABLE "public"."laboratory_statistics" IS 'Statistiques pré-calculées des laboratoires pour optimiser les performances de la page statistiques';



COMMENT ON COLUMN "public"."laboratory_statistics"."weekly_activity" IS 'Données JSON pour le graphique activité hebdomadaire';



COMMENT ON COLUMN "public"."laboratory_statistics"."market_share_data" IS 'Données JSON pour le graphique parts de marché';



CREATE TABLE IF NOT EXISTS "public"."location_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "uuid" NOT NULL,
    "photo_url" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."location_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "place_id" "text",
    "formatted_address" "text" NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "delivery_instructions" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "type" "text" DEFAULT 'unknown'::"text"
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_driver_performance_summary" AS
 SELECT "d"."id" AS "driver_id",
    "d"."full_name" AS "driver_name",
    "d"."sector",
    COALESCE("recent_stats"."total_routes", 0) AS "routes_this_month",
    COALESCE("recent_stats"."completed_routes", 0) AS "completed_routes_this_month",
    COALESCE("recent_stats"."route_completion_rate", (0)::numeric) AS "completion_rate",
    COALESCE("recent_stats"."total_distance_km", (0)::numeric) AS "total_distance_this_month",
    COALESCE("recent_stats"."average_duration_hours", (0)::numeric) AS "avg_duration_hours",
        CASE
            WHEN ("recent_stats"."total_routes" > 0) THEN 'active'::"text"
            ELSE 'inactive'::"text"
        END AS "status",
    "recent_stats"."calculated_at" AS "last_calculation"
   FROM ("public"."drivers" "d"
     LEFT JOIN ( SELECT DISTINCT ON ("driver_statistics"."driver_id") "driver_statistics"."id",
            "driver_statistics"."driver_id",
            "driver_statistics"."period_start",
            "driver_statistics"."period_end",
            "driver_statistics"."total_working_days",
            "driver_statistics"."average_start_time",
            "driver_statistics"."average_end_time",
            "driver_statistics"."average_duration_hours",
            "driver_statistics"."earliest_start_time",
            "driver_statistics"."latest_end_time",
            "driver_statistics"."total_distance_km",
            "driver_statistics"."average_distance_per_day",
            "driver_statistics"."total_stops",
            "driver_statistics"."average_stops_per_day",
            "driver_statistics"."average_stops_per_route",
            "driver_statistics"."total_routes",
            "driver_statistics"."completed_routes",
            "driver_statistics"."total_pickups",
            "driver_statistics"."total_deliveries",
            "driver_statistics"."completed_pickups",
            "driver_statistics"."completed_deliveries",
            "driver_statistics"."route_completion_rate",
            "driver_statistics"."pickup_success_rate",
            "driver_statistics"."delivery_success_rate",
            "driver_statistics"."weekly_activity",
            "driver_statistics"."hourly_distribution",
            "driver_statistics"."client_coverage",
            "driver_statistics"."calculated_at",
            "driver_statistics"."created_at",
            "driver_statistics"."updated_at"
           FROM "public"."driver_statistics"
          WHERE ("driver_statistics"."period_start" >= (CURRENT_DATE - '30 days'::interval))
          ORDER BY "driver_statistics"."driver_id", "driver_statistics"."calculated_at" DESC) "recent_stats" ON (("d"."id" = "recent_stats"."driver_id")))
  ORDER BY "recent_stats"."total_routes" DESC NULLS LAST, "d"."full_name";


ALTER TABLE "public"."v_driver_performance_summary" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_driver_statistics_with_details" AS
 SELECT "ds"."id",
    "ds"."driver_id",
    "ds"."period_start",
    "ds"."period_end",
    "ds"."total_working_days",
    "ds"."average_start_time",
    "ds"."average_end_time",
    "ds"."average_duration_hours",
    "ds"."earliest_start_time",
    "ds"."latest_end_time",
    "ds"."total_distance_km",
    "ds"."average_distance_per_day",
    "ds"."total_stops",
    "ds"."average_stops_per_day",
    "ds"."average_stops_per_route",
    "ds"."total_routes",
    "ds"."completed_routes",
    "ds"."total_pickups",
    "ds"."total_deliveries",
    "ds"."completed_pickups",
    "ds"."completed_deliveries",
    "ds"."route_completion_rate",
    "ds"."pickup_success_rate",
    "ds"."delivery_success_rate",
    "ds"."weekly_activity",
    "ds"."hourly_distribution",
    "ds"."client_coverage",
    "ds"."calculated_at",
    "ds"."created_at",
    "ds"."updated_at",
    "d"."full_name" AS "driver_name",
    "d"."email" AS "driver_email",
    "d"."sector",
    "d"."vehicle_type",
    "d"."start_time" AS "configured_start_time",
        CASE
            WHEN ("ds"."average_duration_hours" > (0)::numeric) THEN ((("floor"("ds"."average_duration_hours") || 'h '::"text") || "lpad"(("round"((("ds"."average_duration_hours" - "floor"("ds"."average_duration_hours")) * (60)::numeric)))::"text", 2, '0'::"text")) || 'min'::"text")
            ELSE '0h 00min'::"text"
        END AS "formatted_average_duration"
   FROM ("public"."driver_statistics" "ds"
     JOIN "public"."drivers" "d" ON (("ds"."driver_id" = "d"."id")));


ALTER TABLE "public"."v_driver_statistics_with_details" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_recent_driver_statistics" AS
 SELECT "v_driver_statistics_with_details"."id",
    "v_driver_statistics_with_details"."driver_id",
    "v_driver_statistics_with_details"."period_start",
    "v_driver_statistics_with_details"."period_end",
    "v_driver_statistics_with_details"."total_working_days",
    "v_driver_statistics_with_details"."average_start_time",
    "v_driver_statistics_with_details"."average_end_time",
    "v_driver_statistics_with_details"."average_duration_hours",
    "v_driver_statistics_with_details"."earliest_start_time",
    "v_driver_statistics_with_details"."latest_end_time",
    "v_driver_statistics_with_details"."total_distance_km",
    "v_driver_statistics_with_details"."average_distance_per_day",
    "v_driver_statistics_with_details"."total_stops",
    "v_driver_statistics_with_details"."average_stops_per_day",
    "v_driver_statistics_with_details"."average_stops_per_route",
    "v_driver_statistics_with_details"."total_routes",
    "v_driver_statistics_with_details"."completed_routes",
    "v_driver_statistics_with_details"."total_pickups",
    "v_driver_statistics_with_details"."total_deliveries",
    "v_driver_statistics_with_details"."completed_pickups",
    "v_driver_statistics_with_details"."completed_deliveries",
    "v_driver_statistics_with_details"."route_completion_rate",
    "v_driver_statistics_with_details"."pickup_success_rate",
    "v_driver_statistics_with_details"."delivery_success_rate",
    "v_driver_statistics_with_details"."weekly_activity",
    "v_driver_statistics_with_details"."hourly_distribution",
    "v_driver_statistics_with_details"."client_coverage",
    "v_driver_statistics_with_details"."calculated_at",
    "v_driver_statistics_with_details"."created_at",
    "v_driver_statistics_with_details"."updated_at",
    "v_driver_statistics_with_details"."driver_name",
    "v_driver_statistics_with_details"."driver_email",
    "v_driver_statistics_with_details"."sector",
    "v_driver_statistics_with_details"."vehicle_type",
    "v_driver_statistics_with_details"."configured_start_time",
    "v_driver_statistics_with_details"."formatted_average_duration"
   FROM "public"."v_driver_statistics_with_details"
  WHERE (("v_driver_statistics_with_details"."period_start" >= (CURRENT_DATE - '30 days'::interval)) AND ("v_driver_statistics_with_details"."period_end" <= CURRENT_DATE));


ALTER TABLE "public"."v_recent_driver_statistics" OWNER TO "postgres";


ALTER TABLE ONLY "public"."administrators"
    ADD CONSTRAINT "administrators_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."administrators"
    ADD CONSTRAINT "administrators_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."admins"
    ADD CONSTRAINT "admins_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admins"
    ADD CONSTRAINT "admins_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."billing_configurations"
    ADD CONSTRAINT "billing_configurations_laboratory_id_client_id_effective_fr_key" UNIQUE ("laboratory_id", "client_id", "effective_from");



ALTER TABLE ONLY "public"."billing_configurations"
    ADD CONSTRAINT "billing_configurations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_invoice_items"
    ADD CONSTRAINT "billing_invoice_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_invoice_number_key" UNIQUE ("invoice_number");



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_laboratory_id_billing_period_start_billing_key" UNIQUE ("laboratory_id", "billing_period_start", "billing_period_end");



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."depot"
    ADD CONSTRAINT "depot_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."depot_shipments"
    ADD CONSTRAINT "depot_shipments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."driver_route_shipments"
    ADD CONSTRAINT "driver_route_shipments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."driver_route_stops"
    ADD CONSTRAINT "driver_route_stops_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."driver_routes"
    ADD CONSTRAINT "driver_routes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."driver_statistics"
    ADD CONSTRAINT "driver_statistics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."drivers"
    ADD CONSTRAINT "drivers_email_unique" UNIQUE ("email");



ALTER TABLE ONLY "public"."drivers"
    ADD CONSTRAINT "drivers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."drivers"
    ADD CONSTRAINT "drivers_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."error_logs"
    ADD CONSTRAINT "error_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_tour_late_stops"
    ADD CONSTRAINT "lab_tour_late_stops_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_tour_shipments"
    ADD CONSTRAINT "lab_tour_shipments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_tour_stops"
    ADD CONSTRAINT "lab_tour_stops_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_tours"
    ADD CONSTRAINT "lab_tours_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."laboratories"
    ADD CONSTRAINT "laboratories_email_unique" UNIQUE ("email");



ALTER TABLE ONLY "public"."laboratories"
    ADD CONSTRAINT "laboratories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."laboratories"
    ADD CONSTRAINT "laboratories_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."laboratory_clients_audit"
    ADD CONSTRAINT "laboratory_clients_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."laboratory_clients"
    ADD CONSTRAINT "laboratory_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."laboratory_statistics"
    ADD CONSTRAINT "laboratory_statistics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lab_tour_late_stops"
    ADD CONSTRAINT "late_stop_unique_per_tour_client" UNIQUE ("lab_tour_id", "client_id");



ALTER TABLE ONLY "public"."location_photos"
    ADD CONSTRAINT "location_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."laboratory_statistics"
    ADD CONSTRAINT "unique_lab_period" UNIQUE ("laboratory_id", "period_start", "period_end");



CREATE INDEX "idx_billing_configurations_active" ON "public"."billing_configurations" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_billing_configurations_lab_client" ON "public"."billing_configurations" USING "btree" ("laboratory_id", "client_id");



CREATE INDEX "idx_billing_invoice_items_client" ON "public"."billing_invoice_items" USING "btree" ("client_id");



CREATE INDEX "idx_billing_invoice_items_invoice" ON "public"."billing_invoice_items" USING "btree" ("invoice_id");



CREATE INDEX "idx_billing_invoices_laboratory" ON "public"."billing_invoices" USING "btree" ("laboratory_id");



CREATE INDEX "idx_billing_invoices_period" ON "public"."billing_invoices" USING "btree" ("billing_period_start", "billing_period_end");



CREATE INDEX "idx_billing_invoices_status" ON "public"."billing_invoices" USING "btree" ("status");



CREATE INDEX "idx_driver_route_shipments_laboratory_id" ON "public"."driver_route_shipments" USING "btree" ("laboratory_id");



CREATE INDEX "idx_driver_route_shipments_late" ON "public"."driver_route_shipments" USING "btree" ("is_late_shipment");



CREATE INDEX "idx_driver_route_stops_is_late_stop" ON "public"."driver_route_stops" USING "btree" ("route_id", "is_late_stop") WHERE ("is_late_stop" = true);



CREATE INDEX "idx_driver_statistics_calculated_at" ON "public"."driver_statistics" USING "btree" ("calculated_at");



CREATE INDEX "idx_driver_statistics_driver_period" ON "public"."driver_statistics" USING "btree" ("driver_id", "period_start", "period_end");



CREATE INDEX "idx_drivers_email" ON "public"."drivers" USING "btree" ("email");



CREATE INDEX "idx_error_logs_created_at" ON "public"."error_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_error_logs_debug" ON "public"."error_logs" USING "btree" ("error_type", "device_type", "created_at" DESC);



CREATE INDEX "idx_error_logs_device_type" ON "public"."error_logs" USING "btree" ("device_type");



CREATE INDEX "idx_error_logs_error_type" ON "public"."error_logs" USING "btree" ("error_type");



CREATE INDEX "idx_error_logs_severity" ON "public"."error_logs" USING "btree" ("severity");



CREATE INDEX "idx_error_logs_unresolved" ON "public"."error_logs" USING "btree" ("is_resolved") WHERE ("is_resolved" = false);



CREATE INDEX "idx_error_logs_user_id" ON "public"."error_logs" USING "btree" ("user_id");



CREATE INDEX "idx_lab_tour_late_stops_client_id" ON "public"."lab_tour_late_stops" USING "btree" ("client_id");



CREATE INDEX "idx_lab_tour_late_stops_requested_at" ON "public"."lab_tour_late_stops" USING "btree" ("requested_at");



CREATE INDEX "idx_lab_tour_late_stops_status" ON "public"."lab_tour_late_stops" USING "btree" ("status");



CREATE INDEX "idx_lab_tour_late_stops_tour_id" ON "public"."lab_tour_late_stops" USING "btree" ("lab_tour_id");



CREATE INDEX "idx_lab_tour_shipments_client_id" ON "public"."lab_tour_shipments" USING "btree" ("client_id");



CREATE INDEX "idx_laboratories_depot_is_lab" ON "public"."laboratories" USING "btree" ("depot_is_lab") WHERE ("depot_is_lab" = true);



CREATE INDEX "idx_laboratories_email" ON "public"."laboratories" USING "btree" ("email");



CREATE INDEX "idx_laboratories_shared_pickup" ON "public"."laboratories" USING "btree" ("shared_pickup") WHERE ("shared_pickup" = true);



CREATE INDEX "idx_laboratory_clients_audit_changed_at" ON "public"."laboratory_clients_audit" USING "btree" ("changed_at");



CREATE INDEX "idx_laboratory_clients_audit_client_id" ON "public"."laboratory_clients_audit" USING "btree" ("client_id");



CREATE INDEX "idx_laboratory_clients_driver_id" ON "public"."laboratory_clients" USING "btree" ("driver_id");



CREATE INDEX "idx_laboratory_statistics_lab_period" ON "public"."laboratory_statistics" USING "btree" ("laboratory_id", "period_start", "period_end");



CREATE INDEX "idx_laboratory_statistics_period" ON "public"."laboratory_statistics" USING "btree" ("period_start", "period_end");



CREATE OR REPLACE TRIGGER "laboratory_client_name_change_logger" BEFORE UPDATE ON "public"."laboratory_clients" FOR EACH ROW EXECUTE FUNCTION "public"."log_laboratory_client_name_changes"();



CREATE OR REPLACE TRIGGER "tr_lab_tour_late_stops_reviewed_at" BEFORE UPDATE ON "public"."lab_tour_late_stops" FOR EACH ROW EXECUTE FUNCTION "public"."set_lab_tour_late_stops_reviewed_at"();



CREATE OR REPLACE TRIGGER "tr_lab_tour_late_stops_updated_at" BEFORE UPDATE ON "public"."lab_tour_late_stops" FOR EACH ROW EXECUTE FUNCTION "public"."update_lab_tour_late_stops_updated_at"();



CREATE OR REPLACE TRIGGER "trigger_billing_configurations_updated_at" BEFORE UPDATE ON "public"."billing_configurations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trigger_prevent_duplicate_driver_routes" BEFORE INSERT ON "public"."driver_routes" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_duplicate_driver_routes"();



CREATE OR REPLACE TRIGGER "trigger_set_invoice_number" BEFORE INSERT ON "public"."billing_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."set_invoice_number"();



CREATE OR REPLACE TRIGGER "trigger_update_driver_statistics_timestamp" BEFORE UPDATE ON "public"."driver_statistics" FOR EACH ROW EXECUTE FUNCTION "public"."update_driver_statistics_timestamp"();



CREATE OR REPLACE TRIGGER "trigger_update_sent_at" BEFORE UPDATE ON "public"."billing_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."update_sent_at"();



CREATE OR REPLACE TRIGGER "update_depot_shipments_timestamp" BEFORE UPDATE ON "public"."depot_shipments" FOR EACH ROW EXECUTE FUNCTION "public"."update_depot_timestamp"();



CREATE OR REPLACE TRIGGER "update_depot_timestamp" BEFORE UPDATE ON "public"."depot" FOR EACH ROW EXECUTE FUNCTION "public"."update_depot_timestamp"();



ALTER TABLE ONLY "public"."administrators"
    ADD CONSTRAINT "administrators_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."admins"
    ADD CONSTRAINT "admins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."billing_configurations"
    ADD CONSTRAINT "billing_configurations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."laboratory_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_configurations"
    ADD CONSTRAINT "billing_configurations_laboratory_id_fkey" FOREIGN KEY ("laboratory_id") REFERENCES "public"."laboratories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_invoice_items"
    ADD CONSTRAINT "billing_invoice_items_billing_configuration_id_fkey" FOREIGN KEY ("billing_configuration_id") REFERENCES "public"."billing_configurations"("id");



ALTER TABLE ONLY "public"."billing_invoice_items"
    ADD CONSTRAINT "billing_invoice_items_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."billing_invoice_items"
    ADD CONSTRAINT "billing_invoice_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."billing_invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_invoices"
    ADD CONSTRAINT "billing_invoices_laboratory_id_fkey" FOREIGN KEY ("laboratory_id") REFERENCES "public"."laboratories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."depot"
    ADD CONSTRAINT "depot_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."driver_route_shipments"
    ADD CONSTRAINT "driver_route_shipments_delivery_stop_id_fkey" FOREIGN KEY ("delivery_stop_id") REFERENCES "public"."driver_route_stops"("id");



ALTER TABLE ONLY "public"."driver_route_shipments"
    ADD CONSTRAINT "driver_route_shipments_laboratory_client_id_fkey" FOREIGN KEY ("laboratory_client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."driver_route_shipments"
    ADD CONSTRAINT "driver_route_shipments_laboratory_id_fkey" FOREIGN KEY ("laboratory_id") REFERENCES "public"."laboratories"("id");



ALTER TABLE ONLY "public"."driver_route_shipments"
    ADD CONSTRAINT "driver_route_shipments_pickup_stop_id_fkey" FOREIGN KEY ("pickup_stop_id") REFERENCES "public"."driver_route_stops"("id");



ALTER TABLE ONLY "public"."driver_route_shipments"
    ADD CONSTRAINT "driver_route_shipments_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."driver_routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."driver_route_stops"
    ADD CONSTRAINT "driver_route_stops_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."driver_route_stops"
    ADD CONSTRAINT "driver_route_stops_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."driver_routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."driver_routes"
    ADD CONSTRAINT "driver_routes_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."drivers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."driver_statistics"
    ADD CONSTRAINT "driver_statistics_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."drivers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."error_logs"
    ADD CONSTRAINT "error_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."drivers"
    ADD CONSTRAINT "fk_drivers_auth_users" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."laboratories"
    ADD CONSTRAINT "fk_laboratories_auth_users" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_tour_late_stops"
    ADD CONSTRAINT "lab_tour_late_stops_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."laboratory_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_tour_late_stops"
    ADD CONSTRAINT "lab_tour_late_stops_lab_tour_id_fkey" FOREIGN KEY ("lab_tour_id") REFERENCES "public"."lab_tours"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_tour_late_stops"
    ADD CONSTRAINT "lab_tour_late_stops_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."lab_tour_shipments"
    ADD CONSTRAINT "lab_tour_shipments_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."lab_tour_shipments"
    ADD CONSTRAINT "lab_tour_shipments_from_location_id_fkey" FOREIGN KEY ("from_location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."lab_tour_shipments"
    ADD CONSTRAINT "lab_tour_shipments_lab_tour_id_fkey" FOREIGN KEY ("lab_tour_id") REFERENCES "public"."lab_tours"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_tour_shipments"
    ADD CONSTRAINT "lab_tour_shipments_to_location_id_fkey" FOREIGN KEY ("to_location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."lab_tour_stops"
    ADD CONSTRAINT "lab_tour_stops_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."lab_tour_stops"
    ADD CONSTRAINT "lab_tour_stops_tour_id_fkey" FOREIGN KEY ("tour_id") REFERENCES "public"."lab_tours"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lab_tours"
    ADD CONSTRAINT "lab_tours_laboratory_id_fkey" FOREIGN KEY ("laboratory_id") REFERENCES "public"."laboratories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."laboratories"
    ADD CONSTRAINT "laboratories_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."laboratory_clients_audit"
    ADD CONSTRAINT "laboratory_clients_audit_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."laboratory_clients"
    ADD CONSTRAINT "laboratory_clients_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."drivers"("id");



ALTER TABLE ONLY "public"."laboratory_clients"
    ADD CONSTRAINT "laboratory_clients_laboratory_id_fkey" FOREIGN KEY ("laboratory_id") REFERENCES "public"."laboratories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."laboratory_clients"
    ADD CONSTRAINT "laboratory_clients_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."laboratory_statistics"
    ADD CONSTRAINT "laboratory_statistics_laboratory_id_fkey" FOREIGN KEY ("laboratory_id") REFERENCES "public"."laboratories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."laboratory_statistics"
    ADD CONSTRAINT "laboratory_statistics_least_delivered_client_id_fkey" FOREIGN KEY ("least_delivered_client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."laboratory_statistics"
    ADD CONSTRAINT "laboratory_statistics_most_delivered_client_id_fkey" FOREIGN KEY ("most_delivered_client_id") REFERENCES "public"."laboratory_clients"("id");



ALTER TABLE ONLY "public"."location_photos"
    ADD CONSTRAINT "location_photos_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



CREATE POLICY "Users can insert own errors" ON "public"."error_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own errors" ON "public"."error_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "admin_all" ON "public"."driver_route_shipments" TO "authenticated" USING ((("auth"."jwt"() ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "admin_all_lab_tour_late_stops" ON "public"."lab_tour_late_stops" TO "authenticated" USING ((("auth"."jwt"() ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "admin_full_access_billing_configurations" ON "public"."billing_configurations" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."admins"
  WHERE ("admins"."user_id" = "auth"."uid"()))));



CREATE POLICY "admin_full_access_billing_invoice_items" ON "public"."billing_invoice_items" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."admins"
  WHERE ("admins"."user_id" = "auth"."uid"()))));



CREATE POLICY "admin_full_access_billing_invoices" ON "public"."billing_invoices" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."admins"
  WHERE ("admins"."user_id" = "auth"."uid"()))));



ALTER TABLE "public"."billing_configurations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_invoice_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."error_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "laboratory_own_late_stops" ON "public"."lab_tour_late_stops" TO "authenticated" USING (((("auth"."jwt"() ->> 'role'::"text") = 'laboratory'::"text") AND (EXISTS ( SELECT 1
   FROM ("public"."lab_tours" "lt"
     JOIN "public"."laboratories" "lab" ON (("lt"."laboratory_id" = "lab"."id")))
  WHERE (("lt"."id" = "lab_tour_late_stops"."lab_tour_id") AND (("lab"."user_id")::"text" = ("auth"."uid"())::"text"))))));



CREATE POLICY "laboratory_select_own" ON "public"."driver_route_shipments" FOR SELECT TO "authenticated" USING (((("auth"."jwt"() ->> 'role'::"text") = 'laboratory'::"text") AND (("laboratory_id")::"text" = ("auth"."jwt"() ->> 'laboratory_id'::"text"))));



ALTER TABLE "public"."laboratory_statistics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "laboratory_statistics_admin_only" ON "public"."laboratory_statistics" USING ((EXISTS ( SELECT 1
   FROM "public"."admins"
  WHERE ("admins"."user_id" = "auth"."uid"()))));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."driver_route_shipments";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."driver_route_stops";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."driver_routes";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."lab_tour_late_stops";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."lab_tour_stops";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."lab_tours";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";














































































































































































GRANT ALL ON FUNCTION "public"."add_unexpected_shipment"("p_route_id" "uuid", "p_pickup_stop_id" "uuid", "p_laboratory_id" "uuid", "p_laboratory_client_id" "uuid", "p_shipment_ref" "text", "p_proof_photo_url" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."add_unexpected_shipment"("p_route_id" "uuid", "p_pickup_stop_id" "uuid", "p_laboratory_id" "uuid", "p_laboratory_client_id" "uuid", "p_shipment_ref" "text", "p_proof_photo_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_unexpected_shipment"("p_route_id" "uuid", "p_pickup_stop_id" "uuid", "p_laboratory_id" "uuid", "p_laboratory_client_id" "uuid", "p_shipment_ref" "text", "p_proof_photo_url" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_route_state"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_route_state"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_route_state"("p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_driver_statistics"("p_driver_id" "uuid", "p_period_start" "date", "p_period_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_driver_statistics"("p_driver_id" "uuid", "p_period_start" "date", "p_period_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_driver_statistics"("p_driver_id" "uuid", "p_period_start" "date", "p_period_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_laboratory_statistics"("p_laboratory_id" "uuid", "p_period_start" "date", "p_period_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_laboratory_statistics"("p_laboratory_id" "uuid", "p_period_start" "date", "p_period_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_laboratory_statistics"("p_laboratory_id" "uuid", "p_period_start" "date", "p_period_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_orphan_shipments"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_orphan_shipments"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_orphan_shipments"("p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_pending_routes"("target_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_pending_routes"("target_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_pending_routes"("target_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_driver_shipments"("p_route_id" "uuid", "p_driver_id" "uuid", "shipments_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_driver_shipments"("p_route_id" "uuid", "p_driver_id" "uuid", "shipments_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_driver_shipments"("p_route_id" "uuid", "p_driver_id" "uuid", "shipments_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_necessary_stops"("p_route_id" "uuid", "shipments_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_necessary_stops"("p_route_id" "uuid", "shipments_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_necessary_stops"("p_route_id" "uuid", "shipments_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_client_complete"("client_id_param" "uuid", "location_id_param" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_client_complete"("client_id_param" "uuid", "location_id_param" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_client_complete"("client_id_param" "uuid", "location_id_param" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_lab_tour_shipments"("lab_tour_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_lab_tour_shipments"("lab_tour_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_lab_tour_shipments"("lab_tour_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_shipments_for_lab_tour"("lab_tour_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_shipments_for_lab_tour"("lab_tour_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_shipments_for_lab_tour"("lab_tour_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."determine_driver_shipments"("driver_id" "uuid", "target_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."determine_driver_shipments"("driver_id" "uuid", "target_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."determine_driver_shipments"("driver_id" "uuid", "target_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."driver_statistics_health_report"() TO "anon";
GRANT ALL ON FUNCTION "public"."driver_statistics_health_report"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."driver_statistics_health_report"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_driver_routes"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_driver_routes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_driver_routes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_driver_routes"("target_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_driver_routes"("target_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_driver_routes"("target_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_driver_routes_v2"("target_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_driver_routes_v2"("target_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_driver_routes_v2"("target_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_invoice_number"("lab_id" "uuid", "period_start" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_invoice_number"("lab_id" "uuid", "period_start" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_invoice_number"("lab_id" "uuid", "period_start" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_lab_tour_shipments"("lab_tour_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_lab_tour_shipments"("lab_tour_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_lab_tour_shipments"("lab_tour_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_monthly_invoice"("lab_id" "uuid", "billing_month" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_monthly_invoice"("lab_id" "uuid", "billing_month" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_monthly_invoice"("lab_id" "uuid", "billing_month" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_shipments_for_lab_tour"("lab_tour_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_shipments_for_lab_tour"("lab_tour_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_shipments_for_lab_tour"("lab_tour_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_all_clients_by_drivers"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_all_clients_by_drivers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_all_clients_by_drivers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_driver_comparison_data"("p_period_start" "date", "p_period_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_driver_comparison_data"("p_period_start" "date", "p_period_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_driver_comparison_data"("p_period_start" "date", "p_period_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_global_driver_statistics"("period_start_param" "date", "period_end_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_global_driver_statistics"("period_start_param" "date", "period_end_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_global_driver_statistics"("period_start_param" "date", "period_end_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_stop_orders_after_position"("route_id_param" "uuid", "position_threshold" integer, "increment_value" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_stop_orders_after_position"("route_id_param" "uuid", "position_threshold" integer, "increment_value" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_stop_orders_after_position"("route_id_param" "uuid", "position_threshold" integer, "increment_value" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."log_laboratory_client_name_changes"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_laboratory_client_name_changes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_laboratory_client_name_changes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."maintain_driver_statistics"() TO "anon";
GRANT ALL ON FUNCTION "public"."maintain_driver_statistics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."maintain_driver_statistics"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_invoice_as_sent"("invoice_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_invoice_as_sent"("invoice_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_invoice_as_sent"("invoice_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."optimize_route"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."optimize_route"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."optimize_route"("p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_duplicate_driver_routes"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_duplicate_driver_routes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_duplicate_driver_routes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_all_driver_statistics"("p_period_start" "date", "p_period_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_all_driver_statistics"("p_period_start" "date", "p_period_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_all_driver_statistics"("p_period_start" "date", "p_period_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."replace_lab_tour_shipments"("old_lab_tour_id" "uuid", "new_lab_tour_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."replace_lab_tour_shipments"("old_lab_tour_id" "uuid", "new_lab_tour_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."replace_lab_tour_shipments"("old_lab_tour_id" "uuid", "new_lab_tour_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_invoice_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_invoice_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_invoice_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_lab_tour_late_stops_reviewed_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_lab_tour_late_stops_reviewed_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_lab_tour_late_stops_reviewed_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_depot_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_depot_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_depot_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_driver_statistics_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_driver_statistics_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_driver_statistics_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_lab_tour_late_stops_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_lab_tour_late_stops_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_lab_tour_late_stops_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_sent_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_sent_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_sent_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_shipments_stop_reference"("p_route_id" "uuid", "p_old_stop_id" "text", "p_new_stop_id" "text", "p_field" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_shipments_stop_reference"("p_route_id" "uuid", "p_old_stop_id" "text", "p_new_stop_id" "text", "p_field" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_shipments_stop_reference"("p_route_id" "uuid", "p_old_stop_id" "text", "p_new_stop_id" "text", "p_field" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";


















GRANT ALL ON TABLE "public"."administrators" TO "anon";
GRANT ALL ON TABLE "public"."administrators" TO "authenticated";
GRANT ALL ON TABLE "public"."administrators" TO "service_role";



GRANT ALL ON TABLE "public"."admins" TO "anon";
GRANT ALL ON TABLE "public"."admins" TO "authenticated";
GRANT ALL ON TABLE "public"."admins" TO "service_role";



GRANT ALL ON TABLE "public"."billing_configurations" TO "anon";
GRANT ALL ON TABLE "public"."billing_configurations" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_configurations" TO "service_role";



GRANT ALL ON TABLE "public"."billing_invoice_items" TO "anon";
GRANT ALL ON TABLE "public"."billing_invoice_items" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_invoice_items" TO "service_role";



GRANT ALL ON TABLE "public"."billing_invoices" TO "anon";
GRANT ALL ON TABLE "public"."billing_invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_invoices" TO "service_role";



GRANT ALL ON TABLE "public"."driver_route_shipments" TO "anon";
GRANT ALL ON TABLE "public"."driver_route_shipments" TO "authenticated";
GRANT ALL ON TABLE "public"."driver_route_shipments" TO "service_role";



GRANT ALL ON TABLE "public"."driver_route_stops" TO "anon";
GRANT ALL ON TABLE "public"."driver_route_stops" TO "authenticated";
GRANT ALL ON TABLE "public"."driver_route_stops" TO "service_role";



GRANT ALL ON TABLE "public"."driver_routes" TO "anon";
GRANT ALL ON TABLE "public"."driver_routes" TO "authenticated";
GRANT ALL ON TABLE "public"."driver_routes" TO "service_role";



GRANT ALL ON TABLE "public"."laboratories" TO "anon";
GRANT ALL ON TABLE "public"."laboratories" TO "authenticated";
GRANT ALL ON TABLE "public"."laboratories" TO "service_role";



GRANT ALL ON TABLE "public"."laboratory_clients" TO "anon";
GRANT ALL ON TABLE "public"."laboratory_clients" TO "authenticated";
GRANT ALL ON TABLE "public"."laboratory_clients" TO "service_role";



GRANT ALL ON TABLE "public"."billing_reports" TO "anon";
GRANT ALL ON TABLE "public"."billing_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_reports" TO "service_role";



GRANT ALL ON TABLE "public"."error_logs" TO "anon";
GRANT ALL ON TABLE "public"."error_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."error_logs" TO "service_role";



GRANT ALL ON TABLE "public"."critical_errors_recent" TO "anon";
GRANT ALL ON TABLE "public"."critical_errors_recent" TO "authenticated";
GRANT ALL ON TABLE "public"."critical_errors_recent" TO "service_role";



GRANT ALL ON TABLE "public"."depot" TO "anon";
GRANT ALL ON TABLE "public"."depot" TO "authenticated";
GRANT ALL ON TABLE "public"."depot" TO "service_role";



GRANT ALL ON TABLE "public"."depot_shipments" TO "anon";
GRANT ALL ON TABLE "public"."depot_shipments" TO "authenticated";
GRANT ALL ON TABLE "public"."depot_shipments" TO "service_role";



GRANT ALL ON TABLE "public"."driver_statistics" TO "anon";
GRANT ALL ON TABLE "public"."driver_statistics" TO "authenticated";
GRANT ALL ON TABLE "public"."driver_statistics" TO "service_role";



GRANT ALL ON TABLE "public"."drivers" TO "anon";
GRANT ALL ON TABLE "public"."drivers" TO "authenticated";
GRANT ALL ON TABLE "public"."drivers" TO "service_role";



GRANT ALL ON TABLE "public"."error_stats" TO "anon";
GRANT ALL ON TABLE "public"."error_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."error_stats" TO "service_role";



GRANT ALL ON TABLE "public"."lab_tour_late_stops" TO "anon";
GRANT ALL ON TABLE "public"."lab_tour_late_stops" TO "authenticated";
GRANT ALL ON TABLE "public"."lab_tour_late_stops" TO "service_role";



GRANT ALL ON TABLE "public"."lab_tour_shipments" TO "anon";
GRANT ALL ON TABLE "public"."lab_tour_shipments" TO "authenticated";
GRANT ALL ON TABLE "public"."lab_tour_shipments" TO "service_role";



GRANT ALL ON TABLE "public"."lab_tour_stops" TO "anon";
GRANT ALL ON TABLE "public"."lab_tour_stops" TO "authenticated";
GRANT ALL ON TABLE "public"."lab_tour_stops" TO "service_role";



GRANT ALL ON TABLE "public"."lab_tours" TO "anon";
GRANT ALL ON TABLE "public"."lab_tours" TO "authenticated";
GRANT ALL ON TABLE "public"."lab_tours" TO "service_role";



GRANT ALL ON TABLE "public"."laboratory_clients_audit" TO "anon";
GRANT ALL ON TABLE "public"."laboratory_clients_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."laboratory_clients_audit" TO "service_role";



GRANT ALL ON TABLE "public"."laboratory_statistics" TO "anon";
GRANT ALL ON TABLE "public"."laboratory_statistics" TO "authenticated";
GRANT ALL ON TABLE "public"."laboratory_statistics" TO "service_role";



GRANT ALL ON TABLE "public"."location_photos" TO "anon";
GRANT ALL ON TABLE "public"."location_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."location_photos" TO "service_role";



GRANT ALL ON TABLE "public"."locations" TO "anon";
GRANT ALL ON TABLE "public"."locations" TO "authenticated";
GRANT ALL ON TABLE "public"."locations" TO "service_role";



GRANT ALL ON TABLE "public"."v_driver_performance_summary" TO "anon";
GRANT ALL ON TABLE "public"."v_driver_performance_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."v_driver_performance_summary" TO "service_role";



GRANT ALL ON TABLE "public"."v_driver_statistics_with_details" TO "anon";
GRANT ALL ON TABLE "public"."v_driver_statistics_with_details" TO "authenticated";
GRANT ALL ON TABLE "public"."v_driver_statistics_with_details" TO "service_role";



GRANT ALL ON TABLE "public"."v_recent_driver_statistics" TO "anon";
GRANT ALL ON TABLE "public"."v_recent_driver_statistics" TO "authenticated";
GRANT ALL ON TABLE "public"."v_recent_driver_statistics" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























