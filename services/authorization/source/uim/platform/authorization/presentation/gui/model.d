module neko.service.authorization.presentation.gui.model;

import neko.service.authorization;

mixin(ShowModule!());

@safe:

class AuthorizationGuiModel {
  string windowTitle() const {
    return "Authorization Management GUI";
  }
}
