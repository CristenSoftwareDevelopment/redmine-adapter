const http = require('http');
const { URL } = require('url');

const port = Number(process.env.REDMINE_PROXY_PORT || 4311);

function setCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, statusCode, payload) {
  setCorsHeaders(res);
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        reject(new Error('Payload muito grande'));
        req.destroy();
      }
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

async function handleFetch(req, res) {
  let parsed;

  try {
    const rawBody = await readRequestBody(req);
    parsed = JSON.parse(rawBody || '{}');
  } catch (_) {
    sendJson(res, 400, { error: 'JSON invalido' });
    return;
  }

  const targetUrl = parsed.url;
  const apiKey = parsed.apiKey;

  if (typeof targetUrl !== 'string' || !/^https?:\/\//i.test(targetUrl)) {
    sendJson(res, 400, { error: 'Campo url invalido' });
    return;
  }

  if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
    sendJson(res, 400, { error: 'Campo apiKey invalido' });
    return;
  }

  let response;
  try {
    response = await fetch(targetUrl, {
      headers: {
        'X-Redmine-API-Key': apiKey,
        'Accept': 'application/json',
      },
    });
  } catch (error) {
    sendJson(res, 502, { error: `Falha ao acessar Redmine: ${error.message}` });
    return;
  }

  const contentType = response.headers.get('content-type') || 'application/json; charset=utf-8';
  const body = await response.text();

  setCorsHeaders(res);
  res.statusCode = response.status;
  res.setHeader('Content-Type', contentType);
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    setCorsHeaders(res);
    res.statusCode = 204;
    res.end();
    return;
  }

  if (req.method === 'POST' && req.url === '/redmine-proxy/fetch') {
    await handleFetch(req, res);
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

server.listen(port, () => {
  console.log(`[proxy] Redmine proxy ouvindo em http://localhost:${port}`);
});
