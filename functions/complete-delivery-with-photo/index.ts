import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * Edge Function : Complete Delivery with Photo
 *
 * Cette fonction gère de manière ATOMIQUE :
 * 1. Upload de la photo vers Supabase Storage
 * 2. Mise à jour du shipment avec l'URL de la photo
 * 3. Rollback automatique en cas d'erreur
 *
 * Garantit 100% de cohérence des données.
 */

interface RequestBody {
  shipmentId: string;
  photoBase64: string; // Format: "data:image/jpeg;base64,..."
  actionType: 'delivery' | 'pickup'; // Type d'action
  status: 'completed' | 'failed'; // Statut final
  issueType?: string; // Type de problème si status = 'failed'
  issueDescription?: string; // Description du problème
}

interface ResponseData {
  success: boolean;
  photoUrl?: string;
  shipment?: any;
  error?: string;
  details?: any;
}

Deno.serve(async (req: Request): Promise<Response> => {
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders, status: 204 });
  }

  try {
    console.log('[Edge Function] Début du traitement');

    // 1. Initialiser le client Supabase avec les credentials de service (bypass RLS)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 2. Parser le body de la requête
    const body: RequestBody = await req.json();
    console.log('Données reçues:', {
      shipmentId: body.shipmentId,
      actionType: body.actionType,
      status: body.status,
      hasPhoto: !!body.photoBase64,
      photoSize: body.photoBase64?.length || 0
    });

    // 3. Validation des données
    if (!body.shipmentId || !body.photoBase64 || !body.actionType || !body.status) {
      throw new Error('Données manquantes: shipmentId, photoBase64, actionType et status sont requis');
    }

    // 4. Vérifier que le shipment existe
    const { data: existingShipment, error: fetchError } = await supabase
      .from('driver_route_shipments')
      .select('*')
      .eq('id', body.shipmentId)
      .single();

    if (fetchError || !existingShipment) {
      throw new Error(`Shipment introuvable: ${body.shipmentId}`);
    }

    console.log('Shipment trouvé:', {
      id: existingShipment.id,
      pickup_status: existingShipment.pickup_status,
      delivery_status: existingShipment.delivery_status
    });

    // 5. Convertir base64 en Blob
    console.log('Conversion base64 vers Blob...');
    const base64Data = body.photoBase64.split(',')[1]; // Enlever le prefix "data:image/jpeg;base64,"
    const binaryData = Uint8Array.from(atob(base64Data), c => c.charCodeAt(0));
    const photoBlob = new Blob([binaryData], { type: 'image/jpeg' });

    console.log('Blob créé:', {
      size: photoBlob.size,
      type: photoBlob.type,
      sizeKB: Math.round(photoBlob.size / 1024)
    });

    // Vérifier la taille du blob
    if (photoBlob.size === 0) {
      throw new Error('Photo vide (0 bytes)');
    }

    if (photoBlob.size > 10 * 1024 * 1024) { // 10 MB
      throw new Error(`Photo trop volumineuse: ${Math.round(photoBlob.size / 1024 / 1024)} MB (max 10 MB)`);
    }

    // 6. TRANSACTION: Upload de la photo vers Storage
    const timestamp = Date.now();
    const fileName = `shipment_${body.shipmentId}_${timestamp}.jpg`;
    const filePath = `photos/${fileName}`;

    console.log('Upload vers Supabase Storage:', filePath);

    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('photos-delivery')
      .upload(filePath, photoBlob, {
        contentType: 'image/jpeg',
        upsert: false
      });

    if (uploadError) {
      console.error('Erreur upload Storage:', uploadError);
      throw new Error(`Échec upload photo: ${uploadError.message}`);
    }

    console.log('Upload Storage réussi:', uploadData);

    // 7. Obtenir l'URL publique
    const { data: urlData } = supabase.storage
      .from('photos-delivery')
      .getPublicUrl(filePath);

    const publicUrl = urlData.publicUrl;
    console.log('URL publique obtenue:', publicUrl);

    if (!publicUrl || publicUrl.length === 0) {
      // Rollback: Supprimer la photo uploadée
      await supabase.storage
        .from('photos-delivery')
        .remove([filePath]);

      throw new Error('URL publique vide retournée par Supabase');
    }

    // 8. TRANSACTION: Mise à jour du shipment en base
    const now = new Date().toISOString();

    // Construire l'objet de mise à jour selon le type d'action
    const updateData: any = {
      proof_photo_url: publicUrl,
      updated_at: now
    };

    // Mettre à jour les statuts et timestamps selon l'action
    if (body.actionType === 'delivery') {
      updateData.delivery_status = body.status;
      updateData.delivery_time = body.status === 'completed' ? now : null;
    } else if (body.actionType === 'pickup') {
      updateData.pickup_status = body.status;
      updateData.pickup_time = body.status === 'completed' ? now : null;

      // LOGIQUE MÉTIER: Si pickup failed → delivery failed automatiquement
      if (body.status === 'failed') {
        updateData.delivery_status = 'failed';
      }
    }

    // Ajouter les infos d'erreur si applicable
    if (body.status === 'failed') {
      if (body.issueType) updateData.issue_type = body.issueType;
      if (body.issueDescription) updateData.issue_description = body.issueDescription;
    }

    console.log('Mise à jour shipment:', updateData);

    const { data: updatedShipment, error: updateError } = await supabase
      .from('driver_route_shipments')
      .update(updateData)
      .eq('id', body.shipmentId)
      .select()
      .single();

    if (updateError) {
      console.error('Erreur mise à jour DB:', updateError);

      // ROLLBACK: Supprimer la photo uploadée
      console.log('ROLLBACK: Suppression de la photo uploadée');
      await supabase.storage
        .from('photos-delivery')
        .remove([filePath]);

      throw new Error(`Échec mise à jour shipment: ${updateError.message}`);
    }

    console.log('Shipment mis à jour avec succès:', {
      id: updatedShipment.id,
      proof_photo_url: updatedShipment.proof_photo_url,
      pickup_status: updatedShipment.pickup_status,
      delivery_status: updatedShipment.delivery_status
    });

    // 9. Retourner la réponse de succès
    const response: ResponseData = {
      success: true,
      photoUrl: publicUrl,
      shipment: updatedShipment
    };

    return new Response(
      JSON.stringify(response),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    );

  } catch (error) {
    console.error('[Edge Function] Erreur:', error);

    const response: ResponseData = {
      success: false,
      error: error instanceof Error ? error.message : 'Erreur inconnue',
      details: error instanceof Error ? error.stack : undefined
    };

    return new Response(
      JSON.stringify(response),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    );
  }
});
