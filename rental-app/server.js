const express = require('express');
const path = require('path');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const pool = new Pool({ connectionString: process.env.DATABASE_URL || 'postgres://localhost/rental' });
const SECRET = process.env.JWT_SECRET || 'change-me';
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const wrap = fn => (req, res) => fn(req, res).catch(e => { console.error(e); res.status(500).json({ error: 'Server error' }); });
const audit = (uid, action, table, id, oldV, newV) =>
  pool.query('INSERT INTO audit_log (user_id,action_type,table_affected,record_id,old_value,new_value) VALUES ($1,$2,$3,$4,$5,$6)',
    [uid, action, table, id, oldV && JSON.stringify(oldV), newV && JSON.stringify(newV)]);

function auth(req, res, next) {
  try { req.user = jwt.verify((req.headers.authorization || '').replace('Bearer ', ''), SECRET); next(); }
  catch { res.status(401).json({ error: 'Please log in' }); }
}
const staffOnly = (req, res, next) =>
  ['staff', 'admin'].includes(req.user.role) ? next() : res.status(403).json({ error: 'Staff only' });

// ---- Auth
app.post('/api/register', wrap(async (req, res) => {
  const { first_name, last_name, email, password, phone_number, home_branch_id } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email and password are required' });
  if (password.length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters' });
  const hash = await bcrypt.hash(password, 10);
  try {
    const { rows } = await pool.query(
      `INSERT INTO users (first_name,last_name,email,password_hash,phone_number,home_branch_id) VALUES ($1,$2,$3,$4,$5,$6)
       RETURNING user_id, first_name, role`, [first_name, last_name, email, hash, phone_number, home_branch_id || null]);
    res.json(session(rows[0]));
  } catch (e) { res.status(400).json({ error: 'That email is already registered' }); }
}));

app.post('/api/login', wrap(async (req, res) => {
  const { rows } = await pool.query('SELECT * FROM users WHERE email=$1', [req.body.email]);
  const u = rows[0];
  if (!u || !(await bcrypt.compare(req.body.password || '', u.password_hash)))
    return res.status(401).json({ error: 'Wrong email or password' });
  res.json(session(u));
}));

const session = u => ({
  token: jwt.sign({ id: u.user_id, role: u.role }, SECRET, { expiresIn: '8h' }),
  user: { id: u.user_id, name: u.first_name, role: u.role },
});

// ---- Items
app.get('/api/items', wrap(async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT i.*, c.category_name, c.daily_rate, b.branch_name
     FROM rental_items i JOIN item_categories c USING (category_id) JOIN branches b USING (branch_id)
     ORDER BY i.item_name`);
  res.json(rows);
}));

app.post('/api/items', auth, staffOnly, wrap(async (req, res) => {
  const { branch_id, category_id, item_name, serial_number } = req.body;
  const { rows } = await pool.query(
    `INSERT INTO rental_items (branch_id,category_id,item_name,serial_number,acquired_date)
     VALUES ($1,$2,$3,$4,CURRENT_DATE) RETURNING *`, [branch_id, category_id, item_name, serial_number]);
  await audit(req.user.id, 'INSERT', 'rental_items', rows[0].item_id, null, rows[0]);
  res.json(rows[0]);
}));

app.get('/api/lookups', wrap(async (_req, res) => {
  const [b, c, s] = await Promise.all([pool.query('SELECT * FROM branches'), pool.query('SELECT * FROM item_categories'),
    pool.query('SELECT * FROM services ORDER BY service_name')]);
  res.json({ branches: b.rows, categories: c.rows, services: s.rows });
}));

// ---- Bookings
app.get('/api/bookings', auth, wrap(async (req, res) => {
  const staff = ['staff', 'admin'].includes(req.user.role);
  const { rows } = await pool.query(
    `SELECT bk.*, i.item_name, u.first_name || ' ' || u.last_name AS customer,
            COALESCE((SELECT SUM(amount) FROM payments p WHERE p.booking_id=bk.booking_id AND payment_status='paid'),0) AS paid
     FROM bookings bk JOIN rental_items i USING (item_id) JOIN users u ON u.user_id=bk.customer_id
     ${staff ? '' : 'WHERE bk.customer_id=$1'} ORDER BY bk.booking_id DESC`, staff ? [] : [req.user.id]);
  res.json(rows);
}));

app.post('/api/bookings', auth, wrap(async (req, res) => {
  const { item_id, start_date, end_date } = req.body;
  if (!(new Date(end_date) > new Date(start_date))) return res.status(400).json({ error: 'End date must be after start date' });
  const it = await pool.query('SELECT status FROM rental_items WHERE item_id=$1', [item_id]);
  if (!it.rows[0]) return res.status(404).json({ error: 'Item not found' });
  if (it.rows[0].status === 'maintenance') return res.status(409).json({ error: 'This item is under maintenance' });
  const clash = await pool.query(
    `SELECT 1 FROM bookings WHERE item_id=$1 AND status IN ('reserved','checked_out')
     AND start_date < $3 AND end_date > $2`, [item_id, start_date, end_date]);
  if (clash.rowCount) return res.status(409).json({ error: 'That item is already booked for those dates' });
  const { rows } = await pool.query(
    'INSERT INTO bookings (customer_id,item_id,start_date,end_date) VALUES ($1,$2,$3,$4) RETURNING *',
    [req.user.id, item_id, start_date, end_date]);
  await audit(req.user.id, 'INSERT', 'bookings', rows[0].booking_id, null, rows[0]);
  for (const s of req.body.services || []) {
    const qty = parseInt(s.quantity, 10);
    if (qty > 0) await pool.query(
      `INSERT INTO booking_services (booking_id,service_id,quantity,line_total)
       SELECT $1, service_id, $3, price * $3 FROM services WHERE service_id=$2`, [rows[0].booking_id, s.service_id, qty]);
  }
  res.json(rows[0]);
}));

app.post('/api/bookings/:id/checkout', auth, staffOnly, wrap(async (req, res) => {
  const { rows } = await pool.query(
    `UPDATE bookings SET status='checked_out', checkout_staff_id=$2 WHERE booking_id=$1 AND status='reserved' RETURNING *`,
    [req.params.id, req.user.id]);
  if (!rows[0]) return res.status(400).json({ error: 'Booking is not waiting for checkout' });
  await pool.query(`UPDATE rental_items SET status='rented' WHERE item_id=$1`, [rows[0].item_id]);
  await pool.query(`INSERT INTO condition_reports (booking_id,item_id,staff_id,stage,condition_notes) VALUES ($1,$2,$3,'checkout',$4)`,
    [rows[0].booking_id, rows[0].item_id, req.user.id, req.body.notes || '']);
  await audit(req.user.id, 'CHECKOUT', 'bookings', rows[0].booking_id, null, rows[0]);
  res.json(rows[0]);
}));

app.post('/api/bookings/:id/return', auth, staffOnly, wrap(async (req, res) => {
  const { notes = '', damaged = false } = req.body;
  const { rows } = await pool.query(
    `UPDATE bookings SET status='returned', actual_return_date=now() WHERE booking_id=$1 AND status='checked_out' RETURNING *`,
    [req.params.id]);
  if (!rows[0]) return res.status(400).json({ error: 'Booking is not checked out' });
  await pool.query('UPDATE rental_items SET status=$2 WHERE item_id=$1', [rows[0].item_id, damaged ? 'maintenance' : 'available']);
  await pool.query(`INSERT INTO condition_reports (booking_id,item_id,staff_id,stage,condition_notes,damage_flag) VALUES ($1,$2,$3,'return',$4,$5)`,
    [rows[0].booking_id, rows[0].item_id, req.user.id, notes, damaged]);
  await audit(req.user.id, 'RETURN', 'bookings', rows[0].booking_id, null, rows[0]);
  res.json(rows[0]);
}));

app.post('/api/bookings/:id/pay', auth, wrap(async (req, res) => {
  const { rows: [bk] } = await pool.query(
    `SELECT bk.*, c.daily_rate,
            (SELECT COALESCE(SUM(line_total),0) FROM booking_services s WHERE s.booking_id=bk.booking_id) AS svc_total
     FROM bookings bk JOIN rental_items i USING (item_id)
     JOIN item_categories c USING (category_id) WHERE bk.booking_id=$1`, [req.params.id]);
  if (!bk) return res.status(404).json({ error: 'Booking not found' });
  if (bk.customer_id !== req.user.id && !['staff', 'admin'].includes(req.user.role))
    return res.status(403).json({ error: 'You can only pay for your own bookings' });
  const dup = await pool.query(`SELECT 1 FROM payments WHERE booking_id=$1 AND payment_status='paid'`, [bk.booking_id]);
  if (dup.rowCount) return res.status(409).json({ error: 'This booking is already paid' });
  const days = Math.max(1, Math.ceil((new Date(bk.end_date) - new Date(bk.start_date)) / 864e5));
  const { rows } = await pool.query(
    `INSERT INTO payments (booking_id,amount,payment_method,payment_status,paid_at) VALUES ($1,$2,$3,'paid',now()) RETURNING *`,
    [bk.booking_id, days * Number(bk.daily_rate) + Number(bk.svc_total), req.body.method || 'cash']);
  await audit(req.user.id, 'INSERT', 'payments', rows[0].payment_id, null, rows[0]);
  res.json(rows[0]);
}));

// ---- Maintenance (staff)
app.get('/api/maintenance', auth, staffOnly, wrap(async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT m.*, i.item_name, u.first_name AS staff FROM maintenance_logs m
     JOIN rental_items i USING (item_id) LEFT JOIN users u ON u.user_id=m.staff_id
     ORDER BY m.performed_at DESC LIMIT 50`);
  res.json(rows);
}));

app.post('/api/maintenance', auth, staffOnly, wrap(async (req, res) => {
  const { item_id, description, cost, mark } = req.body; // mark: 'maintenance' | 'available'
  const { rows: [it] } = await pool.query('SELECT status FROM rental_items WHERE item_id=$1', [item_id]);
  if (!it) return res.status(404).json({ error: 'Item not found' });
  if (it.status === 'rented') return res.status(409).json({ error: 'Return the item before logging maintenance' });
  const { rows } = await pool.query(
    `INSERT INTO maintenance_logs (item_id,staff_id,description,cost,performed_at) VALUES ($1,$2,$3,$4,now()) RETURNING *`,
    [item_id, req.user.id, description, cost || 0]);
  await pool.query('UPDATE rental_items SET status=$2 WHERE item_id=$1', [item_id, mark === 'available' ? 'available' : 'maintenance']);
  await audit(req.user.id, 'INSERT', 'maintenance_logs', rows[0].maintenance_id, null, rows[0]);
  res.json(rows[0]);
}));

app.listen(process.env.PORT || 3000, () => console.log('Running on http://localhost:3000'));
