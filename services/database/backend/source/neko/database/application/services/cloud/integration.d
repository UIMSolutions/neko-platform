/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Anwendungen binden und Datenprodukte installieren.
module neko.database.application.services.cloud.integration;

import neko.database.application.services.cloud.common;
import neko.database.domain;
import neko.database.ports;
import std.algorithm : any, canFind, countUntil, filter, map, sort;
import std.array : array;
import std.format : format;
import std.string : toLower;

@safe:

final class BindingService : IBindingUseCase {
    private IAccessUseCase access;
    private ICredentialCrypto crypto;
    private ICloudRepository repo;
    private CloudAudit audit;

    this(IAccessUseCase access, ICredentialCrypto crypto, ICloudRepository repo, CloudAudit audit = CloudAudit.init) {
        this.access = access;
        this.crypto = crypto;
        this.repo = repo;
        this.audit = audit;
    }

    ServiceBinding[] listBindings(Principal actor) {
        requireTenantPermission(actor, Permission.manageBindings);
        auto r = repo.tenantState(actor.tenant).bindings;
        r.sort!((a, b) => a.name < b.name);
        return r;
    }

    BindingResult createBinding(Principal actor, string name, string application, string role, string baseUrl) {
        requireTenantPermission(actor, Permission.manageBindings);
        return audit.run!BindingResult(actor, "bindings", "createBinding", name, "application=" ~ application, () {
            auto b = ServiceBinding(name, application, actor.tenant, bindingUser(name), role.length ? role : "editor",
                utcNow(), actor.name);
            validate(b);
            auto s = repo.tenantState(actor.tenant);
            if (s.bindings.any!(x => x.name.toLower == name.toLower))
                throw new Conflict("Binding " ~ name ~ " already exists");
            auto password = crypto.randomSecret();
            access.createUser(actor, b.user, password, b.role); // prüft manageAccess und die Rolle
            s.bindings ~= b;
            repo.saveTenantState(actor.tenant, s);
            return BindingResult(b, credentialsFor(baseUrl, actor.tenant, b.user, password));
        });
    }

    void deleteBinding(Principal actor, string name) {
        requireTenantPermission(actor, Permission.manageBindings);
        audit.run!void(actor, "bindings", "deleteBinding", name, "", () {
            auto s = repo.tenantState(actor.tenant);
            auto at = s.bindings.countUntil!(x => x.name.toLower == name.toLower);
            if (at < 0)
                throw new NotFound("No binding " ~ name);
            try
                access.deleteUser(actor, s.bindings[at].user);
            catch (AccessDenied e)
                throw e;
            catch (Exception) {
                // Benutzer schon gelöscht: die Bindung trotzdem lösen
            }
            s.bindings = s.bindings.filter!(x => x.name.toLower != name.toLower).array;
            repo.saveTenantState(actor.tenant, s);
        });
    }
}

final class DataProductService : IDataProductUseCase {
    private ISqlUseCase sql;
    private IDataProductCatalog catalogue;
    private ICloudRepository repo;
    private CloudAudit audit;

    this(ISqlUseCase sql, IDataProductCatalog catalogue, ICloudRepository repo, CloudAudit audit = CloudAudit.init) {
        this.sql = sql;
        this.catalogue = catalogue;
        this.repo = repo;
        this.audit = audit;
    }

    DataProductInfo[] catalog(Principal actor) {
        requireTenantUser(actor);
        auto installed = repo.tenantState(actor.tenant).products;
        return catalogue.products().map!(p => info(p, installed)).array;
    }

    DataProductInfo product(Principal actor, string id) {
        requireTenantUser(actor);
        return info(catalogue.product(id), repo.tenantState(actor.tenant).products);
    }

    InstalledProduct install(Principal actor, string id) {
        requireTenantPermission(actor, Permission.manageDataProducts);
        return audit.run!InstalledProduct(actor, "dataproducts", "installDataProduct", id, "", () {
            auto p = catalogue.product(id);
            validate(p);
            auto s = repo.tenantState(actor.tenant);
            if (s.products.any!(x => x.productId == id))
                throw new Conflict("Data product " ~ id ~ " is already installed");
            auto prefix = tablePrefix(p.id);
            string[] created;
            try {
                foreach (statement; installStatements(p, prefix)) {
                    sql.execute(statement);
                    if (statement.length > 13 && statement[0 .. 13] == "CREATE TABLE ")
                        created ~= statement[13 .. $].findName;
                }
            } catch (Exception e) {
                foreach (t; created) // halbe Installationen wieder entfernen
                    try
                        sql.execute("DROP TABLE " ~ t);
                    catch (Exception) {
                    }
                throw e;
            }
            auto inst = InstalledProduct(p.id, p.version_, prefix, created, utcNow(), actor.name);
            s.products ~= inst;
            repo.saveTenantState(actor.tenant, s);
            return inst;
        });
    }

    void uninstall(Principal actor, string id) {
        requireTenantPermission(actor, Permission.manageDataProducts);
        audit.run!void(actor, "dataproducts", "uninstallDataProduct", id, "", () {
            auto s = repo.tenantState(actor.tenant);
            auto at = s.products.countUntil!(x => x.productId == id);
            if (at < 0)
                throw new NotFound("Data product " ~ id ~ " is not installed");
            auto existing = sql.listTables().map!(t => t.toLower).array;
            foreach (t; s.products[at].tables)
                if (existing.canFind(t.toLower))
                    sql.execute("DROP TABLE " ~ t);
            s.products = s.products.filter!(x => x.productId != id).array;
            repo.saveTenantState(actor.tenant, s);
        });
    }

    private static DataProductInfo info(DataProduct p, InstalledProduct[] installed) {
        size_t rows;
        foreach (ref t; p.tables) {
            rows += t.rows.length;
            t.rows = null;
        }
        auto at = installed.countUntil!(x => x.productId == p.id);
        return DataProductInfo(p, rows, at >= 0, at >= 0 ? installed[at] : InstalledProduct.init);
    }
}

private string findName(string afterCreate) {
    size_t i;
    while (i < afterCreate.length && afterCreate[i] != ' ' && afterCreate[i] != '(')
        i++;
    return afterCreate[0 .. i];
}
