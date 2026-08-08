const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const url = new URL(req.url);
  const endpoint = url.pathname.endsWith('/ocr/product-label')
    ? '/ocr/product-label'
    : url.pathname.endsWith('/ocr/ingredients')
    ? '/ocr/ingredients'
    : null;
  if (endpoint === null) {
    return jsonResponse({ error: 'Not found' }, 404);
  }

  const backendUrl = Deno.env.get('OCR_BACKEND_URL')?.replace(/\/+$/, '');
  const backendApiKey = Deno.env.get('OCR_BACKEND_API_KEY');

  if (!backendUrl || !backendApiKey) {
    return jsonResponse(
      { error: 'OCR proxy is not configured' },
      500,
    );
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  try {
    const upstream = await fetch(`${backendUrl}${endpoint}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${backendApiKey}`,
      },
      body: JSON.stringify(payload),
    });

    const text = await upstream.text();

    return new Response(text, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        'Content-Type':
          upstream.headers.get('Content-Type') ?? 'application/json',
      },
    });
  } catch (_) {
    return jsonResponse(
      { error: 'OCR backend is unreachable' },
      502,
    );
  }
});
