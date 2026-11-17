# Neko Service Platform — UML

## Component diagram (hexagonal architecture)

Dependencies point inwards: presentation and adapters depend on ports, ports on
the domain. Only the composition root (`infrastructure/container.d`) knows the
concrete classes.

```mermaid
flowchart LR
  subgraph presentation["presentation (driving adapters)"]
    REST["rest · OverviewApi, ServicesApi, TransfersApi"]
    OData["odata · PlatformODataController"]
    Web["web · StatusPage / Frontend"]
    CLI["cli · runCli"]
    HTTP["http · SecurityMiddleware / Health"]
    UNIX["unix · listenOnUnixSocket"]
  end
  subgraph ports
    UC["usecases\nIManageServices · ICheckServiceHealth\nITransferPackages · IPlatformOverview"]
    DRV["repositories · storages\nmessaging · gateways · services"]
  end
  subgraph application
    UCI["usecases (implementations)"]
    DTO["dtos · transfer_document"]
  end
  subgraph domain
    ENT["entities · types · enumerations"]
    POL["services: ClassificationPolicy · TransferPolicy"]
    EXC["exceptions"]
  end
  subgraph adapters["persistence / infrastructure (driven adapters)"]
    REPO["DocumentServiceRepository\nDocumentTransferRepository"]
    STORE["MemoryDocumentStore · JsonFileDocumentStore"]
    HG["HttpHealthGateway"]
    LOG["LoggingEventPublisher"]
    CFG["PlatformConfig · loadConfig"]
    WRK["HealthCheckWorker"]
  end

  presentation --> UC
  UCI -. implements .-> UC
  UCI --> DRV
  UCI --> domain
  REPO -. implements .-> DRV
  STORE -. implements .-> DRV
  HG -. implements .-> DRV
  LOG -. implements .-> DRV
  WRK --> UC
  REPO --> STORE
```

## Class diagram — domain

```mermaid
classDiagram
  class SecurityDomain {
    <<enumeration>>
    open
    restricted
    confidential
    secret
    +label() string
    +canExport() bool
    +canImport() bool
    +higherDomains() SecurityDomain[]
  }
  class ServiceStatus {
    <<enumeration>>
    registered
    active
    suspended
    retired
  }
  class PlatformService {
    +ServiceId id
    +ServiceName name
    +string description
    +SecurityDomain classification
    +ServiceEndpoint endpoint
    +ServiceStatus status
    +HealthState health
    +activate(now)
    +suspend(now)
    +retire(now)
    +changeDetails(description, endpoint, now)
    +recordHealth(state, now)
    +isMonitored() bool
  }
  class ServiceEndpoint {
    <<value object>>
    +string baseUrl
    +string healthPath
    +healthUrl() string
  }
  class ServiceName {
    <<value object>>
    +string value
  }
  class TransferPackage {
    +TransferId id
    +string name
    +TransferDirection direction
    +SecurityDomain sourceDomain
    +SecurityDomain targetDomain
    +TransferStatus status
    +string payload
    +string checksum
    +string reason
  }
  class ClassificationPolicy {
    <<domain service>>
    +requireHostable(classification)
  }
  class TransferPolicy {
    <<domain service>>
    +requireExportTo(target)
    +requireImportable(pkg)
    +seal(pkg)$ string
  }
  PlatformService --> ServiceName
  PlatformService --> ServiceEndpoint
  PlatformService --> ServiceStatus
  PlatformService --> SecurityDomain
  TransferPackage --> SecurityDomain
  ClassificationPolicy ..> SecurityDomain
  TransferPolicy ..> TransferPackage
```

## Class diagram — ports and implementations

```mermaid
classDiagram
  class IManageServicesUseCase { <<interface>> }
  class ICheckServiceHealthUseCase { <<interface>> }
  class ITransferPackagesUseCase { <<interface>> }
  class IPlatformOverviewUseCase { <<interface>> }
  class IServiceRepository { <<interface>> }
  class ITransferRepository { <<interface>> }
  class IDocumentStore { <<interface>> }
  class IEventPublisher { <<interface>> }
  class IServiceHealthGateway { <<interface>> }
  class IClock { <<interface>> }
  class IIdGenerator { <<interface>> }

  ManageServicesUseCase ..|> IManageServicesUseCase
  CheckServiceHealthUseCase ..|> ICheckServiceHealthUseCase
  TransferPackagesUseCase ..|> ITransferPackagesUseCase
  PlatformOverviewUseCase ..|> IPlatformOverviewUseCase

  ManageServicesUseCase --> IServiceRepository
  ManageServicesUseCase --> IEventPublisher
  ManageServicesUseCase --> IClock
  ManageServicesUseCase --> IIdGenerator
  CheckServiceHealthUseCase --> IServiceHealthGateway
  TransferPackagesUseCase --> ITransferRepository

  DocumentServiceRepository ..|> IServiceRepository
  DocumentTransferRepository ..|> ITransferRepository
  DocumentServiceRepository --> IDocumentStore
  MemoryDocumentStore ..|> IDocumentStore
  JsonFileDocumentStore ..|> IDocumentStore
  LoggingEventPublisher ..|> IEventPublisher
  HttpHealthGateway ..|> IServiceHealthGateway
  SystemClock ..|> IClock
  UuidGenerator ..|> IIdGenerator
```

## State machine — service life cycle

```mermaid
stateDiagram-v2
  [*] --> registered: register
  registered --> active: activate
  active --> suspended: suspend
  suspended --> active: activate
  registered --> retired: retire
  active --> retired: retire
  suspended --> retired: retire
  retired --> [*]: remove
```

## Sequence — import with rejection

```mermaid
sequenceDiagram
  participant C as OData / REST / CLI
  participant UC as TransferPackagesUseCase
  participant P as TransferPolicy
  participant R as ITransferRepository
  participant E as IEventPublisher
  C->>UC: importPackage(document, actor)
  UC->>UC: fromDocument (format, fields)
  UC->>R: tryGet(id)
  alt already imported
    UC-->>C: ConflictException (409)
  end
  UC->>P: requireImportable(pkg)
  alt violation
    P-->>UC: PolicyViolation / IntegrityException
    UC->>R: save(pkg, status=rejected, reason)
    UC->>E: transfer.rejected
    UC-->>C: rethrow (403 / 422)
  else ok
    UC->>R: save(pkg, status=imported)
    UC->>E: transfer.imported
    UC-->>C: TransferDto
  end
```
