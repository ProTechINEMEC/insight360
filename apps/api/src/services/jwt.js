const jwt = require('jsonwebtoken')
const crypto = require('crypto')
const { db } = require('../db/knex')

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET
const ACCESS_EXPIRES = process.env.JWT_ACCESS_EXPIRES || '15m'
const REFRESH_EXPIRES = process.env.JWT_REFRESH_EXPIRES || '7d'

function signAccessToken(payload) {
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: ACCESS_EXPIRES })
}

function signRefreshToken(payload) {
  return jwt.sign(payload, REFRESH_SECRET, { expiresIn: REFRESH_EXPIRES })
}

function verifyAccessToken(token) {
  return jwt.verify(token, ACCESS_SECRET)
}

function verifyRefreshToken(token) {
  return jwt.verify(token, REFRESH_SECRET)
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex')
}

async function storeRefreshToken(userId, token, ipAddress, userAgent) {
  const hash = hashToken(token)
  const decoded = jwt.decode(token)
  const expiresAt = new Date(decoded.exp * 1000)

  await db('auth.refresh_tokens').insert({
    user_id: userId,
    token_hash: hash,
    expires_at: expiresAt,
    ip_address: ipAddress || null,
    user_agent: userAgent || null,
  })

  return hash
}

async function revokeRefreshToken(token) {
  const hash = hashToken(token)
  await db('auth.refresh_tokens').where({ token_hash: hash }).update({ revoked: true })
}

async function revokeAllUserTokens(userId) {
  await db('auth.refresh_tokens')
    .where({ user_id: userId, revoked: false })
    .update({ revoked: true })
}

async function validateRefreshToken(token) {
  const hash = hashToken(token)
  const stored = await db('auth.refresh_tokens')
    .where({ token_hash: hash, revoked: false })
    .where('expires_at', '>', db.fn.now())
    .first()

  return stored || null
}

// Cleanup expired tokens (run periodically)
async function cleanupExpiredTokens() {
  await db('auth.refresh_tokens')
    .where('expires_at', '<', db.fn.now())
    .delete()
}

module.exports = {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
  hashToken,
  storeRefreshToken,
  revokeRefreshToken,
  revokeAllUserTokens,
  validateRefreshToken,
  cleanupExpiredTokens,
}
