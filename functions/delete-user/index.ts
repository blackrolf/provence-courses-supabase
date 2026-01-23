// Suivre les types de Supabase Edge Functions
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';

// Cette fonction Edge permet de supprimer complètement un utilisateur de Supabase Auth
// Elle est appelée après que toutes les autres ressources associées au laboratoire
// aient été nettoyées (photos, locations, etc.)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

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
    const { userId, apiKey } = await req.json();

    // Vérifier que le userId est fourni
    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'ID utilisateur requis' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Créer un client Supabase avec le service_role key pour avoir des droits admin
    // Remarque: Cette clé doit être fournie depuis l'environnement serveur et jamais exposée côté client
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

    // Supprimer l'utilisateur
    const { error } = await supabase.auth.admin.deleteUser(userId);

    if (error) {
      return new Response(
        JSON.stringify({ error: `Erreur lors de la suppression: ${error.message}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, message: 'Utilisateur supprimé avec succès' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Erreur non gérée: ${err.message}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
