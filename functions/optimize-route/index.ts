import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, X-Client-Info, apikey, Content-Type, Range, x-requested-with, Accept, Origin',
  'Access-Control-Expose-Headers': 'Content-Range, Range, Accept-Ranges',
  'Access-Control-Max-Age': '86400',
  'Access-Control-Allow-Origin': '*'
};

interface DriverRoute {
  id: string;
  driver_id: string;
  status: string;
}

interface Driver {
  id: string;
  latitude: number;
  longitude: number;
  start_time: string;
}

interface Location {
  id: string;
  latitude: number;
  longitude: number;
}

interface DriverRouteShipment {
  id: string;
  route_id: string;
  laboratory_id: string;
  pickup_stop_id: string;
  delivery_stop_id: string;
  shipment_ref: string;
}

interface DriverRouteStop {
  id: string;
  route_id: string;
  location_id: string;
}

interface OptimizationPayload {
  driver_home: {
    lat: number;
    lng: number;
    start_time: string;
  };
  shipments: Array<{
    shipment_label: string;
    pickup: {
      lat: number;
      lng: number;
      service_time_seconds: number;
      visit_id: string;
    };
    delivery: {
      lat: number;
      lng: number;
      service_time_seconds: number;
      visit_id: string;
    };
  }>;
}

interface OptimizationResponse {
  route: Array<{
    visit_id: string;
    arrival_seconds: number;
    order: number;
    arrival_time: string;
    duration_from_previous: number | null;
  }>;
  estimated_duration: string;
  total_distance_meters: number;
  polyline: string;
}

// Default service time in seconds for pickup and delivery
const DEFAULT_SERVICE_TIME = 120;

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Check if the request is a POST
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Parse request body
    const { routeId } = await req.json();
    console.log('[optimize-route] Received routeId:', routeId);

    if (!routeId) {
      return new Response(JSON.stringify({ error: 'Driver route ID is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const supabase = createClient(supabaseUrl, supabaseAnonKey);

    // Step 1: Get the driver route
    const { data: routeData, error: routeError } = await supabase
      .from('driver_routes')
      .select('*')
      .eq('id', routeId)
      .single();

    if (routeError || !routeData) {
      return new Response(JSON.stringify({ error: 'Driver route not found', details: routeError }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const driverRoute: DriverRoute = routeData;
    console.log('[optimize-route] Working with driver route:', driverRoute.id);

    // Return success response (simplified for migration)
    return new Response(JSON.stringify({
      success: true,
      message: 'Route optimization function deployed successfully',
      route_id: routeId
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('[optimize-route] Unexpected error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error', details: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
