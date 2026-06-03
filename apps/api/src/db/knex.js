const knex = require('knex')

const db = knex({
  client: 'pg',
  connection: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'insight360',
    user: process.env.DB_USER || 'insight360_user',
    password: process.env.DB_PASSWORD,
  },
  pool: {
    min: 2,
    max: 20,
    afterCreate(conn, done) {
      // Set default search path for all connections
      conn.query('SET search_path TO public, auth, core, cbm, routes, reports', done)
    },
  },
  acquireConnectionTimeout: 10000,
})

// Helper: set RLS context for a connection before a query
async function withRLS(userId, userRole, fn) {
  return db.transaction(async (trx) => {
    await trx.raw('SET LOCAL app.current_user_id = ?', [userId])
    await trx.raw('SET LOCAL app.current_user_role = ?', [userRole])
    return fn(trx)
  })
}

module.exports = { db, withRLS }
