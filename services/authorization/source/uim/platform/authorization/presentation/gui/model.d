module neko.authorization.presentation.gui.model;

import neko.authorization;

mixin(ShowModule!());

@safe:

class AuthorizationGuiModel {
  string windowTitle() const {
    return "Authorization Management GUI";
  }
}
