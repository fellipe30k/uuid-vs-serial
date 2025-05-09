.PHONY: build up start stop down clean test create-db run-test psql exec-psql query stats

# Variáveis
CONTAINER_POSTGRES = postgres_performance_test
CONTAINER_RUNNER = postgres_test_runner
DB_NAME = performance_test
DB_USER = postgres
DB_PASSWORD = postgres

# Construir imagens
build:
	@echo "Construindo imagens do Docker..."
	docker-compose build

# Iniciar containers
up:
	@echo "Iniciando containers..."
	docker-compose up -d

# Iniciar apenas o PostgreSQL
start-postgres:
	@echo "Iniciando container PostgreSQL..."
	docker-compose up -d postgres

# Parar containers
stop:
	@echo "Parando containers..."
	docker-compose stop

# Destruir containers
down:
	@echo "Removendo containers..."
	docker-compose down

# Limpar volumes e dados
clean:
	@echo "Limpando volumes e dados..."
	docker-compose down -v

# Criar base de dados e estrutura
create-db:
	@echo "Criando estrutura de banco de dados..."
	# Copia o schema.sql para o container
	docker cp schema.sql $(CONTAINER_POSTGRES):/tmp/schema.sql
	# Executa o script SQL
	docker-compose exec postgres psql -U $(DB_USER) -d $(DB_NAME) -f /tmp/schema.sql

# Executar teste completo (subir, criar DB, rodar teste)
test: up create-db run-test

# Executar apenas o teste de performance
run-test:
	@echo "Executando teste de performance..."
	docker-compose run --rm test_runner ruby performance_test.rb

# Entrar no psql
psql:
	@echo "Conectando ao PostgreSQL..."
	docker exec -it $(CONTAINER_POSTGRES) psql -U $(DB_USER) -d $(DB_NAME)

# Executar um arquivo SQL
exec-psql:
	@echo "Executando arquivo SQL..."
	@if [ -z "$(FILE)" ]; then \
		echo "Por favor, especifique o arquivo com FILE=caminho/do/arquivo.sql"; \
	else \
		docker cp $(FILE) $(CONTAINER_POSTGRES):/tmp/query.sql; \
		docker exec -i $(CONTAINER_POSTGRES) psql -U $(DB_USER) -d $(DB_NAME) -f /tmp/query.sql; \
	fi

# Executar uma query específica
query:
	@echo "Executando consulta SQL..."
	@docker exec -it $(CONTAINER_POSTGRES) psql -U $(DB_USER) -d $(DB_NAME) -c "$(SQL)"

# Mostrar estatísticas de tabelas
stats:
	@echo "Estatísticas das tabelas..."
	@docker exec -it $(CONTAINER_POSTGRES) psql -U $(DB_USER) -d $(DB_NAME) -c "\
		SELECT \
			table_name, \
			pg_size_pretty(pg_relation_size(quote_ident(table_name))) as table_size, \
			pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) as total_size, \
			(SELECT count(*) FROM $(table_name)) as row_count \
		FROM \
			information_schema.tables \
		WHERE \
			table_schema = 'public' \
		ORDER BY \
			pg_relation_size(quote_ident(table_name)) DESC;"

# Executar queries do arquivo psql_queries.sql
run-queries:
	@echo "Executando queries de teste..."
	docker cp psql_queries.sql $(CONTAINER_POSTGRES):/tmp/psql_queries.sql
	docker exec -it $(CONTAINER_POSTGRES) psql -U $(DB_USER) -d $(DB_NAME) -f /tmp/psql_queries.sql

# Mostrar ajuda
help:
	@echo "Comandos disponíveis:"
	@echo "  make build              - Construir imagens Docker"
	@echo "  make up                 - Iniciar todos os containers"
	@echo "  make start-postgres     - Iniciar apenas o PostgreSQL"
	@echo "  make stop               - Parar containers"
	@echo "  make down               - Remover containers"
	@echo "  make clean              - Limpar volumes e dados"
	@echo "  make create-db          - Criar estrutura do banco"
	@echo "  make test               - Executar teste completo"
	@echo "  make run-test           - Executar apenas o teste"
	@echo "  make psql               - Entrar no psql"
	@echo "  make exec-psql FILE=arquivo.sql - Executar arquivo SQL"
	@echo "  make query SQL=\"SELECT * FROM tabela;\" - Executar query"
	@echo "  make stats              - Mostrar estatísticas das tabelas"
	@echo "  make run-queries        - Executar queries de teste do arquivo psql_queries.sql"