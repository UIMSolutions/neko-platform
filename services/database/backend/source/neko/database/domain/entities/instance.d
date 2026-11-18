/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Datenbankinstanz im Sinne von HANA Cloud: ein Mandant mit Größe, Leistungsklasse und Optionen.
/// Die Daten, Benutzer und Sicherungen gehören dem gleichnamigen Mandanten; die Instanz ergänzt nur die
/// Betriebsangaben.
module neko.database.domain.entities.instance;

import neko.database.domain.enumerations.cloud;
import std.exception : enforce;

@safe:

/// Grenzen der Größenwahl.
enum size_t minMemoryGb = 16, maxMemoryGb = 6144, memoryStepGb = 16;
enum size_t maxStorageGb = 32_768;
enum size_t maxEcnNodes = 4;

/// Betriebsangaben einer Instanz.
struct DatabaseInstance {
    string name; // = Mandant
    string description;
    PerformanceClass performanceClass = PerformanceClass.memory;
    size_t memoryGb = 32;
    size_t storageGb = 120;
    bool nseEnabled; // Native Storage Extension: seitenweise ladbare Daten erlaubt
    size_t ecnNodes; // Elastic Compute Nodes für Lastspitzen
    string region;
    string version_ = "2026.46.0";
    string createdAt, createdBy, updatedAt;

    /// vCPUs aus Speicher und Leistungsklasse, mindestens 1.
    size_t vcpus() const {
        auto v = memoryGb / gbPerVcpu(performanceClass);
        return v == 0 ? 1 : v;
    }
}

/// Speicher je vCPU einer Leistungsklasse.
size_t gbPerVcpu(PerformanceClass c) {
    final switch (c) {
    case PerformanceClass.compute:
        return 8;
    case PerformanceClass.memory:
        return 16;
    case PerformanceClass.highMemory:
        return 32;
    }
}

/// Speicherplatz, den eine Instanz mindestens braucht: das Doppelte des Arbeitsspeichers für Sicherungen und
/// Protokolle, wie bei Spaltendatenbanken üblich.
size_t minimumStorageGb(size_t memoryGb) {
    return memoryGb * 2;
}

/// Prüft die Größenangaben; wirft mit einer Meldung für den Benutzer.
void validateSizing(const DatabaseInstance i) {
    enforce(i.memoryGb >= minMemoryGb && i.memoryGb <= maxMemoryGb,
        "Memory must be between 16 and 6144 GB");
    enforce(i.memoryGb % memoryStepGb == 0, "Memory must be a multiple of 16 GB");
    enforce(i.storageGb >= minimumStorageGb(i.memoryGb), "Storage must be at least twice the memory");
    enforce(i.storageGb <= maxStorageGb, "Storage must not exceed 32768 GB");
    enforce(i.ecnNodes <= maxEcnNodes, "At most 4 elastic compute nodes");
    enforce(i.description.length <= 256, "The description is limited to 256 characters");
}

/// Nächstgrößere bzw. -kleinere zulässige Speichergröße (für Empfehlungen).
size_t roundMemory(double gb) {
    if (gb < minMemoryGb)
        return minMemoryGb;
    auto steps = cast(size_t)((gb + memoryStepGb - 1) / memoryStepGb);
    auto r = steps * memoryStepGb;
    return r > maxMemoryGb ? maxMemoryGb : r;
}

unittest {
    import std.exception : assertThrown;

    auto i = DatabaseInstance("acme");
    assert(i.vcpus == 2);
    i.performanceClass = PerformanceClass.compute;
    assert(i.vcpus == 4);
    validateSizing(i);
    i.memoryGb = 40;
    assertThrown(validateSizing(i));
    i.memoryGb = 64;
    i.storageGb = 100;
    assertThrown(validateSizing(i));
    assert(roundMemory(17) == 32 && roundMemory(3) == 16 && roundMemory(1e9) == maxMemoryGb);
}
