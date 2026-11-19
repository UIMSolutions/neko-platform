# UML — neko.database (hdb)

Diagrams in Mermaid. They show the structure after the redesign into the hexagonal layout
(`backend/source/neko/database/{domain,ports,application,persistence,infrastructure,presentation}`) and the cloud
functions. Names are D module and type names; fields are abbreviated to what matters for the design.

## Component Diagram — Hexagonal Architecture

```mermaid
flowchart LR
    subgraph Clients
        FIORI[Fiori 3 app<br/>frontend/]
        GTK[hdb-admin<br/>GtkD MVC]
        CLI[hdb-cli<br/>SQL shell + cloud]
        APP[Bound application]
    end

    subgraph Presentation["presentation (driving adapters)"]
        REST[rest<br/>registerHdbRestApi<br/>registerCloudRestApi]
        OD[odata<br/>ODataController /odata/v4<br/>CloudODataController /odata/v4/cloud]
        WEB[web<br/>SqlAdminUi /admin]
        HTTP[http<br/>SqlRestApi, server info]
        UNIX[unix<br/>UnixServer]
    end

    subgraph Infrastructure
        GATE[security<br/>SecurityGate, OpensslCredentialCrypto]
        CONF[configuration<br/>DatabaseConfig, loadConfig]
        WORK[workers<br/>Workers, PeriodicJob]
        LOGC[logging<br/>ApplicationLogCapture]
        CLIENTS[clients<br/>HttpReplicationClient<br/>DataProductCatalog]
        GW[gateway<br/>GatewayProxy]
    end

    subgraph Application
        MON[MonitoredDatabases<br/>ISqlUseCase decorator]
        AUD[AuditedDatabases / AuditedAccess / AuditedTenants]
        TDB[TenantDatabases]
        SQL[SqlService<br/>column engine]
        CLOUD[cloud services<br/>Instance, Workload, Monitoring,<br/>Advisor, CalcView, Binding,<br/>DataProduct, Assistant]
        ACC[AccessService, TenantService,<br/>BackupService, LogService]
    end

    subgraph Domain
        ENT[entities<br/>ColumnTable, Principal, DatabaseInstance,<br/>WorkloadClass, CalculationView,<br/>ServiceBinding, DataProduct]
        DS[services<br/>advisors, diagnosis,<br/>assistant, inspection]
    end

    subgraph Ports
        PIN[usecases<br/>ISqlUseCase, IInstanceUseCase, ...]
        POUT[repositories / storages / gateways<br/>ICloudRepository, IMonitoringStore,<br/>ITableRepository, IDataProductCatalog]
    end

    subgraph Persistence
        REPO[repositories<br/>Memory/File/Json/Binary/Bson tables,<br/>FileBackupStore, CloudRepository]
        STO[storages<br/>FileTenantStorage, FileUserStore,<br/>FileCloudStateStore, MemoryMonitoringStore]
        MAP[mappers + records]
    end

    FIORI --> REST & OD
    GTK --> REST
    CLI --> REST & UNIX
    APP --> REST & OD
    REST & OD & WEB & HTTP & UNIX --> GATE
    REST & OD & WEB & HTTP & UNIX --> PIN
    PIN --> MON --> AUD --> TDB --> SQL
    PIN --> CLOUD
    CLOUD --> DS & ENT
    CLOUD --> POUT
    ACC --> POUT
    POUT --> REPO & STO
    REPO & STO --> MAP
    WORK --> MON & TDB
    CLIENTS -.implements.-> POUT
```

## Class Diagram — Cloud Domain Entities

```mermaid
classDiagram
    class DatabaseInstance {
        +string name
        +string description
        +PerformanceClass performanceClass
        +size_t memoryGb
        +size_t storageGb
        +bool nseEnabled
        +size_t ecnNodes
        +string region
        +string version_
        +vcpus() size_t
    }
    class WorkloadClass {
        +string name
        +int priority
        +size_t statementTimeoutSeconds
        +size_t statementMemoryLimitMb
        +size_t totalStatementLimit
        +size_t statementThreadLimit
        +bool enabled
    }
    class WorkloadMapping {
        +string name
        +string workloadClass
        +string userName
        +string roleName
    }
    class CalculationView {
        +string name
        +CalcViewType viewType
        +string baseTable
        +CalcJoin[] joins
        +CalcAttribute[] attributes
        +CalcMeasure[] measures
        +string filter
    }
    class CalcJoin {
        +string table
        +bool left
        +string leftColumn
        +string rightColumn
    }
    class CalcAttribute {
        +string column
        +string label
    }
    class CalcMeasure {
        +string column
        +Aggregation aggregation
        +string label
    }
    class ServiceBinding {
        +string name
        +string application
        +string user
        +string role
    }
    class BindingCredentials {
        +string host
        +ushort port
        +string odataUrl
        +string user
        +string password
    }
    class DataProduct {
        +string id
        +string version_
        +DataProductTable[] tables
    }
    class DataProductTable {
        +string name
        +DataProductColumn[] columns
        +string[][] rows
    }
    class InstalledProduct {
        +string productId
        +string prefix
        +string[] tables
    }
    class TraceEntry {
        +ulong id
        +string kind
        +string statement
        +double durationMs
        +string error
    }
    class MetricSample {
        +string time
        +size_t statements
        +double avgMs
        +ulong memoryBytes
        +double cpuPercent
    }
    class Recommendation {
        +AdvisorKind advisor
        +Severity severity
        +string target
        +string action
    }
    class IssueSummary {
        +IssueGroup[] groups
        +string rootCause
        +string resolution
        +string text
    }

    CalculationView *-- CalcJoin
    CalculationView *-- CalcAttribute
    CalculationView *-- CalcMeasure
    WorkloadMapping --> WorkloadClass : workloadClass
    DataProduct *-- DataProductTable
    InstalledProduct ..> DataProduct : productId
    ServiceBinding ..> BindingCredentials : issued once
    IssueSummary ..> TraceEntry : summarizes

    class PerformanceClass {
        <<enumeration>>
        compute
        memory
        highMemory
    }
    class AdvisorKind {
        <<enumeration>>
        index
        nse
        partition
        performanceClass
        ecn
    }
    class Aggregation {
        <<enumeration>>
        sum
        count
        avg
        min
        max
        countDistinct
    }
    class InstanceStatus {
        <<enumeration>>
        creating
        running
        stopped
        error
    }
```

## Class Diagram — Domain Services

```mermaid
classDiagram
    class advisors {
        <<module>>
        +runAdvisors(AdvisorInput, AdvisorKind[], AdvisorSettings) Recommendation[]
        +indexAdvisor()
        +nseAdvisor()
        +partitionAdvisor()
        +performanceClassAdvisor()
        +ecnAdvisor()
        +estimatedBytes(TableStats) ulong
    }
    class diagnosis {
        <<module>>
        +summarize(TraceEntry[], string now) IssueSummary
        +normalizeMessage(string) string
    }
    class assistant {
        <<module>>
        +parseMessage(string) AssistantIntent[]
        +splitBatch(string) string[]
        +guideSteps(string topic) string[]
    }
    class inspection {
        <<module>>
        +inspect(string sql) StatementShape
        +normalizeStatement(string) string
    }
    class calcview {
        <<module>>
        +validate(CalculationView)
        +toSql(CalculationView, CalcQuery) string
        +outputColumns(CalculationView) string[]
    }
    class AdvisorInput {
        +TableStats[] stats
        +TableAccess[] access
        +MetricSample[] samples
        +TraceEntry[] traces
        +DatabaseInstance instance
    }
    advisors ..> AdvisorInput
    diagnosis ..> inspection
```

## Class Diagram — Use Cases, Ports and Services

```mermaid
classDiagram
    class ISqlUseCase {
        <<interface>>
        +execute()
        +executeIn()
        +listTables()
        +stats()
        +mergeDelta()
        +checkpoint()
    }
    class IBackupUseCase {
        <<interface>>
        +create()
        +restore()
        +schedule()
        +updateSchedule()
        +updateRetention(int)
    }
    class IInstanceUseCase {
        <<interface>>
        +listInstances()
        +createInstance()
        +updateInstance()
        +startInstance()
        +stopInstance()
        +deleteInstance()
        +instanceMetrics()
        +instanceAdvisors()
    }
    class IWorkloadUseCase {
        <<interface>>
        +listClasses()
        +saveClass()
        +deleteClass()
        +listMappings()
        +saveMapping()
        +deleteMapping()
    }
    class IMonitoringUseCase {
        <<interface>>
        +overview()
        +traces()
        +configureTrace()
        +clearTraces()
        +tableAccess()
        +issueSummary()
    }
    class IAdvisorUseCase {
        <<interface>>
        +runAdvisors()
        +recommendations()
    }
    class ICalcViewUseCase {
        <<interface>>
        +listViews()
        +saveView()
        +deleteView()
        +queryView()
        +viewSql()
    }
    class IBindingUseCase {
        <<interface>>
        +listBindings()
        +createBinding()
        +deleteBinding()
    }
    class IDataProductUseCase {
        <<interface>>
        +catalog()
        +install()
        +uninstall()
    }
    class IAssistantUseCase {
        <<interface>>
        +ask(Principal, string) AssistantReply
    }
    class ICloudRepository {
        <<interface>>
        +instances()
        +saveInstance()
        +tenantState()
        +saveTenantState()
    }
    class IMonitoringStore {
        <<interface>>
        +appendTrace()
        +traces()
        +appendSample()
        +countAccess()
        +access()
    }
    class IDataProductCatalog {
        <<interface>>
        +products()
        +product(id)
    }
    class IStatisticsSource {
        <<interface>>
        +openTenants()
        +statsOf(tenant)
    }

    class MonitoredDatabases
    class InstanceService
    class WorkloadService
    class MonitoringService
    class AdvisorService
    class CalcViewService
    class BindingService
    class DataProductService
    class AssistantService
    class CloudServices {
        +MonitoredDatabases sql
        +InstanceService instances
        +AssistantService assistant
    }
    class TenantDatabases
    class CloudRepository
    class MemoryMonitoringStore
    class DataProductCatalog

    MonitoredDatabases ..|> ISqlUseCase
    MonitoredDatabases --> ISqlUseCase : inner (audited)
    MonitoredDatabases --> ICloudRepository
    MonitoredDatabases --> IMonitoringStore
    TenantDatabases ..|> ISqlUseCase
    TenantDatabases ..|> IBackupUseCase
    TenantDatabases ..|> IStatisticsSource
    InstanceService ..|> IInstanceUseCase
    InstanceService --> ITenantUseCase
    WorkloadService ..|> IWorkloadUseCase
    MonitoringService ..|> IMonitoringUseCase
    AdvisorService ..|> IAdvisorUseCase
    CalcViewService ..|> ICalcViewUseCase
    BindingService ..|> IBindingUseCase
    BindingService --> IAccessUseCase
    DataProductService ..|> IDataProductUseCase
    DataProductService --> IDataProductCatalog
    AssistantService ..|> IAssistantUseCase
    AssistantService --> IInstanceUseCase
    AssistantService --> IMonitoringUseCase
    AssistantService --> IAdvisorUseCase
    CloudServices *-- MonitoredDatabases
    CloudServices *-- InstanceService
    CloudServices *-- AssistantService
    CloudRepository ..|> ICloudRepository
    MemoryMonitoringStore ..|> IMonitoringStore
    DataProductCatalog ..|> IDataProductCatalog
```

## State Diagram — Instance Lifecycle

```mermaid
stateDiagram-v2
    [*] --> creating : createInstance (sizing validated)
    creating --> running : tenant + first admin created
    creating --> [*] : validation or conflict error
    running --> stopped : stopInstance (sessions end)
    stopped --> running : startInstance
    running --> running : updateInstance (resize, class, NSE, ECN)
    stopped --> [*] : deleteInstance (data, users, backups purged)
    running --> [*] : deleteInstance (stops first)
```

## Activity Diagram — Statement through `MonitoredDatabases`

```mermaid
flowchart TD
    A[executeIn tx, sql] --> B{principal is tenant user?}
    B -- no --> Z[inner.executeIn: core rejects or system path]
    B -- yes --> C[resolveWorkload user, role]
    C --> D{concurrency limit reached?}
    D -- yes --> V1[trace violation] --> E1[throw WorkloadLimitExceeded 429]
    D -- no --> F[inFlight++ / measure]
    F --> G[inner.executeIn: audit → tenant → SqlService]
    G -->|exception| H[count error, trace error if enabled] --> R1[rethrow]
    G -->|result| I[count statement + table accesses]
    I --> J{result > memory limit?}
    J -- yes --> V2[trace violation] --> E2[throw WorkloadLimitExceeded]
    J -- no --> K{duration > timeout?}
    K -- yes --> V3[trace violation, keep result]
    K -- no --> L
    V3 --> L{duration ≥ expensive threshold?}
    L -- yes --> T1[trace expensive]
    L -- no --> M{SQL trace on?}
    M -- yes --> T2[trace sql]
    M -- no --> RET[return result]
    T1 --> RET
    T2 --> RET
```

## Activity Diagram — Install a Data Product

```mermaid
flowchart TD
    A[install actor, id] --> B[requireTenantPermission manageDataProducts]
    B --> C[catalog.product id → validate]
    C --> D{already installed?}
    D -- yes --> X[Conflict 409]
    D -- no --> E[installStatements prefix]
    E --> F[execute CREATE TABLE / INSERT via secured SQL]
    F -->|error| G[DROP created tables] --> Y[rethrow]
    F -->|ok| H[save InstalledProduct in TenantCloudState]
```

## Sequence Diagram — Fiori queries a Calculation View over OData

```mermaid
sequenceDiagram
    actor U as User (Fiori)
    participant GATE as SecurityGate
    participant OD as CloudODataController
    participant CV as CalcViewService
    participant MON as MonitoredDatabases
    participant AUD as AuditedDatabases
    participant TDB as TenantDatabases / SqlService
    U->>GATE: GET /odata/v4/cloud/CV_REVENUE?$orderby=REVENUE desc (Bearer)
    GATE->>GATE: authenticate token → Principal (TaskLocal)
    GATE->>OD: dispatch
    OD->>OD: entitySets(actor) incl. CV_<name> per view
    OD->>CV: queryView(actor, "REVENUE", CalcQuery)
    CV->>CV: toSql(view, query)
    CV->>MON: execute(SELECT ... GROUP BY ...)
    MON->>AUD: executeIn (workload + trace)
    AUD->>TDB: executeIn (table permissions, audit "data")
    TDB-->>CV: QueryResult
    CV-->>OD: rows renamed to output columns
    OD-->>U: {"@odata.context": "$metadata#CV_REVENUE", "value": [...]}
```

## Sequence Diagram — Assistant batch

```mermaid
sequenceDiagram
    actor A as Admin
    participant R as REST /api/v1/assistant
    participant S as AssistantService
    participant P as domain.assistant.parseMessage
    participant M as MonitoringService
    participant B as IBackupUseCase
    A->>R: {"message": "status; create a backup labeled nightly"}
    R->>S: ask(actor, message)
    S->>P: parseMessage
    P-->>S: [instanceStatus, createBackup("nightly")]
    S->>M: overview(actor)
    M-->>S: MonitoringOverview
    S->>B: create("nightly")
    B-->>S: BackupInfo
    S-->>R: AssistantReply {text, steps[2], suggestions}
    R-->>A: 200 JSON
```

## Sequence Diagram — System administrator creates an instance with the CLI

```mermaid
sequenceDiagram
    actor O as Operator
    participant C as hdb-cli cloud
    participant R as REST
    participant I as InstanceService
    participant T as TenantService
    participant CR as CloudRepository
    O->>C: instances create acme --memory 64 --class compute
    C->>R: POST /api/v1/auth/login (tenant system)
    C->>R: POST /api/v1/cloud/instances
    R->>I: createInstance(actor, spec)
    I->>I: validateSizing
    I->>T: createTenant(name, admin)
    T-->>I: TenantInfo
    I->>CR: saveInstance
    I-->>R: InstanceInfo (audit "instances")
    R-->>C: 201 JSON
    C->>R: POST /api/v1/auth/logout
```

## Component Diagram — GtkD client (MVC)

```mermaid
flowchart LR
    subgraph models
        API[api.d HdbClient<br/>@safe REST client]
        TR[transport.d CurlTransport<br/>IHttpTransport]
    end
    subgraph views
        PG[pages.d Tables, Console, Stats,<br/>Backups, Users, Tenants, Logs]
        CL[cloud.d Instances, Monitoring, Advisors,<br/>Workloads, Views, Bindings,<br/>Data products, Assistant]
        WG[widgets.d DataGrid, FormDialog]
    end
    subgraph controllers
        WIN[window.d AdminWindow]
        LOG[login.d signIn]
    end
    WIN --> PG & CL
    LOG --> API
    PG & CL --> API --> TR
    PG & CL --> WG
```

## Deployment Diagram — SAP BTP (Cloud Foundry) and containers

```mermaid
flowchart TB
    subgraph BTP["SAP BTP Cloud Foundry (mta.yaml)"]
        AR["hdb-approuter<br/>@sap/approuter + resources/ (Fiori)"]
        SRV["hdb-srv<br/>binary_buildpack ./hdb"]
        X[(hdb-xsuaa)]
        CFG[(hdb-config<br/>user-provided)]
        AR -->|/api/v1, /odata/v4| SRV
        AR --- X
        SRV --- CFG
    end
    subgraph K8S["Kubernetes (k8s/)"]
        DEP["Deployment hdb<br/>image from Containerfile"]
        PVC[(PVC hdb-data /app/data)]
        DEP --- PVC
    end
    Browser --> AR
    Browser --> DEP
```
