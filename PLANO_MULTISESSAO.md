# Plano de Implementação: Multi-Sessão Nativa + Dashboard

## 📋 Objetivo

Implementar suporte nativo a múltiplas sessões WhatsApp no GoWA, mantendo o baixo consumo de memória (~15MB por sessão) e adicionando dashboard de gerenciamento similar ao WAHA.

---

## 🎯 Requisitos

### Funcionalidades Principais
1. ✅ **Múltiplas sessões simultâneas** - Similar ao WAHA com `session_id`
2. ✅ **Dashboard de gerenciamento** - Interface web para gerenciar sessões
3. ✅ **Baixo consumo de memória** - Manter ~15MB por sessão
4. ✅ **API compatível** - Manter compatibilidade com API atual
5. ✅ **Isolamento de dados** - Cada sessão com seu próprio storage

### Métricas de Sucesso
- Memória: ≤ 20MB por sessão ativa
- Tempo de inicialização: < 2s por sessão
- API response time: < 100ms (p95)
- Suporte: Mínimo 50 sessões simultâneas

---

## 🏗️ Arquitetura Proposta

### 1. Gerenciador de Sessões (Session Manager)

```
┌─────────────────────────────────────────────────────────┐
│              Session Manager (Singleton)                 │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Map[sessionID] → *WhatsAppSession              │   │
│  │  - Gerenciamento de ciclo de vida               │   │
│  │  - Pool de conexões                             │   │
│  │  - Health checks                                │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼────┐      ┌────▼────┐      ┌────▼────┐
   │Session 1│      │Session 2│      │Session N│
   │ 15MB    │      │ 15MB    │      │ 15MB    │
   └─────────┘      └─────────┘      └─────────┘
```

### 2. Estrutura de Dados

```go
// WhatsAppSession representa uma sessão WhatsApp isolada
type WhatsAppSession struct {
    ID            string                    // session_id único
    Client        *whatsmeow.Client         // Cliente WhatsApp
    DB            *sqlstore.Container       // Banco de dados da sessão
    KeysDB        *sqlstore.Container       // Banco de chaves (opcional)
    ChatStorage   domainChatStorage.IChatStorageRepository
    Status        SessionStatus             // CONNECTED, DISCONNECTED, etc.
    CreatedAt     time.Time
    LastActivity  time.Time
    Config        SessionConfig             // Configurações específicas
    mu            sync.RWMutex              // Lock para thread-safety
}

// SessionManager gerencia todas as sessões
type SessionManager struct {
    sessions      map[string]*WhatsAppSession
    defaultDBURI  string                    // URI base para novas sessões
    mu            sync.RWMutex
    cleanupTicker *time.Ticker              // Limpeza de sessões inativas
}
```

---

## 📁 Estrutura de Diretórios Proposta

```
src/
├── cmd/
│   └── root.go (modificado)
├── domains/
│   └── session/                    # NOVO - Domínio de sessões
│       ├── session.go              # Entidades e interfaces
│       └── interfaces.go
├── infrastructure/
│   ├── whatsapp/
│   │   ├── init.go (modificado)
│   │   ├── session_manager.go      # NOVO - Gerenciador de sessões
│   │   └── session.go              # NOVO - Estrutura de sessão
│   └── chatstorage/
│       └── (sem mudanças)
├── ui/
│   ├── rest/
│   │   ├── app.go (modificado)
│   │   ├── session.go              # NOVO - Endpoints de sessão
│   │   └── dashboard.go            # NOVO - Dashboard endpoints
│   └── dashboard/                  # NOVO - Frontend do dashboard
│       ├── index.html
│       ├── assets/
│       └── components/
├── usecase/
│   └── session.go                  # NOVO - Casos de uso de sessão
└── validations/
    └── session_validation.go       # NOVO - Validações
```

---

## 🔄 Fluxo de Implementação

### Fase 1: Core - Session Manager (Semana 1-2)

#### 1.1 Criar estrutura base de sessão
- [ ] Criar `domains/session/` com interfaces
- [ ] Implementar `WhatsAppSession` struct
- [ ] Implementar `SessionManager` singleton
- [ ] Adicionar locks para thread-safety

#### 1.2 Modificar inicialização
- [ ] Modificar `InitWaCLI` para aceitar `sessionID`
- [ ] Criar função `InitSession(sessionID string)`
- [ ] Implementar isolamento de banco por sessão
- [ ] Adicionar cleanup de sessões inativas

**Arquivos a modificar:**
- `src/infrastructure/whatsapp/init.go`
- `src/infrastructure/whatsapp/session_manager.go` (NOVO)
- `src/infrastructure/whatsapp/session.go` (NOVO)

### Fase 2: API Multi-Sessão (Semana 2-3)

#### 2.1 Modificar rotas REST
- [ ] Adicionar middleware para extrair `session_id`
- [ ] Modificar todas as rotas para aceitar `session_id`
- [ ] Manter compatibilidade com API antiga (sem session_id = default)
- [ ] Adicionar rotas de gerenciamento de sessão

**Rotas propostas:**
```
# Gerenciamento de Sessões
POST   /api/sessions                    # Criar nova sessão
GET    /api/sessions                    # Listar todas as sessões
GET    /api/sessions/:session_id        # Obter detalhes da sessão
DELETE /api/sessions/:session_id        # Deletar sessão
POST   /api/sessions/:session_id/start  # Iniciar sessão
POST   /api/sessions/:session_id/stop   # Parar sessão

# APIs com session_id (opcional para compatibilidade)
GET    /api/:session_id/app/login
GET    /api/:session_id/app/logout
POST   /api/:session_id/send/message
# ... todas as outras rotas
```

#### 2.2 Middleware de sessão
```go
func SessionMiddleware(c *fiber.Ctx) error {
    sessionID := c.Params("session_id")
    if sessionID == "" {
        sessionID = "default" // Compatibilidade
    }
    
    session := sessionManager.Get(sessionID)
    if session == nil {
        return c.Status(404).JSON(fiber.Map{
            "error": "Session not found",
        })
    }
    
    c.Locals("session", session)
    c.Locals("session_id", sessionID)
    return c.Next()
}
```

**Arquivos a modificar:**
- `src/ui/rest/app.go`
- `src/ui/rest/session.go` (NOVO)
- `src/ui/rest/middleware/session.go` (NOVO)
- Todos os handlers REST existentes

### Fase 3: Dashboard (Semana 3-4)

#### 3.1 Backend do Dashboard
- [ ] Criar endpoints de estatísticas
- [ ] Endpoint de métricas de sessões
- [ ] WebSocket para atualizações em tempo real
- [ ] API de logs por sessão

**Endpoints:**
```
GET /api/dashboard/stats           # Estatísticas gerais
GET /api/dashboard/sessions        # Lista de sessões com status
GET /api/dashboard/metrics         # Métricas de performance
WS  /api/dashboard/events          # Eventos em tempo real
```

#### 3.2 Frontend do Dashboard
- [ ] Criar interface HTML/Vue.js
- [ ] Lista de sessões com status
- [ ] Gráficos de uso de memória
- [ ] Gerenciamento de sessões (criar/deletar)
- [ ] Logs em tempo real

**Arquivos a criar:**
- `src/ui/dashboard/index.html`
- `src/ui/dashboard/assets/dashboard.js`
- `src/ui/dashboard/assets/dashboard.css`
- `src/ui/rest/dashboard.go` (NOVO)

### Fase 4: Otimizações e Isolamento (Semana 4-5)

#### 4.1 Isolamento de recursos
- [ ] Banco de dados isolado por sessão
- [ ] Chat storage isolado por sessão
- [ ] Diretórios de mídia isolados
- [ ] Configurações por sessão

#### 4.2 Otimizações de memória
- [ ] Lazy loading de sessões
- [ ] Unload de sessões inativas
- [ ] Pool de conexões compartilhado
- [ ] Garbage collection otimizado

#### 4.3 Health checks
- [ ] Monitoramento de saúde das sessões
- [ ] Auto-reconnect por sessão
- [ ] Alertas de sessões com problemas
- [ ] Métricas de performance

---

## 💾 Estratégia de Armazenamento

### Opção 1: Banco Único com Prefixo (Recomendado)
```
DB_URI=postgres://.../gowa
- Tabela: sessions (id, session_id, device_id, ...)
- Prefixo nas tabelas: session_<id>_messages, session_<id>_chats
```

**Vantagens:**
- Fácil backup/restore
- Queries cross-session possíveis
- Menos overhead de conexões

**Desvantagens:**
- Schema mais complexo
- Migrations mais complicadas

### Opção 2: Banco por Sessão
```
DB_URI=postgres://.../gowa_session_{session_id}
- Cada sessão tem seu próprio banco
- Isolamento total
```

**Vantagens:**
- Isolamento completo
- Fácil deletar sessão (drop database)
- Schema simples

**Desvantagens:**
- Muitas conexões de banco
- Backup mais complexo
- Overhead de conexões

### Opção 3: Híbrido (Recomendado para produção)
```
- Banco principal: Metadados de sessões
- Banco por sessão: Dados da sessão (SQLite ou PostgreSQL separado)
- Chat storage: SQLite por sessão em disco
```

---

## 🔧 Implementação Técnica Detalhada

### 1. Session Manager

```go
// src/infrastructure/whatsapp/session_manager.go

package whatsapp

import (
    "sync"
    "time"
    "context"
)

type SessionManager struct {
    sessions      map[string]*WhatsAppSession
    mu            sync.RWMutex
    defaultDBURI  string
    cleanupTicker *time.Ticker
}

var (
    globalSessionManager *SessionManager
    sessionManagerOnce   sync.Once
)

func GetSessionManager() *SessionManager {
    sessionManagerOnce.Do(func() {
        globalSessionManager = &SessionManager{
            sessions:     make(map[string]*WhatsAppSession),
            defaultDBURI: config.DBURI,
        }
        globalSessionManager.startCleanup()
    })
    return globalSessionManager
}

func (sm *SessionManager) CreateSession(sessionID string, config SessionConfig) (*WhatsAppSession, error) {
    sm.mu.Lock()
    defer sm.mu.Unlock()
    
    if _, exists := sm.sessions[sessionID]; exists {
        return nil, fmt.Errorf("session %s already exists", sessionID)
    }
    
    session := &WhatsAppSession{
        ID:           sessionID,
        Status:       StatusCreated,
        CreatedAt:    time.Now(),
        LastActivity: time.Now(),
        Config:       config,
    }
    
    // Inicializar banco de dados isolado
    dbURI := sm.getDBURIForSession(sessionID)
    session.DB = InitWaDB(context.Background(), dbURI)
    
    // Inicializar chat storage isolado
    chatStorageDB := initChatStorageForSession(sessionID)
    session.ChatStorage = chatstorage.NewStorageRepository(chatStorageDB)
    
    sm.sessions[sessionID] = session
    return session, nil
}

func (sm *SessionManager) GetSession(sessionID string) *WhatsAppSession {
    sm.mu.RLock()
    defer sm.mu.RUnlock()
    return sm.sessions[sessionID]
}

func (sm *SessionManager) DeleteSession(sessionID string) error {
    sm.mu.Lock()
    defer sm.mu.Unlock()
    
    session, exists := sm.sessions[sessionID]
    if !exists {
        return fmt.Errorf("session %s not found", sessionID)
    }
    
    // Cleanup
    session.Cleanup()
    delete(sm.sessions, sessionID)
    return nil
}

func (sm *SessionManager) ListSessions() []*WhatsAppSession {
    sm.mu.RLock()
    defer sm.mu.RUnlock()
    
    sessions := make([]*WhatsAppSession, 0, len(sm.sessions))
    for _, session := range sm.sessions {
        sessions = append(sessions, session)
    }
    return sessions
}
```

### 2. Modificação dos Handlers

```go
// src/ui/rest/send.go (exemplo)

func (handler *Send) SendMessage(c *fiber.Ctx) error {
    // Obter sessão do contexto (setado pelo middleware)
    session := c.Locals("session").(*whatsapp.WhatsAppSession)
    sessionID := c.Locals("session_id").(string)
    
    // Usar cliente da sessão
    client := session.GetClient()
    if client == nil {
        return c.Status(400).JSON(fiber.Map{
            "error": "Session not connected",
        })
    }
    
    // Resto da lógica usando client da sessão
    // ...
}
```

### 3. Compatibilidade com API Antiga

```go
// Middleware que detecta se session_id está presente
func SessionMiddleware(c *fiber.Ctx) error {
    sessionID := c.Params("session_id")
    
    // Se não tem session_id, usar "default"
    if sessionID == "" {
        sessionID = "default"
        
        // Criar sessão default se não existir
        sm := whatsapp.GetSessionManager()
        if sm.GetSession("default") == nil {
            sm.CreateSession("default", whatsapp.DefaultSessionConfig())
        }
    }
    
    session := whatsapp.GetSessionManager().GetSession(sessionID)
    if session == nil {
        return c.Status(404).JSON(fiber.Map{
            "error": "Session not found",
        })
    }
    
    c.Locals("session", session)
    c.Locals("session_id", sessionID)
    return c.Next()
}
```

---

## 📊 Dashboard - Funcionalidades

### Página Principal
- **Lista de Sessões**
  - Status (Connected/Disconnected/Error)
  - Uso de memória por sessão
  - Última atividade
  - Ações (Start/Stop/Delete)

- **Estatísticas Gerais**
  - Total de sessões
  - Sessões ativas
  - Memória total usada
  - Mensagens enviadas/recebidas (hoje)

- **Gráficos**
  - Uso de memória ao longo do tempo
  - Mensagens por hora
  - Sessões ativas ao longo do tempo

### Página de Sessão
- **Detalhes da Sessão**
  - Device ID
  - Status de conexão
  - Informações do usuário
  - Configurações

- **Logs em Tempo Real**
  - Eventos da sessão
  - Erros
  - Mensagens

- **Ações**
  - Reconnect
  - Logout
  - Exportar dados

---

## 🧪 Testes

### Testes Unitários
- [ ] Session Manager (criar/listar/deletar)
- [ ] Isolamento de dados entre sessões
- [ ] Cleanup de sessões inativas
- [ ] Thread-safety do manager

### Testes de Integração
- [ ] Múltiplas sessões simultâneas
- [ ] API com e sem session_id
- [ ] Dashboard endpoints
- [ ] WebSocket de eventos

### Testes de Performance
- [ ] Memória por sessão (target: ≤20MB)
- [ ] Tempo de criação de sessão
- [ ] Throughput com 50 sessões
- [ ] Garbage collection

---

## 📈 Métricas e Monitoramento

### Métricas por Sessão
- Memória usada
- CPU usage
- Mensagens enviadas/recebidas
- Tempo de resposta da API
- Status de conexão

### Métricas Globais
- Total de sessões
- Sessões ativas
- Memória total
- Requests por segundo
- Erros por tipo

---

## 🚀 Plano de Migração

### Fase de Transição (2 semanas)
1. **Semana 1**: Implementar Session Manager + API multi-sessão
   - Manter API antiga funcionando
   - Adicionar suporte opcional a session_id
   - Testes com 2-3 sessões

2. **Semana 2**: Dashboard + Otimizações
   - Implementar dashboard básico
   - Otimizações de memória
   - Testes com 10+ sessões

### Compatibilidade
- API antiga continua funcionando (usa sessão "default")
- Novos clientes podem usar session_id
- Migração gradual possível

---

## ⚠️ Riscos e Mitigações

### Risco 1: Aumento de memória
**Mitigação:**
- Lazy loading de sessões
- Unload de sessões inativas
- Pool de recursos compartilhados

### Risco 2: Complexidade de código
**Mitigação:**
- Refatoração gradual
- Testes extensivos
- Documentação detalhada

### Risco 3: Performance com muitas sessões
**Mitigação:**
- Benchmarks regulares
- Otimizações baseadas em métricas
- Limite configurável de sessões

---

## 📝 Checklist de Implementação

### Core
- [ ] Session Manager implementado
- [ ] Estrutura WhatsAppSession criada
- [ ] Isolamento de banco por sessão
- [ ] Thread-safety garantido

### API
- [ ] Middleware de sessão
- [ ] Todas as rotas modificadas
- [ ] Compatibilidade com API antiga
- [ ] Endpoints de gerenciamento

### Dashboard
- [ ] Backend de estatísticas
- [ ] Frontend básico
- [ ] WebSocket de eventos
- [ ] Gráficos e métricas

### Otimizações
- [ ] Lazy loading
- [ ] Cleanup automático
- [ ] Pool de recursos
- [ ] Health checks

### Documentação
- [ ] README atualizado
- [ ] API documentation
- [ ] Guia de migração
- [ ] Exemplos de uso

---

## 🎯 Próximos Passos

1. **Revisar este plano** e ajustar conforme necessário
2. **Criar branch** `feature/multi-session`
3. **Implementar Fase 1** (Session Manager)
4. **Testes iniciais** com 2-3 sessões
5. **Iterar** baseado em feedback

---

## 📚 Referências

- [WAHA Architecture](https://github.com/devlikeapro/waha) - Referência de multi-sessão
- [Whatsmeow Documentation](https://github.com/maurodaniel/go-whatsmeow) - Biblioteca base
- [Go Memory Optimization](https://go.dev/doc/gc-guide) - Otimizações de memória

---

**Versão:** 1.0  
**Data:** 2025-01-29  
**Autor:** CloudBlackhand

