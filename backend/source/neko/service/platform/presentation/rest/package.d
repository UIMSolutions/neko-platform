/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// vibe.d REST API (/rest/v1): JSON in camelCase, errors as
/// {"statusMessage": "..."} with the HTTP status of the business error.
///
///   interfaces  wire contract          IOverviewApi, IServicesApi, ITransfersApi
///   services    server implementations OverviewApi, ServicesApi, TransfersApi
///   clients     typed clients          PlatformRestClient
///
///   GET    overview
///   GET    services[?search=&status=&classification=]     POST services
///   GET    services/:id    PATCH services/:id    DELETE services/:id
///   POST   services/:id/{activate,suspend,retire,check}
///   GET    transfers       GET transfers/:id     GET transfers/:id/package
///   POST   transfers/export {name,targetDomain,payload}
///   POST   transfers/import <transfer document>
module neko.platform.presentation.rest;

public:
  import neko.platform.presentation.rest.clients;
  import neko.platform.presentation.rest.interfaces;
  import neko.platform.presentation.rest.services;
