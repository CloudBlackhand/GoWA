# Plano de Implementação: Multi-Sessão no GoWA com Dashboard

## 📋 Objetivo

Transformar o GoWA em uma solução que combine:
- ✅ **Baixo consumo de memória do GoWA** (~15MB por sessão)
- ✅ **Suporte nativo a múltiplas sessões** (como WAHA)
- ✅ **Dashboard web** para gerenciamento de sessões
- ✅ **API REST** com suporte a `session_id`

## 🔍 Análise da Situação Atual

### GoWA (Atual)
- ✅ Consumo: ~15MB por sessão
- ❌ Single-instance: apenas 1 sessão por instância
- ❌ Sem dashboard
- ✅ API REST completa
- ✅ Suporte MCP

### WAHA (Referência)
- ❌ Consumo: ~100-200MB por sessão
- ✅ Multi-instance: múltiplas sessões nativas
- ✅ Dashboard web completo
- ✅ API REST com `session_id`
- ❌ Sem suporte MCP

## 🎯 Arquitetura Proposta

### 1. Gerenciador de Sessões

```
┌─────────────────────────────────────────────────────────┐
│              Session Manager (Singleton)                 │
│  ┌──────────────────────────────────────────────────┐   │
│  │  sessions: map[string]*WhatsAppSession          │   │
│  │  - session_id_1 -> *whatsmeow.Client            │   │
│  │  - session_id_2 -> *whatsmeow.Client            │   │
│  │  - session_id_3 -> *whatsmeow.Client            │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 2. Estrutura de Dados

```go
type SessionManager struct {
    sessions map[string]*WhatsAppSession
    mu       sync.RWMutex
    db       *sqlstore.Container
}

type WhatsAppSession struct {
    ID          string
    Client      *whatsmeow.Client
    DB          *sqlstore.Container
    KeysDB      *sqlstore.Container
    ChatStorage domainChatStorage.IChatStorageRepository
    Status      SessionStatus
    CreatedAt   time.Time
    LastActive  time.Time
}

type SessionStatus string
const (
    StatusDisconnected SessionStatus = "disconnected"
    StatusConnecting   SessionStatus = "connecting"
    StatusConnected    SessionStatus = "connected"
    StatusLoggedIn     SessionStatus = "logged_in"
)
```

## 📐 Plano de Implementação

### Fase 1: Refatoração do Core (Semana 1-2)

#### 1.1 Criar Session Manager
**Arquivo:** `src/infrastructure/session/manager.go`

```go
package session

type Manager interface {
    CreateSession(sessionID string, dbURI string) (*WhatsAppSession, error)
    GetSession(sessionID string) (*WhatsAppSession, error)
    DeleteSession(sessionID string) error
    ListSessions() []*SessionInfo
    GetSessionStatus(sessionID string) (SessionStatus, error)
}
```

**Responsabilidades:**
- Gerenciar ciclo de vida das sessões
- Isolamento de recursos por sessão
- Limpeza automática de sessões inativas

#### 1.2 Refatorar WhatsApp Client
**Arquivo:** `src/infrastructure/whatsapp/session_client.go`

**Mudanças:**
- Remover variável global `cli`
- Cada sessão tem seu próprio cliente
- Isolamento completo de estado

**Antes:**
```go
var cli *whatsmeow.Client  // Global
```

**Depois:**
```go
type SessionClient struct {
    sessionID string
    client    *whatsmeow.Client
    db        *sqlstore.Container
    // ...
}
```

#### 1.3 Isolamento de Banco de Dados
**Estratégia:**
- Cada sessão pode ter seu próprio banco OU
- Usar schema/prefixo por sessão no mesmo banco

**Opção A: Banco separado por sessão (Recomendado)**
```
storages/
  ├── session_abc123/
  │   ├── whatsapp.db
  │   └── chatstorage.db
  ├── session_def456/
  │   ├── whatsapp.db
  │   └── chatstorage.db
```

**Opção B: Schema único com prefixo**
```sql
-- Tabelas com prefixo de sessão
CREATE TABLE session_abc123_devices (...)
CREATE TABLE session_abc123_messages (...)
```

### Fase 2: API REST Multi-Sessão (Semana 2-3)

#### 2.1 Modificar Rotas REST
**Arquivo:** `src/ui/rest/app.go`

**Antes:**
```go
app.Get("/app/login", rest.Login)
app.Get("/send/message", rest.SendMessage)
```

**Depois:**
```go
// Rotas com session_id
app.Get("/api/:session/app/login", rest.Login)
app.Get("/api/:session/send/message", rest.SendMessage)

// Rotas de gerenciamento de sessões
app.Get("/api/sessions", rest.ListSessions)
app.Post("/api/sessions", rest.CreateSession)
app.Delete("/api/sessions/:session", rest.DeleteSession)
app.Get("/api/sessions/:session/status", rest.GetSessionStatus)
```

#### 2.2 Middleware de Sessão
**Arquivo:** `src/ui/rest/middleware/session.go`

```go
func SessionMiddleware(sessionManager session.Manager) fiber.Handler {
    return func(c *fiber.Ctx) error {
        sessionID := c.Params("session")
        if sessionID == "" {
            return c.Status(400).JSON(fiber.Map{
                "error": "session_id is required",
            })
        }
        
        sess, err := sessionManager.GetSession(sessionID)
        if err != nil {
            return c.Status(404).JSON(fiber.Map{
                "error": "session not found",
            })
        }
        
        c.Locals("session", sess)
        return c.Next()
    }
}
```

#### 2.3 Atualizar Handlers
**Exemplo:** `src/ui/rest/send.go`

**Antes:**
```go
func (handler *Send) SendMessage(c *fiber.Ctx) error {
    client := whatsapp.GetClient()  // Global
    // ...
}
```

**Depois:**
```go
func (handler *Send) SendMessage(c *fiber.Ctx) error {
    sess := c.Locals("session").(*session.WhatsAppSession)
    client := sess.Client
    // ...
}
```

### Fase 3: Dashboard Web (Semana 3-4)

#### 3.1 Estrutura do Dashboard
**Arquivos:**
```
src/views/
  ├── dashboard/
  │   ├── index.html          # Página principal
  │   ├── sessions.html       # Lista de sessões
  │   ├── session-detail.html # Detalhes da sessão
  │   └── components/
  │       ├── SessionCard.js
  │       ├── SessionList.js
  │       ├── QRCodeDisplay.js
  │       └── MessageLog.js
```

#### 3.2 API do Dashboard
**Endpoints:**
```
GET  /dashboard                    # Página principal
GET  /api/dashboard/sessions       # Lista todas sessões
GET  /api/dashboard/sessions/:id   # Detalhes da sessão
POST /api/dashboard/sessions       # Criar nova sessão
DELETE /api/dashboard/sessions/:id # Deletar sessão
GET  /api/dashboard/stats          # Estatísticas gerais
```

#### 3.3 WebSocket para Dashboard
**Arquivo:** `src/ui/websocket/dashboard.go`

**Eventos:**
- `session_created` - Nova sessão criada
- `session_deleted` - Sessão deletada
- `session_status_changed` - Status da sessão mudou
- `message_received` - Nova mensagem recebida
- `connection_status` - Status de conexão

### Fase 4: Otimizações de Memória (Semana 4-5)

#### 4.1 Lazy Loading de Sessões
- Carregar sessões apenas quando necessário
- Descarregar sessões inativas após timeout

```go
func (m *Manager) GetSession(sessionID string) (*WhatsAppSession, error) {
    m.mu.RLock()
    sess, exists := m.sessions[sessionID]
    m.mu.RUnlock()
    
    if !exists {
        // Lazy load da sessão
        return m.loadSession(sessionID)
    }
    
    return sess, nil
}
```

#### 4.2 Garbage Collection de Sessões
- Remover sessões desconectadas há mais de X horas
- Limpar recursos não utilizados

```go
func (m *Manager) CleanupInactiveSessions() {
    for sessionID, sess := range m.sessions {
        if time.Since(sess.LastActive) > 24*time.Hour {
            m.DeleteSession(sessionID)
        }
    }
}
```

#### 4.3 Pool de Conexões de Banco
- Reutilizar conexões de banco
- Limitar número máximo de conexões simultâneas

### Fase 5: Migração e Compatibilidade (Semana 5-6)

#### 5.1 Modo de Compatibilidade
- Suportar APIs antigas (sem `session_id`)
- Usar sessão padrão "default"

```go
// Se não especificar session_id, usa "default"
app.Get("/app/login", func(c *fiber.Ctx) error {
    c.Params("session", "default")
    return rest.Login(c)
})
```

#### 5.2 Migração de Dados
- Script para migrar sessões existentes
- Converter banco único em múltiplos bancos

#### 5.3 Documentação
- Atualizar README
- Documentar APIs multi-sessão
- Guia de migração

## 🗂️ Estrutura de Arquivos Proposta

```
src/
├── infrastructure/
│   ├── session/
│   │   ├── manager.go           # Gerenciador de sessões
│   │   ├── session.go           # Estrutura de sessão
│   │   └── storage.go           # Armazenamento de sessões
│   └── whatsapp/
│       ├── session_client.go    # Cliente por sessão
│       └── init.go              # Refatorado (sem global)
├── ui/
│   ├── rest/
│   │   ├── session.go           # Handlers de sessão
│   │   ├── dashboard.go         # API do dashboard
│   │   └── middleware/
│   │       └── session.go       # Middleware de sessão
│   ├── websocket/
│   │   └── dashboard.go         # WebSocket do dashboard
│   └── views/
│       └── dashboard/           # Frontend do dashboard
├── domains/
│   └── session/                 # Domínio de sessão
│       ├── session.go
│       └── interfaces.go
└── usecase/
    └── session.go               # Casos de uso de sessão
```

## 📊 Estimativa de Consumo de Memória

### Por Sessão:
- Cliente WhatsApp: ~10MB
- Banco de dados: ~3MB
- Chat storage: ~2MB
- **Total: ~15MB por sessão** ✅

### Overhead do Sistema:
- Session Manager: ~5MB
- Dashboard: ~10MB
- API REST: ~5MB
- **Total Overhead: ~20MB**

### Exemplo:
- 10 sessões: 10 × 15MB + 20MB = **170MB total**
- 50 sessões: 50 × 15MB + 20MB = **770MB total**

## 🔧 Configurações Necessárias

### Variáveis de Ambiente

```env
# Configuração de sessões
MAX_SESSIONS=100                    # Máximo de sessões simultâneas
SESSION_TIMEOUT=24h                 # Timeout de sessões inativas
SESSION_STORAGE_PATH=./storages     # Caminho base para storages

# Banco de dados padrão (para sessão default)
DB_URI=postgres://.../gowa_default
DB_KEYS_URI=postgres://.../gowa_keys_default

# Dashboard
DASHBOARD_ENABLED=true
DASHBOARD_PORT=3001
DASHBOARD_BASIC_AUTH=admin:password
```

## 🚀 Roadmap de Implementação

### Sprint 1 (Semana 1-2): Fundação
- [ ] Criar estrutura de Session Manager
- [ ] Refatorar WhatsApp client (remover globals)
- [ ] Implementar isolamento de banco por sessão
- [ ] Testes unitários do Session Manager

### Sprint 2 (Semana 2-3): API Multi-Sessão
- [ ] Modificar rotas REST para suportar `session_id`
- [ ] Criar middleware de sessão
- [ ] Atualizar todos os handlers
- [ ] Endpoints de gerenciamento de sessões
- [ ] Testes de integração

### Sprint 3 (Semana 3-4): Dashboard
- [ ] Frontend do dashboard (HTML/JS)
- [ ] API do dashboard
- [ ] WebSocket para atualizações em tempo real
- [ ] Visualização de QR codes
- [ ] Gerenciamento de sessões via UI

### Sprint 4 (Semana 4-5): Otimizações
- [ ] Lazy loading de sessões
- [ ] Garbage collection automático
- [ ] Pool de conexões
- [ ] Monitoramento de memória
- [ ] Benchmarks de performance

### Sprint 5 (Semana 5-6): Polimento
- [ ] Modo de compatibilidade (APIs antigas)
- [ ] Scripts de migração
- [ ] Documentação completa
- [ ] Testes end-to-end
- [ ] Preparação para release

## 🧪 Estratégia de Testes

### Testes Unitários
- Session Manager
- Isolamento de sessões
- Gerenciamento de recursos

### Testes de Integração
- APIs multi-sessão
- Criação/deleção de sessões
- Isolamento de dados

### Testes de Performance
- Consumo de memória por sessão
- Limite de sessões simultâneas
- Tempo de resposta das APIs

### Testes de Carga
- 10 sessões simultâneas
- 50 sessões simultâneas
- 100 sessões simultâneas

## 📝 Considerações Importantes

### 1. Isolamento de Sessões
- Cada sessão deve ser completamente isolada
- Não compartilhar estado entre sessões
- Banco de dados separado ou schema isolado

### 2. Segurança
- Validação de `session_id`
- Rate limiting por sessão
- Autenticação no dashboard

### 3. Escalabilidade
- Suportar 100+ sessões simultâneas
- Lazy loading para economizar memória
- Cleanup automático de recursos

### 4. Compatibilidade
- Manter compatibilidade com APIs antigas
- Migração suave de instalações existentes
- Documentação clara de mudanças

## 🎯 Métricas de Sucesso

- ✅ Consumo de memória: ≤ 20MB por sessão
- ✅ Suporte a 100+ sessões simultâneas
- ✅ Dashboard funcional e responsivo
- ✅ APIs multi-sessão funcionando
- ✅ Zero breaking changes (modo compatibilidade)
- ✅ Performance: < 100ms para operações de sessão

## 📚 Referências

- [Whatsmeow Documentation](https://github.com/tulir/whatsmeow)
- [WAHA Architecture](https://github.com/devlikeapro/waha)
- [GoWA Current Implementation](https://github.com/aldinokemal/go-whatsapp-web-multidevice)

---

**Próximos Passos:**
1. Revisar e aprovar este plano
2. Criar branch de desenvolvimento
3. Iniciar Sprint 1: Fundação
4. Implementar Session Manager
5. Refatorar código existente

**Data de Criação:** 2025-01-29
**Versão:** 1.0

