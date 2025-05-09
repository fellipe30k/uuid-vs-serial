#!/usr/bin/env ruby
require 'pg'
require 'benchmark'
require 'securerandom'
require 'logger'
require 'json'
require 'terminal-table'
require 'fileutils'

# Configuração de logging
$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO
$logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

# Configurações de conexão - usando variáveis de ambiente do Docker
DB_CONFIG = {
  host: ENV['DB_HOST'] || 'postgres',
  port: (ENV['DB_PORT'] || '5432').to_i,
  user: ENV['DB_USER'] || 'postgres',
  password: ENV['DB_PASSWORD'] || 'postgres',
  dbname: ENV['DB_NAME'] || 'performance_test'
}

# Diretório para salvar resultados
RESULTS_DIR = 'results'
FileUtils.mkdir_p(RESULTS_DIR)

class PgPerformanceTest
  BATCH_SIZE = 10000 # Inserir em lotes para melhor performance
  TOTAL_RECORDS = ENV['TOTAL_RECORDS'] ? ENV['TOTAL_RECORDS'].to_i : 1_000_000
  TEST_ITERATIONS = ENV['TEST_ITERATIONS'] ? ENV['TEST_ITERATIONS'].to_i : 5

  def initialize
    @conn = PG.connect(DB_CONFIG)
    @results = {
      metadata: {
        timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        total_records: TOTAL_RECORDS,
        iterations: TEST_ITERATIONS
      },
      db_version: nil,
      uuid_v7_available: false,
      table_stats: {},
      index_stats: {},
      test_results: []
    }
    
    @conn.exec("SELECT version()") do |result|
      version = result[0]['version']
      @results[:db_version] = version
      $logger.info("Conectado ao PostgreSQL: #{version}")
      
      # Verificar se estamos usando PostgreSQL 17
      if !version.include?('PostgreSQL 17')
        $logger.warn("ATENÇÃO: Você não está usando PostgreSQL 17. UUID v7 pode não estar disponível.")
      end
    end
    
    # Verificar se UUID v7 está disponível
    begin
      @conn.exec("SELECT uuid_generate_v7()")
      @uuid_v7_available = true
      @results[:uuid_v7_available] = true
      $logger.info("UUID v7 está disponível!")
    rescue PG::UndefinedFunction
      @uuid_v7_available = false
      @results[:uuid_v7_available] = false
      $logger.warn("UUID v7 não está disponível. Usando UUID v4 como alternativa.")
    end
  end

  def setup_tables
    # Limpar tabelas existentes, se houver
    drop_tables

    $logger.info("Criando tabelas com ID Serial...")
    # Tabelas com ID Serial
    @conn.exec(<<-SQL)
      CREATE TABLE parent_serial (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        value INTEGER
      )
    SQL

    @conn.exec(<<-SQL)
      CREATE TABLE child_serial (
        id SERIAL PRIMARY KEY,
        parent_id INTEGER REFERENCES parent_serial(id),
        description VARCHAR(200),
        active BOOLEAN
      )
    SQL

    $logger.info("Criando tabelas com UUID...")
    # Tabelas com UUID
    if @uuid_v7_available
      # Usar UUID v7 para melhor performance (PostgreSQL 17)
      @conn.exec(<<-SQL)
        CREATE TABLE parent_uuid (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
          name VARCHAR(100),
          value INTEGER
        )
      SQL

      @conn.exec(<<-SQL)
        CREATE TABLE child_uuid (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
          parent_id UUID REFERENCES parent_uuid(id),
          description VARCHAR(200),
          active BOOLEAN
        )
      SQL
    else
      # Fallback para UUID v4
      @conn.exec(<<-SQL)
        CREATE TABLE parent_uuid (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          name VARCHAR(100),
          value INTEGER
        )
      SQL

      @conn.exec(<<-SQL)
        CREATE TABLE child_uuid (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          parent_id UUID REFERENCES parent_uuid(id),
          description VARCHAR(200),
          active BOOLEAN
        )
      SQL
    end

    # Criar índices adicionais para melhorar a performance de joins
    @conn.exec("CREATE INDEX idx_child_serial_parent_id ON child_serial(parent_id)")
    @conn.exec("CREATE INDEX idx_child_uuid_parent_id ON child_uuid(parent_id)")
  end

  def drop_tables
    @conn.exec("DROP TABLE IF EXISTS child_serial CASCADE")
    @conn.exec("DROP TABLE IF EXISTS parent_serial CASCADE")
    @conn.exec("DROP TABLE IF EXISTS child_uuid CASCADE")
    @conn.exec("DROP TABLE IF EXISTS parent_uuid CASCADE")
  end

  def populate_tables
    # Inserir dados nas tabelas SERIAL
    $logger.info("Inserindo #{TOTAL_RECORDS} registros nas tabelas SERIAL...")
    populate_serial_tables

    # Inserir dados nas tabelas UUID
    $logger.info("Inserindo #{TOTAL_RECORDS} registros nas tabelas UUID...")
    populate_uuid_tables

    # Estatísticas das tabelas
    $logger.info("Estatísticas das tabelas após inserção:")
    collect_table_stats
  end

  def populate_serial_tables
    # Inserir dados na tabela pai
    (1..TOTAL_RECORDS).each_slice(BATCH_SIZE) do |batch|
      values = batch.map { |i| "(#{i}, 'Nome #{i}', #{rand(1000)})" }.join(',')
      @conn.exec("INSERT INTO parent_serial (id, name, value) VALUES #{values}")
      
      print "." if batch.first % 100000 == 0
    end
    puts

    # Inserir dados na tabela filha (cerca de 2 filhos por pai em média)
    @conn.exec("SELECT setval('child_serial_id_seq', 1, false)") # Reset sequência
    
    (1..TOTAL_RECORDS).each_slice(BATCH_SIZE) do |batch|
      # Cada registro pai terá entre 1-3 filhos
      child_values = []
      
      batch.each do |parent_id|
        num_children = rand(1..3)
        num_children.times do
          child_values << "(nextval('child_serial_id_seq'), #{parent_id}, 'Descrição para #{parent_id}', #{[true, false].sample})"
        end
      end
      
      unless child_values.empty?
        @conn.exec("INSERT INTO child_serial (id, parent_id, description, active) VALUES #{child_values.join(',')}")
      end
      
      print "." if batch.first % 100000 == 0
    end
    puts
  end

  def populate_uuid_tables
    # Inserir registros na tabela parent_uuid
    parent_uuids = []
    
    (0...TOTAL_RECORDS).each_slice(BATCH_SIZE) do |batch|
      batch_values = []
      batch_uuids = []
      
      batch.each do |_|
        # Gerar UUID usando a função do PostgreSQL
        uuid = nil
        @conn.exec("SELECT #{@uuid_v7_available ? 'uuid_generate_v7()' : 'uuid_generate_v4()'} AS uuid") do |result|
          uuid = result[0]['uuid']
        end
        
        batch_uuids << uuid
        batch_values << "('#{uuid}', 'Nome UUID #{parent_uuids.size + batch_uuids.size}', #{rand(1000)})"
      end
      
      @conn.exec("INSERT INTO parent_uuid (id, name, value) VALUES #{batch_values.join(',')}")
      parent_uuids.concat(batch_uuids)
      
      print "." if batch.first % 100000 == 0
    end
    puts
    
    # Inserir registros na tabela child_uuid
    (0...parent_uuids.size).each_slice(BATCH_SIZE) do |batch_indices|
      child_values = []
      
      batch_indices.each do |idx|
        parent_id = parent_uuids[idx]
        num_children = rand(1..3)
        
        num_children.times do
          # Gerar UUID para o filho
          child_uuid = nil
          @conn.exec("SELECT #{@uuid_v7_available ? 'uuid_generate_v7()' : 'uuid_generate_v4()'} AS uuid") do |result|
            child_uuid = result[0]['uuid']
          end
          
          child_values << "('#{child_uuid}', '#{parent_id}', 'Descrição UUID para #{idx}', #{[true, false].sample})"
        end
      end
      
      unless child_values.empty?
        @conn.exec("INSERT INTO child_uuid (id, parent_id, description, active) VALUES #{child_values.join(',')}")
      end
      
      print "." if batch_indices.first % 100000 == 0
    end
    puts
  end

  def collect_table_stats
    table_stats = {}
    
    # Coletar estatísticas das tabelas
    ['parent_serial', 'child_serial', 'parent_uuid', 'child_uuid'].each do |table|
      stats = {}
      
      # Número de registros
      @conn.exec("SELECT COUNT(*) FROM #{table}") do |result|
        count = result[0]['count'].to_i
        stats['row_count'] = count
        $logger.info("Registros em #{table}: #{count}")
      end
      
      # Tamanho da tabela
      @conn.exec("SELECT pg_size_pretty(pg_relation_size('#{table}')) as size") do |result|
        stats['table_size'] = result[0]['size']
        $logger.info("Tamanho de #{table}: #{result[0]['size']}")
      end
      
      # Tamanho total (tabela + índices)
      @conn.exec("SELECT pg_size_pretty(pg_total_relation_size('#{table}')) as total_size") do |result|
        stats['total_size'] = result[0]['total_size']
        $logger.info("Tamanho total de #{table} (com índices): #{result[0]['total_size']}")
      end
      
      table_stats[table] = stats
    end
    
    @results[:table_stats] = table_stats
    
    # Coletar estatísticas dos índices
    index_stats = {}
    
    @conn.exec(<<-SQL) do |result|
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
        pg_relation_size(i.indexrelid) DESC
    SQL
      result.each do |row|
        index_stats[row['index_name']] = {
          'index_size' => row['index_size'],
          'index_scans' => row['index_scans'].to_i
        }
        $logger.info("Índice #{row['index_name']}: #{row['index_size']}")
      end
    end
    
    @results[:index_stats] = index_stats
  end

  def run_performance_tests
    $logger.info("Realizando testes de performance...")
    
    # Limpar cache do PostgreSQL para testes mais justos
    @conn.exec("DISCARD ALL")
    
    # Definir consultas para testar
    test_queries = [
      {
        name: "Join Simples - Serial",
        query: "SELECT p.id, p.name, c.description FROM parent_serial p JOIN child_serial c ON p.id = c.parent_id WHERE p.value > 500 LIMIT 1000",
        type: "serial"
      },
      {
        name: "Join Simples - UUID",
        query: "SELECT p.id, p.name, c.description FROM parent_uuid p JOIN child_uuid c ON p.id = c.parent_id WHERE p.value > 500 LIMIT 1000",
        type: "uuid"
      },
      {
        name: "Join Complexo - Serial",
        query: "SELECT p.name, COUNT(c.id) as child_count, AVG(p.value) as avg_value FROM parent_serial p LEFT JOIN child_serial c ON p.id = c.parent_id WHERE p.value BETWEEN 200 AND 800 GROUP BY p.name ORDER BY child_count DESC LIMIT 100",
        type: "serial"
      },
      {
        name: "Join Complexo - UUID",
        query: "SELECT p.name, COUNT(c.id) as child_count, AVG(p.value) as avg_value FROM parent_uuid p LEFT JOIN child_uuid c ON p.id = c.parent_id WHERE p.value BETWEEN 200 AND 800 GROUP BY p.name ORDER BY child_count DESC LIMIT 100",
        type: "uuid"
      },
      {
        name: "Múltiplos Joins - Serial",
        query: "WITH active_children AS (SELECT parent_id, COUNT(*) as active_count FROM child_serial WHERE active = true GROUP BY parent_id) SELECT p.id, p.name, p.value, COUNT(c.id) as total_children, COALESCE(ac.active_count, 0) as active_children FROM parent_serial p LEFT JOIN child_serial c ON p.id = c.parent_id LEFT JOIN active_children ac ON p.id = ac.parent_id WHERE p.value > 200 GROUP BY p.id, p.name, p.value, ac.active_count ORDER BY p.value DESC LIMIT 100",
        type: "serial"
      },
      {
        name: "Múltiplos Joins - UUID",
        query: "WITH active_children AS (SELECT parent_id, COUNT(*) as active_count FROM child_uuid WHERE active = true GROUP BY parent_id) SELECT p.id, p.name, p.value, COUNT(c.id) as total_children, COALESCE(ac.active_count, 0) as active_children FROM parent_uuid p LEFT JOIN child_uuid c ON p.id = c.parent_id LEFT JOIN active_children ac ON p.id = ac.parent_id WHERE p.value > 200 GROUP BY p.id, p.name, p.value, ac.active_count ORDER BY p.value DESC LIMIT 100",
        type: "uuid"
      }
    ]
    
    # Armazenar resultados dos testes
    test_results = []
    
    # Executar cada consulta várias vezes
    test_queries.each do |test|
      $logger.info("\nExecutando teste: #{test[:name]}")
      
      times = []
      execution_plans = []
      
      TEST_ITERATIONS.times do |i|
        # Limpar cache entre execuções
        @conn.exec("DISCARD ALL") if i > 0
        
        # Executar consulta com EXPLAIN ANALYZE
        explain_query = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{test[:query]}"
        
        time = Benchmark.realtime do
          @conn.exec(explain_query) do |result|
            execution_plan = JSON.parse(result[0]['QUERY PLAN'])
            execution_plans << execution_plan if i == 0  # Salvar apenas o primeiro plano para economizar espaço
          end
        end
        
        times << time
        $logger.info("  Iteração #{i+1}: #{(time * 1000).round(2)} ms")
      end
      
      # Calcular estatísticas
      avg_time = times.sum / times.size
      min_time = times.min
      max_time = times.max
      std_dev = Math.sqrt(times.map { |t| (t - avg_time) ** 2 }.sum / times.size)
      
      $logger.info("  Média: #{(avg_time * 1000).round(2)} ms")
      $logger.info("  Min: #{(min_time * 1000).round(2)} ms, Max: #{(max_time * 1000).round(2)} ms")
      $logger.info("  Desvio padrão: #{(std_dev * 1000).round(2)} ms")
      
      # Armazenar resultados
      test_results << {
        name: test[:name],
        type: test[:type],
        query: test[:query],
        avg_time_ms: (avg_time * 1000).round(2),
        min_time_ms: (min_time * 1000).round(2),
        max_time_ms: (max_time * 1000).round(2),
        std_dev_ms: (std_dev * 1000).round(2),
        execution_plan: execution_plans.first
      }
    end
    
    @results[:test_results] = test_results
    
    # Calcular e exibir comparações
    show_comparative_results(test_results)
  end
  
  def show_comparative_results(test_results)
    $logger.info("\n=== RESULTADOS COMPARATIVOS ===")
    
    # Agrupar resultados por tipo de teste
    grouped_results = test_results.group_by { |r| r[:name].split(' - ').first }
    
    comparison_data = []
    
    grouped_results.each do |test_type, results|
      serial_result = results.find { |r| r[:type] == 'serial' }
      uuid_result = results.find { |r| r[:type] == 'uuid' }
      
      if serial_result && uuid_result
        diff_percent = ((uuid_result[:avg_time_ms] / serial_result[:avg_time_ms]) - 1) * 100
        
        comparison_data << {
          test_type: test_type,
          serial_time: serial_result[:avg_time_ms],
          uuid_time: uuid_result[:avg_time_ms],
          diff_percent: diff_percent.round(2)
        }
        
        $logger.info("#{test_type}:")
        $logger.info("  Serial: #{serial_result[:avg_time_ms]} ms")
        $logger.info("  UUID: #{uuid_result[:avg_time_ms]} ms")
        $logger.info("  Diferença: UUID é #{diff_percent.round(2)}% #{diff_percent > 0 ? 'mais lento' : 'mais rápido'}")
      end
    end
    
    # Criar tabela comparativa
    table = Terminal::Table.new do |t|
      t.title = "Comparação de Performance"
      t.headings = ['Tipo de Teste', 'ID Serial (ms)', 'UUID (ms)', 'Diferença (%)']
      
      comparison_data.each do |data|
        diff_str = data[:diff_percent] > 0 ? "+#{data[:diff_percent]}%" : "#{data[:diff_percent]}%"
        t << [data[:test_type], data[:serial_time], data[:uuid_time], diff_str]
      end
    end
    
    $logger.info("\n#{table}")
    
    @results[:comparative_results] = comparison_data
  end
  
  def vacuum_tables
    $logger.info("Executando VACUUM ANALYZE nas tabelas...")
    @conn.exec("VACUUM ANALYZE parent_serial")
    @conn.exec("VACUUM ANALYZE child_serial")
    @conn.exec("VACUUM ANALYZE parent_uuid")
    @conn.exec("VACUUM ANALYZE child_uuid")
  end
  
  def save_results
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    filename = "#{RESULTS_DIR}/performance_results_#{timestamp}.json"
    
    File.open(filename, 'w') do |file|
      file.write(JSON.pretty_generate(@results))
    end
    
    $logger.info("Resultados salvos em #{filename}")
    
    # Criar um arquivo de resumo em TXT
    summary_filename = "#{RESULTS_DIR}/performance_summary_#{timestamp}.txt"
    
    File.open(summary_filename, 'w') do |file|
      file.puts "=== RESUMO DE PERFORMANCE: ID SERIAL VS UUID ==="
      file.puts "Data: #{@results[:metadata][:timestamp]}"
      file.puts "PostgreSQL: #{@results[:db_version]}"
      file.puts "UUID v7 disponível: #{@results[:uuid_v7_available]}"
      file.puts "Total de registros: #{@results[:metadata][:total_records]}"
      file.puts "\n=== ESTATÍSTICAS DAS TABELAS ==="
      
      @results[:table_stats].each do |table, stats|
        file.puts "#{table}:"
        file.puts "  Registros: #{stats['row_count']}"
        file.puts "  Tamanho: #{stats['table_size']}"
        file.puts "  Tamanho total (com índices): #{stats['total_size']}"
      end
      
      file.puts "\n=== RESULTADOS COMPARATIVOS ==="
      
      @results[:comparative_results].each do |data|
        file.puts "#{data[:test_type]}:"
        file.puts "  Serial: #{data[:serial_time]} ms"
        file.puts "  UUID: #{data[:uuid_time]} ms"
        file.puts "  Diferença: UUID é #{data[:diff_percent]}% #{data[:diff_percent] > 0 ? 'mais lento' : 'mais rápido'}"
      end
    end
    
    $logger.info("Resumo salvo em #{summary_filename}")
  end

  def run_test
    begin
      start_time = Time.now
      $logger.info("Iniciando teste de performance em #{start_time}")
      
      # Preparar as tabelas
      setup_tables
      
      # Popular com registros
      populate_tables
      
      # Executar VACUUM para estatísticas atualizadas
      vacuum_tables
      
      # Rodar testes de performance
      run_performance_tests
      
      # Salvar resultados
      save_results
      
      end_time = Time.now
      duration = (end_time - start_time) / 60.0  # em minutos
      $logger.info("Teste concluído em #{end_time}. Duração total: #{duration.round(2)} minutos")
      
    rescue PG::Error => e
      $logger.error("Erro de PostgreSQL: #{e.message}")
      $logger.error(e.backtrace.join("\n"))
    rescue StandardError => e
      $logger.error("Erro: #{e.message}")
      $logger.error(e.backtrace.join("\n"))
    ensure
      @conn.close if @conn
    end
  end
end

# Executar o teste
$logger.info("Iniciando teste de performance PostgreSQL: Serial ID vs UUID")
tester = PgPerformanceTest.new
tester.run_test