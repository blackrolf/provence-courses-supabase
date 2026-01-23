// Suivre les types de Supabase Edge Functions
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';

// Headers CORS pour permettre les requêtes cross-origin
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

// Cette fonction Edge permet de migrer les emails des utilisateurs depuis Auth vers les tables laboratories et drivers
Deno.serve(async (req) => {
  // Gérer les requêtes préliminaires CORS (OPTIONS)
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders
    });
  }

  try {
    // Uniquement accepter les requêtes POST
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Méthode non autorisée' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Récupérer les données du corps de la requête
    const { apiKey, userType } = await req.json();

    // Vérifier que le type d'utilisateur est valide
    if (userType && !['laboratory', 'driver', 'all'].includes(userType)) {
      return new Response(
        JSON.stringify({ error: 'Type d\'utilisateur invalide. Utilisez "laboratory", "driver" ou "all"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Créer un client Supabase avec le service_role key pour avoir des droits admin
    const supabaseAdminUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseAdminKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

    if (!supabaseAdminUrl || !supabaseAdminKey) {
      return new Response(
        JSON.stringify({ error: 'Configuration Supabase non trouvée' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Vérification de l'API key pour la sécurité (optionnel selon votre implémentation)
    const expectedApiKey = Deno.env.get('API_KEY');
    if (expectedApiKey && apiKey !== expectedApiKey) {
      return new Response(
        JSON.stringify({ error: 'Clé API non valide' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Créer un client Supabase avec les droits admin
    const supabase = createClient(supabaseAdminUrl, supabaseAdminKey);

    const updates = {
      laboratories: 0,
      drivers: 0,
      errors: [] as string[]
    };

    // Migrer les emails pour les laboratoires
    if (userType === 'laboratory' || userType === 'all') {
      // 1. Récupérer tous les laboratoires
      const { data: laboratories, error: labError } = await supabase
        .from('laboratories')
        .select('id, user_id, email');

      if (labError) {
        updates.errors.push(`Erreur lors de la récupération des laboratoires: ${labError.message}`);
      } else if (laboratories) {
        // 2. Pour chaque laboratoire, récupérer l'email depuis Auth et l'ajouter à la table
        for (const lab of laboratories) {
          try {
            // Ne pas mettre à jour si l'email existe déjà
            if (lab.email) continue;

            // Récupérer l'utilisateur depuis Auth
            const { data: userData, error: userError } = await supabase.auth.admin.getUserById(lab.user_id);

            if (userError || !userData?.user?.email) {
              updates.errors.push(`Impossible de récupérer l'email pour le laboratoire ${lab.id}: ${userError?.message || 'Email non trouvé'}`);
              continue;
            }

            // Mettre à jour le laboratoire avec l'email
            const { error: updateError } = await supabase
              .from('laboratories')
              .update({ email: userData.user.email })
              .eq('id', lab.id);

            if (updateError) {
              updates.errors.push(`Erreur lors de la mise à jour de l'email pour le laboratoire ${lab.id}: ${updateError.message}`);
            } else {
              updates.laboratories++;
            }
          } catch (error) {
            updates.errors.push(`Exception lors de la mise à jour du laboratoire ${lab.id}: ${error.message}`);
          }
        }
      }
    }

    // Migrer les emails pour les livreurs
    if (userType === 'driver' || userType === 'all') {
      // 1. Récupérer tous les livreurs
      const { data: drivers, error: driverError } = await supabase
        .from('drivers')
        .select('id, user_id, email');

      if (driverError) {
        updates.errors.push(`Erreur lors de la récupération des livreurs: ${driverError.message}`);
      } else if (drivers) {
        // 2. Pour chaque livreur, récupérer l'email depuis Auth et l'ajouter à la table
        for (const driver of drivers) {
          try {
            // Ne pas mettre à jour si l'email existe déjà
            if (driver.email) continue;

            // Récupérer l'utilisateur depuis Auth
            const { data: userData, error: userError } = await supabase.auth.admin.getUserById(driver.user_id);

            if (userError || !userData?.user?.email) {
              updates.errors.push(`Impossible de récupérer l'email pour le livreur ${driver.id}: ${userError?.message || 'Email non trouvé'}`);
              continue;
            }

            // Mettre à jour le livreur avec l'email
            const { error: updateError } = await supabase
              .from('drivers')
              .update({ email: userData.user.email })
              .eq('id', driver.id);

            if (updateError) {
              updates.errors.push(`Erreur lors de la mise à jour de l'email pour le livreur ${driver.id}: ${updateError.message}`);
            } else {
              updates.drivers++;
            }
          } catch (error) {
            updates.errors.push(`Exception lors de la mise à jour du livreur ${driver.id}: ${error.message}`);
          }
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        updates: {
          laboratories: updates.laboratories,
          drivers: updates.drivers,
          errors: updates.errors
        }
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Erreur non gérée: ${err.message}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
