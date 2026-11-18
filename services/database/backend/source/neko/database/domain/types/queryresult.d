module neko.database.domain.types.queryresult;

import neko.database;

import uim.core.mixins.version_ : ShowModule;
mixin(ShowModule!());

@safe:

struct QueryResult {
    string[] columns;
    Value[][] rows;
    long affected;
    string message;
    string transaction; // gesetzt von BEGIN
}