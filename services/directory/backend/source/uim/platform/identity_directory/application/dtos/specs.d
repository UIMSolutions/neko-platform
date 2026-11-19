/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.dtos.specs;

import neko.directory;

mixin(ShowModule!());

@safe:

// Field names equal the entity's (see requests.d); defaults equal the entity defaults.

/// Settable fields of a user. `password` is write-only: it is hashed and never stored or returned.
struct UserSpec {
  string userName;
  string externalId;
  string displayName;
  string givenName;
  string familyName;
  string middleName;
  string honorificPrefix;
  string honorificSuffix;
  string nickName;
  string title;
  string profileUrl;
  UserType userType = UserType.employee;
  string preferredLanguage = "en";
  string locale;
  string timezone;
  UserStatus status = UserStatus.active;
  Email[] emails;
  PhoneNumber[] phoneNumbers;
  PostalAddress[] addresses;
  ExtendedAttribute[] extendedAttributes;
  string passwordPolicy;
  bool mustChangePassword;
  string password;
}

alias CreateUserRequest = CreateRootRequest!UserSpec;
alias UpdateUserRequest = UpdateRequest!(DirectoryUserId, UserSpec);

/// Settable fields of a group. Members may be given by id, user name or group name.
struct GroupSpec {
  string displayName;
  string externalId;
  string description;
  GroupType groupType = GroupType.standard;
  string membershipRule;
  GroupMember[] members;
  ExtendedAttribute[] extendedAttributes;
}

alias CreateGroupRequest = CreateRootRequest!GroupSpec;
alias UpdateGroupRequest = UpdateRequest!(GroupId, GroupSpec);

struct SchemaSpec {
  string urn;
  string name;
  string description;
  SchemaTarget target = SchemaTarget.user;
  SchemaAttribute[] attributes;
}

alias CreateSchemaRequest = CreateRootRequest!SchemaSpec;
alias UpdateSchemaRequest = UpdateRequest!(SchemaId, SchemaSpec);

struct PasswordPolicySpec {
  string name;
  string description;
  int minLength = 8;
  int maxLength = 128;
  bool requireUppercase = true;
  bool requireLowercase = true;
  bool requireDigit = true;
  bool requireSpecialChar;
  int minUniqueChars = 3;
  int maxRepeatedChars = 3;
  bool forbidUserName = true;
  int historyCount = 5;
  int maxFailedAttempts = 5;
  int lockoutMinutes = 30;
  int expiryDays = 90;
  int warningDays = 14;
}

alias CreatePasswordPolicyRequest = CreateRootRequest!PasswordPolicySpec;
alias UpdatePasswordPolicyRequest = UpdateRequest!(PasswordPolicyId, PasswordPolicySpec);

struct ApiClientSpec {
  string name;
  string description;
  string[] scopes;
  long expiresAt;
}

alias CreateApiClientRequest = CreateRootRequest!ApiClientSpec;
alias UpdateApiClientRequest = UpdateRequest!(ApiClientId, ApiClientSpec);

/// Audit entries recorded by external components (e.g. the authentication service).
struct AuditEventSpec {
  AuditEventType eventType = AuditEventType.custom;
  AuditOutcome outcome = AuditOutcome.success;
  string actorId;
  ActorType actorType = ActorType.user;
  string targetId;
  string targetType;
  string targetName;
  string description;
  string ipAddress;
  string userAgent;
  KeyValue[] details;
}

alias CreateAuditEventRequest = CreateRootRequest!AuditEventSpec;
alias UpdateAuditEventRequest = UpdateRequest!(AuditEventId, AuditEventSpec);
