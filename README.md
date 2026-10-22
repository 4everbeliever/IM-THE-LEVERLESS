# Toolshed Rentals

Tool and equipment rental app for branches across Bohol (Tagbilaran, Panglao, Tubigon).

## Stack
- React 19 + TypeScript
- Vite 8 + Tailwind CSS v4
- React Router 7 + TanStack Query
- React Hook Form + Zod
- Supabase (PostgreSQL, Auth, Storage, Row Level Security)

## Setup & Local Development

1. **Install dependencies**:
   ```bash
   pnpm install
   ```

2. **Environment variables**:
   Create a `.env.local` file in the root directory:
   ```env
   VITE_SUPABASE_URL=https://ophgpdwzoeuheshcfrrc.supabase.co
   VITE_SUPABASE_ANON_KEY=your-supabase-anon-key
   ```

3. **Start development server**:
   ```bash
   pnpm dev
   ```
   Server runs on `http://localhost:8443`.

## Available Scripts

- `pnpm dev`: Start local Vite development server
- `pnpm build`: Create production bundle
- `pnpm preview`: Preview production build
- `pnpm typecheck`: Run TypeScript compiler check without emitting files
- `pnpm lint`: Run ESLint check across all files
- `pnpm test`: Run Vitest unit & component test suite
- `pnpm test:e2e`: Run Playwright end-to-end tests
- `pnpm format`: Format files using oxfmt
- `pnpm format:check`: Check file formatting
- `pnpm db:types`: Generate TypeScript types from Supabase project

## Database & Migrations

Migrations are stored in `supabase/migrations/` and should be applied in order in the Supabase SQL Editor:
1. `0001_profiles_and_roles.sql`: Roles enum, profiles table, auto-signup customer trigger, and RLS policies.
2. `0002_rental_schema.sql`: Branches, items, bookings, booking extras, payments, maintenance logs, double-booking exclusion constraint, server calculation triggers, and seed data.
3. `0003_schema_refinements.sql`: RPC functions, RLS tightening, and backfill protections.

Run `supabase/tests/rls_checks.sql` in the SQL Editor to verify Row Level Security policies across roles.
