/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct RegisterServiceRequest {
  string name;
  @optional string description;
  /// "open" | "restricted" | "confidential" | "secret"; empty = platform domain
  @optional string classification;
  @optional string baseUrl;
  @optional string healthPath;
  /// Activate right after registration.
  @optional bool activate;
}

/// Partial update; null fields are left unchanged.
struct UpdateServiceRequest {
  @optional Nullable!string description;
  @optional Nullable!string baseUrl;
  @optional Nullable!string healthPath;
}

/// Filters for listing services (all optional, combined with AND).
struct ServiceQuery {
  /// Case-insensitive substring of name or description.
  string search;
  string status;
  string classification;
}

struct ExportPackageRequest {
  string name;
  /// Target domain; must be higher than the platform domain.
  string targetDomain;
  string payload;
}

struct ImportPackageRequest {
  /// The transfer document (JSON text) produced by an export.
  string document;
}

struct CreateUserRequest {
  string userName;
  string password;
  @optional string displayName;
  @optional string email;
  /// "viewer" (default) | "admin"
  @optional string role;
  @optional bool active = true;
}

/// Partial update; null fields are left unchanged.
struct UpdateUserRequest {
  @optional Nullable!string displayName;
  @optional Nullable!string email;
  @optional Nullable!string role;
  @optional Nullable!bool active;
}
