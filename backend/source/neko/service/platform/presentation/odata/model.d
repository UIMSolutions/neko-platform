/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// OData v4 entity model (CSDL) and DTO → entity serialisation.
module neko.platform.presentation.odata.model;

import std.array : appender;
import vibe.data.json;
import neko.platform.application.dtos;

@safe:

enum odataNamespace = "neko.platform";
enum odataContainer = "PlatformService";

struct PropertyDef {
  string name;
  string type;
  bool nullable = true;
  string label;
}

struct EntityTypeDef {
  string name;
  string set; /// entity set or singleton name
  string key;
  bool singleton;
  PropertyDef[] properties;
}

struct ParameterDef {
  string name;
  string type = "Edm.String";
}

struct ActionDef {
  string name;
  ParameterDef[] parameters;
  string returnType; /// entity type name
}

immutable EntityTypeDef[] entityTypes = [
  EntityTypeDef("Service", "Services", "ID", false, [
    PropertyDef("ID", "Edm.String", false, "ID"),
    PropertyDef("Name", "Edm.String", false, "Name"),
    PropertyDef("Description", "Edm.String", true, "Description"),
    PropertyDef("Classification", "Edm.String", false, "Classification"),
    PropertyDef("BaseUrl", "Edm.String", true, "Base URL"),
    PropertyDef("HealthPath", "Edm.String", true, "Health Path"),
    PropertyDef("Status", "Edm.String", false, "Status"),
    PropertyDef("Health", "Edm.String", false, "Health"),
    PropertyDef("LastCheckedAt", "Edm.DateTimeOffset", true, "Last Checked"),
    PropertyDef("CreatedAt", "Edm.DateTimeOffset", true, "Created"),
    PropertyDef("ModifiedAt", "Edm.DateTimeOffset", true, "Modified"),
  ]),
  EntityTypeDef("Transfer", "Transfers", "ID", false, [
    PropertyDef("ID", "Edm.String", false, "ID"),
    PropertyDef("Name", "Edm.String", false, "Name"),
    PropertyDef("Direction", "Edm.String", false, "Direction"),
    PropertyDef("SourceDomain", "Edm.String", false, "Source Domain"),
    PropertyDef("TargetDomain", "Edm.String", false, "Target Domain"),
    PropertyDef("Status", "Edm.String", false, "Status"),
    PropertyDef("Checksum", "Edm.String", true, "SHA-256"),
    PropertyDef("Size", "Edm.Int32", false, "Size (bytes)"),
    PropertyDef("Reason", "Edm.String", true, "Reason"),
    PropertyDef("CreatedBy", "Edm.String", true, "Created By"),
    PropertyDef("CreatedAt", "Edm.DateTimeOffset", true, "Created"),
  ]),
  EntityTypeDef("Overview", "Overview", "Domain", true, [
    PropertyDef("Domain", "Edm.String", false, "Security Domain"),
    PropertyDef("Environment", "Edm.String", true, "Environment"),
    PropertyDef("CanExport", "Edm.Boolean", false, "Export"),
    PropertyDef("CanImport", "Edm.Boolean", false, "Import"),
    PropertyDef("ExportTargets", "Collection(Edm.String)", false, "Export Targets"),
    PropertyDef("ServiceCount", "Edm.Int32", false, "Services"),
    PropertyDef("ActiveServices", "Edm.Int32", false, "Active"),
    PropertyDef("ServicesDown", "Edm.Int32", false, "Down"),
    PropertyDef("TransferCount", "Edm.Int32", false, "Transfers"),
    PropertyDef("OutboundTransfers", "Edm.Int32", false, "Outbound"),
    PropertyDef("InboundTransfers", "Edm.Int32", false, "Inbound"),
    PropertyDef("RejectedTransfers", "Edm.Int32", false, "Rejected"),
  ]),
];

immutable ActionDef[] actions = [
  ActionDef("ActivateService", [ParameterDef("ID")], "Service"),
  ActionDef("SuspendService", [ParameterDef("ID")], "Service"),
  ActionDef("RetireService", [ParameterDef("ID")], "Service"),
  ActionDef("CheckServiceHealth", [ParameterDef("ID")], "Service"),
  ActionDef("ExportPackage", [ParameterDef("Name"), ParameterDef("TargetDomain"), ParameterDef("Payload")], "Transfer"),
  ActionDef("ImportPackage", [ParameterDef("Document")], "Transfer"),
];

const(EntityTypeDef)* findEntitySet(string set) {
  foreach (i; 0 .. entityTypes.length)
    if (entityTypes[i].set == set)
      return &entityTypes[i];
  return null;
}

const(ActionDef)* findAction(string name) {
  foreach (i; 0 .. actions.length)
    if (actions[i].name == name)
      return &actions[i];
  return null;
}

string qualified(string name) pure {
  return odataNamespace ~ "." ~ name;
}

private string xmlEscape(string value) pure {
  import std.array : replace;

  return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
}

/// CSDL (EDMX 4.0) served at $metadata. Capabilities annotations tell Fiori
/// elements / smart controls what is insertable, updatable and deletable.
string buildMetadata() {
  auto x = appender!string;
  x ~= `<?xml version="1.0" encoding="utf-8"?>` ~ "\n";
  x ~= `<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">` ~ "\n";
  x ~= `<edmx:Reference Uri="https://oasis-tcs.github.io/odata-vocabularies/vocabularies/Org.OData.Capabilities.V1.xml">`
    ~ `<edmx:Include Alias="Capabilities" Namespace="Org.OData.Capabilities.V1"/></edmx:Reference>` ~ "\n";
  x ~= `<edmx:Reference Uri="https://sap.github.io/odata-vocabularies/vocabularies/Common.xml">`
    ~ `<edmx:Include Alias="Common" Namespace="com.sap.vocabularies.Common.v1"/></edmx:Reference>` ~ "\n";
  x ~= `<edmx:DataServices><Schema Namespace="` ~ odataNamespace ~ `" xmlns="http://docs.oasis-open.org/odata/ns/edm">` ~ "\n";

  foreach (e; entityTypes) {
    x ~= `<EntityType Name="` ~ e.name ~ `"><Key><PropertyRef Name="` ~ e.key ~ `"/></Key>` ~ "\n";
    foreach (p; e.properties)
      x ~= `  <Property Name="` ~ p.name ~ `" Type="` ~ p.type ~ `"` ~ (p.nullable ? "" : ` Nullable="false"`)
        // timestamps are sent with milliseconds (isoTime); without the facet UI5 rejects them
        ~ (p.type == "Edm.DateTimeOffset" ? ` Precision="3"` : "") ~ "/>\n";
    x ~= "</EntityType>\n";
  }
  foreach (a; actions) {
    x ~= `<Action Name="` ~ a.name ~ `" IsBound="false">`;
    foreach (p; a.parameters)
      x ~= `<Parameter Name="` ~ p.name ~ `" Type="` ~ p.type ~ `" Nullable="false"/>`;
    x ~= `<ReturnType Type="` ~ qualified(a.returnType) ~ `"/></Action>` ~ "\n";
  }

  x ~= `<EntityContainer Name="` ~ odataContainer ~ `">` ~ "\n";
  foreach (e; entityTypes) {
    if (e.singleton)
      x ~= `  <Singleton Name="` ~ e.set ~ `" Type="` ~ qualified(e.name) ~ `"/>` ~ "\n";
    else
      x ~= `  <EntitySet Name="` ~ e.set ~ `" EntityType="` ~ qualified(e.name) ~ `"/>` ~ "\n";
  }
  foreach (a; actions) {
    string set;
    foreach (e; entityTypes)
      if (e.name == a.returnType && !e.singleton)
        set = e.set;
    x ~= `  <ActionImport Name="` ~ a.name ~ `" Action="` ~ qualified(a.name) ~ `" EntitySet="` ~ set ~ `"/>` ~ "\n";
  }
  x ~= "</EntityContainer>\n";

  foreach (e; entityTypes)
    foreach (p; e.properties)
      x ~= `<Annotations Target="` ~ qualified(e.name) ~ "/" ~ p.name ~ `"><Annotation Term="Common.Label" String="`
        ~ xmlEscape(p.label) ~ `"/></Annotations>` ~ "\n";

  void capabilities(string set, bool insert, bool update, bool delete_) {
    x ~= `<Annotations Target="` ~ qualified(odataContainer) ~ "/" ~ set ~ `">`;
    x ~= `<Annotation Term="Capabilities.InsertRestrictions"><Record><PropertyValue Property="Insertable" Bool="`
      ~ (insert ? "true" : "false") ~ `"/></Record></Annotation>`;
    x ~= `<Annotation Term="Capabilities.UpdateRestrictions"><Record><PropertyValue Property="Updatable" Bool="`
      ~ (update ? "true" : "false") ~ `"/></Record></Annotation>`;
    x ~= `<Annotation Term="Capabilities.DeleteRestrictions"><Record><PropertyValue Property="Deletable" Bool="`
      ~ (delete_ ? "true" : "false") ~ `"/></Record></Annotation>`;
    x ~= "</Annotations>\n";
  }

  capabilities("Services", true, true, true);
  // Transfers are an audit trail; they are created through actions only.
  capabilities("Transfers", false, false, false);

  x ~= "</Schema></edmx:DataServices></edmx:Edmx>\n";
  return x.data;
}

private Json timestamp(string iso) {
  return iso.length > 0 ? Json(iso) : Json(null);
}

Json toEntity(const ServiceDto s) {
  auto j = Json.emptyObject;
  j["ID"] = s.id;
  j["Name"] = s.name;
  j["Description"] = s.description;
  j["Classification"] = s.classification;
  j["BaseUrl"] = s.baseUrl;
  j["HealthPath"] = s.healthPath;
  j["Status"] = s.status;
  j["Health"] = s.health;
  j["LastCheckedAt"] = timestamp(s.lastCheckedAt);
  j["CreatedAt"] = timestamp(s.createdAt);
  j["ModifiedAt"] = timestamp(s.modifiedAt);
  return j;
}

Json toEntity(const TransferDto t) {
  auto j = Json.emptyObject;
  j["ID"] = t.id;
  j["Name"] = t.name;
  j["Direction"] = t.direction;
  j["SourceDomain"] = t.sourceDomain;
  j["TargetDomain"] = t.targetDomain;
  j["Status"] = t.status;
  j["Checksum"] = t.checksum;
  j["Size"] = cast(int) t.size;
  j["Reason"] = t.reason;
  j["CreatedBy"] = t.createdBy;
  j["CreatedAt"] = timestamp(t.createdAt);
  return j;
}

Json toEntity(const OverviewDto o) {
  auto j = Json.emptyObject;
  j["Domain"] = o.domain;
  j["Environment"] = o.environment;
  j["CanExport"] = o.canExport;
  j["CanImport"] = o.canImport;
  Json[] targets;
  foreach (t; o.exportTargets)
    targets ~= Json(t);
  j["ExportTargets"] = Json(targets);
  j["ServiceCount"] = cast(int) o.serviceCount;
  j["ActiveServices"] = cast(int) o.activeServices;
  j["ServicesDown"] = cast(int) o.servicesDown;
  j["TransferCount"] = cast(int) o.transferCount;
  j["OutboundTransfers"] = cast(int) o.outboundTransfers;
  j["InboundTransfers"] = cast(int) o.inboundTransfers;
  j["RejectedTransfers"] = cast(int) o.rejectedTransfers;
  return j;
}
