const jwt = require('jsonwebtoken');
const { issuer, audience } = require('./server');

const role = process.argv[2];
const secret = process.env.JWT_SECRET;
if (!['user', 'admin'].includes(role) || !secret || Buffer.byteLength(secret) < 32) {
  console.error('Uso: node api/token.js user|admin con JWT_SECRET de al menos 32 bytes.');
  process.exit(1);
}

console.log(jwt.sign({ role }, secret, {
  algorithm: 'HS256', issuer, audience, subject: 'estudiante', expiresIn: '5m'
}));
