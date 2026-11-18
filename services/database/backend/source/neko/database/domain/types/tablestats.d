module neko.database.domain.types.tablestats;

import neko.database;
import neko.database.domain.types.columnstats;
import neko.database.domain.enumerations.tablestorage;

import uim.core.mixins.version_ : ShowModule;
mixin(ShowModule!());

@safe:

struct TableStats {
    string table;
    size_t rows, deletedRows;
    ColumnStats[] columns;
    TableStorage storage;

    Json toJson() const {
        return Json.emptyObject
            .set("table", table)
            .set("rows", rows)
            .set("deletedRows", deletedRows)
            .set("columns", columns.map!(c => c.toJson).array.toJson)
            .set("storage", storage.to!string);
    }
}
