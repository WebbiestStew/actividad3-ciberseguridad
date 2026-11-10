const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const { once } = require('node:events');
const { test } = require('node:test');
const jwt = require('jsonwebtoken');
const { createApp, issuer, audience } = require('./server');

test('Control de acceso HTTP de /api/admin', async (t) => {
  const secret = randomBytes(32).toString('hex');
  const server = createApp(secret).listen(0, '127.0.0.1');
  t.after(() => server.close());
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/api/admin`;

  function token(role = 'admin', options = {}, key = secret) {
    return jwt.sign({ role }, key, {
      algorithm: 'HS256', issuer, audience, subject: 'estudiante', ...options
    });
  }

  const cases = [
    ['sin token', undefined, 401],
    ['token mal formado', 'abc', 401],
    ['firma incorrecta', token('admin', { expiresIn: 60 }, randomBytes(32)), 401],
    ['token vencido', token('admin', { expiresIn: -60 }), 401],
    ['sin expiración', token(), 401],
    ['algoritmo distinto', token('admin', { algorithm: 'HS384', expiresIn: 60 }), 401],
    ['audiencia incorrecta', token('admin', { audience: 'otra', expiresIn: 60 }), 401],
    ['usuario válido sin permisos', token('user', { expiresIn: 60 }), 403],
    ['administrador válido', token('admin', { expiresIn: 60 }), 200]
  ];

  for (const [name, credential, status] of cases) {
    await t.test(name, async () => {
      const headers = credential ? { Authorization: `Bearer ${credential}` } : {};
      const response = await fetch(url, { headers });
      assert.equal(response.status, status);
      assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
      const body = await response.json();
      assert.equal(Object.hasOwn(body, 'message'), status === 200);
    });
  }
});
