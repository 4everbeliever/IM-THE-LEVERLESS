# Toolshed Rentals

Simple rental management system (Node/Express + PostgreSQL + vanilla JS).

## Setup
1. `createdb rental && psql -d rental -f schema.sql`
2. `npm install`
3. `DATABASE_URL=postgres://localhost/rental JWT_SECRET=pick-a-secret npm start`
4. Open http://localhost:3000

## Staff account
Register in the app, then run:
`UPDATE users SET role='staff' WHERE email='you@example.com';`

## Files
- `schema.sql` – tables from the ERD, constraints, Bohol branch sample data
- `server.js` – REST API (auth, items, bookings, payments, maintenance, audit log)
- `public/index.html` – frontend
