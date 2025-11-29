# Plano de Implementação: Multi-Sessão Nativa no GoWA

## 📋 Objetivo

Transformar o GoWA em uma solução multi-sessão nativa (similar ao WAHA) mantendo o baixo consumo de memória (15MB por sessão) e adicionando dashboard de gerenciamento.

## 🎯 Requisitos

1. **Múltiplas sessões simultâneas** - Suporte nativo a N sessões WhatsApp
2. **Dashboard de gerenciamento** - Interface web para gerenciar sessões
3. **Baixo consumo de memória** - Manter ~15MB por sessão
4. **API com session_id** - Rotas no formato `/api/:session/...`
5. **Isolamento de dados** - Cada sessão com seu próprio armazenamento

---

## 📊 Análise da Arquitetura Atual

### GoWA (Atual) - Single Session

```
┌─────────────────────────────────────┐
│         Aplicação GoWA              │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Global Client (cli)         │  │
│  │  - Único cliente WhatsApp    │  │
│  │  - GetFirstDevice()          │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Database Container          │  │
│  │  - SQLite/PostgreSQL         │  │
│  │  - Armazena todos devices    │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Chat Storage                │  │
│  │  - SQLite separado           │  │
│  │  - Histórico de mensagens    │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Problemas:**
- Cliente global único (`var cli *whatsmeow.Client`)
- Sem isolamento entre sessões
- Sem identificação de sessão nas APIs
- Não escala para múltiplas sessões

### WAHA (Referência) - Multi Session

```
┌─────────────────────────────────────┐
│         Aplicação WAHA              │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Session Manager             │  │
│  │  - Map[sessionID]*Client     │  │
│  │  - Criação/Destruição        │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────┐ ┌──────┐ ┌──────┐       │
│  │ Sess1│ │ Sess2│ │ Sess3│       │
│  │ DB1  │ │ DB2  │ │ DB3  │       │
│  └──────┘ └──────┘ └──────┘       │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Dashboard                   │  │
│  │  - Lista sessões             │  │
│  │  - Status de cada sessão     │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Vantagens:**
- Múltiplas sessões isoladas
- API com `session_id`
- Dashboard de gerenciamento
- Escalável

---

## 🏗️ Arquitetura Proposta

### Nova Estrutura Multi-Session

```
┌─────────────────────────────────────────────────────────┐
│              GoWA Multi-Session                         │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Session Manager (Singleton)              │  │
│  │                                                   │  │
│  │  type SessionManager struct {                    │  │
│  │      sessions map[string]*Session                │  │
│  │      mu       sync.RWMutex                       │  │
│  │  }                                               │  │
│  │                                                   │  │
│  │  type Session struct {                           │  │
│  │      ID            string                        │  │
│  │      Client        *whatsmeow.Client             │  │
│  │      DB            *sqlstore.Container           │  │
│  │      ChatStorage   IChatStorageRepository        │  │
│  │      Status        SessionStatus                 │  │
│  │      CreatedAt     time.Time                     │  │
│  │      LastActivity  time.Time                     │  │
│  │  }                                               │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │   Session 1  │ │   Session 2  │ │   Session 3  │   │
│  │              │ │              │ │              │   │
│  │  Client      │ │  Client      │ │  Client      │   │
│  │  DB (isolado)│ │  DB (isolado)│ │  DB (isolado)│   │
│  │  ChatStorage │ │  ChatStorage │ │  ChatStorage │   │
│  │  ~15MB RAM   │ │  ~15MB RAM   │ │  ~15MB RAM   │   │
│  └──────────────┘ └──────────────┘ └──────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │              Dashboard Web                       │  │
│  │  - Lista todas sessões                           │  │
│  │  - Status (connected/disconnected)               │  │
│  │  - Criar/Deletar sessões                        │  │
│  │  - QR Code por sessão                           │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │              API Routes                          │  │
│  │  GET  /api/sessions              - Lista sessões │  │
│  │  POST /api/sessions              - Cria sessão   │  │
│  │  GET  /api/sessions/:id          - Info sessão   │  │
│  │  DEL  /api/sessions/:id          - Remove sessão │  │
│  │  GET  /api/:session/login        - Login sessão  │  │
│  │  POST /api/:session/send/message - Envia msg     │  │
│  │  ... (todas rotas com :session)                  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Estrutura de Arquivos Proposta

```
src/
├── cmd/
│   ├── root.go              # Modificado: Inicializa SessionManager
│   ├── rest.go              # Modificado: Adiciona rotas de sessão
│   └── mcp.go               # Mantido
│
├── domains/
│   ├── session/             # NOVO: Domínio de sessão
│   │   ├── session.go       # Estruturas e interfaces
│   │   └── interfaces.go    # ISessionManager, ISession
│   └── ... (outros domínios)
│
├── infrastructure/
│   ├── session/             # NOVO: Implementação de sessões
│   │   ├── manager.go       # SessionManager implementation
│   │   ├── session.go       # Session implementation
│   │   └── storage.go       # Gerenciamento de storage por sessão
│   ├── whatsapp/
│   │   ├── init.go          # Modificado: Remove global cli
│   │   └── ... (outros)
│   └── chatstorage/
│       └── ... (mantido)
│
├── ui/
│   ├── rest/
│   │   ├── session.go       # NOVO: Handlers de sessão
│   │   ├── app.go           # Modificado: Adiciona :session
│   │   ├── send.go          # Modificado: Adiciona :session
│   │   └── ... (todos modificados)
│   ├── dashboard/           # NOVO: Dashboard web
│   │   ├── dashboard.go     # Handler principal
│   │   ├── views/
│   │   │   └── dashboard.html
│   │   └── assets/
│   │       ├── dashboard.js
│   │       └── dashboard.css
│   └── websocket/
│       └── websocket.go     # Modificado: Suporta múltiplas sessões
│
├── usecase/
│   ├── session.go           # NOVO: Casos de uso de sessão
│   └── ... (outros)
│
└── config/
    └── settings.go          # Modificado: Configurações de sessão
```

---

## 🔧 Implementação Detalhada

### 1. Domínio de Sessão (`domains/session/`)

```go
// domains/session/session.go
package session

import (
    "context"
    "time"
    "go.mau.fi/whatsmeow"
    "go.mau.fi/whatsmeow/store/sqlstore"
    domainChatStorage "github.com/.../domains/chatstorage"
)

type SessionStatus string

const (
    StatusDisconnected SessionStatus = "disconnected"
    StatusConnecting   SessionStatus = "connecting"
    StatusConnected    SessionStatus = "connected"
    StatusLoggedIn     SessionStatus = "logged_in"
    StatusError        SessionStatus = "error"
)

type Session struct {
    ID            string
    Name          string                    // Nome amigável (opcional)
    Client        *whatsmeow.Client
    DB            *sqlstore.Container
    ChatStorage   domainChatStorage.IChatStorageRepository
    Status        SessionStatus
    DeviceID      string
    CreatedAt     time.Time
    LastActivity  time.Time
    Error         error
}

type ISessionManager interface {
    // Gerenciamento de sessões
    CreateSession(ctx context.Context, sessionID string, name string) (*Session, error)
    GetSession(sessionID string) (*Session, error)
    GetAllSessions() map[string]*Session
    DeleteSession(ctx context.Context, sessionID string) error
    
    // Operações de sessão
    StartSession(ctx context.Context, sessionID string) error
    StopSession(ctx context.Context, sessionID string) error
    RestartSession(ctx context.Context, sessionID string) error
    
    // Status
    GetSessionStatus(sessionID string) (SessionStatus, error)
    GetSessionStats() SessionStats
}

type SessionStats struct {
    Total       int
    Connected   int
    Disconnected int
    Error       int
}
```

### 2. Session Manager (`infrastructure/session/manager.go`)

```go
// infrastructure/session/manager.go
package session

import (
    "context"
    "fmt"
    "sync"
    "time"
    "go.mau.fi/whatsmeow/store/sqlstore"
    domainSession "github.com/.../domains/session"
    domainChatStorage "github.com/.../domains/chatstorage"
    "github.com/.../infrastructure/chatstorage"
    "github.com/.../infrastructure/whatsapp"
)

type SessionManager struct {
    sessions map[string]*domainSession.Session
    mu       sync.RWMutex
    basePath string // Caminho base para storages
}

func NewSessionManager(basePath string) domainSession.ISessionManager {
    return &SessionManager{
        sessions: make(map[string]*domainSession.Session),
        basePath: basePath,
    }
}

func (sm *SessionManager) CreateSession(ctx context.Context, sessionID string, name string) (*domainSession.Session, error) {
    sm.mu.Lock()
    defer sm.mu.Unlock()
    
    // Verifica se já existe
    if _, exists := sm.sessions[sessionID]; exists {
        return nil, fmt.Errorf("session %s already exists", sessionID)
    }
    
    // Cria banco de dados isolado para a sessão
    dbURI := fmt.Sprintf("file:%s/sessions/%s/whatsapp.db?_foreign_keys=on", sm.basePath, sessionID)
    db := whatsapp.InitWaDB(ctx, dbURI)
    
    // Cria chat storage isolado
    chatStorageURI := fmt.Sprintf("file:%s/sessions/%s/chatstorage.db", sm.basePath, sessionID)
    chatStorageDB, err := initChatStorageForSession(chatStorageURI)
    if err != nil {
        return nil, fmt.Errorf("failed to init chat storage: %w", err)
    }
    chatStorageRepo := chatstorage.NewStorageRepository(chatStorageDB)
    chatStorageRepo.InitializeSchema()
    
    // Cria cliente WhatsApp (ainda não conectado)
    device, err := db.GetFirstDevice(ctx)
    if err != nil {
        // Se não existe device, cria um novo
        device = &store.Device{}
    }
    
    client := whatsapp.InitWaCLIForSession(ctx, db, nil, chatStorageRepo, device)
    
    session := &domainSession.Session{
        ID:           sessionID,
        Name:         name,
        Client:       client,
        DB:           db,
        ChatStorage:  chatStorageRepo,
        Status:       domainSession.StatusDisconnected,
        CreatedAt:    time.Now(),
        LastActivity: time.Now(),
    }
    
    sm.sessions[sessionID] = session
    return session, nil
}

func (sm *SessionManager) GetSession(sessionID string) (*domainSession.Session, error) {
    sm.mu.RLock()
    defer sm.mu.RUnlock()
    
    session, exists := sm.sessions[sessionID]
    if !exists {
        return nil, fmt.Errorf("session %s not found", sessionID)
    }
    
    return session, nil
}

func (sm *SessionManager) GetAllSessions() map[string]*domainSession.Session {
    sm.mu.RLock()
    defer sm.mu.RUnlock()
    
    // Retorna cópia para evitar race conditions
    result := make(map[string]*domainSession.Session)
    for k, v := range sm.sessions {
        result[k] = v
    }
    return result
}

func (sm *SessionManager) DeleteSession(ctx context.Context, sessionID string) error {
    sm.mu.Lock()
    defer sm.mu.Unlock()
    
    session, exists := sm.sessions[sessionID]
    if !exists {
        return fmt.Errorf("session %s not found", sessionID)
    }
    
    // Desconecta cliente
    if session.Client != nil {
        session.Client.Disconnect()
    }
    
    // Limpa recursos
    // TODO: Limpar banco de dados e arquivos
    
    delete(sm.sessions, sessionID)
    return nil
}
```

### 3. Modificação das Rotas REST

```go
// ui/rest/app.go (modificado)
func InitRestApp(app fiber.Router, sessionManager domainSession.ISessionManager) {
    // Rotas de gerenciamento de sessões
    sessionHandler := NewSessionHandler(sessionManager)
    app.Get("/api/sessions", sessionHandler.ListSessions)
    app.Post("/api/sessions", sessionHandler.CreateSession)
    app.Get("/api/sessions/:id", sessionHandler.GetSession)
    app.Delete("/api/sessions/:id", sessionHandler.DeleteSession)
    
    // Rotas com :session (middleware para validar sessão)
    sessionGroup := app.Group("/api/:session", sessionMiddleware(sessionManager))
    
    // Rotas de app por sessão
    appHandler := NewAppHandler(sessionManager)
    sessionGroup.Get("/app/login", appHandler.Login)
    sessionGroup.Get("/app/logout", appHandler.Logout)
    sessionGroup.Get("/app/status", appHandler.Status)
    
    // Rotas de envio por sessão
    sendHandler := NewSendHandler(sessionManager)
    sessionGroup.Post("/send/message", sendHandler.SendMessage)
    sessionGroup.Post("/send/image", sendHandler.SendImage)
    // ... outras rotas
}

// Middleware para validar e injetar sessão
func sessionMiddleware(sm domainSession.ISessionManager) fiber.Handler {
    return func(c *fiber.Ctx) error {
        sessionID := c.Params("session")
        if sessionID == "" {
            return c.Status(400).JSON(fiber.Map{
                "error": "session parameter is required",
            })
        }
        
        session, err := sm.GetSession(sessionID)
        if err != nil {
            return c.Status(404).JSON(fiber.Map{
                "error": fmt.Sprintf("session %s not found", sessionID),
            })
        }
        
        // Injeta sessão no contexto
        c.Locals("session", session)
        c.Locals("sessionID", sessionID)
        
        return c.Next()
    }
}
```

### 4. Dashboard Web

```go
// ui/dashboard/dashboard.go
package dashboard

import (
    "github.com/gofiber/fiber/v2"
    domainSession "github.com/.../domains/session"
)

type DashboardHandler struct {
    sessionManager domainSession.ISessionManager
}

func InitDashboard(app fiber.Router, sessionManager domainSession.ISessionManager) {
    handler := &DashboardHandler{sessionManager: sessionManager}
    
    // Dashboard principal
    app.Get("/dashboard", handler.Index)
    app.Get("/dashboard/api/sessions", handler.APISessions)
    
    // Assets estáticos
    app.Static("/dashboard/assets", "./ui/dashboard/assets")
}

func (h *DashboardHandler) Index(c *fiber.Ctx) error {
    return c.Render("dashboard/index", fiber.Map{
        "Title": "GoWA Multi-Session Dashboard",
    })
}

func (h *DashboardHandler) APISessions(c *fiber.Ctx) error {
    sessions := h.sessionManager.GetAllSessions()
    stats := h.sessionManager.GetSessionStats()
    
    return c.JSON(fiber.Map{
        "sessions": sessions,
        "stats": stats,
    })
}
```

### 5. Modificação do `cmd/root.go`

```go
// cmd/root.go (modificado)
var (
    sessionManager domainSession.ISessionManager
    // Remove: whatsappCli, chatStorageDB, etc (agora por sessão)
)

func initApp() {
    // Inicializa Session Manager
    sessionManager = session.NewSessionManager(config.PathStorages)
    
    // Cria sessão padrão se não existir (para compatibilidade)
    defaultSession, err := sessionManager.CreateSession(
        context.Background(),
        "default",
        "Default Session",
    )
    if err != nil && !strings.Contains(err.Error(), "already exists") {
        logrus.Fatalf("Failed to create default session: %v", err)
    }
    
    // Inicializa sessão padrão se já existir
    if defaultSession != nil {
        // Auto-connect se já tiver device salvo
        go func() {
            if defaultSession.Client.Store.ID != nil {
                defaultSession.Client.Connect()
            }
        }()
    }
}
```

---

## 📊 Estratégia de Migração

### Fase 1: Preparação (Sem Breaking Changes)
1. ✅ Criar domínio `session`
2. ✅ Implementar `SessionManager`
3. ✅ Manter compatibilidade com código atual
4. ✅ Adicionar rotas `/api/sessions` (novas)

### Fase 2: Implementação Multi-Session
1. ✅ Modificar rotas para aceitar `:session`
2. ✅ Adicionar middleware de sessão
3. ✅ Modificar todos os handlers para usar sessão do contexto
4. ✅ Manter rotas antigas (deprecated) para compatibilidade

### Fase 3: Dashboard
1. ✅ Criar interface de dashboard
2. ✅ Integrar com SessionManager
3. ✅ Adicionar funcionalidades de gerenciamento

### Fase 4: Otimização
1. ✅ Lazy loading de sessões
2. ✅ Cleanup automático de sessões inativas
3. ✅ Monitoramento de memória
4. ✅ Métricas e logging

---

## 🗄️ Estrutura de Armazenamento

```
storages/
├── sessions/
│   ├── default/
│   │   ├── whatsapp.db
│   │   └── chatstorage.db
│   ├── session1/
│   │   ├── whatsapp.db
│   │   └── chatstorage.db
│   └── session2/
│       ├── whatsapp.db
│       └── chatstorage.db
└── (arquivos temporários compartilhados)
```

---

## 🔐 Isolamento de Sessões

### Por Sessão:
- ✅ Banco de dados WhatsApp isolado
- ✅ Chat storage isolado
- ✅ Cliente WhatsApp isolado
- ✅ Event handlers isolados
- ✅ Webhooks configuráveis por sessão

### Compartilhado:
- ✅ Configurações globais (porta, debug, etc)
- ✅ Assets estáticos
- ✅ Dashboard

---

## 📈 Estimativa de Consumo

| Componente | Memória por Sessão |
|------------|-------------------|
| Cliente WhatsApp | ~10MB |
| Database Connection | ~2MB |
| Chat Storage | ~1MB |
| Event Handlers | ~1MB |
| Overhead | ~1MB |
| **Total** | **~15MB** |

**Exemplo:**
- 10 sessões = ~150MB
- 50 sessões = ~750MB
- 100 sessões = ~1.5GB

---

## 🚀 Próximos Passos

1. **Criar branch de desenvolvimento**
   ```bash
   git checkout -b feature/multi-session
   ```

2. **Implementar Fase 1** (Preparação)
   - Criar `domains/session/`
   - Implementar `SessionManager` básico
   - Testes unitários

3. **Implementar Fase 2** (Multi-Session)
   - Modificar rotas REST
   - Adicionar middleware
   - Migrar handlers

4. **Implementar Fase 3** (Dashboard)
   - Interface web
   - Integração com API

5. **Testes e Otimização**
   - Testes de carga
   - Monitoramento de memória
   - Ajustes finos

---

## 📝 Notas Importantes

1. **Compatibilidade**: Manter rotas antigas funcionando (deprecated)
2. **Migração**: Script para migrar sessão única para multi-session
3. **Documentação**: Atualizar README com novo formato de API
4. **Breaking Changes**: Versão 8.0.0 (major version)

---

## 🎯 Resultado Esperado

Ao final da implementação, teremos:

✅ **GoWA Multi-Session** com:
- Suporte nativo a N sessões simultâneas
- Dashboard web para gerenciamento
- API RESTful com `session_id`
- Baixo consumo de memória (~15MB/sessão)
- Isolamento completo entre sessões
- Compatibilidade com código existente (via sessão "default")

---

**Data de Criação**: 2025-01-29  
**Versão do Plano**: 1.0  
**Status**: Pronto para implementação

