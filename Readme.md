# Teste de Performance: ID Serial vs UUID no PostgreSQL 17

Este projeto contém um ambiente completo para testar e comparar a performance de joins usando ID Serial vs UUID no PostgreSQL 17. O teste insere 1 milhão de registros em tabelas com diferentes tipos de ID e executa diversos tipos de joins para medir o desempenho.

## Estrutura do Projeto

```
.
├── docker-compose.yml     # Configuração dos containers
├── Dockerfile             # Configuração do ambiente Ruby
├── Gemfile                # Dependências Ruby
├── Makefile               # Automação de comandos
├── init-scripts/          # Scripts executados na inicialização do PostgreSQL
│   └── 01-setup-extensions.sql
├── performance_test.rb    # Script Ruby que executa os testes
├── psql_queries.sql       # Queries PSQL para testes livres
├── results/               # Diretório para armazenar resultados
└── schema.sql             # Script de criação da estrutura do banco
```

## Requisitos

- Docker
- Docker Compose
- Make (opcional, mas recomendado)

## Uso Rápido

Para executar o teste completo:

```bash
make test
```

Este comando irá:
1. Iniciar os containers (PostgreSQL 17 e Ruby)
2. Criar a estrutura do banco de dados
3. Executar o teste de performance com 1 milhão de registros

## Comandos Disponíveis

Utilize o Makefile para facilitar a execução dos comandos:

```bash
# Construir as imagens Docker
make build

# Iniciar todos os containers
make up

# Iniciar apenas o PostgreSQL
make start-postgres

# Parar os containers
make stop

# Remover os containers
make down

# Limpar volumes e dados
make clean

# Criar estrutura do banco
make create-db

# Executar teste completo
make test

# Executar apenas o teste
make run-test

# Entrar no psql
make psql

# Executar arquivo SQL específico
make exec-psql FILE=caminho/do/arquivo.sql

# Executar query específica
make query SQL="SELECT * FROM parent_serial LIMIT 10;"

# Mostrar estatísticas das tabelas
make stats

# Mostrar ajuda
make help
```

## Executando Queries PSQL

Para executar as queries definidas em `psql_queries.sql`:

```bash
make exec-psql FILE=psql_queries.sql
```

## Detalhes da Implementação

### Tabelas de Teste

- **ID Serial**: `parent_serial` e `child_serial`
- **UUID**: `parent_uuid` e `child_uuid` (usando UUID v7 no PostgreSQL 17)

Cada tabela possui 3 colunas:
- Tabelas pai: id, name, value
- Tabelas filho: id, parent_id, description, active

### Tipos de Joins Testados

1. **Join Simples**: Joining parent e child com uma condição simples
2. **Join Complexo**: Join com grupamento, ordenação e limite
3. **Agregações**: Join com funções de agregação (COUNT, AVG, MAX, MIN)
4. **Múltiplos Joins**: Queries complexas com CTEs e múltiplos joins

## Visualização dos Resultados

Os resultados dos testes são exibidos no console durante a execução do script Ruby e também salvos no diretório `results/`.

## Notas de Uso

- O script está configurado para inserir 1 milhão de registros, o que pode levar algum tempo
- Você pode ajustar o número de registros alterando a constante `TOTAL_RECORDS` no arquivo `performance_test.rb`
- O PostgreSQL está configurado com parâmetros otimizados para testes de performance
- UUID v7 é uma funcionalidade do PostgreSQL 17. Se estiver usando uma versão anterior, o script criará uma função de compatibilidade

---

+--------------------------------------------------------------+
|                  Comparação de Performance                   |
+-----------------+----------------+-----------+---------------+
| Tipo de Teste   | ID Serial (ms) | UUID (ms) | Diferença (%) |
+-----------------+----------------+-----------+---------------+
| Join Simples    | 0.95           | 2.64      | +177.89%      |
| Join Complexo   | 1287.0         | 1373.71   | +6.74%        |
| Múltiplos Joins | 1660.2         | 2490.19   | +49.99%       |
+-----------------+----------------+-----------+---------------+

*Este projeto foi criado para fins de teste e benchmark. Os resultados podem variar dependendo do hardware e configuração do sistema.*
