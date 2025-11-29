# Configuração para Railway

Este documento contém instruções para fazer o deploy desta aplicação no Railway.

## Arquivos Criados

Foram criados os seguintes arquivos para suportar o deploy no Railway:

1. **Dockerfile** - Dockerfile na raiz para build da aplicação
2. **railway.json** - Configuração JSON para Railway
3. **railway.toml** - Configuração TOML para Railway (alternativa)
4. **nixpacks.toml** - Configuração para Nixpacks (se Railway usar Nixpacks)
5. **start.sh** - Script de inicialização (se necessário)

## Variáveis de Ambiente no Railway

Configure as seguintes variáveis de ambiente no Railway:

### Obrigatórias
- `PORT` - Porta da aplicação (Railway define automaticamente, a app agora lê `PORT` ou `APP_PORT`)
- `DB_URI` - URI do banco de dados (use PostgreSQL do Railway)
  - Exemplo: `postgres://user:pass@host:5432/dbname`

### Opcionais (mas recomendadas)
- `APP_DEBUG` - `true` ou `false` (padrão: `false`)
- `APP_BASIC_AUTH` - Credenciais de autenticação (formato: `user:pass,user2:pass2`)
- `WHATSAPP_WEBHOOK` - URL(s) do webhook (separadas por vírgula)
- `WHATSAPP_WEBHOOK_SECRET` - Chave secreta para HMAC (padrão: `secret`)
- `WHATSAPP_AUTO_REPLY` - Mensagem de auto-resposta
- `WHATSAPP_AUTO_MARK_READ` - `true` ou `false` (padrão: `false`)
- `WHATSAPP_AUTO_DOWNLOAD_MEDIA` - `true` ou `false` (padrão: `true`)

## Configuração da Porta

O Railway define automaticamente a variável `PORT`. A aplicação foi modificada para ler `PORT` 
automaticamente (com fallback para `APP_PORT` se `PORT` não estiver definido). 
**Não é necessário configurar nada** - o Railway já define `PORT` automaticamente.

## Banco de Dados

### PostgreSQL (Recomendado para Railway)
1. Adicione um serviço PostgreSQL no Railway
2. Configure `DB_URI` com a connection string fornecida pelo Railway
3. Formato: `postgres://user:password@host:5432/database`

### SQLite (Não recomendado para produção)
Se usar SQLite, você precisará de um volume persistente para `/app/storages`

## Volumes Persistentes

Configure um volume persistente para:
- `/app/storages` - Armazena dados do WhatsApp (sessões, banco SQLite se usado)

## Build e Deploy

O Railway detectará automaticamente o Dockerfile na raiz e fará o build.

### Se usar Nixpacks
O Railway pode usar Nixpacks se não detectar Dockerfile. Neste caso, use o `nixpacks.toml`.

### Se usar Dockerfile (recomendado)
O Railway usará o `Dockerfile` na raiz automaticamente.

## Comandos de Build

O Dockerfile já está configurado para:
1. Build da aplicação Go
2. Incluir FFmpeg (necessário para processamento de mídia)
3. Criar diretórios necessários
4. Executar `whatsapp rest` como comando padrão

## Troubleshooting

### Erro: "Railpack could not determine how to build"
- Certifique-se de que o `Dockerfile` está na raiz do projeto
- Verifique se o `.dockerignore` não está ignorando arquivos necessários

### Erro: "Port already in use"
- Configure `APP_PORT=$PORT` no Railway
- Ou modifique o código para usar `PORT` diretamente

### Erro: "Database connection failed"
- Verifique se o `DB_URI` está correto
- Certifique-se de que o PostgreSQL está rodando no Railway

### Erro: "FFmpeg not found"
- O Dockerfile já inclui FFmpeg, mas se houver problemas, verifique a instalação

## Notas Importantes

1. **Sessão do WhatsApp**: A sessão do WhatsApp é armazenada em `/app/storages`. 
   Use um volume persistente para manter a sessão entre deploys.

2. **Banco de Dados**: Para produção, use PostgreSQL. SQLite pode ter problemas 
   com múltiplas instâncias ou reinicializações.

3. **Porta**: O Railway define `PORT` automaticamente. Configure `APP_PORT=$PORT` 
   ou modifique o código para ler `PORT` diretamente.

4. **FFmpeg**: Necessário para processamento de mídia. Já incluído no Dockerfile.

