FROM ruby:3.2-alpine

# Instalar dependências do sistema
RUN apk add --no-cache build-base postgresql-dev postgresql-client

# Definir diretório de trabalho
WORKDIR /app

# Copiar arquivos de dependências
COPY Gemfile* ./

# Instalar gems
RUN bundle install

# Copiar todos os outros arquivos
COPY . .

# Criar diretório para resultados
RUN mkdir -p /app/results

# Executar por padrão o teste de performance
CMD ["ruby", "performance_test.rb"]