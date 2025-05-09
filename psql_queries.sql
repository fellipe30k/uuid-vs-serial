-- Arquivo com queries PSQL para teste livre dos joins

-- Estatísticas das tabelas
\echo 'Estatísticas das Tabelas'
SELECT 
    table_name,
    pg_size_pretty(pg_relation_size(quote_ident(table_name))) as table_size,
    pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) as total_size,
    (SELECT count(*) FROM parent_serial) as row_count
FROM 
    information_schema.tables
WHERE 
    table_schema = 'public' AND
    table_name IN ('parent_serial', 'child_serial', 'parent_uuid', 'child_uuid')
ORDER BY 
    pg_relation_size(quote_ident(table_name)) DESC;

-- Tamanho dos índices
\echo 'Tamanho dos Índices'
SELECT
    indexrelname as index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) as index_size,
    idx_scan as index_scans
FROM
    pg_stat_user_indexes ui
    JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE
    ui.schemaname = 'public' AND
    ui.relname IN ('parent_serial', 'child_serial', 'parent_uuid', 'child_uuid')
ORDER BY
    pg_relation_size(i.indexrelid) DESC;

-- JOINS COM ID SERIAL
\echo 'Query 1: Join Simples com ID Serial'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.name, c.description 
FROM parent_serial p 
JOIN child_serial c ON p.id = c.parent_id 
WHERE p.value > 500
LIMIT 100;

\echo 'Query 2: Join Complexo com ID Serial'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.name, COUNT(c.id) as child_count, AVG(p.value) as avg_value
FROM parent_serial p 
LEFT JOIN child_serial c ON p.id = c.parent_id 
WHERE p.value BETWEEN 200 AND 800
GROUP BY p.name 
ORDER BY child_count DESC
LIMIT 100;

\echo 'Query 3: Join com Multiplas Condições usando ID Serial'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.name, c.description, c.active
FROM parent_serial p
JOIN child_serial c ON p.id = c.parent_id
WHERE p.value > 300 AND c.active = true
ORDER BY p.value DESC
LIMIT 200;

-- JOINS COM UUID
\echo 'Query 4: Join Simples com UUID'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.name, c.description 
FROM parent_uuid p 
JOIN child_uuid c ON p.id = c.parent_id 
WHERE p.value > 500
LIMIT 100;

\echo 'Query 5: Join Complexo com UUID'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.name, COUNT(c.id) as child_count, AVG(p.value) as avg_value
FROM parent_uuid p 
LEFT JOIN child_uuid c ON p.id = c.parent_id 
WHERE p.value BETWEEN 200 AND 800
GROUP BY p.name 
ORDER BY child_count DESC
LIMIT 100;

\echo 'Query 6: Join com Multiplas Condições usando UUID'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.name, c.description, c.active
FROM parent_uuid p
JOIN child_uuid c ON p.id = c.parent_id
WHERE p.value > 300 AND c.active = true
ORDER BY p.value DESC
LIMIT 200;

-- QUERIES COM AGREGAÇÕES E JOINS PESADOS
\echo 'Query 7: Agregação Pesada com ID Serial'
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.value / 100 as value_group,
    COUNT(DISTINCT p.id) as unique_parents,
    COUNT(c.id) as total_children,
    AVG(p.value) as avg_value,
    MAX(p.value) as max_value,
    MIN(p.value) as min_value
FROM 
    parent_serial p
LEFT JOIN 
    child_serial c ON p.id = c.parent_id
GROUP BY 
    value_group
ORDER BY 
    value_group;

\echo 'Query 8: Agregação Pesada com UUID'
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.value / 100 as value_group,
    COUNT(DISTINCT p.id) as unique_parents,
    COUNT(c.id) as total_children,
    AVG(p.value) as avg_value,
    MAX(p.value) as max_value,
    MIN(p.value) as min_value
FROM 
    parent_uuid p
LEFT JOIN 
    child_uuid c ON p.id = c.parent_id
GROUP BY 
    value_group
ORDER BY 
    value_group;

-- QUERIES COM MÚLTIPLOS JOINS
\echo 'Query 9: Múltiplos Joins com ID Serial'
EXPLAIN (ANALYZE, BUFFERS)
WITH active_children AS (
    SELECT parent_id, COUNT(*) as active_count
    FROM child_serial 
    WHERE active = true
    GROUP BY parent_id
)
SELECT 
    p.id, 
    p.name, 
    p.value, 
    COUNT(c.id) as total_children,
    COALESCE(ac.active_count, 0) as active_children,
    ROUND(COALESCE(ac.active_count, 0)::numeric / COUNT(c.id) * 100, 2) as active_percentage
FROM 
    parent_serial p
LEFT JOIN 
    child_serial c ON p.id = c.parent_id
LEFT JOIN 
    active_children ac ON p.id = ac.parent_id
WHERE 
    p.value > 200
GROUP BY 
    p.id, p.name, p.value, ac.active_count
ORDER BY 
    active_percentage DESC NULLS LAST
LIMIT 100;

\echo 'Query 10: Múltiplos Joins com UUID'
EXPLAIN (ANALYZE, BUFFERS)
WITH active_children AS (
    SELECT parent_id, COUNT(*) as active_count
    FROM child_uuid 
    WHERE active = true
    GROUP BY parent_id
)
SELECT 
    p.id, 
    p.name, 
    p.value, 
    COUNT(c.id) as total_children,
    COALESCE(ac.active_count, 0) as active_children,
    ROUND(COALESCE(ac.active_count, 0)::numeric / COUNT(c.id) * 100, 2) as active_percentage
FROM 
    parent_uuid p
LEFT JOIN 
    child_uuid c ON p.id = c.parent_id
LEFT JOIN 
    active_children ac ON p.id = ac.parent_id
WHERE 
    p.value > 200
GROUP BY 
    p.id, p.name, p.value, ac.active_count
ORDER BY 
    active_percentage DESC NULLS LAST
LIMIT 100;