/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.infrastructure.container;
// import neko.logging.infrastructure.config;
// Repositories
// import neko.logging.infrastructure.persistence.repositories.log_entry;
// import neko.logging.infrastructure.persistence.repositories.log_stream;
// import neko.logging.infrastructure.persistence.repositories.span;
// import neko.logging.infrastructure.persistence.repositories.dashboard;
// import neko.logging.infrastructure.persistence.repositories.retention_policy;
// import neko.logging.infrastructure.persistence.repositories.alert_rule;
// import neko.logging.infrastructure.persistence.repositories.alert;
// import neko.logging.infrastructure.persistence.repositories.notification_channel;
// import neko.logging.infrastructure.persistence.repositories.pipeline;
// import neko.logging.infrastructure.persistence.repositories.ingestion_token;
// Use Cases
// import neko.logging.application.usecases.ingest_logs;
// import neko.logging.application.usecases.ingest_traces;
// import neko.logging.application.usecases.search_logs;
// import neko.logging.application.usecases.manage.log_streams;
// import neko.logging.application.usecases.manage.dashboards;
// import neko.logging.application.usecases.manage.retention_policies;
// import neko.logging.application.usecases.manage.alert_rules;
// import neko.logging.application.usecases.manage.alerts;
// import neko.logging.application.usecases.manage.notification_channels;
// import neko.logging.application.usecases.manage.pipelines;
// import neko.logging.application.usecases.get_overview;
// Controllers
// import neko.logging.presentation.http.controllers.log;
// import neko.logging.presentation.http.controllers.trace;
// import neko.logging.presentation.http.controllers.search;
// import neko.logging.presentation.http.controllers.stream;
// import neko.logging.presentation.http.controllers.dashboard;
// import neko.logging.presentation.http.controllers.retention;
// import neko.logging.presentation.http.controllers.alert_rule;
// import neko.logging.presentation.http.controllers.alert;
// import neko.logging.presentation.http.controllers.channel;
// import neko.logging.presentation.http.controllers.pipeline;
// import neko.logging.presentation.http.controllers.overview;
// import neko.logging.presentation.http.controllers.health;

import neko.logging;

mixin(ShowModule!());

@safe:

struct Container {
  // Repositories (driven adapters)
  ILogEntryRepository logEntryRepo;
  ILogStreamRepository logStreamRepo;
  ISpanRepository spanRepo;
  IDashboardRepository dashboardRepo;
  IRetentionPolicyRepository retentionRepo;
  IAlertRuleRepository alertRuleRepo;
  IAlertRepository alertRepo;
  INotificationChannelRepository channelRepo;
  IPipelineRepository pipelineRepo;
  IIngestionTokenRepository tokenRepo;

  // Use cases (application layer)
  IngestLogsUseCase ingestLogs;
  IngestTracesUseCase ingestTraces;
  SearchLogsUseCase searchLogs;
  ManageLogStreamsUseCase manageStreams;
  ManageDashboardsUseCase manageDashboards;
  ManageRetentionPoliciesUseCase manageRetention;
  ManageAlertRulesUseCase manageAlertRules;
  ManageAlertsUseCase manageAlerts;
  ManageNotificationChannelsUseCase manageChannels;
  ManagePipelinesUseCase managePipelines;
  GetOverviewUseCase getOverview;

  // Controllers (driving adapters)
  LogController logController;
  TraceController traceController;
  SearchController searchController;
  StreamController streamController;
  DashboardController dashboardController;
  RetentionController retentionController;
  AlertRuleController alertRuleController;
  AlertController alertController;
  ChannelController channelController;
  PipelineController pipelineController;
  OverviewController overviewController;
  HealthController healthController;
}

Container buildContainer(SrvConfig config) {
  Container container;

  // Infrastructure adapters
  container.logEntryRepo = new LogEntryRepository();
  container.logStreamRepo = new LogStreamRepository();
  container.spanRepo = new SpanRepository();
  container.dashboardRepo = new DashboardRepository();
  container.retentionRepo = new RetentionPolicyRepository();
  container.alertRuleRepo = new AlertRuleRepository();
  container.alertRepo = new AlertRepository();
  container.channelRepo = new NotificationChannelRepository();
  container.pipelineRepo = new PipelineRepository();
  container.tokenRepo = new IngestionTokenRepository();

  // Application use cases
  container.ingestLogs = new IngestLogsUseCase(container.logEntryRepo, container.logStreamRepo);
  container.ingestTraces = new IngestTracesUseCase(container.spanRepo);
  container.searchLogs = new SearchLogsUseCase(container.logEntryRepo);
  container.manageStreams = new ManageLogStreamsUseCase(container.logStreamRepo);
  container.manageDashboards = new ManageDashboardsUseCase(container.dashboardRepo);
  container.manageRetention = new ManageRetentionPoliciesUseCase(container.retentionRepo);
  container.manageAlertRules = new ManageAlertRulesUseCase(container.alertRuleRepo);
  container.manageAlerts = new ManageAlertsUseCase(container.alertRepo);
  container.manageChannels = new ManageNotificationChannelsUseCase(container.channelRepo);
  container.managePipelines = new ManagePipelinesUseCase(container.pipelineRepo);
  container.getOverview = new GetOverviewUseCase(container.logEntryRepo, container.spanRepo, container.logStreamRepo, container.dashboardRepo,
    container.alertRepo, container.pipelineRepo, container.channelRepo);

  // Presentation controllers
  container.logController = new LogController(container.ingestLogs);
  container.traceController = new TraceController(container.ingestTraces);
  container.searchController = new SearchController(container.searchLogs);
  container.streamController = new StreamController(container.manageStreams);
  container.dashboardController = new DashboardController(container.manageDashboards);
  container.retentionController = new RetentionController(container.manageRetention);
  container.alertRuleController = new AlertRuleController(container.manageAlertRules);
  container.alertController = new AlertController(container.manageAlerts);
  container.channelController = new ChannelController(container.manageChannels);
  container.pipelineController = new PipelineController(container.managePipelines);
  container.overviewController = new OverviewController(container.getOverview);
  container.healthController = new HealthController("logging");

  return container;
}
