-- Run: psql -d rental -f schema.sql
-- Follows the updated ERD (Blank_diagram-2). Beyond the ERD I added: DEFAULT/CHECK on
-- role, status, stage, payment_status; end_date > start_date; two indexes on bookings.
CREATE TABLE branches (
  branch_id SERIAL PRIMARY KEY, branch_name VARCHAR(100) NOT NULL, address VARCHAR(255),
  city VARCHAR(100), contact_number VARCHAR(20), created_at TIMESTAMP DEFAULT now());

CREATE TABLE users (
  user_id SERIAL PRIMARY KEY, first_name VARCHAR(150), last_name VARCHAR(150),
  email VARCHAR(150) NOT NULL UNIQUE, password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','staff','admin')),
  phone_number VARCHAR(20), home_branch_id INT REFERENCES branches, created_at TIMESTAMP DEFAULT now());

CREATE TABLE item_categories (
  category_id SERIAL PRIMARY KEY, category_name VARCHAR(100) NOT NULL, description VARCHAR(255),
  daily_rate NUMERIC(10,2) NOT NULL CHECK (daily_rate >= 0));

CREATE TABLE rental_items (
  item_id SERIAL PRIMARY KEY, branch_id INT NOT NULL REFERENCES branches,
  category_id INT NOT NULL REFERENCES item_categories, item_name VARCHAR(150) NOT NULL,
  serial_number VARCHAR(100) UNIQUE,
  status VARCHAR(20) NOT NULL DEFAULT 'available' CHECK (status IN ('available','rented','maintenance')),
  acquired_date DATE);

CREATE TABLE services (
  service_id SERIAL PRIMARY KEY, service_name VARCHAR(100) NOT NULL, description VARCHAR(255),
  price NUMERIC(10,2) NOT NULL CHECK (price >= 0));

CREATE TABLE bookings (
  booking_id SERIAL PRIMARY KEY, customer_id INT NOT NULL REFERENCES users,
  item_id INT NOT NULL REFERENCES rental_items, checkout_staff_id INT REFERENCES users,
  start_date TIMESTAMP NOT NULL, end_date TIMESTAMP NOT NULL, actual_return_date TIMESTAMP,
  status VARCHAR(20) NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved','checked_out','returned','cancelled')),
  CHECK (end_date > start_date));

CREATE TABLE payments (
  payment_id SERIAL PRIMARY KEY, booking_id INT NOT NULL REFERENCES bookings,
  amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0), payment_method VARCHAR(30),
  payment_status VARCHAR(20) CHECK (payment_status IN ('pending','paid','refunded')), paid_at TIMESTAMP);

CREATE TABLE maintenance_logs (
  maintenance_id SERIAL PRIMARY KEY, item_id INT NOT NULL REFERENCES rental_items,
  staff_id INT REFERENCES users, description VARCHAR(255), cost NUMERIC(10,2), performed_at TIMESTAMP);

CREATE TABLE booking_services (
  booking_id INT REFERENCES bookings, service_id INT REFERENCES services,
  quantity INT NOT NULL CHECK (quantity > 0), line_total NUMERIC(10,2),
  PRIMARY KEY (booking_id, service_id));

CREATE TABLE staff_branch_assignments (
  staff_id INT REFERENCES users, branch_id INT REFERENCES branches, role_at_branch VARCHAR(50),
  start_date DATE, end_date DATE, PRIMARY KEY (staff_id, branch_id, start_date));

CREATE TABLE condition_reports (
  report_id SERIAL PRIMARY KEY, booking_id INT NOT NULL REFERENCES bookings,
  item_id INT NOT NULL REFERENCES rental_items, staff_id INT REFERENCES users,
  stage VARCHAR(20) CHECK (stage IN ('checkout','return')), condition_notes VARCHAR(500),
  damage_flag BOOLEAN DEFAULT false, reported_at TIMESTAMP DEFAULT now());

CREATE TABLE audit_log (
  audit_id SERIAL PRIMARY KEY, user_id INT REFERENCES users, action_type VARCHAR(50),
  table_affected VARCHAR(50), record_id INT, old_value TEXT, new_value TEXT,
  performed_at TIMESTAMP DEFAULT now());

CREATE INDEX idx_bookings_item_dates ON bookings (item_id, start_date, end_date);
CREATE INDEX idx_bookings_customer ON bookings (customer_id);

-- Sample data
-- Bohol: Tagbilaran City + 47 municipalities (province = Bohol)
INSERT INTO branches (branch_name, address, city, contact_number) VALUES
  ('Tagbilaran City', 'Poblacion', 'Tagbilaran City', '+63 38 555 0100'),
  ('Panglao', 'Poblacion', 'Panglao', '+63 38 555 0101'),
  ('Tubigon', 'Poblacion', 'Tubigon', '+63 38 555 0102'),
  ('Carmen', 'Poblacion', 'Carmen', '+63 38 555 0103'),
  ('Alburquerque', 'Poblacion', 'Alburquerque', '+63 38 555 0104'),
  ('Alicia', 'Poblacion', 'Alicia', '+63 38 555 0105'),
  ('Anda', 'Poblacion', 'Anda', '+63 38 555 0106'),
  ('Antequera', 'Poblacion', 'Antequera', '+63 38 555 0107'),
  ('Baclayon', 'Poblacion', 'Baclayon', '+63 38 555 0108'),
  ('Balilihan', 'Poblacion', 'Balilihan', '+63 38 555 0109'),
  ('Batuan', 'Poblacion', 'Batuan', '+63 38 555 0110'),
  ('Bien Unido', 'Poblacion', 'Bien Unido', '+63 38 555 0111'),
  ('Bilar', 'Poblacion', 'Bilar', '+63 38 555 0112'),
  ('Buenavista', 'Poblacion', 'Buenavista', '+63 38 555 0113'),
  ('Calape', 'Poblacion', 'Calape', '+63 38 555 0114'),
  ('Candijay', 'Poblacion', 'Candijay', '+63 38 555 0115'),
  ('Catigbian', 'Poblacion', 'Catigbian', '+63 38 555 0116'),
  ('Clarin', 'Poblacion', 'Clarin', '+63 38 555 0117'),
  ('Corella', 'Poblacion', 'Corella', '+63 38 555 0118'),
  ('Cortes', 'Poblacion', 'Cortes', '+63 38 555 0119'),
  ('Dagohoy', 'Poblacion', 'Dagohoy', '+63 38 555 0120'),
  ('Danao', 'Poblacion', 'Danao', '+63 38 555 0121'),
  ('Dauis', 'Poblacion', 'Dauis', '+63 38 555 0122'),
  ('Dimiao', 'Poblacion', 'Dimiao', '+63 38 555 0123'),
  ('Duero', 'Poblacion', 'Duero', '+63 38 555 0124'),
  ('Garcia Hernandez', 'Poblacion', 'Garcia Hernandez', '+63 38 555 0125'),
  ('Getafe', 'Poblacion', 'Getafe', '+63 38 555 0126'),
  ('Guindulman', 'Poblacion', 'Guindulman', '+63 38 555 0127'),
  ('Inabanga', 'Poblacion', 'Inabanga', '+63 38 555 0128'),
  ('Jagna', 'Poblacion', 'Jagna', '+63 38 555 0129'),
  ('Lila', 'Poblacion', 'Lila', '+63 38 555 0130'),
  ('Loay', 'Poblacion', 'Loay', '+63 38 555 0131'),
  ('Loboc', 'Poblacion', 'Loboc', '+63 38 555 0132'),
  ('Loon', 'Poblacion', 'Loon', '+63 38 555 0133'),
  ('Mabini', 'Poblacion', 'Mabini', '+63 38 555 0134'),
  ('Maribojoc', 'Poblacion', 'Maribojoc', '+63 38 555 0135'),
  ('Pilar', 'Poblacion', 'Pilar', '+63 38 555 0136'),
  ('President Carlos P. Garcia', 'Poblacion', 'President Carlos P. Garcia', '+63 38 555 0137'),
  ('Sagbayan', 'Poblacion', 'Sagbayan', '+63 38 555 0138'),
  ('San Isidro', 'Poblacion', 'San Isidro', '+63 38 555 0139'),
  ('San Miguel', 'Poblacion', 'San Miguel', '+63 38 555 0140'),
  ('Sevilla', 'Poblacion', 'Sevilla', '+63 38 555 0141'),
  ('Sierra Bullones', 'Poblacion', 'Sierra Bullones', '+63 38 555 0142'),
  ('Sikatuna', 'Poblacion', 'Sikatuna', '+63 38 555 0143'),
  ('Talibon', 'Poblacion', 'Talibon', '+63 38 555 0144'),
  ('Trinidad', 'Poblacion', 'Trinidad', '+63 38 555 0145'),
  ('Ubay', 'Poblacion', 'Ubay', '+63 38 555 0146'),
  ('Valencia', 'Poblacion', 'Valencia', '+63 38 555 0147');
INSERT INTO item_categories (category_name, description, daily_rate) VALUES
  ('Power Tools', 'Drills, saws, sanders', 25.00), ('Camping', 'Tents and stoves', 15.00);
INSERT INTO rental_items (branch_id, category_id, item_name, serial_number, acquired_date) VALUES
  (1, 1, 'Cordless Drill', 'PT-001', '2025-01-10'), (3, 1, 'Circular Saw', 'PT-002', '2025-02-01'),
  (2, 2, '4-Person Tent', 'CP-001', '2025-03-05'), (4, 2, 'Camping Stove', 'CP-002', '2025-03-20');
INSERT INTO services (service_name, description, price) VALUES
  ('Delivery', 'Drop-off and pick-up', 10.00), ('Insurance', 'Damage cover for the rental', 5.00);
-- To create a staff account: register in the app, then run
-- UPDATE users SET role='staff' WHERE email='you@example.com';
