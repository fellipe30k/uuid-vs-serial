-- Este script será executado quando o container do PostgreSQL for iniciado pela primeira vez

-- Criar extensão UUID-OSSP para suporte a UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Verificar se a função uuid_generate_v7 está disponível (PostgreSQL 17)
DO $$
BEGIN
    -- Tenta executar a função uuid_generate_v7() para verificar se está disponível
    PERFORM uuid_generate_v7();
    
    RAISE NOTICE 'UUID v7 está disponível na instalação do PostgreSQL!';
EXCEPTION
    WHEN undefined_function THEN
        RAISE NOTICE 'UUID v7 não está disponível. Criando uma função de compatibilidade...';
        
        -- Criar uma função compatível (não é tão eficiente quanto a nativa, mas funciona para testes)
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
            
            -- Converter para bytes
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
END;
$$;

-- Mostrar mensagem para confirmar que a inicialização foi concluída
DO $$
BEGIN
    RAISE NOTICE 'Inicialização do banco de dados concluída. Banco preparado para testes de performance.';
END;
$$;