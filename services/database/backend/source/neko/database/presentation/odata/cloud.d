/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// OData-4.0-Dienst der Cloud-Funktionen unter /odata/v4/cloud, für SAP-Fiori-3-Oberflächen.
///
/// Systemadministratoren sehen das Entity Set Instances; Benutzer eines Mandanten sehen WorkloadClasses,
/// WorkloadMappings, Traces, Metrics, TableAccess, Recommendations, CalculationViews, Bindings, DataProducts und je
/// Calculation View ein eigenes Entity Set CV_<name> mit den Merkmalen und Kennzahlen als Eigenschaften
/// (Beschreibungen als Core.Description). $metadata hängt deshalb von der Anmeldung ab.
///
/// Unterstützt: $filter (eq, ne, gt, ge, lt, le, contains, startswith mit and), $select, $orderby, $top, $skip,
/// $count. Aktionen: StartInstance, StopInstance, RunAdvisors, InstallDataProduct, UninstallDataProduct,
/// ClearTraces, Ask; Funktion IssueSummary.
module neko.database.presentation.odata.cloud;

import neko.database.domain;
import neko.database.ports;
import neko.database.presentation.odata.errors;
import neko.database.presentation.rest.cloud : CloudUseCases, calcView, instancePatch, instanceSpec, valueJson,
    workloadClass, workloadMapping;
import std.algorithm : all, any, canFind, filter, map, sort, startsWith;
import std.array : appender, array, join, replace, split;
import std.conv : to;
import std.string : indexOf, strip, toLower;
import vibe.data.json : Json, parseJsonString;
import vibe.http.common : HTTPMethod;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.stream.operations : readAllUTF8;
import vibe.textfilter.urlencode : urlDecode;

@safe:

enum cloudNamespace = "hdb.cloud";

struct EdmProperty {
    string name;
    string type = "Edm.String";
    bool nullable = true;
    string description;
}

/// Ein Entity Set mit seinen Handlern. Fehlende Handler bedeuten: diese Methode ist nicht erlaubt.
struct EntitySetDef {
    string name, typeName, key;
    EdmProperty[] properties;
    string description;
    Json[] delegate() @safe list;
    Json delegate(Json) @safe create;
    Json delegate(string, Json) @safe update;
    void delegate(string) @safe remove;
}

struct OperationDef {
    string name;
    bool isFunction;
    EdmProperty[] parameters;
    string returnType; // leer: keine Rückgabe
    string entitySet; // bei Rückgabe eines Entity-Typs
    Json delegate(Json) @safe run;
}

final class CloudODataController {
    enum root = "/odata/v4/cloud";
    private CloudUseCases u;
    private Principal delegate() @safe current;

    this(CloudUseCases u, Principal delegate() @safe current) {
        this.u = u;
        this.current = current;
    }

    void register(URLRouter router) {
        router.any(root, &dispatch);
        router.any(root ~ "/*", &dispatch);
    }

    private void dispatch(HTTPServerRequest req, HTTPServerResponse res) {
        res.headers["OData-Version"] = "4.0";
        try
            route(req, res);
        catch (ODataError e)
            writeError(res, e.status, e.code, e.msg);
        catch (AuthenticationRequired e)
            writeError(res, 401, "Unauthorized", e.msg);
        catch (AccessDenied e)
            writeError(res, 403, "Forbidden", e.msg);
        catch (NotFound e)
            writeError(res, 404, "NotFound", e.msg);
        catch (Conflict e)
            writeError(res, 409, "Conflict", e.msg);
        catch (WorkloadLimitExceeded e)
            writeError(res, 429, "TooManyRequests", e.msg);
        catch (Exception e)
            writeError(res, 400, "BadRequest", e.msg);
    }

    private void route(HTTPServerRequest req, HTTPServerResponse res) {
        auto actor = current();
        if (!actor.authenticated)
            throw new AuthenticationRequired;
        auto path = req.requestPath.toString[root.length .. $];
        if (path.startsWith("/"))
            path = path[1 .. $];
        auto sets = entitySets(actor);
        auto ops = operations(actor);
        if (path.length == 0)
            return writeJson(res, 200, serviceDocument(sets, ops));
        if (path == "$metadata")
            return res.writeBody(metadataXml(sets, ops), "application/xml");
        if (path == "$batch")
            throw notImplemented("$batch is not supported");

        auto paren = path.indexOf('(');
        auto name = paren >= 0 ? path[0 .. paren] : path.split("/")[0];
        foreach (op; ops)
            if (op.name == name)
                return operation(req, res, op, paren >= 0 ? path[paren .. $] : "");
        EntitySetDef set;
        bool found;
        foreach (s; sets)
            if (s.name == name) {
                set = s;
                found = true;
            }
        if (!found)
            throw notFound("Unknown entity set: " ~ name);
        if (paren >= 0) {
            auto close = path.indexOf(')');
            if (close < paren)
                throw badRequest("Invalid key");
            return entity(req, res, set, keyText(path[paren + 1 .. close]));
        }
        auto rest = path[name.length .. $];
        if (rest == "/$count")
            return res.writeBody(applyQuery(req, set, set.list()).length.to!string, "text/plain");
        if (rest.length)
            throw notFound("Unknown path segment: " ~ rest);
        switch (req.method) {
        case HTTPMethod.GET:
            auto rows = applyQuery(req, set, set.list());
            auto total = rows.length;
            rows = page(req, rows);
            auto out_ = Json.emptyObject;
            out_["@odata.context"] = "$metadata#" ~ set.name;
            if (req.query.get("$count", "") == "true")
                out_["@odata.count"] = total;
            out_["value"] = Json(rows.map!(r => select(req, r)).array);
            return writeJson(res, 200, out_);
        case HTTPMethod.POST:
            if (set.create is null)
                throw new ODataError(405, "MethodNotAllowed", set.name ~ " is read-only");
            return writeJson(res, 201, withContext(set, set.create(readBody(req))));
        default:
            throw new ODataError(405, "MethodNotAllowed", "Method not allowed");
        }
    }

    private void entity(HTTPServerRequest req, HTTPServerResponse res, EntitySetDef set, string key) {
        switch (req.method) {
        case HTTPMethod.GET:
            foreach (r; set.list())
                if (r[set.key].type != Json.Type.undefined && plain(r[set.key]) == key)
                    return writeJson(res, 200, withContext(set, select(req, r)));
            throw notFound("No " ~ set.typeName ~ " " ~ key);
        case HTTPMethod.PATCH:
        case HTTPMethod.PUT:
            if (set.update is null)
                throw new ODataError(405, "MethodNotAllowed", set.name ~ " can't be changed");
            return writeJson(res, 200, withContext(set, set.update(key, readBody(req))));
        case HTTPMethod.DELETE:
            if (set.remove is null)
                throw new ODataError(405, "MethodNotAllowed", set.name ~ " can't be deleted");
            set.remove(key);
            res.statusCode = 204;
            return res.writeVoidBody();
        default:
            throw new ODataError(405, "MethodNotAllowed", "Method not allowed");
        }
    }

    private void operation(HTTPServerRequest req, HTTPServerResponse res, OperationDef op, string args) {
        Json params = Json.emptyObject;
        if (op.isFunction) {
            if (req.method != HTTPMethod.GET)
                throw new ODataError(405, "MethodNotAllowed", "Functions are called with GET");
            // IssueSummary() oder IssueSummary(name='x')
            auto inner = args.length >= 2 ? args[1 .. $ - 1] : "";
            foreach (part; inner.split(","))
                if (auto eq = part.indexOf('='))
                    if (eq > 0)
                        params[part[0 .. eq].strip] = keyText(part[eq + 1 .. $].strip);
        } else {
            if (req.method != HTTPMethod.POST)
                throw new ODataError(405, "MethodNotAllowed", "Actions are called with POST");
            params = readBody(req);
        }
        foreach (p; op.parameters)
            if (!p.nullable && params[p.name].type == Json.Type.undefined)
                throw badRequest("Missing parameter " ~ p.name);
        auto result = op.run(params);
        if (op.returnType.length == 0) {
            res.statusCode = 204;
            return res.writeVoidBody();
        }
        if (op.entitySet.length) {
            auto ctx = op.returnType.startsWith("Collection(") ? op.entitySet : op.entitySet ~ "/$entity";
            if (result.type == Json.Type.array) {
                auto wrap = Json.emptyObject;
                wrap["@odata.context"] = "$metadata#" ~ ctx;
                wrap["value"] = result;
                return writeJson(res, 200, wrap);
            }
            result["@odata.context"] = "$metadata#" ~ ctx;
            return writeJson(res, 200, result);
        }
        auto wrap = Json.emptyObject;
        wrap["@odata.context"] = "$metadata#" ~ op.returnType;
        wrap["value"] = result;
        writeJson(res, 200, wrap);
    }

    // --- Modell ---

    EntitySetDef[] entitySets(Principal actor) {
        EntitySetDef[] sets;
        if (actor.isSystem) {
            if (auto i = u.instances)
                sets ~= EntitySetDef("Instances", "Instance", "name", instanceProperties,
                    "Database instances with size, performance class and status",
                    () => i.listInstances(actor).map!(x => instanceRow(x)).array,
                    (Json j) => instanceRow(i.createInstance(actor, instanceSpec(fromOData(j)))),
                    (string k, Json j) => instanceRow(i.updateInstance(actor, k, instancePatch(fromOData(j)))),
                    (string k) { i.deleteInstance(actor, k); });
            return sets;
        }
        if (auto w = u.workloads) {
            sets ~= EntitySetDef("WorkloadClasses", "WorkloadClass", "name", [EdmProperty("name", "Edm.String", false),
                    EdmProperty("priority", "Edm.Int32"), EdmProperty("statementTimeoutSeconds", "Edm.Int32"),
                    EdmProperty("statementMemoryLimitMb", "Edm.Int32"), EdmProperty("totalStatementLimit", "Edm.Int32"),
                    EdmProperty("statementThreadLimit", "Edm.Int32"), EdmProperty("enabled", "Edm.Boolean"),
                    EdmProperty("description")], "Workload classes with limits",
                () => w.listClasses(actor).map!(c => classRow(c)).array,
                (Json j) => classRow(w.saveClass(actor, workloadClass(j, ""))),
                (string k, Json j) {
                    auto merged = Json.emptyObject;
                    foreach (c; w.listClasses(actor))
                        if (c.name == k)
                            merged = classRow(c);
                    foreach (f, v; j.get!(Json[string]))
                        merged[f] = v;
                    return classRow(w.saveClass(actor, workloadClass(merged, k)));
                }, (string k) { w.deleteClass(actor, k); });
            sets ~= EntitySetDef("WorkloadMappings", "WorkloadMapping", "name", [EdmProperty("name", "Edm.String", false),
                    EdmProperty("workloadClass"), EdmProperty("userName"), EdmProperty("roleName")],
                "Users and roles mapped to workload classes",
                () => w.listMappings(actor).map!(m => mappingRow(m)).array,
                (Json j) => mappingRow(w.saveMapping(actor, workloadMapping(j, ""))),
                (string k, Json j) => mappingRow(w.saveMapping(actor, workloadMapping(j, k))),
                (string k) { w.deleteMapping(actor, k); });
        }
        if (auto m = u.monitoring) {
            sets ~= EntitySetDef("Traces", "Trace", "id", [EdmProperty("id", "Edm.Int32", false),
                    EdmProperty("time", "Edm.DateTimeOffset"), EdmProperty("user"), EdmProperty("kind"),
                    EdmProperty("statement"), EdmProperty("verb"), EdmProperty("tables"),
                    EdmProperty("durationMs", "Edm.Double"), EdmProperty("rows", "Edm.Int32"),
                    EdmProperty("affected", "Edm.Int32"), EdmProperty("error"), EdmProperty("workloadClass")],
                "SQL trace, expensive statements, errors and workload violations",
                () => m.traces(actor, TraceQuery("", "", "", 0)).map!(t => traceRow(t)).array);
            sets ~= EntitySetDef("Metrics", "Metric", "time", [EdmProperty("time", "Edm.DateTimeOffset", false),
                    EdmProperty("statements", "Edm.Int32"), EdmProperty("errors", "Edm.Int32"),
                    EdmProperty("expensive", "Edm.Int32"), EdmProperty("avgMs", "Edm.Double"),
                    EdmProperty("maxMs", "Edm.Double"), EdmProperty("tables", "Edm.Int32"), EdmProperty("rows", "Edm.Double"),
                    EdmProperty("memoryBytes", "Edm.Double"), EdmProperty("cpuPercent", "Edm.Double"),
                    EdmProperty("residentBytes", "Edm.Double"), EdmProperty("reads", "Edm.Int32"),
                    EdmProperty("writes", "Edm.Int32")], "Metric samples, one per interval",
                () => m.overview(actor).samples.map!(s => metricRow(s)).array);
            sets ~= EntitySetDef("TableAccess", "TableAccessEntry", "table", [EdmProperty("table", "Edm.String", false),
                    EdmProperty("reads", "Edm.Int32"), EdmProperty("writes", "Edm.Int32"),
                    EdmProperty("filters", "Edm.Int32"), EdmProperty("filterColumns"),
                    EdmProperty("lastAccess", "Edm.DateTimeOffset")], "Accesses per table since start",
                () => m.tableAccess(actor).map!(a => accessRow(a)).array);
        }
        if (auto adv = u.advisors)
            sets ~= EntitySetDef("Recommendations", "Recommendation", "id", [EdmProperty("id", "Edm.String", false),
                    EdmProperty("advisor"), EdmProperty("severity"), EdmProperty("target"), EdmProperty("title"),
                    EdmProperty("detail"), EdmProperty("action"), EdmProperty("executable", "Edm.Boolean"),
                    EdmProperty("benefit", "Edm.Double"), EdmProperty("createdAt", "Edm.DateTimeOffset")],
                "Recommendations of the Index, NSE, Partition, Performance Class and ECN advisors",
                () => adv.recommendations(actor).map!(r => recommendationRow(r)).array);
        if (auto v = u.views) {
            auto views = v.listViews(actor);
            sets ~= EntitySetDef("CalculationViews", "CalculationView", "name", [EdmProperty("name", "Edm.String", false),
                    EdmProperty("label"), EdmProperty("description"), EdmProperty("viewType"), EdmProperty("baseTable"),
                    EdmProperty("tables"), EdmProperty("attributes"), EdmProperty("measures"), EdmProperty("filter"),
                    EdmProperty("entitySet"), EdmProperty("createdBy"), EdmProperty("updatedAt", "Edm.DateTimeOffset")],
                "Calculation view definitions", () => views.map!(x => viewRow(x)).array,
                (Json j) => viewRow(v.saveView(actor, calcView(j, ""))), null,
                (string k) { v.deleteView(actor, k); });
            foreach (view; views)
                sets ~= viewSet(actor, v, view);
        }
        if (auto b = u.bindings)
            sets ~= EntitySetDef("Bindings", "Binding", "name", [EdmProperty("name", "Edm.String", false),
                    EdmProperty("application"), EdmProperty("tenant"), EdmProperty("user"), EdmProperty("role"),
                    EdmProperty("createdAt", "Edm.DateTimeOffset"), EdmProperty("createdBy")],
                "Applications bound to this instance (credentials only via REST at creation)",
                () => b.listBindings(actor).map!(x => bindingRow(x)).array, null, null,
                (string k) { b.deleteBinding(actor, k); });
        if (auto p = u.products)
            sets ~= EntitySetDef("DataProducts", "DataProduct", "id", [EdmProperty("id", "Edm.String", false),
                    EdmProperty("title"), EdmProperty("description"), EdmProperty("provider"), EdmProperty("version"),
                    EdmProperty("tags"), EdmProperty("tables"), EdmProperty("rows", "Edm.Int32"),
                    EdmProperty("installed", "Edm.Boolean"), EdmProperty("installedAt", "Edm.DateTimeOffset"),
                    EdmProperty("installedTables")], "Data products shared to this environment",
                () => p.catalog(actor).map!(x => productRow(x)).array);
        return sets;
    }

    OperationDef[] operations(Principal actor) {
        OperationDef[] ops;
        auto name = [EdmProperty("name", "Edm.String", false)];
        if (actor.isSystem) {
            if (auto i = u.instances) {
                ops ~= OperationDef("StartInstance", false, name, cloudNamespace ~ ".Instance", "Instances",
                    (Json p) => instanceRow(i.startInstance(actor, p["name"].get!string)));
                ops ~= OperationDef("StopInstance", false, name, cloudNamespace ~ ".Instance", "Instances",
                    (Json p) => instanceRow(i.stopInstance(actor, p["name"].get!string)));
            }
        } else {
            if (auto adv = u.advisors)
                ops ~= OperationDef("RunAdvisors", false, [EdmProperty("advisors")],
                    "Collection(" ~ cloudNamespace ~ ".Recommendation)", "Recommendations", (Json p) {
                    AdvisorKind[] kinds;
                    if (p["advisors"].type == Json.Type.string)
                        foreach (k; p["advisors"].get!string.split(","))
                            if (k.strip.length)
                                kinds ~= parseEnum!AdvisorKind(k);
                    return Json(adv.runAdvisors(actor, kinds).map!(r => recommendationRow(r)).array);
                });
            if (auto pr = u.products) {
                auto id = [EdmProperty("id", "Edm.String", false)];
                ops ~= OperationDef("InstallDataProduct", false, id, "", "", (Json p) {
                    pr.install(actor, p["id"].get!string);
                    return Json.undefined;
                });
                ops ~= OperationDef("UninstallDataProduct", false, id, "", "", (Json p) {
                    pr.uninstall(actor, p["id"].get!string);
                    return Json.undefined;
                });
            }
            if (auto m = u.monitoring) {
                ops ~= OperationDef("ClearTraces", false, null, "", "", (Json p) {
                    m.clearTraces(actor);
                    return Json.undefined;
                });
                ops ~= OperationDef("IssueSummary", true, null, "Edm.String", "", (Json p) => Json(m.issueSummary(actor).text));
            }
        }
        if (auto a = u.assistant)
            ops ~= OperationDef("Ask", false, [EdmProperty("message", "Edm.String", false)], "Edm.String", "",
                (Json p) => Json(a.ask(actor, p["message"].get!string).text));
        return ops;
    }

    private EntitySetDef viewSet(Principal actor, ICalcViewUseCase v, CalculationView view) {
        EdmProperty[] props = [EdmProperty("ID", "Edm.Int32", false, "Row number")];
        foreach (a; view.attributes)
            props ~= EdmProperty(outputName(a), "Edm.String", true, a.description.length ? a.description : a.column);
        foreach (m; view.measures)
            props ~= EdmProperty(outputName(m), m.aggregation == Aggregation.count || m.aggregation == Aggregation.countDistinct
                    ? "Edm.Int64" : "Edm.Double", true,
                    m.description.length ? m.description : enumName(m.aggregation) ~ " of " ~ m.column);
        auto name = view.name;
        return EntitySetDef("CV_" ~ name, "CV_" ~ name ~ "Type", "ID", props,
            view.label.length ? view.label : view.description, () {
            auto r = v.queryView(actor, name, CalcQuery.init);
            Json[] rows;
            foreach (i, row; r.rows) {
                auto o = Json.emptyObject;
                o["ID"] = cast(long) i + 1;
                foreach (c, value; row) {
                    auto j = valueJson(value);
                    // Merkmale sind Text, Kennzahlen Zahlen (Int64 als Text wegen IEEE754Compatible)
                    if (c < view.attributes.length)
                        o[r.columns[c]] = j.type == Json.Type.null_ ? j : Json(plain(j));
                    else if (props[c + 1].type == "Edm.Int64")
                        o[r.columns[c]] = j.type == Json.Type.null_ ? j : Json(plain(j));
                    else
                        o[r.columns[c]] = j.type == Json.Type.int_ ? Json(cast(double) j.get!long) : j;
                }
                rows ~= o;
            }
            return rows;
        });
    }

    // --- Abfrageoptionen ---

    private Json[] applyQuery(HTTPServerRequest req, EntitySetDef set, Json[] rows) {
        foreach (name, value; req.query.byKeyValue)
            if (name.startsWith("$") && !["$filter", "$select", "$orderby", "$top", "$skip", "$count", "$format"].canFind(name))
                throw notImplemented(name ~ " is not supported");
        auto f = req.query.get("$filter", "");
        if (f.length) {
            auto conds = parseFilter(f);
            rows = rows.filter!(r => conds.all!(c => c.matches(r))).array;
        }
        auto order = req.query.get("$orderby", "");
        if (order.length) {
            auto parts = order.strip.split(" ");
            auto field = parts[0];
            immutable desc = parts.length > 1 && parts[$ - 1].toLower == "desc";
            if (!set.properties.any!(p => p.name == field))
                throw badRequest("Unknown property in $orderby: " ~ field);
            rows.sort!((a, b) => desc ? less(b[field], a[field]) : less(a[field], b[field]));
        }
        return rows;
    }

    private Json[] page(HTTPServerRequest req, Json[] rows) {
        auto skip = req.query.get("$skip", "0").to!size_t;
        auto top = req.query.get("$top", "0").to!size_t;
        if (skip >= rows.length)
            return null;
        rows = rows[skip .. $];
        return top && top < rows.length ? rows[0 .. top] : rows;
    }

    private Json select(HTTPServerRequest req, Json row) {
        auto s = req.query.get("$select", "");
        if (s.length == 0)
            return row;
        auto out_ = Json.emptyObject;
        foreach (f; s.split(","))
            if (row[f.strip].type != Json.Type.undefined)
                out_[f.strip] = row[f.strip];
        return out_;
    }

    // --- Ausgabe ---

    private Json serviceDocument(EntitySetDef[] sets, OperationDef[] ops) {
        auto value = Json.emptyArray;
        foreach (s; sets)
            value ~= Json(["name": Json(s.name), "kind": Json("EntitySet"), "url": Json(s.name)]);
        foreach (o; ops)
            if (o.isFunction)
                value ~= Json(["name": Json(o.name), "kind": Json("FunctionImport"), "url": Json(o.name)]);
        auto j = Json.emptyObject;
        j["@odata.context"] = "$metadata";
        j["value"] = value;
        return j;
    }

    private Json withContext(EntitySetDef set, Json row) {
        row["@odata.context"] = "$metadata#" ~ set.name ~ "/$entity";
        return row;
    }
}

/// CSDL der Entity Sets und Operationen.
string metadataXml(EntitySetDef[] sets, OperationDef[] ops) {
    auto x = appender!string;
    x ~= `<?xml version="1.0" encoding="utf-8"?>`;
    x ~= `<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">`;
    x ~= `<edmx:Reference Uri="https://oasis-tcs.github.io/odata-vocabularies/vocabularies/Org.OData.Core.V1.xml">`;
    x ~= `<edmx:Include Namespace="Org.OData.Core.V1" Alias="Core"/></edmx:Reference>`;
    x ~= `<edmx:DataServices><Schema Namespace="` ~ cloudNamespace ~ `" xmlns="http://docs.oasis-open.org/odata/ns/edm">`;
    foreach (s; sets) {
        x ~= `<EntityType Name="` ~ s.typeName ~ `"><Key><PropertyRef Name="` ~ s.key ~ `"/></Key>`;
        foreach (p; s.properties)
            x ~= `<Property Name="` ~ p.name ~ `" Type="` ~ p.type ~ `"` ~ (p.nullable && p.name != s.key ? "" : ` Nullable="false"`) ~ `/>`;
        x ~= `</EntityType>`;
    }
    foreach (o; ops) {
        x ~= (o.isFunction ? `<Function Name="` : `<Action Name="`) ~ o.name ~ `">`;
        foreach (p; o.parameters)
            x ~= `<Parameter Name="` ~ p.name ~ `" Type="` ~ p.type ~ `"` ~ (p.nullable ? "" : ` Nullable="false"`) ~ `/>`;
        if (o.returnType.length)
            x ~= `<ReturnType Type="` ~ o.returnType ~ `"/>`;
        x ~= o.isFunction ? `</Function>` : `</Action>`;
    }
    x ~= `<EntityContainer Name="Container">`;
    foreach (s; sets)
        x ~= `<EntitySet Name="` ~ s.name ~ `" EntityType="` ~ cloudNamespace ~ "." ~ s.typeName ~ `"/>`;
    foreach (o; ops)
        x ~= (o.isFunction ? `<FunctionImport Name="` ~ o.name ~ `" Function="` : `<ActionImport Name="` ~ o.name ~ `" Action="`)
            ~ cloudNamespace ~ "." ~ o.name ~ `"` ~ (o.entitySet.length ? ` EntitySet="` ~ o.entitySet ~ `"` : "")
            ~ (o.isFunction ? ` IncludeInServiceDocument="true"` : "") ~ `/>`;
    x ~= `</EntityContainer>`;
    // Semantische Anreicherung: Beschreibungen der Sets und der Eigenschaften
    foreach (s; sets) {
        if (s.description.length)
            x ~= `<Annotations Target="` ~ cloudNamespace ~ `.Container/` ~ s.name ~ `"><Annotation Term="Core.Description" String="`
                ~ xmlEscape(s.description) ~ `"/></Annotations>`;
        foreach (p; s.properties)
            if (p.description.length)
                x ~= `<Annotations Target="` ~ cloudNamespace ~ "." ~ s.typeName ~ "/" ~ p.name
                    ~ `"><Annotation Term="Core.Description" String="` ~ xmlEscape(p.description) ~ `"/></Annotations>`;
    }
    x ~= `</Schema></edmx:DataServices></edmx:Edmx>`;
    return x.data;
}

// --- Zeilen ---

private EdmProperty[] instanceProperties() {
    return [EdmProperty("name", "Edm.String", false), EdmProperty("description"), EdmProperty("status"),
        EdmProperty("performanceClass"), EdmProperty("memoryGb", "Edm.Int32"), EdmProperty("vcpus", "Edm.Int32"),
        EdmProperty("storageGb", "Edm.Int32"), EdmProperty("nseEnabled", "Edm.Boolean"),
        EdmProperty("ecnNodes", "Edm.Int32"), EdmProperty("region"), EdmProperty("version"),
        EdmProperty("users", "Edm.Int32"), EdmProperty("createdAt", "Edm.DateTimeOffset"), EdmProperty("createdBy"),
        EdmProperty("updatedAt", "Edm.DateTimeOffset"), EdmProperty("adminName"), EdmProperty("adminPassword")];
}

private Json instanceRow(InstanceInfo i) {
    auto j = Json.emptyObject;
    j["name"] = i.instance.name;
    j["description"] = i.instance.description;
    j["status"] = enumName(i.status);
    j["performanceClass"] = enumName(i.instance.performanceClass);
    j["memoryGb"] = i.instance.memoryGb;
    j["vcpus"] = i.vcpus;
    j["storageGb"] = i.instance.storageGb;
    j["nseEnabled"] = i.instance.nseEnabled;
    j["ecnNodes"] = i.instance.ecnNodes;
    j["region"] = i.instance.region;
    j["version"] = i.instance.version_;
    j["users"] = i.users;
    j["createdAt"] = time(i.instance.createdAt);
    j["createdBy"] = i.instance.createdBy;
    j["updatedAt"] = time(i.instance.updatedAt);
    j["adminName"] = Json(null);
    j["adminPassword"] = Json(null); // nur beim Anlegen, nie lesbar
    return j;
}

private Json classRow(WorkloadClass c) {
    auto j = Json.emptyObject;
    j["name"] = c.name;
    j["priority"] = c.priority;
    j["statementTimeoutSeconds"] = c.statementTimeoutSeconds;
    j["statementMemoryLimitMb"] = c.statementMemoryLimitMb;
    j["totalStatementLimit"] = c.totalStatementLimit;
    j["statementThreadLimit"] = c.statementThreadLimit;
    j["enabled"] = c.enabled;
    j["description"] = c.description;
    return j;
}

private Json mappingRow(WorkloadMapping m) {
    return Json(["name": Json(m.name), "workloadClass": Json(m.workloadClass), "userName": Json(m.userName),
            "roleName": Json(m.roleName)]);
}

private Json traceRow(TraceEntry t) {
    auto j = Json.emptyObject;
    j["id"] = cast(long) t.id;
    j["time"] = time(t.time);
    j["user"] = t.user;
    j["kind"] = t.kind;
    j["statement"] = t.statement;
    j["verb"] = t.verb;
    j["tables"] = t.tables.join(", ");
    j["durationMs"] = t.durationMs;
    j["rows"] = t.rows;
    j["affected"] = t.affected;
    j["error"] = t.error;
    j["workloadClass"] = t.workloadClass;
    return j;
}

private Json metricRow(MetricSample s) {
    auto j = Json.emptyObject;
    j["time"] = s.time;
    j["statements"] = s.statements;
    j["errors"] = s.errors;
    j["expensive"] = s.expensive;
    j["avgMs"] = s.avgMs;
    j["maxMs"] = s.maxMs;
    j["tables"] = s.tables;
    j["rows"] = cast(double) s.rows;
    j["memoryBytes"] = cast(double) s.memoryBytes;
    j["cpuPercent"] = s.cpuPercent;
    j["residentBytes"] = cast(double) s.residentBytes;
    j["reads"] = s.reads;
    j["writes"] = s.writes;
    return j;
}

private Json accessRow(TableAccess a) {
    return Json(["table": Json(a.table), "reads": Json(a.reads), "writes": Json(a.writes), "filters": Json(a.filters),
            "filterColumns": Json(a.filterColumns.join(", ")), "lastAccess": time(a.lastAccess)]);
}

private Json recommendationRow(Recommendation r) {
    auto j = Json.emptyObject;
    j["id"] = r.id;
    j["advisor"] = enumName(r.advisor);
    j["severity"] = enumName(r.severity);
    j["target"] = r.target;
    j["title"] = r.title;
    j["detail"] = r.detail;
    j["action"] = r.action;
    j["executable"] = r.executable;
    j["benefit"] = r.benefit;
    j["createdAt"] = time(r.createdAt);
    return j;
}

private Json viewRow(CalculationView v) {
    auto j = Json.emptyObject;
    j["name"] = v.name;
    j["label"] = v.label;
    j["description"] = v.description;
    j["viewType"] = enumName(v.viewType);
    j["baseTable"] = v.baseTable;
    j["tables"] = tablesOf(v).join(", ");
    j["attributes"] = v.attributes.map!(a => outputName(a)).join(", ");
    j["measures"] = v.measures.map!(m => outputName(m) ~ " = " ~ aggregateSql(m)).join(", ");
    j["filter"] = v.filter;
    j["entitySet"] = "CV_" ~ v.name;
    j["createdBy"] = v.createdBy;
    j["updatedAt"] = time(v.updatedAt);
    return j;
}

private Json bindingRow(ServiceBinding b) {
    return Json(["name": Json(b.name), "application": Json(b.application), "tenant": Json(b.tenant), "user": Json(b.user),
            "role": Json(b.role), "createdAt": time(b.createdAt), "createdBy": Json(b.createdBy)]);
}

private Json productRow(DataProductInfo p) {
    auto j = Json.emptyObject;
    j["id"] = p.product.id;
    j["title"] = p.product.title;
    j["description"] = p.product.description;
    j["provider"] = p.product.provider;
    j["version"] = p.product.version_;
    j["tags"] = p.product.tags.join(", ");
    j["tables"] = p.product.tables.map!(t => t.name).join(", ");
    j["rows"] = p.rows;
    j["installed"] = p.installed;
    j["installedAt"] = p.installed ? time(p.installation.installedAt) : Json(null);
    j["installedTables"] = p.installation.tables.join(", ");
    return j;
}

// --- Hilfen ---

private Json time(string iso) {
    return iso.length ? Json(iso) : Json(null);
}

/// Eingaben in OData-Form: Zahlen können wegen IEEE754Compatible als Text kommen, @odata-Felder fallen weg.
private Json fromOData(Json j) {
    auto out_ = Json.emptyObject;
    if (j.type != Json.Type.object)
        return out_;
    foreach (k, v; j.get!(Json[string]))
        if (!k.startsWith("@"))
            out_[k] = v;
    return out_;
}

private Json readBody(HTTPServerRequest req) @trusted {
    auto text = req.bodyReader.readAllUTF8();
    return text.strip.length ? fromOData(parseJsonString(text)) : Json.emptyObject;
}

/// Schlüssel aus dem Pfad: 'a''b' → a'b, name='x' → x, 5 → 5.
string keyText(string raw) {
    auto t = urlDecode(raw).strip;
    auto eq = t.indexOf('=');
    if (eq > 0 && t[0] != '\'')
        t = t[eq + 1 .. $].strip;
    if (t.length >= 2 && t[0] == '\'' && t[$ - 1] == '\'')
        return t[1 .. $ - 1].replace("''", "'");
    return t;
}

private string plain(Json j) {
    return j.type == Json.Type.string ? j.get!string : j.toString;
}

private bool less(Json a, Json b) {
    if ((a.type == Json.Type.int_ || a.type == Json.Type.float_) && (b.type == Json.Type.int_ || b.type == Json.Type.float_))
        return a.to!double < b.to!double;
    return plain(a) < plain(b);
}

private struct FilterCond {
    string field, op, value;
    bool quoted;

    bool matches(Json row) const {
        auto v = row[field];
        if (v.type == Json.Type.undefined)
            throw badRequest("Unknown property in $filter: " ~ field);
        if (v.type == Json.Type.null_)
            return value == "null" ? op == "eq" : op == "ne";
        auto text = plain(v);
        switch (op) {
        case "contains":
            return text.toLower.indexOf(value.toLower) >= 0;
        case "startswith":
            return text.toLower.startsWith(value.toLower);
        default:
            break;
        }
        int cmp;
        if (!quoted && (v.type == Json.Type.int_ || v.type == Json.Type.float_)) {
            double a = v.to!double, b;
            try
                b = value.to!double;
            catch (Exception)
                throw badRequest("Not a number: " ~ value);
            cmp = a < b ? -1 : a > b ? 1 : 0;
        } else if (v.type == Json.Type.bool_)
            cmp = text == value ? 0 : 1;
        else
            cmp = text < value ? -1 : text > value ? 1 : 0;
        switch (op) {
        case "eq":
            return cmp == 0;
        case "ne":
            return cmp != 0;
        case "gt":
            return cmp > 0;
        case "ge":
            return cmp >= 0;
        case "lt":
            return cmp < 0;
        case "le":
            return cmp <= 0;
        default:
            throw badRequest("Unsupported operator: " ~ op);
        }
    }
}

/// Einfache $filter-Ausdrücke, mit `and` verknüpft.
private FilterCond[] parseFilter(string f) {
    import std.regex : ctRegex, matchFirst, split;

    FilterCond[] r;
    foreach (part; split(f.strip, ctRegex!(`\s+and\s+`, "i"))) {
        auto p = part.strip;
        while (p.length > 1 && p[0] == '(' && p[$ - 1] == ')')
            p = p[1 .. $ - 1].strip;
        auto fn = matchFirst(p, ctRegex!(`^(contains|startswith)\s*\(\s*(\w+)\s*,\s*'((?:[^']|'')*)'\s*\)$`, "i"));
        if (!fn.empty) {
            r ~= FilterCond(fn[2], fn[1].toLower, fn[3].replace("''", "'"), true);
            continue;
        }
        auto cmp = matchFirst(p, ctRegex!(`^(\w+)\s+(eq|ne|gt|ge|lt|le)\s+('(?:[^']|'')*'|[\w.+\-:]+)$`, "i"));
        if (cmp.empty)
            throw notImplemented("Unsupported $filter expression: " ~ p);
        auto v = cmp[3];
        immutable quoted = v.length >= 2 && v[0] == '\'';
        r ~= FilterCond(cmp[1], cmp[2].toLower, quoted ? v[1 .. $ - 1].replace("''", "'") : v, quoted);
    }
    return r;
}

private string xmlEscape(string s) {
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(`"`, "&quot;");
}

private void writeJson(HTTPServerResponse res, int status, Json j) {
    res.statusCode = status;
    res.writeBody(j.toString, "application/json;odata.metadata=minimal;IEEE754Compatible=true");
}

private void writeError(HTTPServerResponse res, int status, string code, string message) {
    res.statusCode = status;
    res.writeBody(`{"error":{"code":` ~ Json(code).toString ~ `,"message":` ~ Json(message).toString ~ "}}",
        "application/json");
}

unittest {
    assert(keyText("'it''s'") == "it's" && keyText("name='acme'") == "acme" && keyText("42") == "42");
    auto f = parseFilter("kind eq 'error' and contains(statement,'ORDERS') and durationMs gt 5");
    auto row = Json(["kind": Json("error"), "statement": Json("select * from orders"), "durationMs": Json(7.5)]);
    assert(f.all!(c => c.matches(row)));
    row["durationMs"] = 2;
    assert(!f.all!(c => c.matches(row)));
    auto xml = metadataXml([EntitySetDef("Things", "Thing", "id", [EdmProperty("id", "Edm.Int32", false, "Key & <id>")])],
        [OperationDef("Ask", false, [EdmProperty("message", "Edm.String", false)], "Edm.String")]);
    assert(xml.canFind(`<EntitySet Name="Things" EntityType="hdb.cloud.Thing"/>`));
    assert(xml.canFind(`<ActionImport Name="Ask" Action="hdb.cloud.Ask"/>`));
    assert(xml.canFind("Key &amp; &lt;id&gt;"));
}
