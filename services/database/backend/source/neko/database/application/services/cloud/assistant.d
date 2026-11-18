/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Virtueller Assistent: führt die Absichten aus neko.database.domain.services.assistant über die Anwendungsfälle
/// aus. Er hat keine eigenen Rechte; was der Fragende nicht darf, scheitert wie in jeder anderen Oberfläche.
module neko.database.application.services.cloud.assistant;

import neko.database.application.services.cloud.common;
import neko.database.domain;
import neko.database.ports;
import std.algorithm : filter, map, min, sum;
import std.array : array, join;
import std.conv : to;
import std.format : format;
import vibe.data.json : Json, serializeToJson;

@safe:

/// Höchstens so viele Aufträge je Nachricht.
enum size_t maxBatch = 10;

final class AssistantService : IAssistantUseCase {
    IInstanceUseCase instances;
    ISqlUseCase sql;
    IBackupUseCase backups;
    IMonitoringUseCase monitoring;
    IAdvisorUseCase advisors;
    IWorkloadUseCase workloads;
    ICalcViewUseCase views;
    IDataProductUseCase products;
    IBindingUseCase bindings;
    private CloudAudit audit;

    this(CloudAudit audit = CloudAudit.init) {
        this.audit = audit;
    }

    AssistantReply ask(Principal actor, string message) {
        if (!actor.authenticated)
            throw new AuthenticationRequired;
        if (message.length > 4000)
            throw new Exception("The message is limited to 4000 characters");
        auto intents = parseMessage(message);
        AssistantReply reply;
        if (intents.length > maxBatch)
            throw new Exception(format("At most %s tasks per message", maxBatch));
        foreach (intent; intents)
            reply.steps ~= step(actor, intent);
        if (reply.steps.length == 0)
            reply.steps ~= step(actor, AssistantIntent(Intent.help, "", ""));
        reply.text = reply.steps.length == 1 ? reply.steps[0].text
            : reply.steps.map!(s => (s.ok ? "✔ " : "✘ ") ~ s.command ~ ": " ~ s.text).join("\n\n");
        reply.suggestions = actor.isSystem ? ["status of instances", "how do I create an instance?", "stop instance <name>"]
            : ["summarize issues", "run advisors", "show expensive statements", "create a backup"];
        return reply;
    }

    private AssistantStep step(Principal actor, AssistantIntent intent) {
        auto s = AssistantStep(intent.text, intent.intent.to!string);
        try
            audit.run!void(actor, "assistant", intent.intent.to!string, intent.argument, intent.text, () {
                perform(actor, intent, s);
            });
        catch (AccessDenied e) {
            s.ok = false;
            s.text = "You are not allowed to do that: " ~ e.msg;
        } catch (Exception e) {
            s.ok = false;
            s.text = "That did not work: " ~ e.msg;
        }
        return s;
    }

    private void perform(Principal actor, AssistantIntent intent, ref AssistantStep s) {
        final switch (intent.intent) {
        case Intent.help:
            s.text = "I can check status, run maintenance and backups, summarize issues, run the advisors and guide "
                ~ "you through tasks. Several tasks can be chained with ';' or 'then'. Examples: "
                ~ assistantExamples.map!(e => "\"" ~ e ~ "\"").join(", ") ~ ".";
            break;
        case Intent.guide:
            auto steps = guideSteps(intent.argument);
            s.text = (intent.argument.length ? "Guide: " ~ intent.argument ~ "\n" : "")
                ~ steps.map!(x => "• " ~ x).join("\n");
            s.data = serializeToJson(steps);
            break;
        case Intent.instanceStatus:
            if (actor.isSystem) {
                auto list = need(instances).listInstances(actor);
                auto running = list.filter!(i => i.status == InstanceStatus.running).array.length;
                s.text = format("%s instances, %s running, %s stopped.", list.length, running, list.length - running);
                foreach (i; list)
                    s.text ~= format("\n• %s: %s, %s GB / %s vCPU (%s), %s users", i.instance.name, enumName(i.status),
                        i.instance.memoryGb, i.vcpus, enumName(i.instance.performanceClass), i.users);
                s.data = serializeToJson(list.map!(i => i.instance.name).array);
            } else {
                auto o = need(monitoring).overview(actor);
                auto st = need(sql).stats();
                s.text = format("Instance %s is running%s. %s tables with %s rows. Since start: %s statements, %s errors, "
                        ~ "%s expensive statements, %s workload violations. Current interval: %s statements, "
                        ~ "average %.1f ms.", o.tenant, o.hasInstance ? format(" with %s GB and %s vCPUs",
                            o.instance.instance.memoryGb, o.instance.vcpus) : "", st.length,
                        st.map!(t => t.rows).sum, o.statements, o.errors, o.expensive, o.violations,
                        o.current.statements, o.current.avgMs);
            }
            break;
        case Intent.startInstance:
        case Intent.stopInstance:
            if (intent.argument.length == 0)
                throw new Exception("Which instance? Say for example \"stop instance acme\"");
            auto i = intent.intent == Intent.startInstance ? need(instances).startInstance(actor, intent.argument)
                : need(instances).stopInstance(actor, intent.argument);
            s.text = format("Instance %s is now %s.", i.instance.name, enumName(i.status));
            break;
        case Intent.listTables:
            auto t = need(sql).listTables();
            s.text = t.length ? format("%s tables: %s", t.length, t.join(", ")) : "There are no tables yet.";
            s.data = serializeToJson(t);
            break;
        case Intent.statistics:
            auto st = need(sql).stats();
            ulong bytes;
            foreach (x; st)
                bytes += estimatedBytes(x);
            s.text = format("%s tables, %s rows, about %s in memory.", st.length, st.map!(t => t.rows).sum,
                humanBytes(bytes));
            break;
        case Intent.createBackup:
            auto b = need(backups).create(intent.argument);
            s.text = format("Backup %s created (%s tables, %s rows).", b.name, b.tables, b.rows);
            break;
        case Intent.listBackups:
            auto list = need(backups).list();
            auto sch = need(backups).schedule();
            s.text = format("%s backups. Scheduled every %s hours, automatic backups kept %s days.", list.length,
                sch.intervalHours, sch.retentionDays);
            foreach (b; list[0 .. min(5, list.length)])
                s.text ~= format("\n• %s (%s, %s)", b.name, b.kind, b.created);
            break;
        case Intent.mergeDelta:
            need(sql).mergeDelta();
            s.text = "Delta merge finished.";
            break;
        case Intent.checkpoint:
            need(sql).checkpoint();
            s.text = "Checkpoint written.";
            break;
        case Intent.expensiveStatements:
            auto top = need(monitoring).overview(actor).topExpensive;
            s.text = top.length ? format("The %s most expensive statements:", top.length)
                : "No expensive statements were traced. Lower the threshold in the trace settings to see more.";
            foreach (t; top)
                s.text ~= format("\n• %.0f ms by %s: %s", t.durationMs, t.user, t.statement);
            s.data = serializeToJson(top);
            break;
        case Intent.issueSummary:
            auto sum_ = need(monitoring).issueSummary(actor);
            s.text = sum_.text;
            s.data = serializeToJson(sum_);
            break;
        case Intent.runAdvisors:
            auto r = need(advisors).runAdvisors(actor, null);
            s.text = r.length ? format("%s recommendations:", r.length) : "The advisors have no recommendations.";
            foreach (x; r[0 .. min(8, r.length)])
                s.text ~= format("\n• [%s/%s] %s", enumName(x.advisor), enumName(x.severity), x.title);
            s.data = serializeToJson(r.map!(x => x.id).array);
            break;
        case Intent.listWorkloads:
            auto c = need(workloads).listClasses(actor);
            s.text = c.length ? format("%s workload classes: %s", c.length, c.map!(x => x.name).join(", "))
                : "No workload classes yet. Ask \"how do I set up a workload class?\"";
            break;
        case Intent.listViews:
            auto v = need(views).listViews(actor);
            s.text = v.length ? format("%s calculation views: %s", v.length, v.map!(x => x.name).join(", "))
                : "No calculation views yet.";
            break;
        case Intent.listDataProducts:
            auto p = need(products).catalog(actor);
            s.text = format("%s data products are shared:", p.length);
            foreach (x; p)
                s.text ~= format("\n• %s %s (%s)%s", x.product.id, x.product.version_, x.product.title,
                    x.installed ? " — installed" : "");
            break;
        case Intent.installDataProduct:
            if (intent.argument.length == 0)
                throw new Exception("Which data product? Say for example \"install data product bdc.sales.orders\"");
            auto inst = need(products).install(actor, intent.argument);
            s.text = format("Installed %s %s as tables %s.", inst.productId, inst.version_, inst.tables.join(", "));
            break;
        case Intent.listBindings:
            auto b = need(bindings).listBindings(actor);
            s.text = b.length ? format("%s bindings: %s", b.length, b.map!(x => x.name ~ " → " ~ x.application).join(", "))
                : "No applications are bound.";
            break;
        case Intent.unknown:
            s.ok = false;
            s.text = "I did not understand that. Try \"help\" for examples.";
            break;
        }
    }

    private static T need(T)(T dependency) {
        if (dependency is null)
            throw new Exception("This function is not available here");
        return dependency;
    }
}
