const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;

// PostgreSQL connection pool configuration
const pool = new Pool({
  host: process.env.DB_HOST || 'db-server',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'testdb',
  connectionTimeoutMillis: 5000
});

// Handle idle connection errors gracefully (e.g. when DB container restarts)
pool.on('error', (err, client) => {
  console.error('Unexpected error on idle database client:', err.message);
});

// Root endpoint: displays API info and DB configuration
app.get('/', (req, res) => {
  res.json({
    status: 'online',
    message: 'Backend Web API connected via Docker Custom Bridge Network',
    db_config: {
      host: process.env.DB_HOST || 'db-server',
      port: process.env.DB_PORT || '5432',
      database: process.env.DB_NAME || 'testdb'
    }
  });
});

// Health check endpoint: verifies PostgreSQL database connection
app.get('/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as current_time, version() as version;');
    res.json({
      status: 'healthy',
      database: 'connected',
      current_time: result.rows[0].current_time,
      version: result.rows[0].version
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      database: 'disconnected',
      error: error.message
    });
  }
});

// Query users from database
app.get('/users', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM users ORDER BY id ASC;');
    res.json({
      success: true,
      total: result.rowCount,
      data: result.rows
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Insert a user into database
app.post('/users', async (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) {
    return res.status(400).json({ error: 'name and email are required' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING *;',
      [name, email]
    );
    res.status(201).json({
      success: true,
      message: 'User created successfully',
      data: result.rows[0]
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`Backend API server is running on port ${PORT}`);
  console.log(`Connected to Database Host: ${process.env.DB_HOST || 'db-server'}`);
  console.log(`====================================================`);
});
