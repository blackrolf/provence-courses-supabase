export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "12.2.3 (519615d)"
  }
  public: {
    Tables: {
      administrators: {
        Row: {
          created_at: string | null
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          user_id?: string
        }
        Relationships: []
      }
      admins: {
        Row: {
          created_at: string | null
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          user_id?: string
        }
        Relationships: []
      }
      billing_configurations: {
        Row: {
          billing_type: string
          client_id: string
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          is_active: boolean
          laboratory_id: string
          monthly_flat_rate: number | null
          price_per_visit: number | null
          updated_at: string
        }
        Insert: {
          billing_type: string
          client_id: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_active?: boolean
          laboratory_id: string
          monthly_flat_rate?: number | null
          price_per_visit?: number | null
          updated_at?: string
        }
        Update: {
          billing_type?: string
          client_id?: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_active?: boolean
          laboratory_id?: string
          monthly_flat_rate?: number | null
          price_per_visit?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_configurations_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "billing_configurations_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_configurations_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_invoice_items: {
        Row: {
          billing_configuration_id: string
          billing_type: string
          both_count: number
          client_id: string
          created_at: string
          delivery_count: number
          flat_rate: number | null
          id: string
          invoice_id: string
          line_total: number
          pickup_count: number
          total_visits: number | null
          unit_price: number | null
        }
        Insert: {
          billing_configuration_id: string
          billing_type: string
          both_count?: number
          client_id: string
          created_at?: string
          delivery_count?: number
          flat_rate?: number | null
          id?: string
          invoice_id: string
          line_total: number
          pickup_count?: number
          total_visits?: number | null
          unit_price?: number | null
        }
        Update: {
          billing_configuration_id?: string
          billing_type?: string
          both_count?: number
          client_id?: string
          created_at?: string
          delivery_count?: number
          flat_rate?: number | null
          id?: string
          invoice_id?: string
          line_total?: number
          pickup_count?: number
          total_visits?: number | null
          unit_price?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_invoice_items_billing_configuration_id_fkey"
            columns: ["billing_configuration_id"]
            isOneToOne: false
            referencedRelation: "billing_configurations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_invoice_items_billing_configuration_id_fkey"
            columns: ["billing_configuration_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["billing_configuration_id"]
          },
          {
            foreignKeyName: "billing_invoice_items_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "billing_invoice_items_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_invoice_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "billing_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_invoices: {
        Row: {
          billing_period_end: string
          billing_period_start: string
          created_at: string
          generated_at: string
          id: string
          invoice_number: string
          laboratory_id: string
          notes: string | null
          sent_at: string | null
          status: string
          total_amount_euros: number
          updated_at: string
        }
        Insert: {
          billing_period_end: string
          billing_period_start: string
          created_at?: string
          generated_at?: string
          id?: string
          invoice_number: string
          laboratory_id: string
          notes?: string | null
          sent_at?: string | null
          status?: string
          total_amount_euros?: number
          updated_at?: string
        }
        Update: {
          billing_period_end?: string
          billing_period_start?: string
          created_at?: string
          generated_at?: string
          id?: string
          invoice_number?: string
          laboratory_id?: string
          notes?: string | null
          sent_at?: string | null
          status?: string
          total_amount_euros?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_invoices_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
        ]
      }
      depot: {
        Row: {
          created_at: string | null
          id: string
          is_active: boolean | null
          location_id: string | null
          name: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          location_id?: string | null
          name: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          location_id?: string | null
          name?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "depot_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      depot_shipments: {
        Row: {
          arrival_time: string | null
          created_at: string | null
          departure_time: string | null
          handler_name: string | null
          id: string
          notes: string | null
          shipment_id: string
          status: string
          updated_at: string | null
        }
        Insert: {
          arrival_time?: string | null
          created_at?: string | null
          departure_time?: string | null
          handler_name?: string | null
          id?: string
          notes?: string | null
          shipment_id: string
          status?: string
          updated_at?: string | null
        }
        Update: {
          arrival_time?: string | null
          created_at?: string | null
          departure_time?: string | null
          handler_name?: string | null
          id?: string
          notes?: string | null
          shipment_id?: string
          status?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      driver_route_shipments: {
        Row: {
          created_at: string
          delivery_status: string
          delivery_stop_id: string
          delivery_time: string | null
          id: string
          is_late_shipment: boolean | null
          is_shared_pickup: boolean | null
          issue_description: string | null
          issue_type: string | null
          laboratory_client_id: string | null
          laboratory_id: string
          pickup_status: string
          pickup_stop_id: string
          pickup_time: string | null
          proof_photo_url: string | null
          route_id: string | null
          shipment_ref: string | null
          shipment_type: string | null
          unexpected: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          delivery_status?: string
          delivery_stop_id: string
          delivery_time?: string | null
          id?: string
          is_late_shipment?: boolean | null
          is_shared_pickup?: boolean | null
          issue_description?: string | null
          issue_type?: string | null
          laboratory_client_id?: string | null
          laboratory_id: string
          pickup_status?: string
          pickup_stop_id: string
          pickup_time?: string | null
          proof_photo_url?: string | null
          route_id?: string | null
          shipment_ref?: string | null
          shipment_type?: string | null
          unexpected?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          delivery_status?: string
          delivery_stop_id?: string
          delivery_time?: string | null
          id?: string
          is_late_shipment?: boolean | null
          is_shared_pickup?: boolean | null
          issue_description?: string | null
          issue_type?: string | null
          laboratory_client_id?: string | null
          laboratory_id?: string
          pickup_status?: string
          pickup_stop_id?: string
          pickup_time?: string | null
          proof_photo_url?: string | null
          route_id?: string | null
          shipment_ref?: string | null
          shipment_type?: string | null
          unexpected?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_route_shipments_delivery_stop_id_fkey"
            columns: ["delivery_stop_id"]
            isOneToOne: false
            referencedRelation: "driver_route_stops"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_route_shipments_laboratory_client_id_fkey"
            columns: ["laboratory_client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "driver_route_shipments_laboratory_client_id_fkey"
            columns: ["laboratory_client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_route_shipments_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_route_shipments_pickup_stop_id_fkey"
            columns: ["pickup_stop_id"]
            isOneToOne: false
            referencedRelation: "driver_route_stops"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_route_shipments_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "driver_routes"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_route_stops: {
        Row: {
          arrival_time: string | null
          client_actions: string | null
          completed: boolean | null
          created_at: string | null
          distance_from_previous: number | null
          duration_from_previous: number | null
          estimated_arrival_time: string | null
          estimated_departure_time: string | null
          id: string
          is_late_stop: boolean | null
          is_shared_pickup_stop: boolean | null
          location_id: string
          route_id: string
          stop_order: number
          stop_type: string | null
        }
        Insert: {
          arrival_time?: string | null
          client_actions?: string | null
          completed?: boolean | null
          created_at?: string | null
          distance_from_previous?: number | null
          duration_from_previous?: number | null
          estimated_arrival_time?: string | null
          estimated_departure_time?: string | null
          id?: string
          is_late_stop?: boolean | null
          is_shared_pickup_stop?: boolean | null
          location_id: string
          route_id: string
          stop_order: number
          stop_type?: string | null
        }
        Update: {
          arrival_time?: string | null
          client_actions?: string | null
          completed?: boolean | null
          created_at?: string | null
          distance_from_previous?: number | null
          duration_from_previous?: number | null
          estimated_arrival_time?: string | null
          estimated_departure_time?: string | null
          id?: string
          is_late_stop?: boolean | null
          is_shared_pickup_stop?: boolean | null
          location_id?: string
          route_id?: string
          stop_order?: number
          stop_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_route_stops_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_route_stops_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "driver_routes"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_routes: {
        Row: {
          created_at: string | null
          date: string
          driver_id: string
          estimated_duration: number | null
          id: string
          polyline: string | null
          status: string
          total_distance_km: number | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          date: string
          driver_id: string
          estimated_duration?: number | null
          id?: string
          polyline?: string | null
          status: string
          total_distance_km?: number | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          date?: string
          driver_id?: string
          estimated_duration?: number | null
          id?: string
          polyline?: string | null
          status?: string
          total_distance_km?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_routes_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_routes_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "v_driver_performance_summary"
            referencedColumns: ["driver_id"]
          },
        ]
      }
      driver_statistics: {
        Row: {
          average_distance_per_day: number | null
          average_duration_hours: number | null
          average_end_time: string | null
          average_start_time: string | null
          average_stops_per_day: number | null
          average_stops_per_route: number | null
          calculated_at: string | null
          client_coverage: Json | null
          completed_deliveries: number | null
          completed_pickups: number | null
          completed_routes: number | null
          created_at: string | null
          delivery_success_rate: number | null
          driver_id: string
          earliest_start_time: string | null
          hourly_distribution: Json | null
          id: string
          latest_end_time: string | null
          period_end: string
          period_start: string
          pickup_success_rate: number | null
          route_completion_rate: number | null
          total_deliveries: number | null
          total_distance_km: number | null
          total_pickups: number | null
          total_routes: number | null
          total_stops: number | null
          total_working_days: number | null
          updated_at: string | null
          weekly_activity: Json | null
        }
        Insert: {
          average_distance_per_day?: number | null
          average_duration_hours?: number | null
          average_end_time?: string | null
          average_start_time?: string | null
          average_stops_per_day?: number | null
          average_stops_per_route?: number | null
          calculated_at?: string | null
          client_coverage?: Json | null
          completed_deliveries?: number | null
          completed_pickups?: number | null
          completed_routes?: number | null
          created_at?: string | null
          delivery_success_rate?: number | null
          driver_id: string
          earliest_start_time?: string | null
          hourly_distribution?: Json | null
          id?: string
          latest_end_time?: string | null
          period_end: string
          period_start: string
          pickup_success_rate?: number | null
          route_completion_rate?: number | null
          total_deliveries?: number | null
          total_distance_km?: number | null
          total_pickups?: number | null
          total_routes?: number | null
          total_stops?: number | null
          total_working_days?: number | null
          updated_at?: string | null
          weekly_activity?: Json | null
        }
        Update: {
          average_distance_per_day?: number | null
          average_duration_hours?: number | null
          average_end_time?: string | null
          average_start_time?: string | null
          average_stops_per_day?: number | null
          average_stops_per_route?: number | null
          calculated_at?: string | null
          client_coverage?: Json | null
          completed_deliveries?: number | null
          completed_pickups?: number | null
          completed_routes?: number | null
          created_at?: string | null
          delivery_success_rate?: number | null
          driver_id?: string
          earliest_start_time?: string | null
          hourly_distribution?: Json | null
          id?: string
          latest_end_time?: string | null
          period_end?: string
          period_start?: string
          pickup_success_rate?: number | null
          route_completion_rate?: number | null
          total_deliveries?: number | null
          total_distance_km?: number | null
          total_pickups?: number | null
          total_routes?: number | null
          total_stops?: number | null
          total_working_days?: number | null
          updated_at?: string | null
          weekly_activity?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_statistics_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_statistics_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "v_driver_performance_summary"
            referencedColumns: ["driver_id"]
          },
        ]
      }
      drivers: {
        Row: {
          created_at: string | null
          email: string | null
          full_name: string
          id: string
          latitude: number | null
          longitude: number | null
          place_id: string | null
          sector: string | null
          start_address: string
          start_time: string | null
          user_id: string
          vehicle_type: string | null
        }
        Insert: {
          created_at?: string | null
          email?: string | null
          full_name: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          place_id?: string | null
          sector?: string | null
          start_address: string
          start_time?: string | null
          user_id: string
          vehicle_type?: string | null
        }
        Update: {
          created_at?: string | null
          email?: string | null
          full_name?: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          place_id?: string | null
          sector?: string | null
          start_address?: string
          start_time?: string | null
          user_id?: string
          vehicle_type?: string | null
        }
        Relationships: []
      }
      error_logs: {
        Row: {
          app_version: string | null
          browser_name: string | null
          browser_version: string | null
          created_at: string
          current_route_id: string | null
          current_stop_index: number | null
          device_model: string | null
          device_type: string | null
          driver_id: string | null
          error_message: string
          error_source: string | null
          error_stack: string | null
          error_type: string
          first_seen: string | null
          id: string
          is_resolved: boolean | null
          last_seen: string | null
          memory_usage: Json | null
          network_status: Json | null
          occurrence_count: number | null
          os_version: string | null
          page_url: string | null
          pending_sync_actions: number | null
          resolution_notes: string | null
          session_id: string | null
          severity: string | null
          storage_usage: Json | null
          user_action: string | null
          user_agent: string | null
          user_email: string | null
          user_id: string | null
        }
        Insert: {
          app_version?: string | null
          browser_name?: string | null
          browser_version?: string | null
          created_at?: string
          current_route_id?: string | null
          current_stop_index?: number | null
          device_model?: string | null
          device_type?: string | null
          driver_id?: string | null
          error_message: string
          error_source?: string | null
          error_stack?: string | null
          error_type: string
          first_seen?: string | null
          id?: string
          is_resolved?: boolean | null
          last_seen?: string | null
          memory_usage?: Json | null
          network_status?: Json | null
          occurrence_count?: number | null
          os_version?: string | null
          page_url?: string | null
          pending_sync_actions?: number | null
          resolution_notes?: string | null
          session_id?: string | null
          severity?: string | null
          storage_usage?: Json | null
          user_action?: string | null
          user_agent?: string | null
          user_email?: string | null
          user_id?: string | null
        }
        Update: {
          app_version?: string | null
          browser_name?: string | null
          browser_version?: string | null
          created_at?: string
          current_route_id?: string | null
          current_stop_index?: number | null
          device_model?: string | null
          device_type?: string | null
          driver_id?: string | null
          error_message?: string
          error_source?: string | null
          error_stack?: string | null
          error_type?: string
          first_seen?: string | null
          id?: string
          is_resolved?: boolean | null
          last_seen?: string | null
          memory_usage?: Json | null
          network_status?: Json | null
          occurrence_count?: number | null
          os_version?: string | null
          page_url?: string | null
          pending_sync_actions?: number | null
          resolution_notes?: string | null
          session_id?: string | null
          severity?: string | null
          storage_usage?: Json | null
          user_action?: string | null
          user_agent?: string | null
          user_email?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      lab_tour_late_stops: {
        Row: {
          client_id: string
          created_at: string
          has_delivery: boolean
          has_pickup: boolean
          id: string
          lab_tour_id: string
          rejection_reason: string | null
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["late_stop_status"]
          updated_at: string
          urgent_instructions: string | null
        }
        Insert: {
          client_id: string
          created_at?: string
          has_delivery?: boolean
          has_pickup?: boolean
          id?: string
          lab_tour_id: string
          rejection_reason?: string | null
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["late_stop_status"]
          updated_at?: string
          urgent_instructions?: string | null
        }
        Update: {
          client_id?: string
          created_at?: string
          has_delivery?: boolean
          has_pickup?: boolean
          id?: string
          lab_tour_id?: string
          rejection_reason?: string | null
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["late_stop_status"]
          updated_at?: string
          urgent_instructions?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lab_tour_late_stops_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "lab_tour_late_stops_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_tour_late_stops_lab_tour_id_fkey"
            columns: ["lab_tour_id"]
            isOneToOne: false
            referencedRelation: "lab_tours"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_tour_shipments: {
        Row: {
          client_id: string | null
          created_at: string | null
          from_location_id: string
          id: string
          is_return_next_day: boolean | null
          lab_tour_id: string
          scheduled_date: string
          shipment_type: string
          to_location_id: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string | null
          from_location_id: string
          id?: string
          is_return_next_day?: boolean | null
          lab_tour_id: string
          scheduled_date: string
          shipment_type: string
          to_location_id: string
        }
        Update: {
          client_id?: string | null
          created_at?: string | null
          from_location_id?: string
          id?: string
          is_return_next_day?: boolean | null
          lab_tour_id?: string
          scheduled_date?: string
          shipment_type?: string
          to_location_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_tour_shipments_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "lab_tour_shipments_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_tour_shipments_from_location_id_fkey"
            columns: ["from_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_tour_shipments_lab_tour_id_fkey"
            columns: ["lab_tour_id"]
            isOneToOne: false
            referencedRelation: "lab_tours"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_tour_shipments_to_location_id_fkey"
            columns: ["to_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_tour_stops: {
        Row: {
          client_id: string
          created_at: string | null
          has_delivery: boolean | null
          has_pickup: boolean | null
          id: string
          tour_id: string
        }
        Insert: {
          client_id: string
          created_at?: string | null
          has_delivery?: boolean | null
          has_pickup?: boolean | null
          id?: string
          tour_id: string
        }
        Update: {
          client_id?: string
          created_at?: string | null
          has_delivery?: boolean | null
          has_pickup?: boolean | null
          id?: string
          tour_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lab_tour_stops_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "lab_tour_stops_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lab_tour_stops_tour_id_fkey"
            columns: ["tour_id"]
            isOneToOne: false
            referencedRelation: "lab_tours"
            referencedColumns: ["id"]
          },
        ]
      }
      lab_tours: {
        Row: {
          created_at: string | null
          date: string
          id: string
          laboratory_id: string
          pickup_time: string | null
          rejection_reason: string | null
          return_time: string | null
          status: string
          submission_time: string | null
        }
        Insert: {
          created_at?: string | null
          date: string
          id?: string
          laboratory_id: string
          pickup_time?: string | null
          rejection_reason?: string | null
          return_time?: string | null
          status: string
          submission_time?: string | null
        }
        Update: {
          created_at?: string | null
          date?: string
          id?: string
          laboratory_id?: string
          pickup_time?: string | null
          rejection_reason?: string | null
          return_time?: string | null
          status?: string
          submission_time?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lab_tours_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
        ]
      }
      laboratories: {
        Row: {
          created_at: string | null
          depot_is_lab: boolean
          email: string | null
          id: string
          location_id: string
          name: string
          shared_pickup: boolean
          user_id: string
        }
        Insert: {
          created_at?: string | null
          depot_is_lab?: boolean
          email?: string | null
          id?: string
          location_id: string
          name: string
          shared_pickup?: boolean
          user_id: string
        }
        Update: {
          created_at?: string | null
          depot_is_lab?: boolean
          email?: string | null
          id?: string
          location_id?: string
          name?: string
          shared_pickup?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "laboratories_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      laboratory_clients: {
        Row: {
          client_type: string
          created_at: string | null
          depot_is_dentist: boolean | null
          depot_is_lab: boolean | null
          driver_id: string | null
          id: string
          is_active: boolean
          is_mika_client: boolean | null
          is_pickup_depot: boolean | null
          is_return_depot: boolean | null
          is_return_next_day: boolean | null
          laboratory_id: string
          location_id: string
          name: string | null
        }
        Insert: {
          client_type: string
          created_at?: string | null
          depot_is_dentist?: boolean | null
          depot_is_lab?: boolean | null
          driver_id?: string | null
          id?: string
          is_active?: boolean
          is_mika_client?: boolean | null
          is_pickup_depot?: boolean | null
          is_return_depot?: boolean | null
          is_return_next_day?: boolean | null
          laboratory_id: string
          location_id: string
          name?: string | null
        }
        Update: {
          client_type?: string
          created_at?: string | null
          depot_is_dentist?: boolean | null
          depot_is_lab?: boolean | null
          driver_id?: string | null
          id?: string
          is_active?: boolean
          is_mika_client?: boolean | null
          is_pickup_depot?: boolean | null
          is_return_depot?: boolean | null
          is_return_next_day?: boolean | null
          laboratory_id?: string
          location_id?: string
          name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "laboratory_clients_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "laboratory_clients_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "v_driver_performance_summary"
            referencedColumns: ["driver_id"]
          },
          {
            foreignKeyName: "laboratory_clients_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "laboratory_clients_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      laboratory_clients_audit: {
        Row: {
          additional_info: Json | null
          changed_at: string | null
          changed_by: string | null
          client_id: string
          id: string
          new_name: string | null
          old_name: string | null
          operation: string
        }
        Insert: {
          additional_info?: Json | null
          changed_at?: string | null
          changed_by?: string | null
          client_id: string
          id?: string
          new_name?: string | null
          old_name?: string | null
          operation: string
        }
        Update: {
          additional_info?: Json | null
          changed_at?: string | null
          changed_by?: string | null
          client_id?: string
          id?: string
          new_name?: string | null
          old_name?: string | null
          operation?: string
        }
        Relationships: [
          {
            foreignKeyName: "laboratory_clients_audit_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "laboratory_clients_audit_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
        ]
      }
      laboratory_statistics: {
        Row: {
          calculated_at: string | null
          completed_shipments: number | null
          created_at: string | null
          failed_shipments: number | null
          failure_rate: number | null
          id: string
          laboratory_id: string
          least_delivered_client_id: string | null
          least_delivered_client_name: string | null
          least_delivered_count: number | null
          market_share_data: Json | null
          most_delivered_client_id: string | null
          most_delivered_client_name: string | null
          most_delivered_count: number | null
          period_end: string
          period_start: string
          success_rate: number | null
          total_shipments: number | null
          updated_at: string | null
          weekly_activity: Json | null
        }
        Insert: {
          calculated_at?: string | null
          completed_shipments?: number | null
          created_at?: string | null
          failed_shipments?: number | null
          failure_rate?: number | null
          id?: string
          laboratory_id: string
          least_delivered_client_id?: string | null
          least_delivered_client_name?: string | null
          least_delivered_count?: number | null
          market_share_data?: Json | null
          most_delivered_client_id?: string | null
          most_delivered_client_name?: string | null
          most_delivered_count?: number | null
          period_end: string
          period_start: string
          success_rate?: number | null
          total_shipments?: number | null
          updated_at?: string | null
          weekly_activity?: Json | null
        }
        Update: {
          calculated_at?: string | null
          completed_shipments?: number | null
          created_at?: string | null
          failed_shipments?: number | null
          failure_rate?: number | null
          id?: string
          laboratory_id?: string
          least_delivered_client_id?: string | null
          least_delivered_client_name?: string | null
          least_delivered_count?: number | null
          market_share_data?: Json | null
          most_delivered_client_id?: string | null
          most_delivered_client_name?: string | null
          most_delivered_count?: number | null
          period_end?: string
          period_start?: string
          success_rate?: number | null
          total_shipments?: number | null
          updated_at?: string | null
          weekly_activity?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "laboratory_statistics_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "laboratory_statistics_least_delivered_client_id_fkey"
            columns: ["least_delivered_client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "laboratory_statistics_least_delivered_client_id_fkey"
            columns: ["least_delivered_client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "laboratory_statistics_most_delivered_client_id_fkey"
            columns: ["most_delivered_client_id"]
            isOneToOne: false
            referencedRelation: "billing_reports"
            referencedColumns: ["client_id"]
          },
          {
            foreignKeyName: "laboratory_statistics_most_delivered_client_id_fkey"
            columns: ["most_delivered_client_id"]
            isOneToOne: false
            referencedRelation: "laboratory_clients"
            referencedColumns: ["id"]
          },
        ]
      }
      location_photos: {
        Row: {
          created_at: string | null
          description: string | null
          id: string
          location_id: string
          photo_url: string
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          id?: string
          location_id: string
          photo_url: string
        }
        Update: {
          created_at?: string | null
          description?: string | null
          id?: string
          location_id?: string
          photo_url?: string
        }
        Relationships: [
          {
            foreignKeyName: "location_photos_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      locations: {
        Row: {
          created_at: string | null
          delivery_instructions: string | null
          formatted_address: string
          id: string
          latitude: number
          longitude: number
          place_id: string | null
          type: string | null
        }
        Insert: {
          created_at?: string | null
          delivery_instructions?: string | null
          formatted_address: string
          id?: string
          latitude: number
          longitude: number
          place_id?: string | null
          type?: string | null
        }
        Update: {
          created_at?: string | null
          delivery_instructions?: string | null
          formatted_address?: string
          id?: string
          latitude?: number
          longitude?: number
          place_id?: string | null
          type?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      billing_reports: {
        Row: {
          billing_configuration_id: string | null
          billing_month: string | null
          billing_type: string | null
          both_count: number | null
          client_id: string | null
          client_name: string | null
          delivery_count: number | null
          has_billing_config: boolean | null
          laboratory_id: string | null
          laboratory_name: string | null
          monthly_flat_rate: number | null
          pickup_count: number | null
          price_per_visit: number | null
          total_amount_euros: number | null
          total_visits: number | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_route_shipments_laboratory_id_fkey"
            columns: ["laboratory_id"]
            isOneToOne: false
            referencedRelation: "laboratories"
            referencedColumns: ["id"]
          },
        ]
      }
      critical_errors_recent: {
        Row: {
          created_at: string | null
          device_model: string | null
          device_type: string | null
          error_message: string | null
          error_type: string | null
          id: string | null
          occurrence_count: number | null
          os_version: string | null
          page_url: string | null
          user_action: string | null
          user_email: string | null
        }
        Insert: {
          created_at?: string | null
          device_model?: string | null
          device_type?: string | null
          error_message?: string | null
          error_type?: string | null
          id?: string | null
          occurrence_count?: number | null
          os_version?: string | null
          page_url?: string | null
          user_action?: string | null
          user_email?: string | null
        }
        Update: {
          created_at?: string | null
          device_model?: string | null
          device_type?: string | null
          error_message?: string | null
          error_type?: string | null
          id?: string | null
          occurrence_count?: number | null
          os_version?: string | null
          page_url?: string | null
          user_action?: string | null
          user_email?: string | null
        }
        Relationships: []
      }
      error_stats: {
        Row: {
          affected_users: number | null
          avg_occurrences_per_session: number | null
          device_type: string | null
          error_count: number | null
          error_type: string | null
          first_occurrence: string | null
          last_occurrence: string | null
          severity: string | null
        }
        Relationships: []
      }
      v_driver_performance_summary: {
        Row: {
          avg_duration_hours: number | null
          completed_routes_this_month: number | null
          completion_rate: number | null
          driver_id: string | null
          driver_name: string | null
          last_calculation: string | null
          routes_this_month: number | null
          sector: string | null
          status: string | null
          total_distance_this_month: number | null
        }
        Relationships: []
      }
      v_driver_statistics_with_details: {
        Row: {
          average_distance_per_day: number | null
          average_duration_hours: number | null
          average_end_time: string | null
          average_start_time: string | null
          average_stops_per_day: number | null
          average_stops_per_route: number | null
          calculated_at: string | null
          client_coverage: Json | null
          completed_deliveries: number | null
          completed_pickups: number | null
          completed_routes: number | null
          configured_start_time: string | null
          created_at: string | null
          delivery_success_rate: number | null
          driver_email: string | null
          driver_id: string | null
          driver_name: string | null
          earliest_start_time: string | null
          formatted_average_duration: string | null
          hourly_distribution: Json | null
          id: string | null
          latest_end_time: string | null
          period_end: string | null
          period_start: string | null
          pickup_success_rate: number | null
          route_completion_rate: number | null
          sector: string | null
          total_deliveries: number | null
          total_distance_km: number | null
          total_pickups: number | null
          total_routes: number | null
          total_stops: number | null
          total_working_days: number | null
          updated_at: string | null
          vehicle_type: string | null
          weekly_activity: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_statistics_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_statistics_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "v_driver_performance_summary"
            referencedColumns: ["driver_id"]
          },
        ]
      }
      v_recent_driver_statistics: {
        Row: {
          average_distance_per_day: number | null
          average_duration_hours: number | null
          average_end_time: string | null
          average_start_time: string | null
          average_stops_per_day: number | null
          average_stops_per_route: number | null
          calculated_at: string | null
          client_coverage: Json | null
          completed_deliveries: number | null
          completed_pickups: number | null
          completed_routes: number | null
          configured_start_time: string | null
          created_at: string | null
          delivery_success_rate: number | null
          driver_email: string | null
          driver_id: string | null
          driver_name: string | null
          earliest_start_time: string | null
          formatted_average_duration: string | null
          hourly_distribution: Json | null
          id: string | null
          latest_end_time: string | null
          period_end: string | null
          period_start: string | null
          pickup_success_rate: number | null
          route_completion_rate: number | null
          sector: string | null
          total_deliveries: number | null
          total_distance_km: number | null
          total_pickups: number | null
          total_routes: number | null
          total_stops: number | null
          total_working_days: number | null
          updated_at: string | null
          vehicle_type: string | null
          weekly_activity: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_statistics_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_statistics_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "v_driver_performance_summary"
            referencedColumns: ["driver_id"]
          },
        ]
      }
    }
    Functions: {
      add_unexpected_shipment: {
        Args: {
          p_laboratory_client_id: string
          p_laboratory_id: string
          p_pickup_stop_id: string
          p_proof_photo_url?: string
          p_route_id: string
          p_shipment_ref?: string
        }
        Returns: {
          delivery_stop_id: string
          delivery_stop_type: string
          shipment_id: string
        }[]
      }
      analyze_route_state: { Args: { p_route_id: string }; Returns: Json }
      calculate_driver_statistics: {
        Args: {
          p_driver_id: string
          p_period_end: string
          p_period_start: string
        }
        Returns: undefined
      }
      calculate_laboratory_statistics: {
        Args: {
          p_laboratory_id: string
          p_period_end: string
          p_period_start: string
        }
        Returns: string
      }
      check_orphan_shipments: { Args: { p_route_id: string }; Returns: Json }
      cleanup_pending_routes: {
        Args: { target_date: string }
        Returns: undefined
      }
      create_driver_shipments: {
        Args: { p_driver_id: string; p_route_id: string; shipments_data: Json }
        Returns: undefined
      }
      create_necessary_stops: {
        Args: { p_route_id: string; shipments_data: Json }
        Returns: {
          location_id: string
          stop_id: string
          stop_type: string
        }[]
      }
      delete_client_complete: {
        Args: { client_id_param: string; location_id_param: string }
        Returns: boolean
      }
      delete_lab_tour_shipments: {
        Args: { lab_tour_id: string }
        Returns: undefined
      }
      delete_shipments_for_lab_tour: {
        Args: { lab_tour_id: string }
        Returns: undefined
      }
      determine_driver_shipments: {
        Args: { driver_id: string; target_date: string }
        Returns: {
          client_name: string
          from_location_id: string
          lab_tour_shipment_id: string
          laboratory_id: string
          laboratory_name: string
          responsible_client_id: string
          shipment_type: string
          to_location_id: string
        }[]
      }
      driver_statistics_health_report: {
        Args: Record<PropertyKey, never>
        Returns: {
          metric: string
          status: string
          value: string
        }[]
      }
      generate_driver_routes:
        | { Args: Record<PropertyKey, never>; Returns: undefined }
        | { Args: { target_date?: string }; Returns: undefined }
      generate_driver_routes_v2: {
        Args: { target_date?: string }
        Returns: undefined
      }
      generate_invoice_number: {
        Args: { lab_id: string; period_start: string }
        Returns: string
      }
      generate_lab_tour_shipments: {
        Args: { lab_tour_id: string }
        Returns: undefined
      }
      generate_monthly_invoice: {
        Args: { billing_month: string; lab_id: string }
        Returns: string
      }
      generate_shipments_for_lab_tour: {
        Args: { lab_tour_id: string }
        Returns: undefined
      }
      get_all_clients_by_drivers: { Args: Record<PropertyKey, never>; Returns: Json }
      get_driver_comparison_data: {
        Args: { p_period_end?: string; p_period_start?: string }
        Returns: Json
      }
      get_global_driver_statistics: {
        Args: { period_end_param?: string; period_start_param?: string }
        Returns: Json
      }
      increment_stop_orders_after_position: {
        Args: {
          increment_value: number
          position_threshold: number
          route_id_param: string
        }
        Returns: undefined
      }
      maintain_driver_statistics: { Args: Record<PropertyKey, never>; Returns: string }
      mark_invoice_as_sent: { Args: { invoice_id: string }; Returns: boolean }
      optimize_route: { Args: { p_route_id: string }; Returns: Json }
      refresh_all_driver_statistics: {
        Args: { p_period_end?: string; p_period_start?: string }
        Returns: string
      }
      replace_lab_tour_shipments: {
        Args: { new_lab_tour_id: string; old_lab_tour_id: string }
        Returns: undefined
      }
      update_shipments_stop_reference: {
        Args: {
          p_field: string
          p_new_stop_id: string
          p_old_stop_id: string
          p_route_id: string
        }
        Returns: Json
      }
    }
    Enums: {
      late_stop_status: "pending" | "approved" | "rejected"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      late_stop_status: ["pending", "approved", "rejected"],
    },
  },
} as const
