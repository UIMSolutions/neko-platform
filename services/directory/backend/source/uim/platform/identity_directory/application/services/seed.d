/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.services.seed;

import neko.directory;

mixin(ShowModule!());

@safe:

/// The SCIM enterprise user extension (RFC 7643 section 4.3).
enum enterpriseUserUrn = "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User";

/// Application service: installs the predefined password policies and the
/// enterprise user schema. Existing names are kept (idempotent).
class DirectorySeedService : IDirectorySeedService {
  protected DirectoryRepositories repos;
  protected AuditTrail audit;

  this(DirectoryRepositories repos, AuditTrail audit) {
    this.repos = repos;
    this.audit = audit;
  }

  SeedReport seed(TenantId tenantId, UserId actor) {
    SeedReport report;
    report.tenantId = tenantId;

    void policy(string name, string description, int minLength, bool special, int history, int expiry, bool isDefault) {
      if (!repos.policies.findByName(tenantId, name).isNull) {
        report.skipped++;
        return;
      }
      auto p = PasswordPolicy(tenantId);
      p.name = name;
      p.description = description;
      p.minLength = minLength;
      p.requireSpecialChar = special;
      p.historyCount = history;
      p.expiryDays = expiry;
      p.maxFailedAttempts = minLength >= 14 ? 3 : 5;
      p.strength = classifyStrength(p);
      p.isDefault = isDefault && repos.policies.findMatching(tenantId, (const PasswordPolicy x) => x.isDefault).length == 0;
      p.predefined = true;
      p.createdBy = actor;
      p.updatedBy = actor;
      repos.policies.save(p);
      audit.record(tenantId, AuditEventType.policyCreated, actor, "PasswordPolicy", p.id.value, name, "Predefined password policy installed");
      report.created++;
      report.items ~= "password policy " ~ name;
    }

    policy("Standard", "Default policy: 8 characters, upper/lower case and digits", 8, false, 5, 90, true);
    policy("Strong", "12 characters incl. a special character", 12, true, 10, 90, false);
    policy("Enterprise", "14 characters, all character classes, 3 attempts", 14, true, 12, 60, false);

    if (repos.schemas.findMatching(tenantId, (const CustomSchema s) => s.urn == enterpriseUserUrn).length > 0) {
      report.skipped++;
    } else {
      auto s = CustomSchema(tenantId);
      s.urn = enterpriseUserUrn;
      s.name = "Enterprise User";
      s.description = "SCIM 2.0 enterprise user extension (RFC 7643)";
      s.target = SchemaTarget.user;
      s.predefined = true;
      SchemaAttribute attr(string name, string description, AttributeType type = AttributeType.string_) {
        SchemaAttribute a;
        a.name = name;
        a.description = description;
        a.type = type;
        return a;
      }

      s.attributes = [
        attr("employeeNumber", "Numeric or alphanumeric identifier assigned to a person"),
        attr("costCenter", "Name of a cost center"),
        attr("organization", "Name of an organization"),
        attr("division", "Name of a division"),
        attr("department", "Name of a department"),
        attr("manager", "Id of the user's manager", AttributeType.reference),
      ];
      s.attributes[0].uniqueness = Uniqueness.server;
      s.createdBy = actor;
      s.updatedBy = actor;
      repos.schemas.save(s);
      audit.record(tenantId, AuditEventType.schemaCreated, actor, "Schema", s.id.value, s.name, "Predefined schema installed");
      report.created++;
      report.items ~= "schema " ~ s.name;
    }
    return report;
  }
}
