-- TCHOP — extensions requises par les migrations (idempotent).
create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";
-- Schéma realtime : doit exister AVANT le démarrage de realtime
-- (DB_AFTER_CONNECT_QUERY fait SET search_path TO _realtime).
create schema if not exists _realtime;
