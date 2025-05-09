-- Esquema para teste de performance PostgreSQL: Serial ID vs UUID

-- Habilitar extensão UUID (necessário para suporte básico a UUID)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Criar função uuid_generate_v7 diretamente (sem usar blocos DO)
CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS uuid AS $$
DECLARE
    v7_uuid uuid;
    timestamp_ms bigint;
    timestamp_bytes bytea;
    random_bytes bytea;
BEGIN
    -- Obter timestamp em milissegundos
    timestamp_ms := (EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) * 1000)::bigint;
    
    -- Converter para bytes (primeiros 6 bytes do UUID são o timestamp)
    timestamp_bytes := E'\\x' || lpad(to_hex(timestamp_ms), 12, '0');
    
    -- Gerar bytes aleatórios para o restante do UUID
    random_bytes := gen_random_bytes(10);
    
    -- Montar o UUID v7 (versão 7, variante 2)
    v7_uuid := (
        decode(substring(encode(timestamp_bytes, 'hex') from 1 for 12), 'hex') ||
        decode('7', 'hex') || -- Version 7
        decode(substring(encode(random_bytes, 'hex') from 3 for 2), 'hex') ||
        decode('8', 'hex') || -- Variant 2
        decode(substring(encode(random_bytes, 'hex') from 5 for 12), 'hex')
    )::uuid;
    
    RETURN v7_uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Limpando tabelas existentes (se já existirem)
DROP TABLE IF EXISTS child_serial CASCADE;
DROP TABLE IF EXISTS parent_serial CASCADE;
DROP TABLE IF EXISTS child_uuid CASCADE;
DROP TABLE IF EXISTS parent_uuid CASCADE;

-- Criando tabelas com ID Serial (INT)
CREATE TABLE parent_serial (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  value INTEGER
);

CREATE TABLE child_serial (
  id SERIAL PRIMARY KEY,
  parent_id INTEGER REFERENCES parent_serial(id),
  description VARCHAR(200),
  active BOOLEAN
);

-- Criando tabelas com UUID (usando UUID v7)
CREATE TABLE parent_uuid (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
  name VARCHAR(100),
  value INTEGER
);

CREATE TABLE child_uuid (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
  parent_id UUID REFERENCES parent_uuid(id),
  description VARCHAR(200),
  active BOOLEAN
);

-- Criando índices para melhorar performance de joins
CREATE INDEX idx_child_serial_parent_id ON child_serial(parent_id);
CREATE INDEX idx_child_uuid_parent_id ON child_uuid(parent_id);

-- Ajustar estatísticas do otimizador para valores mais realistas
ALTER TABLE parent_serial ALTER COLUMN id SET STATISTICS 1000;
ALTER TABLE child_serial ALTER COLUMN parent_id SET STATISTICS 1000;
ALTER TABLE parent_uuid ALTER COLUMN id SET STATISTICS 1000;
ALTER TABLE child_uuid ALTER COLUMN parent_id SET STATISTICS 1000;

ANALYZE;