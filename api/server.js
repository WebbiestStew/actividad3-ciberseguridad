const express = require('express');
const jwt = require('jsonwebtoken');

const issuer = 'actividad3';
const audience = 'actividad3-api';

function createApp(secret) {
  if (!secret || Buffer.byteLength(secret) < 32) {
    throw new Error('JWT_SECRET debe tener al menos 32 bytes.');
  }

  const app = express();
  app.disable('x-powered-by');

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));
  app.get('/openapi.json', (_req, res) => res.json(require('./openapi.json')));

  app.get('/api/admin', (req, res) => {
    const bearer = /^Bearer ([^\s]+)$/i.exec(req.get('Authorization') || '');
    let claims;
    try {
      claims = jwt.verify(bearer?.[1], secret, {
        algorithms: ['HS256'],
        issuer,
        audience
      });
    } catch {
      // Las solicitudes inválidas reciben la misma respuesta.
    }

    res.set('Cache-Control', 'no-store');
    if (!claims || typeof claims.exp !== 'number' || typeof claims.sub !== 'string' || !claims.sub) {
      return res.set('WWW-Authenticate', 'Bearer').status(401).json({ error: 'Token requerido o inválido' });
    }
    if (claims.role !== 'admin') {
      return res.status(403).json({ error: 'Permisos insuficientes' });
    }
    return res.json({ message: 'Acceso administrativo concedido' });
  });

  return app;
}

if (require.main === module) {
  createApp(process.env.JWT_SECRET).listen(3000, '127.0.0.1', () => {
    console.log('API disponible en http://127.0.0.1:3000');
  });
}

module.exports = { createApp, issuer, audience };
