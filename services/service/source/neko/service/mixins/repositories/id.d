module neko.service.mixins.repositories.id;
import neko.service;

mixin(ShowModule!());

@safe:

template IdRepositoryTemplate(alias Repository, TEntity, TId) {
    this() {
        super();
    }


}
