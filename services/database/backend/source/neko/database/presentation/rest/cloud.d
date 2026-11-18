/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// REST-API der Cloud-Funktionen. Alle Antworten sind JSON; Aufzählungen erscheinen als Namen.
///
/// Bereich system:   /api/v1/cloud/instances[/{name}[/start|/stop|/metrics|/advisors]]
/// Mandant:          /api/v1/workloads/classes, /api/v1/workloads/mappings, /api/v1/monitoring[/traces|/issues|/access|
///                   /trace-settings], /api/v1/advisors[/run], /api/v1/views[/{name}[/data|/sql]], /api/v1/bindings,
///                   /api/v1/dataproducts[/{id}[/install]], /api/v1/assistant
module neko.database.presentation.rest.cloud;

import neko.database.domain;
import neko.database.persistence.mappers : toDomain, toRecord;
import neko.database.persistence.records : CalcViewRecord;
import neko.database.ports;
import neko.database.presentation.rest.services : writeRestError;
import std.algorithm : map;
import std.array : array, split;
import std.conv : to;
import std.string : strip;
import vibe.data.json : Json, deserializeJson, serializeToJson;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;
import vibe.textfilter.urlencode : urlDecode;

@safe:

// --- JSON-Darstellung ---

Json cloudJson(InstanceInfo i) {
    auto j = serializeToJson(toRecord(i.instance));
    j["status"] = enumName(i.status);
    j["vcpus"] = i.vcpus;
    j["users"] = i.users;
    j["networks"] = serializeToJson(i.networks);
    j["version"] = i.instance.version_;
    j.remove("version_");
    return j;
}

Json cloudJson(Recommendation r) {
    auto j = serializeToJson(r);
    j["advisor"] = enumName(r.advisor);
    j["severity"] = enumName(r.severity);
    return j;
}

Json cloudJson(CalculationView v) {
    auto j = serializeToJson(toRecord(v));
    j["outputColumns"] = serializeToJson(outputColumns(v));
    j["tables"] = serializeToJson(tablesOf(v));
    return j;
}

Json cloudJson(MonitoringOverview o) {
    auto j = Json.emptyObject;
    j["tenant"] = o.tenant;
    j["instance"] = o.hasInstance ? cloudJson(o.instance) : Json(null);
    j["current"] = serializeToJson(o.current);
    j["samples"] = serializeToJson(o.samples);
    j["statements"] = o.statements;
    j["errors"] = o.errors;
    j["expensive"] = o.expensive;
    j["violations"] = o.violations;
    j["settings"] = serializeToJson(o.settings);
    j["topExpensive"] = serializeToJson(o.topExpensive);
    j["workers"] = o.workers;
    return j;
}

Json cloudJson(DataProductInfo p) {
    auto j = serializeToJson(p.product);
    j["version"] = p.product.version_;
    j.remove("version_");
    j["rows"] = p.rows;
    j["installed"] = p.installed;
    j["installation"] = p.installed ? serializeToJson(p.installation) : Json(null);
    return j;
}

Json cloudJson(QueryResult r) {
    auto rows = Json.emptyArray;
    foreach (row; r.rows) {
        auto o = Json.emptyObject;
        foreach (i, v; row)
            o[i < r.columns.length ? r.columns[i] : "c" ~ i.to!string] = valueJson(v);
        rows ~= o;
    }
    auto j = Json.emptyObject;
    j["columns"] = serializeToJson(r.columns);
    j["rows"] = rows;
    j["count"] = r.rows.length;
    return j;
}

/// Wert einer Zelle: Zahlen als Zahl, alles andere als Text.
Json valueJson(Value v) {
    if (isNull(v))
        return Json(null);
    if (auto l = v.peek!long)
        return Json(*l);
    if (auto d = v.peek!double)
        return Json(*d);
    if (auto b = v.peek!bool)
        return Json(*b);
    return Json(valueText(v));
}

// --- Eingaben ---

InstanceSpec instanceSpec(Json j) {
    InstanceSpec s;
    s.name = j["name"].opt!string;
    s.description = j["description"].opt!string;
    s.adminName = j["adminName"].opt!string("admin");
    s.adminPassword = j["adminPassword"].opt!string;
    if (j["performanceClass"].type == Json.Type.string)
        s.performanceClass = parseEnum!PerformanceClass(j["performanceClass"].get!string);
    s.memoryGb = sizeOf(j["memoryGb"], 32);
    s.storageGb = sizeOf(j["storageGb"], 0);
    s.nseEnabled = j["nseEnabled"].opt!bool;
    s.ecnNodes = sizeOf(j["ecnNodes"], 0);
    return s;
}

InstancePatch instancePatch(Json j) {
    InstancePatch p;
    if (j["description"].type == Json.Type.string) {
        p.hasDescription = true;
        p.description = j["description"].get!string;
    }
    if (j["memoryGb"].type != Json.Type.undefined) {
        p.hasSizing = true;
        p.memoryGb = sizeOf(j["memoryGb"], 0);
        p.storageGb = sizeOf(j["storageGb"], 0);
    }
    if (j["performanceClass"].type == Json.Type.string) {
        p.hasClass = true;
        p.performanceClass = parseEnum!PerformanceClass(j["performanceClass"].get!string);
    }
    if (j["nseEnabled"].type == Json.Type.bool_) {
        p.hasNse = true;
        p.nseEnabled = j["nseEnabled"].get!bool;
    }
    if (j["ecnNodes"].type != Json.Type.undefined) {
        p.hasEcn = true;
        p.ecnNodes = sizeOf(j["ecnNodes"], 0);
    }
    return p;
}

CalculationView calcView(Json j, string name) {
    if (name.length)
        j["name"] = name;
    if (j["baseTable"].type == Json.Type.undefined)
        j["baseTable"] = "";
    return toDomain(deserializeJson!CalcViewRecord(j));
}

WorkloadClass workloadClass(Json j, string name) {
    WorkloadClass c;
    c.name = name.length ? name : j["name"].opt!string;
    c.priority = cast(int) sizeOf(j["priority"], 5);
    c.statementTimeoutSeconds = sizeOf(j["statementTimeoutSeconds"], 0);
    c.statementMemoryLimitMb = sizeOf(j["statementMemoryLimitMb"], 0);
    c.totalStatementLimit = sizeOf(j["totalStatementLimit"], 0);
    c.statementThreadLimit = sizeOf(j["statementThreadLimit"], 0);
    c.enabled = j["enabled"].opt!bool(true);
    c.description = j["description"].opt!string;
    return c;
}

WorkloadMapping workloadMapping(Json j, string name) {
    return WorkloadMapping(name.length ? name : j["name"].opt!string, j["workloadClass"].opt!string,
        j["userName"].opt!string, j["roleName"].opt!string);
}

TraceSettings traceSettings(Json j, TraceSettings base) {
    if (j["sqlTrace"].type == Json.Type.bool_)
        base.sqlTrace = j["sqlTrace"].get!bool;
    if (j["traceErrors"].type == Json.Type.bool_)
        base.traceErrors = j["traceErrors"].get!bool;
    if (j["expensiveThresholdMs"].type != Json.Type.undefined)
        base.expensiveThresholdMs = sizeOf(j["expensiveThresholdMs"], 0);
    if (j["maxEntries"].type != Json.Type.undefined)
        base.maxEntries = sizeOf(j["maxEntries"], 2000);
    return base;
}

private size_t sizeOf(Json j, size_t fallback) {
    switch (j.type) {
    case Json.Type.int_:
        auto v = j.get!long;
        if (v < 0)
            throw new Exception("Negative values are not allowed");
        return cast(size_t) v;
    case Json.Type.float_:
        return cast(size_t) j.get!double;
    case Json.Type.string:
        return j.get!string.strip.to!size_t;
    default:
        return fallback;
    }
}

/// Öffentliche Adresse aus der Anfrage (hinter einem Proxy aus X-Forwarded-Proto und -Host).
string requestBaseUrl(HTTPServerRequest req, string configured) {
    if (configured.length)
        return configured;
    auto proto = req.headers.get("X-Forwarded-Proto", req.tls ? "https" : "http");
    auto host = req.headers.get("X-Forwarded-Host", req.host);
    return proto ~ "://" ~ host;
}

// --- Routen ---

/// Alle Cloud-Dienste, wie app.d sie verdrahtet. Fehlende (null) Dienste haben keine Routen.
struct CloudUseCases {
    IInstanceUseCase instances;
    IWorkloadUseCase workloads;
    IMonitoringUseCase monitoring;
    IAdvisorUseCase advisors;
    ICalcViewUseCase views;
    IBindingUseCase bindings;
    IDataProductUseCase products;
    IAssistantUseCase assistant;
    string publicUrl; // leer: aus der Anfrage
}

void registerCloudRestApi(URLRouter router, CloudUseCases u, Principal delegate() @safe current) {
    alias Handler = Json delegate(HTTPServerRequest req, Principal actor) @safe;

    void route(string method, string path, Handler h, int status = 200) {
        auto handler = (HTTPServerRequest req, HTTPServerResponse res) @safe {
            try {
                auto result = h(req, current());
                res.statusCode = result.type == Json.Type.undefined ? HTTPStatus.noContent : status;
                if (result.type == Json.Type.undefined)
                    res.writeVoidBody();
                else
                    res.writeJsonBody(result);
            } catch (Exception e)
                writeRestError(res, e);
        };
        switch (method) {
        case "GET":
            router.get(path, handler);
            break;
        case "POST":
            router.post(path, handler);
            break;
        case "PUT":
            router.put(path, handler);
            break;
        case "PATCH":
            router.patch(path, handler);
            break;
        default:
            router.delete_(path, handler);
        }
    }

    Json body_(HTTPServerRequest req) {
        auto j = req.json;
        return j.type == Json.Type.object ? j : Json.emptyObject;
    }

    string param(HTTPServerRequest req, string name) {
        return urlDecode(req.params[name]);
    }

    enum base = "/api/v1";
    if (auto i = u.instances) {
        route("GET", base ~ "/cloud/instances", (req, a) => Json(i.listInstances(a).map!(x => cloudJson(x)).array));
        route("POST", base ~ "/cloud/instances", (req, a) => cloudJson(i.createInstance(a, instanceSpec(body_(req)))), 201);
        route("GET", base ~ "/cloud/instances/:name", (req, a) => cloudJson(i.getInstance(a, param(req, "name"))));
        route("PATCH", base ~ "/cloud/instances/:name", (req, a) => cloudJson(i.updateInstance(a, param(req, "name"),
                instancePatch(body_(req)))));
        route("DELETE", base ~ "/cloud/instances/:name", (req, a) {
            i.deleteInstance(a, param(req, "name"));
            return Json.undefined;
        });
        route("POST", base ~ "/cloud/instances/:name/start", (req, a) => cloudJson(i.startInstance(a, param(req, "name"))));
        route("POST", base ~ "/cloud/instances/:name/stop", (req, a) => cloudJson(i.stopInstance(a, param(req, "name"))));
        route("GET", base ~ "/cloud/instances/:name/metrics", (req, a) => serializeToJson(i.instanceMetrics(a,
                param(req, "name"))));
        route("GET", base ~ "/cloud/instances/:name/advisors", (req, a) => Json(i.instanceAdvisors(a, param(req, "name"))
                .map!(x => cloudJson(x)).array));
    }
    if (auto w = u.workloads) {
        route("GET", base ~ "/workloads/classes", (req, a) => serializeToJson(w.listClasses(a)));
        route("POST", base ~ "/workloads/classes", (req, a) => serializeToJson(w.saveClass(a, workloadClass(body_(req), ""))), 201);
        route("PUT", base ~ "/workloads/classes/:name", (req, a) => serializeToJson(w.saveClass(a,
                workloadClass(body_(req), param(req, "name")))));
        route("DELETE", base ~ "/workloads/classes/:name", (req, a) {
            w.deleteClass(a, param(req, "name"));
            return Json.undefined;
        });
        route("GET", base ~ "/workloads/mappings", (req, a) => serializeToJson(w.listMappings(a)));
        route("POST", base ~ "/workloads/mappings", (req, a) => serializeToJson(w.saveMapping(a,
                workloadMapping(body_(req), ""))), 201);
        route("PUT", base ~ "/workloads/mappings/:name", (req, a) => serializeToJson(w.saveMapping(a,
                workloadMapping(body_(req), param(req, "name")))));
        route("DELETE", base ~ "/workloads/mappings/:name", (req, a) {
            w.deleteMapping(a, param(req, "name"));
            return Json.undefined;
        });
    }
    if (auto m = u.monitoring) {
        route("GET", base ~ "/monitoring", (req, a) => cloudJson(m.overview(a)));
        route("GET", base ~ "/monitoring/traces", (req, a) {
            TraceQuery q;
            q.kind = req.query.get("kind", "");
            q.user = req.query.get("user", "");
            q.text = req.query.get("text", "");
            q.limit = req.query.get("limit", "200").to!size_t;
            return serializeToJson(m.traces(a, q));
        });
        route("DELETE", base ~ "/monitoring/traces", (req, a) {
            m.clearTraces(a);
            return Json.undefined;
        });
        route("GET", base ~ "/monitoring/trace-settings", (req, a) => serializeToJson(m.traceSettings(a)));
        route("PUT", base ~ "/monitoring/trace-settings", (req, a) => serializeToJson(m.configureTrace(a,
                traceSettings(body_(req), m.traceSettings(a)))));
        route("GET", base ~ "/monitoring/access", (req, a) => serializeToJson(m.tableAccess(a)));
        route("GET", base ~ "/monitoring/issues", (req, a) => serializeToJson(m.issueSummary(a)));
    }
    if (auto adv = u.advisors) {
        route("GET", base ~ "/advisors", (req, a) => Json(adv.recommendations(a).map!(x => cloudJson(x)).array));
        route("POST", base ~ "/advisors/run", (req, a) {
            AdvisorKind[] kinds;
            auto b = body_(req);
            if (b["advisors"].type == Json.Type.array)
                foreach (k; b["advisors"].get!(Json[]))
                    kinds ~= parseEnum!AdvisorKind(k.get!string);
            else if (req.query.get("advisors", "").length)
                foreach (k; req.query["advisors"].split(","))
                    kinds ~= parseEnum!AdvisorKind(k);
            return Json(adv.runAdvisors(a, kinds).map!(x => cloudJson(x)).array);
        });
    }
    if (auto v = u.views) {
        CalcQuery queryOf(HTTPServerRequest req) {
            return CalcQuery(req.query.get("filter", ""), req.query.get("orderby", ""),
                req.query.get("top", "0").to!size_t, req.query.get("skip", "0").to!size_t);
        }

        route("GET", base ~ "/views", (req, a) => Json(v.listViews(a).map!(x => cloudJson(x)).array));
        route("POST", base ~ "/views", (req, a) => cloudJson(v.saveView(a, calcView(body_(req), ""))), 201);
        route("GET", base ~ "/views/:name", (req, a) => cloudJson(v.getView(a, param(req, "name"))));
        route("PUT", base ~ "/views/:name", (req, a) => cloudJson(v.saveView(a, calcView(body_(req), param(req, "name")))));
        route("DELETE", base ~ "/views/:name", (req, a) {
            v.deleteView(a, param(req, "name"));
            return Json.undefined;
        });
        route("GET", base ~ "/views/:name/data", (req, a) => cloudJson(v.queryView(a, param(req, "name"), queryOf(req))));
        route("GET", base ~ "/views/:name/sql", (req, a) => Json(["sql": Json(v.viewSql(a, param(req, "name"),
                queryOf(req)))]));
    }
    if (auto b = u.bindings) {
        route("GET", base ~ "/bindings", (req, a) => serializeToJson(b.listBindings(a)));
        route("POST", base ~ "/bindings", (req, a) {
            auto j = body_(req);
            auto r = b.createBinding(a, j["name"].opt!string, j["application"].opt!string, j["role"].opt!string,
                requestBaseUrl(req, u.publicUrl));
            auto out_ = Json.emptyObject;
            out_["binding"] = serializeToJson(r.binding);
            out_["credentials"] = serializeToJson(r.credentials);
            return out_;
        }, 201);
        route("DELETE", base ~ "/bindings/:name", (req, a) {
            b.deleteBinding(a, param(req, "name"));
            return Json.undefined;
        });
    }
    if (auto p = u.products) {
        route("GET", base ~ "/dataproducts", (req, a) => Json(p.catalog(a).map!(x => cloudJson(x)).array));
        route("GET", base ~ "/dataproducts/:id", (req, a) => cloudJson(p.product(a, param(req, "id"))));
        route("POST", base ~ "/dataproducts/:id/install", (req, a) => serializeToJson(p.install(a, param(req, "id"))), 201);
        route("DELETE", base ~ "/dataproducts/:id/install", (req, a) {
            p.uninstall(a, param(req, "id"));
            return Json.undefined;
        });
    }
    if (auto s = u.assistant)
        route("POST", base ~ "/assistant", (req, a) => serializeToJson(s.ask(a, body_(req)["message"].opt!string)));
}
